//
//  ShareExtensionDataStore.swift
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

class ShareExtensionDataStore: SharedDataStore {

    private let xmppController: XMPPController
    private let mediaUploader: MediaUploader

    init(xmppController: XMPPController) {
        self.xmppController = xmppController
        mediaUploader = MediaUploader(xmppController: xmppController)
        super.init()
        mediaUploader.resolveMediaPath = { (relativeMediaPath) in
            return Self.fileURL(forRelativeFilePath: relativeMediaPath)
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
                mediaItem.uploadUrl = mediaURLs.put
                mediaItem.url = mediaURLs.get
                self.save(managedObjectContext)
            }) { (uploadResult) in
                DDLogInfo("SharedDataStore/upload-media/\(mediaIndex)/finished result=[\(uploadResult)]")

                // Save URLs acquired during upload to the database.
                switch uploadResult {
                case .success(_):
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

    public typealias SharePostCompletion = (Result<FeedPostID, Error>) -> ()
    
    func post(text: String, media: [PendingMedia], completion: @escaping SharePostCompletion) {
        let postId: FeedPostID = UUID().uuidString
        DDLogInfo("SharedDataStore/post/\(postId)/created")

        // 1. Save post to the db and copy media to permanent storage directory.
        let managedObjectContext = persistentContainer.viewContext
        let feedPost = NSEntityDescription.insertNewObject(forEntityName: SharedFeedPost.entity().name!, into: managedObjectContext) as! SharedFeedPost
        feedPost.id = postId
        feedPost.text = text
        feedPost.timestamp = Date()
        feedPost.userId = AppContext.shared.userData.userId
        feedPost.status = .none
        
        media.forEach { (mediaItem) in
            attach(media: mediaItem, to: .post(feedPost), using: managedObjectContext)
        }
        feedPost.media?.forEach({ $0.status = .uploading })
        
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
        let managedObjectContext = feedPost.managedObjectContext!

        DDLogError("SharedDataStore/post/\(feedPost.id)/send")

        let request = XMPPPostItemRequest(feedItem: feedPost, feedOwnerId: feedPost.userId) { (result) in
            switch result {
            case .success(let timestamp):
                DDLogError("SharedDataStore/post/\(feedPost.id)/send/complete")

                feedPost.status = .sent
                if let timestamp = timestamp {
                    feedPost.timestamp = timestamp
                }
                self.save(managedObjectContext)

                completion(.success(feedPost.id))

            case .failure(let error):
                DDLogError("SharedDataStore/post/\(feedPost.id)/send/error \(error)")

                feedPost.status = .sendError
                self.save(managedObjectContext)

                completion(.failure(error))
            }
        }
        xmppController.enqueue(request: request)
    }

    public typealias SendMessageCompletion = (Result<String, Error>) -> ()
    
    func send(to userId: UserID, text: String, media: [PendingMedia], completion: @escaping SendMessageCompletion) {

        let messageId = UUID().uuidString
        
        DDLogInfo("SharedDataStore/message/\(messageId)/created")
        
        // 1. Save message to the db and copy media to permanent storage directory.
        let managedObjectContext = persistentContainer.viewContext
        let chatMessage = NSEntityDescription.insertNewObject(forEntityName: SharedChatMessage.entity().name!, into: managedObjectContext) as! SharedChatMessage
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

        xmppController.xmppStream.send(message.xmppElement)
        // TODO: Find a way to detect send error
        completion(.success(message.id))
    }
}


extension SharedMedia: MediaUploadable {

    var encryptedFilePath: String? {
        return relativeFilePath.appending(".enc")
    }

    var index: Int {
        get { Int(order) }
    }
}
