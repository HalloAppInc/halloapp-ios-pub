//
//  DataStore.swift
//  Share Extension
//
//  Created by Alan Luo on 7/27/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import CoreData

class DataStore: ShareExtensionDataStore {

    private let service: CoreService
    let mediaUploader: MediaUploader
    let mediaProcessingId = "shared-media-processing-id"

    init(service: CoreService) {
        self.service = service
        mediaUploader = MediaUploader(service: service)
        super.init()
        mediaUploader.resolveMediaPath = { [weak self] (relativeMediaPath) in
            return self!.fileURL(forRelativeFilePath: relativeMediaPath)
        }
    }

    private var isSendingCanceled = false
    
    func cancelSending() {
        isSendingCanceled = true
        mediaUploader.cancelAllUploads()
    }

    /**
     - parameter completion Completion handler will not be called if sending was canceled.
     */
    private func upload(media mediaItemsToUpload: [CommonMedia], postOrMessageOrLinkPreviewId: String, managedObjectContext: NSManagedObjectContext, completion: @escaping (Bool) -> ()) {
        var numberOfFailedUploads = 0
        let totalUploads = mediaItemsToUpload.count
        DDLogInfo("SharedDataStore/upload-media/starting [\(totalUploads)]")

        let uploadGroup = DispatchGroup()
        for mediaItem in mediaItemsToUpload {
            let mediaIndex = mediaItem.order
            uploadGroup.enter()

            let onUploadCompletion: MediaUploader.Completion = { (uploadResult) in
                    DDLogInfo("SharedDataStore/upload-media/\(mediaIndex)/finished result=[\(uploadResult)]")
                    // URLs acquired are already saved to the database by the time this block is executed.
                    switch uploadResult {
                    case .failure(_):
                        numberOfFailedUploads += 1
                    default:
                        break
                    }
                    uploadGroup.leave()
            }

            if let relativeFilePath = mediaItem.relativeFilePath, mediaItem.sha256.isEmpty && mediaItem.key.isEmpty {
                let url = fileURL(forRelativeFilePath: relativeFilePath)
                let path = Self.relativeFilePath(forFilename: "\(postOrMessageOrLinkPreviewId)-\(mediaIndex).processed", mediaType: mediaItem.type)
                let output = fileURL(forRelativeFilePath: path)
                let shouldStreamVideo = mediaItem.blobVersion == .chunked

                ImageServer.shared.prepare(mediaItem.type, url: url, for: mediaProcessingId, index: Int(mediaIndex), shouldStreamVideo: shouldStreamVideo) { [weak self] in
                    guard let self = self else { return }

                    switch $0 {
                    case .success(let result):
                        result.copy(to: output)

                        mediaItem.size = result.size
                        mediaItem.key = result.key
                        mediaItem.sha256 = result.sha256
                        mediaItem.relativeFilePath = path
                        mediaItem.chunkSize = result.chunkSize
                        mediaItem.blobSize = result.blobSize
                        self.save(managedObjectContext)
                        self.uploadMedia(mediaItem: mediaItem, postOrMessageOrLinkPreviewId: postOrMessageOrLinkPreviewId, in: managedObjectContext, completion: onUploadCompletion)

                        // the original media file should be deleted after it's been processed to save space
                        // nb: the original and processed files have different ids, should revisit to see if they could use the same one to make debugging easier
                        do {
                            try FileManager.default.removeItem(at: url)
                            DDLogInfo("SharedDataStore/upload-media/prepare/success/delete original [\(url)]")
                        } catch { }
                    case .failure(_):
                        numberOfFailedUploads += 1

                        mediaItem.status = .uploadError
                        self.save(managedObjectContext)

                        uploadGroup.leave()
                    }
                }
            } else {
                self.uploadMedia(mediaItem: mediaItem, postOrMessageOrLinkPreviewId: postOrMessageOrLinkPreviewId, in: managedObjectContext, completion: onUploadCompletion)
            }
        }

        uploadGroup.notify(queue: .main) {
            self.mediaUploader.clearTasks(withGroupID: postOrMessageOrLinkPreviewId)
            guard !self.isSendingCanceled else {
                DDLogWarn("SharedDataStore/upload-media/canceled Will not call completion handler")
                return
            }
            DDLogInfo("SharedDataStore/upload-media/all/finished [\(totalUploads-numberOfFailedUploads)/\(totalUploads)]")
            completion(numberOfFailedUploads == 0)
        }
    }

