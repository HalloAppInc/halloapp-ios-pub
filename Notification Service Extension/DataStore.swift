//
//  DataStore.swift
//  Notification Service Extension
//
//  Created by Igor Solomennikov on 9/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreData

class DataStore: NotificationServiceExtensionDataStore {

    func save(protoPost: Clients_Post, notificationMetadata: NotificationMetadata) -> SharedFeedPost {
        let managedObjectContext = persistentContainer.viewContext

        let userId = notificationMetadata.fromId
        let postId = notificationMetadata.feedPostId!

        DDLogInfo("DataStore/post/\(postId)/create")

        let feedPost = NSEntityDescription.insertNewObject(forEntityName: "SharedFeedPost", into: managedObjectContext) as! SharedFeedPost
        feedPost.id = postId
        feedPost.userId = userId
        feedPost.groupId = notificationMetadata.groupId
        feedPost.text = protoPost.text.isEmpty ? nil : protoPost.text
        feedPost.status = .received
        feedPost.timestamp = notificationMetadata.timestamp ?? Date()

        // Add mentions
        var mentions: Set<SharedFeedMention> = []
        for protoMention in protoPost.mentions {
            let mention = NSEntityDescription.insertNewObject(forEntityName: "SharedFeedMention", into: managedObjectContext) as! SharedFeedMention
            mention.index = Int(protoMention.index)
            mention.userID = protoMention.userID
            mention.name = protoMention.name
            mentions.insert(mention)
        }
        feedPost.mentions = mentions

        // Add media
        var postMedia: Set<SharedMedia> = []
        for (index, protoMedia) in protoPost.media.enumerated() {
            guard let mediaType: FeedMediaType = {
                switch protoMedia.type {
                case .image: return .image
                case .video: return .video
                default: return nil
                }}() else { continue }

            guard let url = URL(string: protoMedia.downloadURL) else { continue }

            let width = CGFloat(protoMedia.width), height = CGFloat(protoMedia.height)
            guard width > 0 && height > 0 else { continue }

            let media = NSEntityDescription.insertNewObject(forEntityName: "SharedMedia", into: managedObjectContext) as! SharedMedia
            media.type = mediaType
            media.status = .none
            media.url = url
            media.size = CGSize(width: width, height: height)
            media.key = protoMedia.encryptionKey.base64EncodedString()
            media.sha256 = protoMedia.ciphertextHash.base64EncodedString()
            media.order = Int16(index)
            postMedia.insert(media)
        }
        feedPost.media = postMedia

        // set a merge policy so that we dont end up with duplicate feedposts.
        managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        save(managedObjectContext)

        return feedPost
    }
    
    func save(protoComment: Clients_Comment, notificationMetadata: NotificationMetadata) {
        let managedObjectContext = persistentContainer.viewContext
        
        // Extract info from parameters
        let userId = notificationMetadata.fromId
        let commentId = notificationMetadata.feedPostCommentId!
        let postId = protoComment.feedPostID
        let parentCommentId: String?
        if protoComment.parentCommentID == "" {
            parentCommentId = nil
        } else {
            parentCommentId = protoComment.parentCommentID
        }
        
        // Add mentions
        var mentionSet = Set<SharedFeedMention>()
        for mention in protoComment.mentions {
            let feedMention = NSEntityDescription.insertNewObject(forEntityName: "SharedFeedMention", into: managedObjectContext) as! SharedFeedMention
            feedMention.index = Int(mention.index)
            feedMention.userID = mention.userID
            feedMention.name = mention.name
            if feedMention.name == "" {
                DDLogError("FeedData/new-comment/mention/\(mention.userID) missing push name")
            }
            mentionSet.insert(feedMention)
        }
        
        // Create comment
        DDLogInfo("NotificationExtension/DataStore/new-comment/create id=[\(commentId)]  postId=[\(postId)]")
        let feedComment = NSEntityDescription.insertNewObject(forEntityName: "SharedFeedComment", into: managedObjectContext) as! SharedFeedComment
        feedComment.id = commentId
        feedComment.userId = userId
        feedComment.postId = postId
        feedComment.parentCommentId = parentCommentId
        feedComment.text = protoComment.text
        feedComment.mentions = mentionSet
        feedComment.status = .received
        feedComment.timestamp = notificationMetadata.timestamp ?? Date()
        
        managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        save(managedObjectContext)
    }

