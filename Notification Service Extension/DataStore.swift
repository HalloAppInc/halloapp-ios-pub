//
//  DataStore.swift
//  Notification Service Extension
//
//  Created by Igor Solomennikov on 9/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import CoreData

class DataStore: NotificationServiceExtensionDataStore {

    func save(postData: PostData?, status: SharedFeedPost.Status, notificationMetadata: NotificationMetadata, completion: @escaping (SharedFeedPost) -> ()) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in

            // set a merge policy so that we dont end up with duplicate feedposts.
            managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

            let userId = notificationMetadata.fromId
            let postId = notificationMetadata.contentId

            let fetchRequest: NSFetchRequest<SharedFeedPost> = SharedFeedPost.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", postId)
            do {
                let existingPost = try managedObjectContext.fetch(fetchRequest).first
                if let sharedExistingPost = existingPost {
                    if sharedExistingPost.status == .received {
                        DDLogInfo("NotificationExtension/DataStore/duplicate-post/id=[\(postId)]")
                        // post was already processed and stored, so just return
                    } else {
                        DDLogInfo("NotificationExtension/DataStore/update-post/id=[\(postId)]")
                        // post fallback to unencrypted content: just update status now, save and return
                        sharedExistingPost.status = status
                        self.save(managedObjectContext)
                    }
                    completion(sharedExistingPost)
                    return
                }
            } catch {
                DDLogError("NotificationExtension/DataStore/feedPosts/error  [\(error)]")
            }

            DDLogInfo("NotificationExtension/DataStore/post/\(postId)/create")

            let feedPost = NSEntityDescription.insertNewObject(forEntityName: "SharedFeedPost", into: managedObjectContext) as! SharedFeedPost
            feedPost.id = postId
            feedPost.userId = userId
            feedPost.groupId = notificationMetadata.groupId
            feedPost.text = postData?.text
            feedPost.status = status
            feedPost.timestamp = notificationMetadata.timestamp ?? Date()

            switch postData?.content {
            case .album, .text, .retracted, .none, .voiceNote, .waiting:
                feedPost.rawData = nil
            case .unsupported(let data):
                feedPost.rawData = data
            }

            // Add mentions
            var mentions: Set<SharedFeedMention> = []
            for protoMention in postData?.orderedMentions ?? [] {
                let mention = NSEntityDescription.insertNewObject(forEntityName: "SharedFeedMention", into: managedObjectContext) as! SharedFeedMention
                mention.index = Int(protoMention.index)
                mention.userID = protoMention.userID
                mention.name = protoMention.name
                mentions.insert(mention)
            }
            feedPost.mentions = mentions
            
            // Post Audience
            if let audience = postData?.audience {
                feedPost.audienceType = audience.audienceType
                feedPost.audienceUserIds = Array(audience.userIds)
            }

            // Add link previews
            var linkPreviews: Set<SharedFeedLinkPreview> = []
            postData?.linkPreviewData.forEach { linkPreviewData in
                DDLogDebug("NotificationExtension/DataStore/new-comment/add-link-preview [\(linkPreviewData.url)]")
                let linkPreview = NSEntityDescription.insertNewObject(forEntityName: SharedFeedLinkPreview.entity().name!, into: managedObjectContext) as! SharedFeedLinkPreview
                linkPreview.id = PacketID.generate()
                linkPreview.url = linkPreviewData.url
                linkPreview.title = linkPreviewData.title
                linkPreview.desc = linkPreviewData.description
//                linkPreview.post = feedPost
                // Set preview image if present
                linkPreviewData.previewImages.forEach { previewMedia in
                    let media = NSEntityDescription.insertNewObject(forEntityName: SharedMedia.entity().name!, into: managedObjectContext) as! SharedMedia
                    media.type = previewMedia.type
                    media.status = .none
                    media.url = previewMedia.url
                    media.size = previewMedia.size
                    media.key = previewMedia.key
                    media.sha256 = previewMedia.sha256
                    media.linkPreview = linkPreview
                }
                linkPreviews.insert(linkPreview)
            }
            feedPost.linkPreviews = linkPreviews

            // Add media
            var postMedia: Set<SharedMedia> = []
            for (index, feedPostMedia) in postData?.orderedMedia.enumerated() ?? [].enumerated() {
                guard let mediaType: FeedMediaType = {
                    switch feedPostMedia.type {
                    case .image: return .image
                    case .video: return .video
                    case .audio: return .audio
                    }}() else { continue }
                let media = NSEntityDescription.insertNewObject(forEntityName: "SharedMedia", into: managedObjectContext) as! SharedMedia
                media.type = mediaType
                media.status = .none
                media.url = feedPostMedia.url
                media.size = feedPostMedia.size
                media.key = feedPostMedia.key
                media.sha256 = feedPostMedia.sha256
                media.blobVersion = feedPostMedia.blobVersion
                media.chunkSize = feedPostMedia.chunkSize
                media.blobSize = feedPostMedia.blobSize
                media.order = Int16(index)
                postMedia.insert(media)
            }
            feedPost.media = postMedia

