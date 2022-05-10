//
//  CoreChatData.swift
//  Core
//
//  Created by Murali Balusu on 5/5/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import Foundation
import CoreCommon
import CoreData
import CocoaLumberjackSwift


// TODO: (murali@): reuse this logic in FeedData

public class CoreChatData {
    private let mainDataStore: MainDataStore

    public init(mainDataStore: MainDataStore) {
        self.mainDataStore = mainDataStore
    }

    public func saveChatMessage(chatMessage: IncomingChatMessage, completion: @escaping ((Result<Void, Error>) -> Void)) {
        switch chatMessage {
        case .notDecrypted(let tombstone):
            saveTombstone(tombstone, completion: completion)
        case .decrypted(let chatMessageProtocol):
            saveChatMessage(chatMessageProtocol, completion: completion)
        }
    }

    private func saveTombstone(_ tombstone: ChatMessageTombstone, completion: @escaping ((Result<Void, Error>) -> Void)) {
        mainDataStore.saveSeriallyOnBackgroundContext({ context in
            guard self.chatMessage(with: tombstone.id, in: context) == nil else {
                DDLogInfo("CoreChatData/saveTombstone/skipping [already exists]")
                return
            }

            DDLogDebug("CoreChatData/saveTombstone [\(tombstone.id)]")
            let chatMessage = ChatMessage(context: context)
            chatMessage.id = tombstone.id
            chatMessage.toUserId = tombstone.to
            chatMessage.fromUserId = tombstone.from
            chatMessage.timestamp = tombstone.timestamp
            let serialID = AppContext.shared.getchatMsgSerialId()
            DDLogDebug("CoreChatData/saveTombstone/\(tombstone.id)/serialId [\(serialID)]")
            chatMessage.serialID = serialID
            chatMessage.incomingStatus = .rerequesting
            chatMessage.outgoingStatus = .none
        }, completion: completion)
    }