    func saveServerMsg(notificationMetadata: NotificationMetadata) {
        guard let serverMsgPb = notificationMetadata.serverMsgPb else {
            DDLogError("NotificationExtension/DataStore/serverMsgPb is nil, unable to save Msg")
            return
        }
        DDLogInfo("NotificationExtension/DataStore/saveServerMsg, contentId: \(notificationMetadata.contentId)")
        // why use view context in nse to save? all functions are using this.
        // todo(murali@): update this.
        let managedObjectContext = persistentContainer.viewContext
        let serverMsg = NSEntityDescription.insertNewObject(forEntityName: "SharedServerMessage", into: managedObjectContext) as! SharedServerMessage
        serverMsg.msg = serverMsgPb
        serverMsg.timestamp = notificationMetadata.timestamp ?? Date()
        save(managedObjectContext)
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
        chatMedia.order = Int16(index)

        return chatMedia
    }

    func save(protobuf: MessageProtobuf?, metadata: NotificationMetadata, status: SharedChatMessage.Status, failure: DecryptionFailure?) -> SharedChatMessage? {
        let managedObjectContext = persistentContainer.viewContext

        let messageId = metadata.contentId
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
        chatMessage.timestamp = Date()
        let serialID = AppContext.shared.getchatMsgSerialId()
        DDLogInfo("SharedDataStore/message/\(messageId)/created/serialId \(serialID)")
        chatMessage.serialID = serialID

        switch status {
        case .received:
            switch protobuf {
            case .container(let container):
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
            case .legacy(let clientChatMsg):
                chatMessage.text = clientChatMsg.text
                for (index, mediaItem) in clientChatMsg.media.enumerated() {
                    guard let mediaData = XMPPChatMedia(protoMedia: mediaItem) else { continue }
                    let sharedMedia = insertSharedMedia(for: mediaData, index: index, into: managedObjectContext)
                    sharedMedia.message = chatMessage
                }
                chatMessage.clientChatMsgPb = try? clientChatMsg.serializedData()
            case .none:
                DDLogError("SharedDataStore/message/\(messageId)/missing-protobuf")
                break
            }

        case .decryptionError:
            break
        case .acked, .rerequesting:
            // when we save the message initially - status will always be received/decryptionError.
            break
        case .none, .sent, .sendError:
            // not relevant here.
            break
        }
        save(managedObjectContext)
        return chatMessage
    }

    func getChatMessagesToAck() -> [SharedChatMessage] {
        let managedObjectContext = persistentContainer.viewContext

        let fetchRequest: NSFetchRequest<SharedChatMessage> = SharedChatMessage.fetchRequest()

        // We fetch (and ack) these messages in ascending order so the sender receives delivery receipts in order.
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SharedChatMessage.timestamp, ascending: true)]

        var messagesToAck = [SharedChatMessage]()
        do {
            let chatMessages = try managedObjectContext.fetch(fetchRequest)
            for message in chatMessages {
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
        return messagesToAck
    }

    func getChatMessagesToRerequest() -> [SharedChatMessage] {
        let managedObjectContext = persistentContainer.viewContext

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
        return messagesToRerequest
    }

    func sharedMediaObject(forObjectId objectId: NSManagedObjectID) throws -> SharedMedia? {
        return try persistentContainer.viewContext.existingObject(with: objectId) as? SharedMedia
    }

    func updateMessageStatus(for msgId: String, status: SharedChatMessage.Status) {
        let managedObjectContext = persistentContainer.viewContext

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
            save(managedObjectContext)
        } catch {
            DDLogError("NotificationExtension/SharedDataStore/sharedChatMessage/error  [\(error)], msgId: \(msgId)")
        }
        return
    }
}

enum MessageProtobuf {
    case legacy(Clients_ChatMessage)
    case container(Clients_ChatContainer)

    var chatContent: ChatContent {
        switch self {
        case .legacy(let legacyChat):
            return legacyChat.chatContent
        case .container(let chatContainer):
            return chatContainer.chatContent
        }
    }
}
