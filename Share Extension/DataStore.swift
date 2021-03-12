//
//  DataStore.swift
//  Share Extension
//
//  Created by Alan Luo on 7/27/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import CoreData

enum ShareExtensionError: Error {
    case mediaUploadFailed
}

class DataStore: ShareExtensionDataStore {

    private let service: CoreService
    private let mediaUploader: MediaUploader

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
            mediaUploader.upload(media: mediaItem, groupId: postOrMessageId, didGetURLs: { (mediaURLs) in
                DDLogInfo("SharedDataStore/upload-media/\(mediaIndex)/acquired-urls [\(mediaURLs)]")

                // Save URLs acquired during upload to the database.
                switch mediaURLs {
                case .getPut(let getURL, let putURL):
                    mediaItem.uploadUrl = putURL
                    mediaItem.url = getURL

                case .patch(let patchURL):
                    mediaItem.uploadUrl = patchURL
                }
                self.save(managedObjectContext)
            }) { (uploadResult) in
                DDLogInfo("SharedDataStore/upload-media/\(mediaIndex)/finished result=[\(uploadResult)]")

                // Save URLs acquired during upload to the database.
                switch uploadResult {
                case .success(let details):
                    mediaItem.url = details.downloadURL
                    mediaItem.status = .uploaded

                case .failure(_):
                    numberOfFailedUploads += 1
                    mediaItem.status = .error
                }
                self.save(managedObjectContext)

                uploadGroup.leave()
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

    private func attach(media: PendingMedia, to target: PostOrMessage, using managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("SharedDataStore/attach-media [\(media.fileURL!)]")

        let feedMedia = NSEntityDescription.insertNewObject(forEntityName: "SharedMedia", into: managedObjectContext) as! SharedMedia
        feedMedia.type = media.type
        feedMedia.url = media.url
        feedMedia.uploadUrl = media.uploadUrl
        feedMedia.size = media.size!
        feedMedia.key = media.key!
        feedMedia.sha256 = media.sha256!
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

    public typealias SharePostCompletion = (Result<FeedPostID, Error>) -> ()
    
    func post(text: MentionText, media: [PendingMedia], completion: @escaping SharePostCompletion) {
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
        for (index, userID) in text.mentions {
            let feedMention = NSEntityDescription.insertNewObject(forEntityName: "SharedFeedMention", into: managedObjectContext) as! SharedFeedMention
            feedMention.index = index
            feedMention.userID = userID
            feedMention.name = AppContext.shared.contactStore.pushNames[userID] ?? ""
            if feedMention.name == "" {
                DDLogError("SharedDataStore/send-post/mention/\(userID) missing push name")
            }
            mentionSet.insert(feedMention)
        }
        feedPost.mentions = mentionSet
        
        media.forEach { (mediaItem) in
            attach(media: mediaItem, to: .post(feedPost), using: managedObjectContext)
        }
        feedPost.media?.forEach({ $0.status = .uploading })

        let postAudience = try! ShareExtensionContext.shared.privacySettings.currentFeedAudience()
        feedPost.privacyListType = postAudience.privacyListType
        feedPost.audienceUserIds = Array(postAudience.userIds)

        save(managedObjectContext)

        // 2. Upload any media if necesary.
        if let itemsToUpload = feedPost.media?.sorted(by: { $0.order < $1.order }), !itemsToUpload.isEmpty {
            upload(media: itemsToUpload, postOrMessageId: postId, managedObjectContext: managedObjectContext) { (allItemsUploaded) in
                if allItemsUploaded {
                    // Send if all items have been uploaded.
                    self.send(post: feedPost, completion: completion)
                } else {
                    completion(.failure(ShareExtensionError.mediaUploadFailed))
                }
            }
        } else {
            // Send immediately.
            send(post: feedPost, completion: completion)
        }
    }

    private func send(post feedPost: SharedFeedPost, completion: @escaping SharePostCompletion) {
        guard let postAudience = feedPost.audience else {
            DDLogError("SharedDataStore/send-post/\(feedPost.id) No audience set")
            feedPost.status = .sendError
            save(feedPost.managedObjectContext!)
            return
        }

        let managedObjectContext = feedPost.managedObjectContext!

        DDLogError("SharedDataStore/post/\(feedPost.id)/send")

        service.publishPost(feedPost, feed: .personal(postAudience)) { result in
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

    public typealias SendMessageCompletion = (Result<String, Error>) -> ()
    
    func send(to userId: UserID, text: String, media: [PendingMedia], completion: @escaping SendMessageCompletion) {

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
        chatMessage.timestamp = Date()
        
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
                    completion(.failure(ShareExtensionError.mediaUploadFailed))
                }
            }
        } else {
            // Send immediately.
            send(message: chatMessage, completion: completion)
        }
    }

    private func send(message: SharedChatMessage, completion: @escaping SendMessageCompletion) {
        if let managedObjectContext = message.managedObjectContext {
            message.status = .sent
            save(managedObjectContext)
        }

        service.sendChatMessage(message) { result in
            switch result {
            case .success:
                completion(.success(message.id))
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
        guard let uploadUrl = uploadUrl else {
            return nil
        }
        if let downloadUrl = url {
            return .getPut(downloadUrl, uploadUrl)
        } else {
            return .patch(uploadUrl)
        }
    }
}
