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
import Combine
import CocoaLumberjackSwift


// TODO: (murali@): reuse this logic in ChatData

public class CoreChatData {
    private let service: CoreService
    private let mainDataStore: MainDataStore
    private var cancellableSet: Set<AnyCancellable> = []

    public init(service: CoreService, mainDataStore: MainDataStore) {
        self.mainDataStore = mainDataStore
        self.service = service
        cancellableSet.insert(
            service.didGetNewWhisperMessage.sink { [weak self] whisperMessage in
                self?.handleIncomingWhisperMessage(whisperMessage)
            }
        )
    }

    // MARK: Handle rerequests

    public func handleRerequest(for messageID: String, from userID: UserID, ack: (() -> Void)?) {
        handleRerequest(for: messageID, from: userID) { result in
            switch result {
            case .failure(let error):
                DDLogError("CoreChatData/handleRerequest/\(messageID)/error: \(error)/from: \(userID)")
                if error.canAck {
                    ack?()
                }
            case .success:
                DDLogInfo("CoreChatData/handleRerequest/\(messageID)/success/from: \(userID)")
                ack?()
            }
        }
    }

    public func handleRerequest(for messageID: String, from userID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        mainDataStore.saveSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else {
                completion(.failure(.aborted))
                return
            }
            guard let chatMessage = self.chatMessage(with: messageID, in: managedObjectContext) else {
                DDLogError("CoreChatData/handleRerequest/\(messageID)/error could not find message")
                self.service.sendContentMissing(id: messageID, type: .chat, to: userID) { result in
                    completion(result)
                }
                return
            }
            guard userID == chatMessage.toUserId else {
                DDLogError("CoreChatData/handleRerequest/\(messageID)/error user mismatch [original: \(chatMessage.toUserId)] [rerequest: \(userID)]")
                completion(.failure(.aborted))
                return
            }
            guard chatMessage.resendAttempts < 5 else {
                DDLogInfo("CoreChatData/handleRerequest/\(messageID)/skipping (\(chatMessage.resendAttempts) resend attempts)")
                completion(.failure(.aborted))
                return
            }
            chatMessage.resendAttempts += 1

            switch chatMessage.outgoingStatus {
            case .retracted, .retracting:
                let retractID = chatMessage.retractID ?? PacketID.generate()
                chatMessage.retractID = retractID
                self.service.retractChatMessage(messageID: retractID, toUserID: userID, messageToRetractID: messageID, completion: completion)
            default:
                let xmppChatMessage = XMPPChatMessage(chatMessage: chatMessage)
                self.service.sendChatMessage(xmppChatMessage, completion: completion)
            }
        }
    }

    // MARK: Handle whisper messages
    // This part is not great and should be in CoreModule - but since the groups list is stored in ChatData.
    // This code is ending up here for now - should fix this soon.
    private func handleIncomingWhisperMessage(_ whisperMessage: WhisperMessage) {
        DDLogInfo("ChatData/handleIncomingWhisperMessage/begin")
        switch whisperMessage {
        case .update(let userID, _):
            DDLogInfo("ChatData/handleIncomingWhisperMessage/execute update for \(userID)")
            mainDataStore.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                guard let self = self else { return }
                let groupIds = self.chatGroupIds(for: userID, in: managedObjectContext)
                groupIds.forEach { groupId in
                    DDLogInfo("ChatData/handleIncomingWhisperMessage/updateWhisperSession/addToPending \(userID) in \(groupId)")
                    AppContext.shared.messageCrypter.addMembers(userIds: [userID], in: groupId)
                }

                self.recordNewChatEvent(userID: userID, type: .whisperKeysChange)
            }
        default:
            DDLogInfo("ChatData/handleIncomingWhisperMessage/ignore")
            break
        }
    }

    // MARK: Save content

    public func saveChatMessage(chatMessage: IncomingChatMessage, hasBeenProcessed: Bool, completion: @escaping ((Result<Void, Error>) -> Void)) {
        switch chatMessage {
        case .notDecrypted(let tombstone):
            saveTombstone(tombstone, hasBeenProcessed: hasBeenProcessed, completion: completion)
        case .decrypted(let chatMessageProtocol):
            switch  chatMessageProtocol.content {
            case .reaction(_):
                saveReaction(chatMessageProtocol, hasBeenProcessed: hasBeenProcessed, completion: completion)
            case .album, .text, .voiceNote, .location, .unsupported:
                saveChatMessage(chatMessageProtocol, hasBeenProcessed: hasBeenProcessed, completion: completion)
            }
        }
    }

    private func saveTombstone(_ tombstone: ChatMessageTombstone, hasBeenProcessed: Bool, completion: @escaping ((Result<Void, Error>) -> Void)) {
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
            chatMessage.hasBeenProcessed = hasBeenProcessed
        }, completion: completion)
    }

    private func saveChatMessage(_ chatMessageProtocol: ChatMessageProtocol, hasBeenProcessed: Bool, completion: @escaping ((Result<Void, Error>) -> Void)) {
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

            chatMessage.hasBeenProcessed = hasBeenProcessed

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
            case .reaction(let emoji):
                DDLogDebug("CoreChatData/saveChatMessage/processing reaction as message")
                chatMessage.rawText = emoji
            case .location(let chatLocation):
                chatMessage.location = CommonLocation(chatLocation: chatLocation, context: context)
                lastMsgMediaType = .location
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
                linkPreviewData.previewImages.enumerated().forEach { (index, previewMedia) in
                    let media = CommonMedia(context: context)
                    media.id = "\(linkPreview.id)-\(index)"
                    media.type = previewMedia.type
                    media.status = .downloading
                    media.url = previewMedia.url
                    media.size = previewMedia.size
                    media.key = previewMedia.key
                    media.sha256 = previewMedia.sha256
                    media.linkPreview = linkPreview
                    media.order = Int16(index)
                }
                linkPreview.message = chatMessage
            }

            for (index, media) in chatMessageProtocol.orderedMedia.enumerated() {
                DDLogDebug("CoreChatData/saveChatMessage/new/add-media/index; \(index)/url: [\(String(describing: media.url))]")
                let chatMedia = CommonMedia(context: context)
                chatMedia.id = "\(chatMessage.id)-\(index)"
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
    
    private func saveReaction(_ chatMessageProtocol: ChatMessageProtocol, hasBeenProcessed: Bool, completion: @escaping ((Result<Void, Error>) -> Void)) {
        mainDataStore.saveSeriallyOnBackgroundContext ({ context in
            let existingReaction = self.commonReaction(with: chatMessageProtocol.id, in: context)
            if let existingReaction = existingReaction {
                switch existingReaction.incomingStatus {
                case .unsupported, .none, .rerequesting:
                    DDLogInfo("CoreChatData/saveReaction/already-exists/updating [\(existingReaction.incomingStatus)] [\(chatMessageProtocol.id)]")
                    break
                case .error, .incoming, .retracted:
                    DDLogError("CoreChatData/saveReaction/already-exists/error [\(existingReaction.incomingStatus)] [\(chatMessageProtocol.id)]")
                    return
                }
            }

            DDLogDebug("CoreChatData/saveReaction [\(chatMessageProtocol.id)]")
            let commonReaction: CommonReaction = {
                guard let existingReaction = existingReaction else {
                    let existingTombstone = self.chatMessage(with: chatMessageProtocol.id, in: context)
                    if let existingTombstone = existingTombstone, existingTombstone.incomingStatus == .rerequesting {
                        //Delete tombstone
                        DDLogInfo("CoreChatData/saveReaction/deleteTombstone [\(existingTombstone.id)]")
                        context.delete(existingTombstone)
                    }
                    DDLogDebug("CoreChatData/saveReaction/new [\(chatMessageProtocol.id)]")
                    return CommonReaction(context: context)
                }
                DDLogDebug("CoreChatData/saveReaction/updating rerequested reaction [\(chatMessageProtocol.id)]")
                return existingReaction
            }()

            commonReaction.id = chatMessageProtocol.id
            commonReaction.toUserID = chatMessageProtocol.toUserId
            commonReaction.fromUserID = chatMessageProtocol.fromUserId
            switch chatMessageProtocol.content {
            case .reaction(let emoji):
                commonReaction.emoji = emoji
            case .album, .text, .voiceNote, .location, .unsupported:
                DDLogError("CoreChatData/saveReaction content not reaction type")
            }
            if let chatReplyMsgId = chatMessageProtocol.context.chatReplyMessageID {
                // Set up parent chat message
                if let message = self.chatMessage(with: chatReplyMsgId, in: context) {
                    commonReaction.message = message
                }
            }

            commonReaction.incomingStatus = .incoming
            commonReaction.outgoingStatus = .none

            if let ts = chatMessageProtocol.timeIntervalSince1970 {
                commonReaction.timestamp = Date(timeIntervalSince1970: ts)
            } else {
                commonReaction.timestamp = Date()
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
            quotedMedia.id = "\(quoted.message?.id ?? UUID().uuidString)-\(chatQuotedMediaItem.order)"
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
            fatalError("Failed to fetch chat messages.")
        }
    }

    public func commonReaction(with commonReactionID: CommonReactionID, in managedObjectContext: NSManagedObjectContext) -> CommonReaction? {
        let fetchRequest: NSFetchRequest<CommonReaction> = CommonReaction.fetchRequest()

        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "id == %@", commonReactionID)
        ])

        fetchRequest.returnsObjectsAsFaults = false
        do {
            let messages = try managedObjectContext.fetch(fetchRequest)
            return messages.first
        }
        catch {
            DDLogError("NotificationProtoService/fetch-posts/error  [\(error)]")
            fatalError("Failed to fetch reactions.")
        }
    }

    private func chatThreads(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext) -> [CommonThread] {
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

    private func chatMessages(predicate: NSPredicate? = nil,
                              sortDescriptors: [NSSortDescriptor]? = nil,
                              limit: Int? = nil,
                              in managedObjectContext: NSManagedObjectContext) -> [ChatMessage] {
        let fetchRequest: NSFetchRequest<ChatMessage> = ChatMessage.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        if let fetchLimit = limit { fetchRequest.fetchLimit = fetchLimit }
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let chatMessages = try managedObjectContext.fetch(fetchRequest)
            return chatMessages
        }
        catch {
            DDLogError("ChatData/fetch-messages/error  [\(error)]")
            fatalError("Failed to fetch chat messages")
        }
    }

    func chatGroupMemberUserIds(for groupID: GroupID, in managedObjectContext: NSManagedObjectContext) -> [UserID] {
        let groupMembers = chatGroupMembers(predicate: NSPredicate(format: "groupID == %@", groupID), in: managedObjectContext)
        return groupMembers.map { $0.userID }
    }

    func chatGroupIds(for memberUserId: UserID, in managedObjectContext: NSManagedObjectContext) -> [GroupID] {
        let chatGroupMemberItems = chatGroupMembers(predicate: NSPredicate(format: "userID == %@", memberUserId), in: managedObjectContext)
        return chatGroupMemberItems.map { $0.groupID }
    }

    private func chatGroupMembers(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext) -> [GroupMember] {
        let fetchRequest: NSFetchRequest<GroupMember> = GroupMember.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let chatGroupMembers = try managedObjectContext.fetch(fetchRequest)
            return chatGroupMembers
        }
        catch {
            DDLogError("ChatData/group/fetchGroupMembers/error  [\(error)]")
            fatalError("Failed to fetch chat group members")
        }
    }
}