    private func saveChatMessage(_ chatMessageProtocol: ChatMessageProtocol, completion: @escaping ((Result<Void, Error>) -> Void)) {
        mainDataStore.saveSeriallyOnBackgroundContext ({ context in
            let existingChatMessage = self.chatMessage(with: chatMessageProtocol.id, in: context)
            if let existingChatMessage = existingChatMessage {
                switch existingChatMessage.incomingStatus {
                case .rerequesting:
                    DDLogInfo("CoreChatData/saveChatMessage/already-exists/updating [\(existingChatMessage.incomingStatus)] [\(chatMessageProtocol.id)]")
                    break
                case .unsupported, .error, .haveSeen, .none, .retracted, .sentSeenReceipt, .played, .sentPlayedReceipt:
                    DDLogError("CoreChatData/saveChatMessage/already-exists/error [\(existingChatMessage.incomingStatus)] [\(chatMessageProtocol.id)]")
                    return
                }
            }

            DDLogDebug("CoreChatData/saveChatMessage [\(chatMessageProtocol.id)]")
            let chatMessage: ChatMessage = {
                guard let existingChatMessage = existingChatMessage else {
                    DDLogDebug("CoreChatData/saveChatMessage/new [\(chatMessageProtocol.id)]")
                    return ChatMessage(context: context)
                }
                DDLogDebug("CoreChatData/saveChatMessage/updating rerequested message [\(chatMessageProtocol.id)]")
                return existingChatMessage
            }()

            chatMessage.id = chatMessageProtocol.id
            chatMessage.toUserId = chatMessageProtocol.toUserId
            chatMessage.fromUserId = chatMessageProtocol.fromUserId
            chatMessage.feedPostId = chatMessageProtocol.context.feedPostID
            chatMessage.feedPostMediaIndex = chatMessageProtocol.context.feedPostMediaIndex

            chatMessage.chatReplyMessageID = chatMessageProtocol.context.chatReplyMessageID
            chatMessage.chatReplyMessageSenderID = chatMessageProtocol.context.chatReplyMessageSenderID
            chatMessage.chatReplyMessageMediaIndex = chatMessageProtocol.context.chatReplyMessageMediaIndex

            chatMessage.incomingStatus = .none
            chatMessage.outgoingStatus = .none

            if let ts = chatMessageProtocol.timeIntervalSince1970 {
                chatMessage.timestamp = Date(timeIntervalSince1970: ts)
            } else {
                chatMessage.timestamp = Date()
            }
            let serialID = AppContext.shared.getchatMsgSerialId()
            DDLogDebug("CoreChatData/saveChatMessage/\(chatMessageProtocol.id)/serialId [\(serialID)]")
            chatMessage.serialID = serialID


            var lastMsgMediaType: CommonThread.LastMediaType = .none
            // Process chat content
            switch chatMessageProtocol.content {
            case .album(let text, let media):
                chatMessage.rawText = text
                switch media.first?.mediaType {
                case .image:
                    lastMsgMediaType = .image
                case .video:
                    lastMsgMediaType = .video
                case .audio:
                    lastMsgMediaType = .audio
                case .none:
                    lastMsgMediaType = .none
                }
            case .voiceNote(let xmppMedia):
                guard (xmppMedia.url) != nil else { break }
                chatMessage.rawText = ""
                lastMsgMediaType = .audio
            case .text(let text, _):
                chatMessage.rawText = text
            case .unsupported(let data):
                chatMessage.rawData = data
                chatMessage.incomingStatus = .unsupported
            }

            chatMessageProtocol.linkPreviewData.forEach { linkPreviewData in
                DDLogDebug("CoreChatData/saveChatMessage/new/add-link-preview [\(linkPreviewData.url)]")
                let linkPreview = CommonLinkPreview(context: context)
                linkPreview.id = PacketID.generate()
                linkPreview.url = linkPreviewData.url
                linkPreview.title = linkPreviewData.title
                linkPreview.desc = linkPreviewData.description
                // Set preview image if present
                linkPreviewData.previewImages.forEach { previewMedia in
                    let media = CommonMedia(context: context)
                    media.type = previewMedia.type
                    media.status = .downloading
                    media.url = previewMedia.url
                    media.size = previewMedia.size
                    media.key = previewMedia.key
                    media.sha256 = previewMedia.sha256
                    media.linkPreview = linkPreview
                }
                linkPreview.message = chatMessage
            }

            for (index, media) in chatMessageProtocol.orderedMedia.enumerated() {
                DDLogDebug("CoreChatData/saveChatMessage/new/add-media/index; \(index)/url: [\(String(describing: media.url))]")
                let chatMedia = CommonMedia(context: context)
                chatMedia.type = media.mediaType
                chatMedia.status = .downloading
                chatMedia.url = media.url
                chatMedia.size = media.size
                chatMedia.key = media.key
                chatMedia.order = Int16(index)
                chatMedia.sha256 = media.sha256
                chatMedia.message = chatMessage
            }

            // Process quoted content.
            if let feedPostId = chatMessageProtocol.context.feedPostID {
                // Process Quoted Feedpost
                if let quotedFeedPost = AppContext.shared.coreFeedData.feedPost(with: feedPostId, in: context) {
                    self.copyQuoted(to: chatMessage, from: quotedFeedPost, using: context)
                }
            } else if let chatReplyMsgId = chatMessageProtocol.context.chatReplyMessageID {
                // Process Quoted Message
                if let quotedChatMessage = self.chatMessage(with: chatReplyMsgId, in: context) {
                    self.copyQuoted(to: chatMessage, from: quotedChatMessage, using: context)
                }
            }

            // Update Chat Thread
            if let chatThread = self.chatThread(type: ChatType.oneToOne, id: chatMessage.fromUserId, in: context) {
                chatThread.lastMsgTimestamp = chatMessage.timestamp
                chatThread.lastMsgId = chatMessage.id
                chatThread.lastMsgUserId = chatMessage.fromUserId
                chatThread.lastMsgText = chatMessage.rawText
                chatThread.lastMsgMediaType = lastMsgMediaType
                chatThread.lastMsgStatus = .none
                chatThread.lastMsgTimestamp = chatMessage.timestamp
                chatThread.unreadCount = chatThread.unreadCount + 1
            } else {
                let chatThread = CommonThread(context: context)
                chatThread.userID = chatMessage.fromUserId
                chatThread.lastMsgId = chatMessage.id
                chatThread.lastMsgUserId = chatMessage.fromUserId
                chatThread.lastMsgText = chatMessage.rawText
                chatThread.lastMsgMediaType = lastMsgMediaType
                chatThread.lastMsgStatus = .none
                chatThread.lastMsgTimestamp = chatMessage.timestamp
                chatThread.unreadCount = 1
            }
        }, completion: completion)
    }

