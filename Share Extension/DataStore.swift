//
//  DataStore.swift
//  Share Extension
//
//  Created by Alan Luo on 7/27/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreData

class DataStore: ShareExtensionDataStore {

    private let service: CoreService
    private let mediaUploader: MediaUploader
    private let imageServer = ImageServer()

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
    private func upload(media mediaItemsToUpload: [SharedMedia], postOrMessageId: String, managedObjectContext: NSManagedObjectContext, completion: @escaping (Bool) -> ()) {
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
                let path = Self.relativeFilePath(forFilename: UUID().uuidString + ".processed", mediaType: mediaItem.type)
                let output = fileURL(forRelativeFilePath: path)

                imageServer.prepare(mediaItem.type, url: url, output: output) { [weak self] in
                    guard let self = self else { return }

                    switch $0 {
                    case .success(let result):
                        mediaItem.size = result.size
                        mediaItem.key = result.key
                        mediaItem.sha256 = result.sha256
                        mediaItem.relativeFilePath = path
                        self.save(managedObjectContext)
                        self.uploadMedia(mediaItem: mediaItem, postOrMessageId: postOrMessageId, in: managedObjectContext, completion: onUploadCompletion)
                    case .failure(_):
                        numberOfFailedUploads += 1

                        mediaItem.status = .error
                        self.save(managedObjectContext)

                        uploadGroup.leave()
                    }
                }
            } else {
                self.uploadMedia(mediaItem: mediaItem, postOrMessageId: postOrMessageId, in: managedObjectContext, completion: onUploadCompletion)
            }
        }

        uploadGroup.notify(queue: .main) {
            guard !self.isSendingCanceled else {
                DDLogWarn("SharedDataStore/upload-media/canceled Will not call completion handler")
                return
            }
            DDLogInfo("SharedDataStore/upload-media/all/finished [\(totalUploads-numberOfFailedUploads)/\(totalUploads)]")
            completion(numberOfFailedUploads == 0)
        }
    }

    private func uploadMedia(mediaItem: SharedMedia, postOrMessageId: String, in managedObjectContext: NSManagedObjectContext, completion: @escaping MediaUploader.Completion) {
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
            DDLogError("SharedDataStore/uploadMedia/\(postOrMessageId)/\(mediaIndex) missing file path")
            return completion(.failure(MediaUploadError.unknownError))
        }
        let processed = fileURL(forRelativeFilePath: relativeFilePath)
        AppContext.shared.mediaHashStore.fetch(url: processed) { [weak self] upload in
            guard let self = self else { return }
            if let url = upload?.url {
                DDLogInfo("Media \(processed) has been uploaded before at \(url).")
                if let uploadUrl = mediaItem.uploadUrl {
                    DDLogInfo("SharedDataStore/uploadMedia/upload url is supposed to be nil here/\(postOrMessageId)/\(mediaIndex), uploadUrl: \(uploadUrl)")
                    // we set it to be nil here explicitly.
                    mediaItem.uploadUrl = nil
                }
                mediaItem.url = url
            } else {
                DDLogInfo("SharedDataStore/uploadMedia/uploading media now/\(postOrMessageId)/\(mediaItem.order), index:\(mediaIndex)")
            }

            self.mediaUploader.upload(media: mediaItem, groupId: postOrMessageId, didGetURLs: onDidGetURLs) { (uploadResult) in
                switch uploadResult {
                case .success(let details):
                    mediaItem.url = details.downloadURL
                    mediaItem.status = .uploaded

                    // If the download url was successfully refreshed - then use the old key and old hash.
                    if mediaItem.url == upload?.url, let key = upload?.key, let sha256 = upload?.sha256 {
                        mediaItem.key = key
                        mediaItem.sha256 = sha256
                    }
                    AppExtensionContext.shared.mediaHashStore.update(url: processed, key: mediaItem.key, sha256: mediaItem.sha256, downloadURL: mediaItem.url!)
                case .failure(let error):
                    DDLogError("SharedDataStore/uploadMedia/failed to upload media, error: \(error)")
                    mediaItem.status = .error
                }
                self.save(managedObjectContext)
                completion(uploadResult)
            }
        }
    }

    private func attach(media: PendingMedia, to target: PostOrMessage, using managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("SharedDataStore/attach-media [\(media.fileURL!)]")

        let feedMedia = NSEntityDescription.insertNewObject(forEntityName: "SharedMedia", into: managedObjectContext) as! SharedMedia
        feedMedia.type = media.type
        feedMedia.url = media.url
        feedMedia.uploadUrl = media.uploadUrl
        feedMedia.size = media.size!
        feedMedia.key = ""
        feedMedia.sha256 = ""
        feedMedia.order = Int16(media.order)

        switch target {
        case .post(let feedPost):
            feedMedia.post = feedPost
        case .message(let chatMessage):
            feedMedia.message = chatMessage
        }

        let relativeFilePath = Self.relativeFilePath(forFilename: UUID().uuidString, mediaType: media.type)

        do {
            let destinationUrl = fileURL(forRelativeFilePath: relativeFilePath)
            Self.preparePathForWriting(destinationUrl)

            // Copy unencrypted media file.
            if let sourceUrl = media.fileURL {
                try FileManager.default.copyItem(at: sourceUrl, to: destinationUrl)
                DDLogDebug("SharedDataStore/attach-media/ copied [\(sourceUrl)] to [\(destinationUrl)]")

                feedMedia.relativeFilePath = relativeFilePath
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

    func post(group: GroupListItem? = nil, text: MentionText, media: [PendingMedia], completion: @escaping (Result<String, Error>) -> ()) {
        let postId: FeedPostID = UUID().uuidString
        DDLogInfo("SharedDataStore/post/\(postId)/created")

        // 1. Save post to the db and copy media to permanent storage directory.
        let managedObjectContext = persistentContainer.viewContext
        let feedPost = NSEntityDescription.insertNewObject(forEntityName: "SharedFeedPost", into: managedObjectContext) as! SharedFeedPost
        feedPost.id = postId
        feedPost.text = text.collapsedText
        feedPost.timestamp = Date()
        feedPost.userId = AppContext.shared.userData.userId
        feedPost.status = .none

        // Add mentions
        var mentionSet = Set<SharedFeedMention>()
        for (index, user) in text.mentions {
            let feedMention = NSEntityDescription.insertNewObject(forEntityName: "SharedFeedMention", into: managedObjectContext) as! SharedFeedMention
            feedMention.index = index
            feedMention.userID = user.userID
            feedMention.name = AppContext.shared.contactStore.pushNames[user.userID] ?? user.pushName ?? ""
            if feedMention.name == "" {
                DDLogError("SharedDataStore/send-post/mention/\(user.userID) missing push name")
            }
            mentionSet.insert(feedMention)
        }
        feedPost.mentions = mentionSet
        
        media.forEach { (mediaItem) in
            attach(media: mediaItem, to: .post(feedPost), using: managedObjectContext)
        }
        feedPost.media?.forEach({ $0.status = .uploading })

        if let group = group {
            feedPost.groupId = group.id
            feedPost.audienceType = .group
            feedPost.audienceUserIds = group.users
        } else {
            let postAudience = try! ShareExtensionContext.shared.privacySettings.currentFeedAudience()
            feedPost.audienceType = postAudience.audienceType
            feedPost.audienceUserIds = Array(postAudience.userIds)
        }

        save(managedObjectContext)

        // All this code is not great - we are using viewContext to perform all Coredata write operations here
        // and we are passing coredata objects across threads.
        // it will result in unexpected behaviors at times.
        // TOOD: check with team and refactor this code.

        // 2. Upload any media if necesary.
        if let itemsToUpload = feedPost.media?.sorted(by: { $0.order < $1.order }), !itemsToUpload.isEmpty {
            upload(media: itemsToUpload, postOrMessageId: postId, managedObjectContext: managedObjectContext) { (allItemsUploaded) in
                if allItemsUploaded {
                    // Send if all items have been uploaded.
                    self.send(post: feedPost, completion: completion)
                } else {
                    completion(.failure(ShareError.mediaUploadFailed))
                }
            }
        } else {
            // Send immediately.
            send(post: feedPost, completion: completion)
        }
    }

    private func send(post feedPost: SharedFeedPost, completion: @escaping (Result<String, Error>) -> ()) {
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
    
    func send(to userId: UserID, text: String, media: [PendingMedia], completion: @escaping (Result<String, Error>) -> ()) {

        let messageId = UUID().uuidString
        
        DDLogInfo("SharedDataStore/message/\(messageId)/created")
        
        // 1. Save message to the db and copy media to permanent storage directory.
        let managedObjectContext = persistentContainer.viewContext
        let chatMessage = NSEntityDescription.insertNewObject(forEntityName: "SharedChatMessage", into: managedObjectContext) as! SharedChatMessage
        chatMessage.id = messageId
        chatMessage.toUserId = userId
        chatMessage.fromUserId = AppContext.shared.userData.userId
        chatMessage.text = text
        chatMessage.status = .none
        chatMessage.clientChatMsgPb = nil
        chatMessage.senderClientVersion = nil
        chatMessage.decryptionError = nil
        chatMessage.ephemeralKey = nil
        chatMessage.timestamp = Date()
        let serialID = AppContext.shared.getchatMsgSerialId()
        DDLogInfo("SharedDataStore/message/\(messageId)/created/serialId \(serialID)")
        chatMessage.serialID = serialID
        
        media.forEach { (mediaItem) in
            attach(media: mediaItem, to: .message(chatMessage), using: managedObjectContext)
        }
        chatMessage.media?.forEach({ $0.status = .uploading })
        
        save(managedObjectContext)

        // 2. Upload any media if necesary.
        if let itemsToUpload = chatMessage.media?.sorted(by: { $0.order < $1.order }), !itemsToUpload.isEmpty {
            upload(media: itemsToUpload, postOrMessageId: messageId, managedObjectContext: managedObjectContext) { (allItemsUploaded) in
                if allItemsUploaded {
                    // Send if all items have been uploaded.
                    self.send(message: chatMessage, completion: completion)
                } else {
                    completion(.failure(ShareError.mediaUploadFailed))
                }
            }
        } else {
            // Send immediately.
            send(message: chatMessage, completion: completion)
        }
    }

    private func send(message: SharedChatMessage, completion: @escaping (Result<String, Error>) -> ()) {
        // Found a case with chatMsg.status=sent but the shared.outgoingStatus=.uploading
        // not clear how that can happen? check with team on this.
        if let managedObjectContext = message.managedObjectContext {
            message.status = .sent
            save(managedObjectContext)
        }

        service.sendChatMessage(message) { result in
            switch result {
            case .success:
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