// MARK: Chat Events
extension CoreChatData {

    public func recordNewChatEvent(userID: UserID, type: ChatEventType) {
        mainDataStore.saveSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            DDLogInfo("ChatData/recordNewChatEvent/for: \(userID)")

            let appUserID = AppContext.shared.userData.userId
            let predicate = NSPredicate(format: "(fromUserID = %@ AND toUserID = %@) || (toUserID = %@ AND fromUserID = %@)", userID, appUserID, userID, appUserID)
            guard self.chatMessages(predicate: predicate, limit: 1, in: managedObjectContext).count > 0 else {
                DDLogInfo("ChatData/recordNewChatEvent/\(userID)/no messages yet, skip recording keys change event")
                return
            }

            let chatEvent = ChatEvent(context: managedObjectContext)
            chatEvent.userID = userID
            chatEvent.type = type
            chatEvent.timestamp = Date()
        }
    }

    public func deleteChatEvents(userID: UserID) {
        DDLogInfo("ChatData/deleteChatEvents")
        mainDataStore.saveSeriallyOnBackgroundContext { (managedObjectContext) in
            let fetchRequest = NSFetchRequest<ChatEvent>(entityName: ChatEvent.entity().name!)
            fetchRequest.predicate = NSPredicate(format: "userID = %@", userID)

            do {
                let events = try managedObjectContext.fetch(fetchRequest)
                DDLogInfo("ChatData/events/deleteChatEvents/count=[\(events.count)]")
                events.forEach {
                    managedObjectContext.delete($0)
                }
            }
            catch {
                DDLogError("ChatData/events/deleteChatEvents/error  [\(error)]")
                return
            }
        }
    }

}