    private func uploadMedia(mediaItem: CommonMedia, postOrMessageOrLinkPreviewId: String, in managedObjectContext: NSManagedObjectContext, completion: @escaping MediaUploader.Completion) {
        let mediaIndex = mediaItem.order
        let onDidGetURLs: (MediaURLInfo) -> () = { (mediaURLs) in
            DDLogInfo("SharedDataStore/uploadMedia/\(mediaIndex)/acquired-urls [\(mediaURLs)]")

            // Save URLs acquired during upload to the database.
            switch mediaURLs {
            case .getPut(let getURL, let putURL):
                mediaItem.uploadUrl = putURL
                mediaItem.url = getURL

            case .patch(let patchURL):
                mediaItem.uploadUrl = patchURL
                mediaItem.url = nil

            // this will be revisited when we refactor share extension.
            case .download(let downloadURL):
                mediaItem.url = downloadURL
            }
            self.save(managedObjectContext)
        }

        guard let relativeFilePath = mediaItem.relativeFilePath else {
            DDLogError("SharedDataStore/uploadMedia/\(postOrMessageOrLinkPreviewId)/\(mediaIndex) missing file path")
            return completion(.failure(MediaUploadError.unknownError))
        }
        let processed = fileURL(forRelativeFilePath: relativeFilePath)
        AppContext.shared.mediaHashStore.fetch(url: processed, blobVersion: mediaItem.blobVersion) { [weak self] upload in
            guard let self = self else { return }
            if let url = upload?.url {
                DDLogInfo("Media \(processed) has been uploaded before at \(url).")
                if let uploadUrl = mediaItem.uploadUrl {
                    DDLogInfo("SharedDataStore/uploadMedia/upload url is supposed to be nil here/\(postOrMessageOrLinkPreviewId)/\(mediaIndex), uploadUrl: \(uploadUrl)")
                    // we set it to be nil here explicitly.
                    mediaItem.uploadUrl = nil
                }
                mediaItem.url = url
            } else {
                DDLogInfo("SharedDataStore/uploadMedia/uploading media now/\(postOrMessageOrLinkPreviewId)/\(mediaItem.order), index:\(mediaIndex)")
            }

            self.mediaUploader.upload(media: mediaItem, groupId: postOrMessageOrLinkPreviewId, didGetURLs: onDidGetURLs) { (uploadResult) in
                switch uploadResult {
                case .success(let details):
                    mediaItem.url = details.downloadURL
                    mediaItem.status = .uploaded

                    // If the download url was successfully refreshed - then use the old key and old hash.
                    if mediaItem.url == upload?.url, let key = upload?.key, let sha256 = upload?.sha256 {
                        mediaItem.key = key
                        mediaItem.sha256 = sha256
                    }
                    AppExtensionContext.shared.mediaHashStore.update(url: processed, blobVersion: mediaItem.blobVersion, key: mediaItem.key, sha256: mediaItem.sha256, downloadURL: mediaItem.url!)
                case .failure(let error):
                    DDLogError("SharedDataStore/uploadMedia/failed to upload media, error: \(error)")
                    mediaItem.status = .uploadError
                }
                self.save(managedObjectContext)
                completion(uploadResult)
            }
        }
    }