            // set a merge policy so that we dont end up with duplicate feedposts.
            managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            self.save(managedObjectContext)

            completion(feedPost)
        }
    }
    
    func save(commentData: CommentData?, status: SharedFeedComment.Status, notificationMetadata: NotificationMetadata, completion: @escaping (SharedFeedComment) -> ()) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in

            managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

            // Extract info from parameters
            let userId = notificationMetadata.fromId
            let commentId = notificationMetadata.contentId
            guard let postId = notificationMetadata.feedPostId else {
                DDLogError("NotificationExtension/DataStore/new-comment/\(commentId) - invalid feedPostId")
                return
            }
            let parentCommentId = notificationMetadata.parentId?.isEmpty ?? true ? nil : notificationMetadata.parentId

            // TODO: If this function was called twice on the same comment
            // We would end up inserting multiple media items on the same comment.
            // We have a unique-key constraint on the contentId of the comment but not on the media items.
            // We should have an id for the media item: which is (contentId-index) and use this as the key everywhere.
            // That should prevent duplicates being inserted everywhere in the main app and all the extensions.
            // Check with team on this?
            let fetchRequest: NSFetchRequest<SharedFeedComment> = SharedFeedComment.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", commentId)
            do {
                let existingComment = try managedObjectContext.fetch(fetchRequest).first
                if let sharedExistingComment = existingComment {
                    if sharedExistingComment.status == .received {
                        DDLogInfo("NotificationExtension/DataStore/duplicate-comment/id=[\(commentId)]  postId=[\(postId)]")
                        // comment was already processed and stored, so just return
                    } else {
                        DDLogInfo("NotificationExtension/DataStore/update-comment/id=[\(commentId)]  postId=[\(postId)]")
                        // comment fallback to unencrypted content: just update status now, save and return
                        sharedExistingComment.status = status
                        self.save(managedObjectContext)
                    }
                    completion(sharedExistingComment)
                    return
                }
            } catch {
                DDLogError("SharedDataStore/feedPosts/error  [\(error)]")
            }

            // Create comment
            DDLogInfo("NotificationExtension/DataStore/new-comment/create id=[\(commentId)]  postId=[\(postId)]")
            let feedComment = NSEntityDescription.insertNewObject(forEntityName: "SharedFeedComment", into: managedObjectContext) as! SharedFeedComment
            feedComment.id = commentId
            feedComment.userId = userId
            feedComment.postId = postId
            feedComment.parentCommentId = parentCommentId
            feedComment.status = status
            feedComment.timestamp = notificationMetadata.timestamp ?? Date()

            // populate text with empty string as text is required, could be removed if this changes
            switch commentData?.content {
            case .text(let mentionText, let linkPreviewData):
                self.processText(feedComment: feedComment, mentionText: mentionText, linkPreviewData: linkPreviewData, managedObjectContext: managedObjectContext)
                feedComment.rawData = nil
            case .album(let mentionText, let media):
                self.processText(feedComment: feedComment, mentionText: mentionText, linkPreviewData: [], managedObjectContext: managedObjectContext)
                // Process Comment Media
                for (index, mediaItem) in media.enumerated() {
                    DDLogDebug("NotificationExtension/DataStore/add-comment-media [\(mediaItem.url!)]")
                    let feedCommentMedia = NSEntityDescription.insertNewObject(forEntityName: SharedMedia.entity().name!, into: managedObjectContext) as! SharedMedia
                    switch mediaItem.type {
                    case .image:
                        feedCommentMedia.type = .image
                    case .video:
                        feedCommentMedia.type = .video
                    case .audio:
                        feedCommentMedia.type = .audio
                    }
                    feedCommentMedia.status = .none
                    feedCommentMedia.url = mediaItem.url
                    feedCommentMedia.size = mediaItem.size
                    feedCommentMedia.key = mediaItem.key
                    feedCommentMedia.order = Int16(index)
                    feedCommentMedia.sha256 = mediaItem.sha256
                    feedCommentMedia.comment = feedComment
                    feedCommentMedia.blobVersion = mediaItem.blobVersion
                    feedCommentMedia.chunkSize = mediaItem.chunkSize
                    feedCommentMedia.blobSize = mediaItem.blobSize
                }
                feedComment.rawData = nil
            case .voiceNote(let media):
                let feedCommentMedia = SharedMedia(context: managedObjectContext)
                feedCommentMedia.type = .audio
                feedCommentMedia.status = .none
                feedCommentMedia.url = media.url
                feedCommentMedia.size = media.size
                feedCommentMedia.key = media.key
                feedCommentMedia.order = 0
                feedCommentMedia.sha256 = media.sha256
                feedCommentMedia.comment = feedComment
                feedComment.rawData = nil
            case .retracted:
                DDLogError("NotificationExtension/DataStore/incoming-retracted-comment [\(commentId)]")
                feedComment.rawData = nil
            case .unsupported(let data):
                feedComment.rawData = data
            case .waiting, .none:
                feedComment.rawData = nil
            }

            self.save(managedObjectContext)

            completion(feedComment)
        }
    }

    func processText(feedComment: SharedFeedComment, mentionText: MentionText, linkPreviewData: [LinkPreviewData], managedObjectContext: NSManagedObjectContext) {
        feedComment.text = mentionText.collapsedText
        var mentions = Set<SharedFeedMention>()
        for (i, mention) in mentionText.mentions {
            let feedMention = NSEntityDescription.insertNewObject(forEntityName: "SharedFeedMention", into: managedObjectContext) as! SharedFeedMention
            feedMention.index = Int(i)
            feedMention.userID = mention.userID
            feedMention.name = mention.pushName ?? ""
            if feedMention.name == "" {
                DDLogError("NotificationExtension/DataStore/new-comment/mention/\(mention.userID) missing push name")
            }
            mentions.insert(feedMention)
        }
        feedComment.mentions = mentions
        
        // Process url preview if present
        var linkPreviews: Set<SharedFeedLinkPreview> = []
        linkPreviewData.forEach { linkPreviewData in
            DDLogDebug("NotificationExtension/DataStore/new-comment/add-link-preview [\(linkPreviewData.url)]")
            let linkPreview = NSEntityDescription.insertNewObject(forEntityName: SharedFeedLinkPreview.entity().name!, into: managedObjectContext) as! SharedFeedLinkPreview
            linkPreview.id = PacketID.generate()
            linkPreview.url = linkPreviewData.url
            linkPreview.title = linkPreviewData.title
            linkPreview.desc = linkPreviewData.description
            linkPreview.comment = feedComment
            // Set preview image if present
            linkPreviewData.previewImages.forEach { previewMedia in
                let media = NSEntityDescription.insertNewObject(forEntityName: SharedMedia.entity().name!, into: managedObjectContext) as! SharedMedia
                media.type = previewMedia.type
                media.status = .none
                media.url = previewMedia.url
                media.size = previewMedia.size
                media.key = previewMedia.key
                media.sha256 = previewMedia.sha256
                media.linkPreview = linkPreview
            }
            linkPreviews.insert(linkPreview)
        }
        feedComment.linkPreviews = linkPreviews
    }

    func saveServerMsg(notificationMetadata: NotificationMetadata) {
        guard let serverMsgPb = notificationMetadata.serverMsgPb else {
            DDLogError("NotificationExtension/DataStore/serverMsgPb is nil, unable to save Msg")
            return
        }
        DDLogInfo("NotificationExtension/DataStore/saveServerMsg, contentId: \(notificationMetadata.contentId)")
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            let serverMsg = NSEntityDescription.insertNewObject(forEntityName: "SharedServerMessage", into: managedObjectContext) as! SharedServerMessage
            serverMsg.msg = serverMsgPb
            serverMsg.timestamp = notificationMetadata.timestamp ?? Date()
            self.save(managedObjectContext)
        }
    }

    func saveServerMsg(contentId: String, serverMsgPb: Data) {
        DDLogInfo("NotificationExtension/DataStore/saveServerMsg, contentId: \(contentId)")
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            let serverMsg = NSEntityDescription.insertNewObject(forEntityName: "SharedServerMessage", into: managedObjectContext) as! SharedServerMessage
            serverMsg.msg = serverMsgPb
            serverMsg.timestamp = Date()
            self.save(managedObjectContext)
        }
    }

    func insertSharedMedia(for mediaData: XMPPChatMedia, index: Int, into managedObjectContext: NSManagedObjectContext) -> SharedMedia {
        let chatMedia = NSEntityDescription.insertNewObject(forEntityName: "SharedMedia", into: managedObjectContext) as! SharedMedia
        chatMedia.type = {
            switch mediaData.mediaType {
            case .image: return .image
            case .video: return .video
            case .audio: return .audio
            }
        }()
        chatMedia.status = .none
        chatMedia.url = mediaData.url
        chatMedia.uploadUrl = nil
        chatMedia.size = mediaData.size
        chatMedia.key = mediaData.key
        chatMedia.sha256 = mediaData.sha256
        chatMedia.blobVersion = mediaData.blobVersion
        chatMedia.chunkSize = mediaData.chunkSize
        chatMedia.blobSize = mediaData.blobSize
        chatMedia.order = Int16(index)

        return chatMedia
    }

    func save(container: Clients_ChatContainer?, metadata: NotificationMetadata, status: SharedChatMessage.Status, failure: DecryptionFailure?, completion: @escaping (SharedChatMessage) -> ()) {
        performSeriallyOnBackgroundContext { [self] (managedObjectContext) in

            let messageId = metadata.contentId

            // TODO: Need for shared container.
            // Check to make sure we don't overwrite existing chat message in the database.
            let fetchRequest: NSFetchRequest<SharedChatMessage> = SharedChatMessage.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", messageId)
            do {
                let existingMessage = try managedObjectContext.fetch(fetchRequest).first
                if let sharedExistingMessage = existingMessage {
                    if sharedExistingMessage.status == .received {
                        DDLogInfo("NotificationExtension/DataStore/duplicate-message/id=[\(messageId)]/processed successfully")
                        // message was already processed and stored, so just return
                        completion(sharedExistingMessage)
                        return
                    }
                }
            } catch {
                DDLogError("NotificationExtension/SharedDataStore/message/error  [\(error)]")
            }

            DDLogInfo("NotificationExtension/SharedDataStore/message/\(messageId)/created")

            // TODO(murali@): add a field for retryCount of this message if necessary.
            let chatMessage = NSEntityDescription.insertNewObject(forEntityName: "SharedChatMessage", into: managedObjectContext) as! SharedChatMessage
            chatMessage.id = messageId
            chatMessage.toUserId = AppContext.shared.userData.userId
            chatMessage.fromUserId = metadata.fromId
            chatMessage.status = status
            chatMessage.decryptionError = failure?.error.rawValue
            chatMessage.ephemeralKey = failure?.ephemeralKey
            chatMessage.senderClientVersion = metadata.senderClientVersion
            chatMessage.serverMsgPb = metadata.serverMsgPb
            chatMessage.serverTimestamp = metadata.timestamp
            chatMessage.timestamp = metadata.timestamp ?? Date()
            let serialID = AppContext.shared.getchatMsgSerialId()
            DDLogInfo("SharedDataStore/message/\(messageId)/created/serialId \(serialID)")
            chatMessage.serialID = serialID

            switch status {
            case .received:
                guard let container = container else {
                    DDLogInfo("SharedDataStore/message/\(messageId)/missing container")
                    return
                }
                switch container.message {
                case .album(let album):
                    chatMessage.text = album.text.text
                    for (index, mediaItem) in album.media.enumerated() {
                        guard let mediaData = XMPPChatMedia(albumMedia: mediaItem) else { continue }
                        let sharedMedia = insertSharedMedia(for: mediaData, index: index, into: managedObjectContext)
                        sharedMedia.message = chatMessage
                    }
                case .text(let text):
                    chatMessage.text = text.text
                    // Add link previews
                    var linkPreviews: Set<SharedFeedLinkPreview> = []
                    text.linkPreviewData.forEach { linkPreviewData in
                        DDLogDebug("NotificationExtension/DataStore/new-chat/add-link-preview [\(linkPreviewData.url)]")
                        let linkPreview = NSEntityDescription.insertNewObject(forEntityName: SharedFeedLinkPreview.entity().name!, into: managedObjectContext) as! SharedFeedLinkPreview
                        linkPreview.id = PacketID.generate()
                        linkPreview.url = linkPreviewData.url
                        linkPreview.title = linkPreviewData.title
                        linkPreview.desc = linkPreviewData.description
                        // Set preview image if present
                        linkPreviewData.previewImages.forEach { previewMedia in
                            let media = NSEntityDescription.insertNewObject(forEntityName: SharedMedia.entity().name!, into: managedObjectContext) as! SharedMedia
                            media.type = previewMedia.type
                            media.status = .none
                            media.url = previewMedia.url
                            media.size = previewMedia.size
                            media.key = previewMedia.key
                            media.sha256 = previewMedia.sha256
                            media.linkPreview = linkPreview
                        }
                        linkPreviews.insert(linkPreview)
                    }
                    chatMessage.linkPreviews = linkPreviews

                case .contactCard:
                    DDLogInfo("SharedDataStore/message/\(messageId)/unsupported [contact]")
                case .voiceNote(let voiceNote):
                    if let audioMediaData = XMPPChatMedia(audio: voiceNote.audio) {
                        let sharedMedia = insertSharedMedia(for: audioMediaData, index: 0, into: managedObjectContext)
                        sharedMedia.message = chatMessage
                    } else {
                        DDLogError("SharedDataStore/message/\(messageId)/unsupported [voice]")
                    }
                case .none:
                    DDLogInfo("SharedDataStore/message/\(messageId)/unsupported [unknown]")
                }
                chatMessage.clientChatMsgPb = try? container.serializedData()
            case .decryptionError:
                break
            case .acked, .rerequesting:
                // when we save the message initially - status will always be received/decryptionError.
                break
            case .none, .sent, .sendError:
                // not relevant here.
                break
            }
            DDLogInfo("saving message: \(messageId) - \(status)")
            managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            save(managedObjectContext)
            completion(chatMessage)
        }
    }

    func getChatMessagesToAck(completion: @escaping ([SharedChatMessage]) -> ()) {
        performSeriallyOnBackgroundContext { managedObjectContext in

            let fetchRequest: NSFetchRequest<SharedChatMessage> = SharedChatMessage.fetchRequest()

            // We fetch (and ack) these messages in ascending order so the sender receives delivery receipts in order.
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SharedChatMessage.timestamp, ascending: true)]

            var messagesToAck = [SharedChatMessage]()
            do {
                let chatMessages = try managedObjectContext.fetch(fetchRequest)
                for message in chatMessages {
                    DDLogInfo("message : \(message.id)")
                    switch message.status {
                    case .received, .rerequesting:
                        messagesToAck.append(message)
                    case .acked, .decryptionError:
                        break
                    case .sent, .sendError, .none:
                        DDLogError("NotificationExtension/getChatMessagesToAck/unexpected-status [\(message.status)] [\(message.id)]")
                    }
                }
            } catch {
                DDLogError("NotificationExtension/SharedDataStore/getChatMessagesToAck/error  [\(error)]")
            }
            DDLogInfo("NotificationExtension/SharedDataStore/getChatMessagesToAck - num: \(messagesToAck.count)")
            completion(messagesToAck)
        }
    }

    func getChatMessagesToRerequest(completion: @escaping ([SharedChatMessage]) -> ()) {
        performSeriallyOnBackgroundContext { managedObjectContext in
            let fetchRequest: NSFetchRequest<SharedChatMessage> = SharedChatMessage.fetchRequest()
            // We fetch (and rerequest) these messages in ascending order.
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SharedChatMessage.timestamp, ascending: true)]

            var messagesToRerequest = [SharedChatMessage]()
            do {
                let chatMessages = try managedObjectContext.fetch(fetchRequest)
                for message in chatMessages {
                    switch message.status {
                    case .decryptionError:
                        messagesToRerequest.append(message)
                    case .acked, .received, .rerequesting:
                        break
                    case .sent, .sendError, .none:
                        DDLogError("NotificationExtension/getChatMessagesToRerequest/unexpected-status [\(message.status)] [\(message.id)]")
                    }
                }
            } catch {
                DDLogError("NotificationExtension/SharedDataStore/getChatMessagesToRerequest/error  [\(error)]")
            }
            DDLogInfo("NotificationExtension/SharedDataStore/getChatMessagesToRerequest - num: \(messagesToRerequest.count)")
            completion(messagesToRerequest)
        }
    }

    func sharedMediaObject(forObjectId objectId: NSManagedObjectID) throws -> SharedMedia? {
        return try persistentContainer.viewContext.existingObject(with: objectId) as? SharedMedia
    }

    func updateMessageStatus(for msgId: String, status: SharedChatMessage.Status) {
        performSeriallyOnBackgroundContext { managedObjectContext in
            let fetchRequest: NSFetchRequest<SharedChatMessage> = SharedChatMessage.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id = %@", msgId)
            do {
                let chatMessages = try managedObjectContext.fetch(fetchRequest)
                guard let message = chatMessages.first else {
                    DDLogError("NotificationExtension/SharedDataStore/sharedChatMessage/ no message found for \(msgId)")
                    return
                }
                DDLogInfo("NotificationExtension/SharedDataStore/sharedChatMessage/update status to: \(status)")
                message.status = status
                self.save(managedObjectContext)
            } catch {
                DDLogError("NotificationExtension/SharedDataStore/sharedChatMessage/error  [\(error)], msgId: \(msgId)")
            }
        }
    }
}