    // This function can nicely copy references to quoted feed post or quoted message to the new chatMessage.
    private func copyQuoted(to chatMessage: ChatMessage, from chatQuoted: ChatQuotedProtocol, using managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("CoreChatData/copyQuoted/message/\(chatMessage.id), chatQuotedType: \(chatQuoted.type)")
        let quoted = ChatQuoted(context: managedObjectContext)
        quoted.type = chatQuoted.type
        quoted.userID = chatQuoted.userId
        quoted.rawText = chatQuoted.quotedText
        quoted.message = chatMessage
        quoted.mentions = chatQuoted.mentions

        // TODO: Why Int16? - other classes have Int32 for the order attribute.
        var mediaIndex: Int16 = 0
        // Ensure Id of the quoted object is not empty - postId/msgId.
        if let feedPostId = chatMessage.feedPostId, !feedPostId.isEmpty {
            mediaIndex = Int16(chatMessage.feedPostMediaIndex)
        } else if let chatReplyMessageID = chatMessage.chatReplyMessageID, !chatReplyMessageID.isEmpty {
            mediaIndex = Int16(chatMessage.chatReplyMessageMediaIndex)
        }
        if let chatQuotedMediaItem = chatQuoted.mediaList.first(where: { $0.order == mediaIndex }) {
            DDLogInfo("CoreChatData/copyQuoted/message/\(chatMessage.id), chatQuotedMediaIndex: \(chatQuotedMediaItem.order)")
            let quotedMedia = CommonMedia(context: managedObjectContext)
            quotedMedia.type = chatQuotedMediaItem.quotedMediaType
            quotedMedia.order = chatQuotedMediaItem.order
            quotedMedia.width = Float(chatQuotedMediaItem.width)
            quotedMedia.height = Float(chatQuotedMediaItem.height)
            quotedMedia.chatQuoted = quoted
            quotedMedia.relativeFilePath = chatQuotedMediaItem.relativeFilePath
            quotedMedia.mediaDirectory = chatQuotedMediaItem.mediaDirectory

            // TODO: We dont generate the previewData for now.
            // This will result in empty preview if the corresponding quoted content was deleted.
            // We need to generate the preview while merging this data to the main-app.
            // Or - we need to have access to the media data in nse when writing media.
            // Library to generate preview is also included only on the main-app for now.
        }
    }

    public func chatMessage(with chatMessageID: ChatMessageID, in managedObjectContext: NSManagedObjectContext) -> ChatMessage? {
        let managedObjectContext = managedObjectContext
        let fetchRequest: NSFetchRequest<ChatMessage> = ChatMessage.fetchRequest()

        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "id == %@", chatMessageID)
        ])

        fetchRequest.returnsObjectsAsFaults = false
        do {
            let messages = try managedObjectContext.fetch(fetchRequest)
            return messages.first
        }
        catch {
            DDLogError("NotificationProtoService/fetch-posts/error  [\(error)]")
            fatalError("Failed to fetch feed posts.")
        }
    }

    private func chatThreads(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext) -> [CommonThread] {
        let managedObjectContext = managedObjectContext
        let fetchRequest: NSFetchRequest<CommonThread> = CommonThread.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let chatThreads = try managedObjectContext.fetch(fetchRequest)
            return chatThreads
        } catch {
            DDLogError("ChatThread/fetch/error  [\(error)]")
            fatalError("Failed to fetch chat threads")
        }
    }

    func chatThread(type: ChatType, id: String, in managedObjectContext: NSManagedObjectContext) -> CommonThread? {
        if type == .group {
            return chatThreads(predicate: NSPredicate(format: "groupID == %@", id), in: managedObjectContext).first
        } else {
            return chatThreads(predicate: NSPredicate(format: "userID == %@", id), in: managedObjectContext).first
        }
    }
}