    private func attach(media: PendingMedia, to target: PostOrMessageOrLinkPreview, using managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("SharedDataStore/attach-media [\(media.fileURL!)]")

        let feedMedia = CommonMedia(context: managedObjectContext)
        feedMedia.type = media.type
        feedMedia.url = media.url
        feedMedia.uploadUrl = media.uploadUrl
        feedMedia.size = media.size!
        feedMedia.key = ""
        feedMedia.sha256 = ""
        feedMedia.order = Int16(media.order)
        feedMedia.status = .uploading

        let mediaContentId: String
        switch target {
        case .post(let feedPost):
            feedMedia.post = feedPost
            mediaContentId = "\(feedPost.id)-\(feedMedia.order)"
        case .message(let chatMessage):
            feedMedia.message = chatMessage
            mediaContentId = "\(chatMessage.id)-\(feedMedia.order)"
        case .linkPreview(let linkPreview):
            feedMedia.linkPreview = linkPreview
            mediaContentId = "\(linkPreview.id)-\(feedMedia.order)"
        }

        let relativeFilePath = Self.relativeFilePath(forFilename: mediaContentId, mediaType: media.type)

        do {
            let destinationUrl = fileURL(forRelativeFilePath: relativeFilePath)
            Self.preparePathForWriting(destinationUrl)

            // Copy unencrypted media file.
            if let sourceUrl = media.fileURL {
                try FileManager.default.copyItem(at: sourceUrl, to: destinationUrl)
                DDLogDebug("SharedDataStore/attach-media/ copied [\(sourceUrl)] to [\(destinationUrl)]")

                feedMedia.relativeFilePath = relativeFilePath
                feedMedia.mediaDirectory = .commonMedia
            }

            // Copy encrypted media file.
            // Encrypted media would be saved at the same file path with an additional ".enc" appended.
            if let sourceUrl = media.encryptedFileUrl {
                let encryptedDestinationUrl = destinationUrl.appendingPathExtension("enc")
                try FileManager.default.copyItem(at: sourceUrl, to: encryptedDestinationUrl)
                DDLogDebug("SharedDataStore/attach-media/ copied [\(sourceUrl)] to [\(encryptedDestinationUrl)]")
            }
        } catch {
            DDLogError("SharedDataStore/attach-media/error [\(error)]")
        }
    }

    func post(group: GroupListSyncItem? = nil, text: MentionText, media: [PendingMedia], linkPreviewData: LinkPreviewData? = nil, linkPreviewMedia: PendingMedia? = nil, completion: @escaping (Result<String, Error>) -> ()) {
        let postId: FeedPostID = UUID().uuidString
        DDLogInfo("SharedDataStore/post/\(postId)/created")

        // 1. Save post to the db and copy media to permanent storage directory.
        AppContext.shared.mainDataStore.saveSeriallyOnBackgroundContext { managedObjectContext in
            let feedPost = FeedPost(context: managedObjectContext)
            feedPost.id = postId
            feedPost.userId = AppContext.shared.userData.userId
            feedPost.rawText = text.collapsedText
            feedPost.timestamp = Date()
            feedPost.status = .sending
            feedPost.lastUpdated = Date()

            // Add mentions
            feedPost.mentions = text.mentionsArray.map {
                return MentionData(
                    index: $0.index,
                    userID: $0.userID,
                    name: AppContext.shared.contactStore.pushNames[$0.userID] ?? $0.name)
            }
            feedPost.mentions.filter { $0.name == "" }.forEach {
                DDLogError("FeedData/new-post/mention/\($0.userID) missing push name")
            }

            var lastMsgMediaType: CommonThread.LastMediaType = .none
            media.forEach { (mediaItem) in
                self.attach(media: mediaItem, to: .post(feedPost), using: managedObjectContext)
                if lastMsgMediaType == .none {
                    switch mediaItem.type {
                    case .image:
                        lastMsgMediaType = .image
                    case .video:
                        lastMsgMediaType = .video
                    case .audio:
                        lastMsgMediaType = .audio
                    }
                }
            }
            feedPost.media?.forEach({ $0.status = .uploading })

            if let group = group {
                let feedPostInfo = ContentPublishInfo(context: managedObjectContext)
                var receipts = [UserID : Receipt]()
                group.users.forEach({ userID in
                    receipts[userID] = Receipt()
                })
                feedPostInfo.receipts = receipts
                feedPostInfo.audienceType = .group
                feedPost.info = feedPostInfo
                feedPost.groupID = group.id

                // Code for streaming upload/download.
                let shouldStreamFeedVideo = ServerProperties.streamingSendingEnabled && ChunkedMediaTestConstants.STREAMING_FEED_GROUP_IDS.contains(group.id)
                if shouldStreamFeedVideo {
                    feedPost.media?.forEach({ $0.blobVersion = ($0.type == .video) ? .chunked : .default })
                }
            } else {
                let feedPostInfo = ContentPublishInfo(context: managedObjectContext)
                let postAudience = try! AppContext.shared.privacySettings.currentFeedAudience()
                let receipts = postAudience.userIds.reduce(into: [UserID : Receipt]()) { (receipts, userId) in
                    receipts[userId] = Receipt()
                }
                feedPostInfo.receipts = receipts
                feedPostInfo.audienceType = postAudience.audienceType
                feedPost.info = feedPostInfo
            }

            //Process LinkPreviews
            if let linkPreviewData = linkPreviewData {
                var linkPreviews: Set<CommonLinkPreview> = []
                DDLogDebug("NotificationExtension/DataStore/new-post/add-link-preview [\(linkPreviewData.url)]")
                let linkPreview = CommonLinkPreview(context: managedObjectContext)
                linkPreview.id = UUID().uuidString
                linkPreview.url = linkPreviewData.url
                linkPreview.title = linkPreviewData.title
                linkPreview.desc = linkPreviewData.description
                // Set preview image if present
                if let linkPreviewMedia = linkPreviewMedia {
                    self.attach(media: linkPreviewMedia, to: .linkPreview(linkPreview), using: managedObjectContext)
                }
                linkPreviews.insert(linkPreview)
                feedPost.linkPreviews = linkPreviews
            }

            self.save(managedObjectContext)

            // 2. Upload any media if necesary.
            if let itemsToUpload = feedPost.media?.sorted(by: { $0.order < $1.order }), !itemsToUpload.isEmpty {
                self.upload(media: itemsToUpload, postOrMessageOrLinkPreviewId: postId, managedObjectContext: managedObjectContext) { (allItemsUploaded) in
                    if allItemsUploaded {
                        // Send if all items have been uploaded.
                        self.send(post: feedPost, completion: completion)
                    } else {
                        completion(.failure(ShareError.mediaUploadFailed))
                    }
                }
            } else if let linkPreview = feedPost.linkPreviews?.first, let itemsToUpload = linkPreview.media {
                self.upload(media: itemsToUpload.sorted(by: { $0.order < $1.order }), postOrMessageOrLinkPreviewId: linkPreview.id, managedObjectContext: managedObjectContext) { (allItemsUploaded) in
                    if allItemsUploaded {
                        // Send if all items have been uploaded.
                        self.send(post: feedPost, completion: completion)
                    } else {
                        completion(.failure(ShareError.mediaUploadFailed))
                    }
                }
            } else {
                // Send immediately.
                self.send(post: feedPost, completion: completion)
            }
        }
    }

    private func send(post feedPost: FeedPost, completion: @escaping (Result<String, Error>) -> ()) {
        let feed: Feed
        if let groupId = feedPost.groupId, !groupId.isEmpty {
            feed = .group(groupId)
        } else {
            guard let postAudience = feedPost.audience else {
                DDLogError("SharedDataStore/send-post/\(feedPost.id) No audience set")
                feedPost.status = .sendError
                save(feedPost.managedObjectContext!)
                return
            }

            feed = .personal(postAudience)
        }

        let managedObjectContext = feedPost.managedObjectContext!

        DDLogError("SharedDataStore/post/\(feedPost.id)/send")

        service.publishPost(feedPost.postData, feed: feed) { result in
            switch result {
            case .success(let timestamp):
                DDLogError("SharedDataStore/post/\(feedPost.id)/send/complete")

                feedPost.status = .sent
                feedPost.timestamp = timestamp
                self.save(managedObjectContext)

                // Update messageIds to be re-processed by the main-app.
                var sharePostIds = AppContext.shared.userDefaults.value(forKey: AppContext.shareExtensionPostsKey) as? [FeedPostID] ?? []
                sharePostIds.append(feedPost.id)
                AppContext.shared.userDefaults.set(Array(Set(sharePostIds)), forKey: AppContext.shareExtensionPostsKey)

                completion(.success(feedPost.id))

            case .failure(let error):
                DDLogError("SharedDataStore/post/\(feedPost.id)/send/error \(error)")

                if error.isKnownFailure {
                    feedPost.status = .sendError
                    self.save(managedObjectContext)
                }

                completion(.failure(error))
            }
        }
    }
    
    func send(to userId: UserID, text: String, media: [PendingMedia], linkPreviewData: LinkPreviewData? = nil, linkPreviewMedia: PendingMedia? = nil, completion: @escaping (Result<String, Error>) -> ()) {

        let messageId = UUID().uuidString
        let isMsgToYourself: Bool = userId == AppContext.shared.userData.userId
        
        DDLogInfo("SharedDataStore/message/\(messageId)/created")
        
        // 1. Save message to the db and copy media to permanent storage directory.
        AppContext.shared.mainDataStore.saveSeriallyOnBackgroundContext { managedObjectContext in
            let chatMessage = ChatMessage(context: managedObjectContext)
            chatMessage.id = messageId
            chatMessage.toUserId = userId
            chatMessage.fromUserId = AppContext.shared.userData.userId
            chatMessage.rawText = text
            chatMessage.incomingStatus = .none
            chatMessage.outgoingStatus = isMsgToYourself ? .seen : .pending
            chatMessage.timestamp = Date()
            let serialID = AppContext.shared.getchatMsgSerialId()
            DDLogDebug("ChatData/createChatMsg/\(messageId)/serialId [\(serialID)]")
            chatMessage.serialID = serialID

            var lastMsgMediaType: CommonThread.LastMediaType = .none
            media.forEach { (mediaItem) in
                self.attach(media: mediaItem, to: .message(chatMessage), using: managedObjectContext)
                if lastMsgMediaType == .none {
                    switch mediaItem.type {
                    case .image:
                        lastMsgMediaType = .image
                    case .video:
                        lastMsgMediaType = .video
                    case .audio:
                        lastMsgMediaType = .audio
                    }
                }
            }
            chatMessage.media?.forEach({ $0.status = .uploading })

            //Process LinkPreviews
            if let linkPreviewData = linkPreviewData {
                var linkPreviews: Set<CommonLinkPreview> = []
                DDLogDebug("NotificationExtension/DataStore/new-chat/add-link-preview [\(linkPreviewData.url)]")
                let linkPreview = CommonLinkPreview(context: managedObjectContext)
                linkPreview.id = UUID().uuidString
                linkPreview.url = linkPreviewData.url
                linkPreview.title = linkPreviewData.title
                linkPreview.desc = linkPreviewData.description
                // Set preview image if present
                if let linkPreviewMedia = linkPreviewMedia {
                    self.attach(media: linkPreviewMedia, to: .linkPreview(linkPreview), using: managedObjectContext)
                }
                linkPreview.media?.forEach({ $0.status = .uploading })
                linkPreviews.insert(linkPreview)
                chatMessage.linkPreviews = linkPreviews
            }

            // Update Chat Thread
            if let chatThread = AppContext.shared.mainDataStore.chatThread(type: .oneToOne, id: chatMessage.toUserID, in: managedObjectContext) {
                chatThread.userID = chatMessage.toUserId
                chatThread.lastMsgId = chatMessage.id
                chatThread.lastMsgUserId = chatMessage.fromUserId
                chatThread.lastMsgText = chatMessage.rawText
                chatThread.lastMsgMediaType = lastMsgMediaType
                chatThread.lastMsgStatus = .none
                chatThread.lastMsgTimestamp = chatMessage.timestamp
            } else {
                let chatThread = CommonThread(context: managedObjectContext)
                chatThread.userID = chatMessage.toUserId
                chatThread.lastMsgId = chatMessage.id
                chatThread.lastMsgUserId = chatMessage.fromUserId
                chatThread.lastMsgText = chatMessage.rawText
                chatThread.lastMsgMediaType = lastMsgMediaType
                chatThread.lastMsgStatus = .none
                chatThread.lastMsgTimestamp = chatMessage.timestamp
            }

            self.save(managedObjectContext)

            // 2. Upload any media if necesary.
            if let itemsToUpload = chatMessage.media?.sorted(by: { $0.order < $1.order }), !itemsToUpload.isEmpty {
                self.upload(media: itemsToUpload, postOrMessageOrLinkPreviewId: messageId, managedObjectContext: managedObjectContext) { (allItemsUploaded) in
                    if allItemsUploaded {
                        // Send if all items have been uploaded.
                        self.send(message: chatMessage, completion: completion)
                    } else {
                        completion(.failure(ShareError.mediaUploadFailed))
                    }
                }
            } else if let linkPreview = chatMessage.linkPreviews?.first, let itemsToUpload = linkPreview.media {
                self.upload(media: itemsToUpload.sorted(by: { $0.order < $1.order }), postOrMessageOrLinkPreviewId: linkPreview.id, managedObjectContext: managedObjectContext) { (allItemsUploaded) in
                    if allItemsUploaded {
                        // Send if all items have been uploaded.
                        self.send(message: chatMessage, completion: completion)
                    } else {
                        completion(.failure(ShareError.mediaUploadFailed))
                    }
                }
            } else {
                // Send immediately.
                self.send(message: chatMessage, completion: completion)
            }
        }
    }

    private func send(message: ChatMessage, completion: @escaping (Result<String, Error>) -> ()) {
        let xmppChatMessage = XMPPChatMessage(chatMessage: message)
        service.sendChatMessage(xmppChatMessage) { result in
            switch result {
            case .success:
                // Found a case with chatMsg.status=sent but the shared.outgoingStatus=.uploading
                // not clear how that can happen? check with team on this.
                AppContext.shared.mainDataStore.performSeriallyOnBackgroundContext { _ in
                    if let managedObjectContext = message.managedObjectContext {
                        message.outgoingStatus = .sentOut
                        self.save(managedObjectContext)
                    }
                }

                // Update messageIds to be re-processed by the main-app.
                var shareChatMsgIds = AppContext.shared.userDefaults.value(forKey: AppContext.shareExtensionMessagesKey) as? [ChatMessageID] ?? []
                shareChatMsgIds.append(xmppChatMessage.id)
                AppContext.shared.userDefaults.set(Array(Set(shareChatMsgIds)), forKey: AppContext.shareExtensionMessagesKey)

                // ShareExtensions can die quickly. Give it some time to send enqueued posts or messages.
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                    completion(.success(message.id))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}


extension SharedMedia: MediaUploadable {

    var encryptedFilePath: String? {
        return relativeFilePath?.appending(".enc")
    }

    var index: Int {
        get { Int(order) }
    }

    var urlInfo: MediaURLInfo? {
        if let uploadUrl = uploadUrl {
            if let downloadUrl = url {
                return .getPut(downloadUrl, uploadUrl)
            } else {
                return .patch(uploadUrl)
            }
        } else {
            if let downloadUrl = url {
                return .download(downloadUrl)
            } else {
                return nil
            }
        }
    }
}
