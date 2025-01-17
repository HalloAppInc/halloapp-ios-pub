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
import Intents
import CryptoKit

public struct FileSharingData {
    public init(name: String, size: Int, localURL: URL) {
        self.localURL = localURL
        self.size = size
        self.name = name
    }

    public var localURL: URL
    public var size: Int
    public var name: String
}

// TODO: (murali@): reuse this logic in ChatData

public class CoreChatData {
    private let service: CoreService
    private let mainDataStore: MainDataStore
    private let userData: UserData
    private let contactStore: ContactStoreCore
    private let commonMediaUploader: CommonMediaUploader
    private var cancellableSet: Set<AnyCancellable> = []
    private var currentlyChattingWithUserId: String? = nil
    private var currentlyChattingInGroup: GroupID? = nil

    public init(service: CoreService, mainDataStore: MainDataStore, userData: UserData, contactStore: ContactStoreCore, commonMediaUploader: CommonMediaUploader) {
        self.mainDataStore = mainDataStore
        self.service = service
        self.userData = userData
        self.contactStore = contactStore
        self.commonMediaUploader = commonMediaUploader
        cancellableSet.insert(
            service.didGetNewWhisperMessage.sink { [weak self] whisperMessage in
                self?.handleIncomingWhisperMessage(whisperMessage)
            }
        )

        commonMediaUploader.chatMessageMediaStatusChangedPublisher
            .sink { [weak self] chatMessageID in self?.uploadChatMessageIfMediaReady(chatMessageID: chatMessageID) }
            .store(in: &cancellableSet)
    }

    // MARK: - Getters

    // includes seen but not sent messages
    func unseenChatMessages(with fromUserId: String, in managedObjectContext: NSManagedObjectContext) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.serialID, ascending: true),
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return self.chatMessages(predicate: NSPredicate(format: "fromUserID = %@ && toUserID = %@ && (incomingStatusValue = %d OR incomingStatusValue = %d)", fromUserId, userData.userId, ChatMessage.IncomingStatus.none.rawValue, ChatMessage.IncomingStatus.haveSeen.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }

    func unseenGroupChatMessages(in groupId: GroupID, in managedObjectContext: NSManagedObjectContext) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.serialID, ascending: true),
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return self.chatMessages(predicate: NSPredicate(format: "toGroupID = %@ && (incomingStatusValue = %d OR incomingStatusValue = %d)", groupId, ChatMessage.IncomingStatus.none.rawValue, ChatMessage.IncomingStatus.haveSeen.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }

    private func chatGroups(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext) -> [Group] {
        let fetchRequest: NSFetchRequest<Group> = Group.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let chatGroups = try managedObjectContext.fetch(fetchRequest)
            return chatGroups
        }
        catch {
            DDLogError("CoreChatData/group/fetch/error  [\(error)]")
            return []
        }
    }

    func chatGroup(groupId id: String, in managedObjectContext: NSManagedObjectContext) -> Group? {
        return chatGroups(predicate: NSPredicate(format: "id == %@", id), in: managedObjectContext).first
    }

    public func chatReceiptInfo(messageId: String, userId: UserID, in managedObjectContext: NSManagedObjectContext) -> ChatReceiptInfo? {
        return self.chatReceiptInfoAll(predicate: NSPredicate(format: "chatMessageId == %@ && userId == %@", messageId, userId), in: managedObjectContext).first
    }

    private func chatReceiptInfoAll(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext) -> [ChatReceiptInfo] {
        let fetchRequest: NSFetchRequest<ChatReceiptInfo> = ChatReceiptInfo.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let chatGroupMessageInfo = try managedObjectContext.fetch(fetchRequest)
            return chatGroupMessageInfo
        }
        catch {
            DDLogError("ChatData/chatMessageAllInfo/fetch-messageInfo/error  [\(error)]")
            return []
        }
    }

    // MARK: Chat messgage upload and posting

    public func sendMessage(chatMessageRecipient: ChatMessageRecipient,
                            mentionText: MentionText,
                            media: [PendingMedia],
                            files: [FileSharingData],
                            linkPreviewData: LinkPreviewData? = nil,
                            linkPreviewMedia : PendingMedia? = nil,
                            location: ChatLocationProtocol? = nil,
                            feedPostId: String? = nil,
                            feedPostMediaIndex: Int32 = 0,
                            chatReplyMessageID: String? = nil,
                            chatReplyMessageSenderID: UserID? = nil,
                            chatReplyMessageMediaIndex: Int32 = 0,
                            forwardCount: Int32 = 0,
                            didCreateMessage: ((Result<(ChatMessageID, [CommonMediaID]), Error>) -> Void)? = nil,
                            didBeginUpload: ((Result<ChatMessageID, Error>) -> Void)? = nil) {
        mainDataStore.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            if let toUserId = chatMessageRecipient.toUserId {
                DDLogInfo("CoreChatData/sendMessage/createChatMsg/toUserId: \(String(describing: toUserId))")
                self.addIntent(toUserId: toUserId)
            } else if let toGroupId = chatMessageRecipient.toGroupId {
                DDLogInfo("CoreChatData/sendMessage/createChatMsg/toGroupId: \(toGroupId)")
                AppContext.shared.coreFeedData.addIntent(groupId: toGroupId)
            }

            self.createChatMsg(chatMessageRecipient: chatMessageRecipient,
                               mentionText: mentionText,
                               media: media,
                               files: files,
                               linkPreviewData: linkPreviewData,
                               linkPreviewMedia: linkPreviewMedia,
                               location: location,
                               feedPostId: feedPostId,
                               feedPostMediaIndex: feedPostMediaIndex,
                               chatReplyMessageID: chatReplyMessageID,
                               chatReplyMessageSenderID: chatReplyMessageSenderID,
                               chatReplyMessageMediaIndex: chatReplyMessageMediaIndex,
                               forwardCount: forwardCount,
                               using: managedObjectContext,
                               didCreateMessage: didCreateMessage,
                               didBeginUpload: didBeginUpload)
        }
    }

    @discardableResult
    public func createChatMsg(chatMessageRecipient: ChatMessageRecipient,
                              mentionText: MentionText,
                              media: [PendingMedia],
                              files: [FileSharingData],
                              linkPreviewData: LinkPreviewData?,
                              linkPreviewMedia : PendingMedia?,
                              location: ChatLocationProtocol?,
                              feedPostId: String?,
                              feedPostMediaIndex: Int32,
                              isMomentReply: Bool = false,
                              chatReplyMessageID: String? = nil,
                              chatReplyMessageSenderID: UserID? = nil,
                              chatReplyMessageMediaIndex: Int32,
                              forwardCount: Int32 = 0,
                              using context: NSManagedObjectContext,
                              didCreateMessage: ((Result<(ChatMessageID, [CommonMediaID]), Error>) -> Void)? = nil,
                              didBeginUpload: ((Result<ChatMessageID, Error>) -> Void)? = nil) -> ChatMessageID {

        let messageId = PacketID.generate()
        let toUserId = chatMessageRecipient.toUserId
        let isMsgToYourself: Bool = toUserId == userData.userId

        // Create and save new ChatMessage object.
        DDLogDebug("CoreChatData/createChatMsg/\(messageId)/toUserId: \(String(describing: toUserId))")
        let chatMessage = ChatMessage(context: context)
        chatMessage.id = messageId
        chatMessage.chatMessageRecipient = chatMessageRecipient
        chatMessage.fromUserId = userData.userId
        chatMessage.user = UserProfile.findOrCreate(with: userData.userId, in: context)
        chatMessage.rawText = mentionText.collapsedText
        chatMessage.mentions = mentionText.mentions.map { (index, user) in
            let name = UserProfile.find(with: user.userID, in: context)?.name ?? ""
            return MentionData(index: index, userID: user.userID, name: name)
        }
        chatMessage.feedPostId = feedPostId
        chatMessage.feedPostMediaIndex = feedPostMediaIndex
        chatMessage.chatReplyMessageID = chatReplyMessageID
        chatMessage.chatReplyMessageSenderID = chatReplyMessageSenderID
        chatMessage.chatReplyMessageMediaIndex = chatReplyMessageMediaIndex
        chatMessage.forwardCount = forwardCount
        chatMessage.incomingStatus = .none
        let timestamp = Date()
        chatMessage.timestamp = timestamp
        // Track outgoing status of all the group members
        if let toGroupId = chatMessageRecipient.toGroupId, let chatGroup = self.chatGroup(groupId: toGroupId, in: context) {
            chatMessage.outgoingStatus = .pending
            if let members = chatGroup.members {
                for member in members {
                    guard member.userID != userData.userId else { continue }
                    let messageInfo = ChatReceiptInfo(context: context)
                    messageInfo.chatMessageId = chatMessage.id
                    messageInfo.userId = member.userID
                    messageInfo.outgoingStatus = .none
                    messageInfo.chatMessage = chatMessage
                    messageInfo.timestamp = timestamp
                }
            }
        } else {
            chatMessage.outgoingStatus = isMsgToYourself ? .seen : .pending
        }
        let serialID = AppContext.shared.getchatMsgSerialId()
        DDLogDebug("CoreChatData/createChatMsg/\(messageId)/serialId [\(serialID)]")
        chatMessage.serialID = serialID

        var lastMsgTextFallback: String?
        var lastMsgMediaType: CommonThread.LastMediaType = .none // going with the first media

        var mediaIDs: [CommonMediaID] = []

        for (index, mediaItem) in media.enumerated() {
            DDLogDebug("CoreChatData/createChatMsg/\(messageId)/add-media [\(mediaItem)]")
            guard let mediaItemSize = mediaItem.size, mediaItem.fileURL != nil else {
                DDLogDebug("CoreChatData/createChatMsg/\(messageId)/add-media/skip/missing info")
                continue
            }

            let chatMedia = CommonMedia(context: context)
            let chatMediaID = "\(chatMessage.id)-\(index)"
            chatMedia.id = chatMediaID
            mediaIDs.append(chatMediaID)
            chatMedia.type = mediaItem.type
            if lastMsgMediaType == .none {
                lastMsgMediaType = CommonThread.lastMediaType(for: mediaItem.type)
            }
            chatMedia.outgoingStatus = isMsgToYourself ? .uploaded : .pending
            chatMedia.url = mediaItem.url
            chatMedia.uploadUrl = mediaItem.uploadUrl
            chatMedia.size = mediaItemSize
            chatMedia.key = ""
            chatMedia.sha256 = ""
            chatMedia.order = Int16(index)
            chatMedia.message = chatMessage

            do {
                try CommonMedia.copyMedia(from: mediaItem, to: chatMedia)
            }
            catch {
                DDLogError("CoreChatData/createChatMsg/\(messageId)/copy-media/error [\(error)]")
            }
        }

        for (index, file) in files.enumerated() {
            DDLogDebug("CoreChatData/createChatMsg/\(messageId)/add-file [\(file.localURL)]")

            // TODO: Iterate over files with other media to avoid this adjusted index
            let adjustedIndex = index + media.count
            let chatMedia = CommonMedia(context: context)
            let chatMediaID = "\(chatMessage.id)-\(adjustedIndex)"
            chatMedia.id = chatMediaID
            mediaIDs.append(chatMediaID)
            chatMedia.type = .document
            chatMedia.name = file.name
            chatMedia.fileSize = Int64(file.size)
            if lastMsgMediaType == .none {
                lastMsgMediaType = CommonThread.lastMediaType(for: .document)
            }
            lastMsgTextFallback = file.name
            chatMedia.outgoingStatus = isMsgToYourself ? .uploaded : .pending
            chatMedia.url = file.localURL
            chatMedia.key = ""
            chatMedia.sha256 = ""
            chatMedia.order = Int16(adjustedIndex)
            chatMedia.message = chatMessage

            do {
                try CommonMedia.copyMedia(
                    at: file.localURL,
                    encryptedFileURL: nil,
                    fileExtension: file.localURL.pathExtension,
                    to: chatMedia)
            }
            catch {
                DDLogError("CoreChatData/createChatMsg/\(messageId)/copy-media/error [\(error)]")
            }
        }

        if let location = location {
            chatMessage.location = CommonLocation(chatLocation: location, context: context)
            lastMsgMediaType = .location
        }

        if isMomentReply, let feedPostId = feedPostId, let feedPost = AppContext.shared.coreFeedData.feedPost(with: feedPostId, in: context) {
            Self.copyQuotedMoment(to: chatMessage,
                                from: feedPost,
                       selfieLeading: feedPost.isMomentSelfieLeading,
                               using: context)
        } else if let feedPostId = feedPostId, let feedPost = AppContext.shared.coreFeedData.feedPost(with: feedPostId, in: context) {
            // Create and save Quoted FeedPost
            let quoted = ChatQuoted(context: context)
            quoted.type = .feedpost
            quoted.userID = feedPost.userId
            quoted.rawText = feedPost.rawText
            quoted.message = chatMessage
            quoted.mentions = feedPost.mentions

            if let feedPostMedia = feedPost.media?.first(where: { $0.order == feedPostMediaIndex }) {
                let quotedMedia = CommonMedia(context: context)
                let quotedMediaID = "\(quoted.message?.id ?? UUID().uuidString)-quoted-\(feedPostMedia.order)"
                quotedMedia.id = quotedMediaID
                mediaIDs.append(quotedMediaID)
                quotedMedia.type = feedPostMedia.type
                quotedMedia.order = feedPostMedia.order
                quotedMedia.width = Float(feedPostMedia.size.width)
                quotedMedia.height = Float(feedPostMedia.size.height)
                quotedMedia.chatQuoted = quoted
                quotedMedia.relativeFilePath = feedPostMedia.relativeFilePath
                quotedMedia.mediaDirectory = feedPostMedia.mediaDirectory
                quotedMedia.previewData = Self.quotedMediaPreviewData(mediaDirectory: feedPostMedia.mediaDirectory,
                                                                      path: feedPostMedia.relativeFilePath,
                                                                      type: feedPostMedia.type)
            }
        }
        // Process link preview if present
        if let linkPreviewData = linkPreviewData {
            DDLogDebug("CoreChatData/process-chats/new/generate-link-preview [\(linkPreviewData.url)]")
            let linkPreview = CommonLinkPreview(context: context)
            linkPreview.id = PacketID.generate()
            linkPreview.url = linkPreviewData.url
            linkPreview.title = linkPreviewData.title
            linkPreview.desc = linkPreviewData.description
            linkPreview.message = chatMessage
            // Set preview image if present
            if let linkPreviewMedia = linkPreviewMedia {
                let linkPreviewChatMedia = CommonMedia(context: context)
                let linkPreviewMediaID = "\(linkPreview.id)-0"
                linkPreviewChatMedia.id = linkPreviewMediaID
                mediaIDs.append(linkPreviewMediaID)
                if let mediaItemSize = linkPreviewMedia.size, linkPreviewMedia.fileURL != nil {
                    linkPreviewChatMedia.type = linkPreviewMedia.type
                    linkPreviewChatMedia.outgoingStatus = isMsgToYourself ? .uploaded : .pending
                    linkPreviewChatMedia.url = linkPreviewMedia.url
                    linkPreviewChatMedia.uploadUrl = linkPreviewMedia.uploadUrl
                    linkPreviewChatMedia.size = mediaItemSize
                    linkPreviewChatMedia.key = ""
                    linkPreviewChatMedia.sha256 = ""
                    linkPreviewChatMedia.order = 0
                    linkPreviewChatMedia.linkPreview = linkPreview
                    do {
                        try CommonMedia.copyMedia(from: linkPreviewMedia, to: linkPreviewChatMedia)
                    }
                    catch {
                        DDLogError("CoreChatData/createChatMsg/\(messageId)/copy-media-linkPreview/error [\(error)]")
                    }
                } else {
                    DDLogDebug("CoreChatData/createChatMsg/\(messageId)/add-media-linkPreview/skip/missing info")
                }
            }
        }

        if let chatReplyMessageID = chatReplyMessageID,
           let chatReplyMessageSenderID = chatReplyMessageSenderID,
           let quotedChatMessage = self.chatMessage(with: chatReplyMessageID, in: context) {

            let quoted = ChatQuoted(context: context)
            quoted.type = .message
            quoted.userID = chatReplyMessageSenderID
            quoted.rawText = quotedChatMessage.rawText
            quoted.message = chatMessage

            if let quotedChatMessageMedia = quotedChatMessage.media?.first(where: { $0.order == chatReplyMessageMediaIndex }) {
                let quotedMedia = CommonMedia(context: context)
                let quotedMediaID = "\(quotedChatMessage.id)-quoted-\(quotedChatMessageMedia.order)"
                quotedMedia.id = quotedMediaID
                mediaIDs.append(quotedMediaID)
                quotedMedia.type = quotedChatMessageMedia.type
                quotedMedia.order = quotedChatMessageMedia.order
                quotedMedia.width = Float(quotedChatMessageMedia.size.width)
                quotedMedia.height = Float(quotedChatMessageMedia.size.height)
                quotedMedia.chatQuoted = quoted
                quotedMedia.relativeFilePath = quotedChatMessageMedia.relativeFilePath
                quotedMedia.mediaDirectory = quotedChatMessageMedia.mediaDirectory
                quotedMedia.previewData = Self.quotedMediaPreviewData(mediaDirectory: quotedChatMessageMedia.mediaDirectory,
                                                                      path: quotedChatMessageMedia.relativeFilePath,
                                                                      type: quotedChatMessageMedia.type)
            }
        }

        // Update Chat Thread
        updateChatThreadOnMessageCreate(
            chatMessageRecipient: chatMessageRecipient,
            chatMessage: chatMessage,
            isMsgToYourself: isMsgToYourself,
            lastMsgMediaType: lastMsgMediaType,
            lastMsgText: (chatMessage.rawText ?? "").isEmpty ? lastMsgTextFallback : chatMessage.rawText,
            mentions: chatMessage.mentions,
            using: context)

        mainDataStore.save(context)

        didCreateMessage?(.success((messageId, mediaIDs)))

        if !isMsgToYourself {
            beginMediaUploadAndSend(chatMessage: chatMessage, didBeginUpload: didBeginUpload)
        } else {
            didBeginUpload?(.success(messageId))
        }

        return messageId
    }

    public func updateChatThreadOnMessageCreate(chatMessageRecipient: ChatMessageRecipient, chatMessage: ChatMessage, isMsgToYourself:Bool, lastMsgMediaType: CommonThread.LastMediaType, lastMsgText: String?, mentions: [MentionData], using context: NSManagedObjectContext) {
        guard let recipientId = chatMessageRecipient.recipientId else {
            DDLogError("CoreChatData/updateChatThread/ unable to update chat thread chatMessageId: \(chatMessage.id)")
            return
        }
        var chatThread: CommonThread
        let isIncomingMsg = chatMessage.fromUserID != userData.userId

        var isCurrentlyChattingWithRecipient = false
        switch chatMessageRecipient {
        case .oneToOneChat(let toUserId, let fromUserId):
            let userId = isIncomingMsg ? fromUserId : toUserId
            isCurrentlyChattingWithRecipient = isCurrentlyChatting(with: userId)
        case .groupChat(let groupId, _):
            isCurrentlyChattingWithRecipient = isCurrentlyChatting(in: groupId)
        }

        if let existingChatThread = self.chatThread(type: chatMessageRecipient.chatType, id: recipientId, in: context) {
            DDLogDebug("CoreChatData/updateChatThread/ update-thread")
            chatThread = existingChatThread
            if isIncomingMsg {
                chatThread.unreadCount = chatThread.unreadCount + 1
            } else if isCurrentlyChattingWithRecipient {
                // Sending a message always clears out the unread count when currently chatting with user
                chatThread.unreadCount = 0
            }
        } else {
            DDLogDebug("CoreChatData/updateChatThread/\(chatMessage.id)/new-thread type \(chatMessageRecipient.chatType) recipientId: \(chatMessageRecipient.recipientId ?? "")")
            chatThread = CommonThread(context: context)
            switch chatMessageRecipient.chatType {
            case .oneToOne:
                chatThread.userID = isIncomingMsg ? chatMessage.fromUserId : chatMessage.toUserId
            case .groupChat:
                chatThread.groupId = chatMessage.toGroupId
            default:
                break
            }
            chatThread.type = chatMessageRecipient.chatType
            if isIncomingMsg {
                chatThread.unreadCount = 1
            } else if isCurrentlyChattingWithRecipient {
                // Sending a message always clears out the unread count when currently chatting with user
                chatThread.unreadCount = 0
            }
        }

        let mentionText = UserProfile.text(with: chatMessage.orderedMentions, collapsedText: chatMessage.rawText, in: context)
        chatThread.lastMsgId = chatMessage.id
        chatThread.lastMsgUserId = chatMessage.fromUserId
        chatThread.lastMsgText = mentionText?.string
        chatThread.lastMsgMediaType = lastMsgMediaType
        if isIncomingMsg {
            chatThread.lastMsgStatus = .none
        } else {
            chatThread.lastMsgStatus = isMsgToYourself ? .seen : .pending
        }
        chatThread.lastMsgTimestamp = chatMessage.timestamp
    }

    public func setCurrentlyChattingWithUserId(for chatWithUserId: String?) {
        currentlyChattingWithUserId = chatWithUserId
    }

    public func setCurrentlyChattingInGroup(in groupId: GroupID?) {
        currentlyChattingInGroup = groupId
    }

    public func getCurrentlyChattingWithUserId() -> String? {
        return currentlyChattingWithUserId
    }

    public func getCurrentlyChattingInGroup() -> String? {
        return currentlyChattingInGroup
    }

    public func isCurrentlyChatting(with userId: UserID) -> Bool {
        if let currentlyChattingWithUserId = self.currentlyChattingWithUserId {
            if userId == currentlyChattingWithUserId {
                return true
            }
        }
        return false
    }

    public func isCurrentlyChatting(in groupID: GroupID) -> Bool {
        if let currentlyChattingInGroupId = self.currentlyChattingInGroup, currentlyChattingInGroupId == groupID {
            return true
        }
        return false
    }

    public func beginMediaUploadAndSend(chatMessage: ChatMessage, didBeginUpload: ((Result<ChatMessageID, Error>) -> Void)? = nil) {
        let mediaToUpload = chatMessage.allUploadableMedia.filter { [.none, .readyToUpload, .processedForUpload, .uploading, .uploadError].contains($0.status) }
        if mediaToUpload.isEmpty {
            send(message: chatMessage, completion: didBeginUpload)
        } else {
            var uploadedMediaCount = 0
            var failedMediaCount = 0
            let totalMediaCount = mediaToUpload.count
            let postID = chatMessage.id
            // chatMessageMediaStatusChangedPublisher should trigger post upload once all media has been uploaded
            mediaToUpload.forEach { media in
                guard media.status != .uploading else {
                    uploadedMediaCount += 1
                    if uploadedMediaCount + failedMediaCount == totalMediaCount {
                        if failedMediaCount == 0 {
                            didBeginUpload?(.success(postID))
                        } else {
                            didBeginUpload?(.failure(PostError.mediaUploadFailed))
                        }
                    }
                    return
                }

                commonMediaUploader.upload(mediaID: media.id) { result in
                    switch result {
                    case .success:
                        uploadedMediaCount += 1
                    case .failure:
                        failedMediaCount += 1
                    }

                    if uploadedMediaCount + failedMediaCount == totalMediaCount {
                        if failedMediaCount == 0 {
                            didBeginUpload?(.success(postID))
                        } else {
                            didBeginUpload?(.failure(PostError.mediaUploadFailed))
                        }
                    }
                }
            }
        }
    }

    private func uploadChatMessageIfMediaReady(chatMessageID: ChatMessageID) {
        let endBackgroundTask = AppContext.shared.startBackgroundTask(withName: "uploadChatMessageIfMediaReady-\(chatMessageID)")
        DDLogInfo("CoreChatData/uploadChatMessageIfMediaReady/begin \(chatMessageID)")
        mainDataStore.performSeriallyOnBackgroundContext { [weak self] context in
            guard let self = self, let chatMessage = self.chatMessage(with: chatMessageID, in: context) else {
                DDLogError("CoreChatData/uploadChatMessageIfMediaReady/Chat message not found with id \(chatMessageID)")
                endBackgroundTask()
                return
            }

            let media = chatMessage.allUploadableMedia

            let uploadedMedia = media.filter { $0.status == .uploaded }
            let failedMedia = media.filter { $0.status == .uploadError }

            // Check if all media is uploaded
            guard media.count == uploadedMedia.count + failedMedia.count else {
                endBackgroundTask()
                return
            }

            if failedMedia.isEmpty {
                // Upload post
                DDLogInfo("CoreChatData/uploadChatMessageIfMediaReady/sending \(chatMessageID)")
                self.send(message: chatMessage) { _ in
                    endBackgroundTask()
                }
            } else {
                // Mark message as failed
                DDLogInfo("CoreChatData/uploadChatMessageIfMediaReady/failed to send \(chatMessageID)")
                chatMessage.outgoingStatus = .error
                self.mainDataStore.save(context)
                endBackgroundTask()
            }
        }
    }

    private func send(message: ChatMessage, completion: ((Result<ChatMessageID, Error>) -> Void)? = nil) {
        let chatMessageID = message.id
        service.sendChatMessage(XMPPChatMessage(chatMessage: message)) { result in
            switch result {
            case .success:
                completion?(.success(chatMessageID))
            case .failure(let error):
                completion?(.failure(error))
            }
        }
    }

    /// Donates an intent to Siri for improved suggestions when sharing content.
    ///
    /// Intents are used by iOS to provide contextual suggestions to the user for certain interactions. In this case, we are suggesting the user send another message to the user they just shared with.
    /// For more information, see [this documentation](https://developer.apple.com/documentation/sirikit/insendmessageintent)\.
    /// - Parameter toUserId: The user ID for the person the user just shared with
    /// - Remark: This is different from the implementation in `ShareComposerViewController.swift` because `MainAppContext` isn't available in the share extension.
    public func addIntent(toUserId: UserID) {
        AppContext.shared.mainDataStore.performSeriallyOnBackgroundContext { context in
            let name = UserProfile.find(with: toUserId, in: context)?.displayName ?? ""
            let recipient = INSpeakableString(spokenPhrase: name)
            let sendMessageIntent = INSendMessageIntent(recipients: nil,
                                                        outgoingMessageType: .outgoingMessageText,
                                                        content: nil,
                                                        speakableGroupName: recipient,
                                                        conversationIdentifier: ConversationID(id: toUserId, type: .chat).description,
                                                        serviceName: nil, 
                                                        sender: nil,
                                                        attachments: nil)

            let potentialUserAvatar = AppContext.shared.avatarStore.userAvatar(forUserId: toUserId).image
            guard let defaultAvatar = UIImage(named: "AvatarUser") else { return }

            // Have to convert UIImage to data and then NIImage because NIImage(uiimage: UIImage) initializer was throwing exception
            guard let userAvaterUIImage = (potentialUserAvatar ?? defaultAvatar).pngData() else { return }
            let userAvatar = INImage(imageData: userAvaterUIImage)

            sendMessageIntent.setImage(userAvatar, forParameterNamed: \.speakableGroupName)

            let interaction = INInteraction(intent: sendMessageIntent, response: nil)
            interaction.donate(completion: { error in
                if let error = error {
                    DDLogDebug("ChatViewController/sendMessage/\(error.localizedDescription)")
                }
            })
        }
    }

    // MARK: - Receipts

    public func markSeenMessages(type: ChatType, for id: String, in managedObjectContext: NSManagedObjectContext) {
        var unseenChatMsgs: [ChatMessage] = []
        switch type {
        case .oneToOne:
            unseenChatMsgs = unseenChatMessages(with: id, in: managedObjectContext)
        case .groupChat:
            unseenChatMsgs = unseenGroupChatMessages(in : id, in: managedObjectContext)
        case .groupFeed:
            return
        }

        unseenChatMsgs.forEach {
            sendReceipt(for: $0, type: .read)
            $0.incomingStatus = ChatMessage.IncomingStatus.haveSeen
        }
        if managedObjectContext.hasChanges {
            try? managedObjectContext.save()
        }
    }

    public func markSeenMessage(for id: String) {
        mainDataStore.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            guard let message = self.chatMessage(with: id, in: managedObjectContext) else { return }
            guard message.fromUserID != self.userData.userId else { return }
            guard ![.haveSeen, .sentSeenReceipt].contains(message.incomingStatus) else { return }

            self.sendReceipt(for: message, type: .read)
            message.incomingStatus = .haveSeen

            if managedObjectContext.hasChanges {
                try? managedObjectContext.save()
            }
        }
    }

    public func markPlayedMessage(for id: String) {
        mainDataStore.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            guard let message = self.chatMessage(with: id, in: managedObjectContext) else { return }
            guard message.fromUserID != self.userData.userId else { return }
            guard ![.played, .sentPlayedReceipt].contains(message.incomingStatus) else { return }

            self.sendReceipt(for: message, type: .played)
            message.incomingStatus = .played

            if managedObjectContext.hasChanges {
                try? managedObjectContext.save()
            }
        }
    }

    public func sendReceipt(for chatMessage: ChatMessage, type: HalloReceipt.`Type`) {
        let messageID = chatMessage.id
        DDLogInfo("ChatData/sendReceipt/\(type) \(messageID)")
        service.sendReceipt(
            itemID: messageID,
            thread: .none,
            type: type,
            fromUserID: userData.userId,
            toUserID: chatMessage.fromUserId) { [weak self] result in
                switch result {
                case .failure(let error):
                    DDLogError("ChatData/sendReceipt/\(type)/error [\(error)]")
                case .success:
                    self?.handleReceiptAck(messageID: messageID, type: type)
                }
            }
    }

    private func handleReceiptAck(messageID: String, type: HalloReceipt.`Type`) {
        switch type {
        case .read:
            updateChatMessage(with: messageID) { (chatMessage) in
                chatMessage.incomingStatus = .sentSeenReceipt
            }
        case .played:
            updateChatMessage(with: messageID) { (chatMessage) in
                chatMessage.incomingStatus = .sentPlayedReceipt
            }
        case .delivery, .screenshot, .saved:
            DDLogInfo("CoreChatData/handleReceiptAck/\(type) [\(messageID)]")
        }
    }

    // MARK: - Updates

    private func updateChatMessage(with chatMessageId: String, block: @escaping (ChatMessage) -> (), performAfterSave: (() -> ())? = nil) {
        mainDataStore.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            defer {
                if let performAfterSave = performAfterSave {
                    performAfterSave()
                }
            }
            guard let self = self else { return }
            guard let chatMessage = self.chatMessage(with: chatMessageId, in: managedObjectContext) else {
                DDLogError("CoreChatData/update-message/missing [\(chatMessageId)]")
                return
            }
            DDLogVerbose("CoreChatData/update-existing-message [\(chatMessageId)]")
            block(chatMessage)
            if managedObjectContext.hasChanges {
                try? managedObjectContext.save()
            }
        }
    }

    open func updateThreadWithGroupFeed(_ id: FeedPostID, isInbound: Bool, using managedObjectContext: NSManagedObjectContext) {
        guard let groupFeedPost = AppContext.shared.coreFeedData.feedPost(with: id, in: managedObjectContext) else { return }
        guard let groupID = groupFeedPost.groupId else { return }

        var groupExist = true

        var chatGroup = chatGroup(groupId: groupID, in: managedObjectContext)
        if isInbound {
            // if group doesn't exist yet, create
            if chatGroup == nil {
                DDLogDebug("CoreChatData/group/updateThreadWithGroupFeed/group not exist yet [\(groupID)]")
                groupExist = false
                chatGroup = Group(context: managedObjectContext)
                chatGroup?.id = groupID
            }
        }

        chatGroup?.lastUpdate = Date()

        var lastFeedMediaType: CommonThread.LastMediaType = .none // going with the first media found

        // Process chat media
        if groupFeedPost.orderedMedia.count > 0 {
            if let firstMedia = groupFeedPost.orderedMedia.first {
                lastFeedMediaType = CommonThread.lastMediaType(for: firstMedia.type)
            }
        }

        mainDataStore.save(managedObjectContext) // extra save

        guard groupFeedPost.status != .retracted else {
            updateThreadWithGroupFeedRetract(id, using: managedObjectContext)
            return
        }

        let mentionText = UserProfile.text(with: groupFeedPost.orderedMentions, collapsedText: groupFeedPost.rawText, in: managedObjectContext)

        // Update Chat Thread
        if let chatThread = chatThread(type: .groupFeed, id: groupID, in: managedObjectContext) {
            // extra save for fetchedcontroller to notice re-ordering changes mixed in with other changes
            chatThread.lastFeedTimestamp = groupFeedPost.timestamp
            mainDataStore.save(managedObjectContext)

            chatThread.lastFeedId = groupFeedPost.id
            chatThread.lastFeedUserID = groupFeedPost.userId
            chatThread.lastFeedText = mentionText?.string ?? ""
            chatThread.lastFeedMediaType = lastFeedMediaType
            chatThread.lastFeedStatus = .none
            chatThread.lastFeedTimestamp = groupFeedPost.timestamp
            if isInbound {
                chatThread.unreadFeedCount = chatThread.unreadFeedCount + 1
            }
        } else {
            DDLogInfo("CoreChatData/saveChatMessage/ creating new thread type: \(ChatType.groupFeed) groupId: \(groupID)")
            let chatThread = CommonThread(context: managedObjectContext)
            chatThread.type = ChatType.groupFeed
            chatThread.groupId = groupID
            chatThread.lastFeedId = groupFeedPost.id
            chatThread.lastFeedUserID = groupFeedPost.userId
            chatThread.lastFeedText = mentionText?.string ?? ""
            chatThread.lastFeedMediaType = lastFeedMediaType
            chatThread.lastFeedStatus = .none
            chatThread.lastFeedTimestamp = groupFeedPost.timestamp
            if isInbound {
                chatThread.unreadFeedCount = 1
            }
        }

        mainDataStore.save(managedObjectContext)

        if isInbound {
            if !groupExist {
                getAndSyncGroup(groupId: groupID)
            }
        }
    }

    public func updateThreadWithGroupFeedRetract(_ id: FeedPostID, using managedObjectContext: NSManagedObjectContext) {
        guard let groupFeedPost = AppContext.shared.coreFeedData.feedPost(with: id, in: managedObjectContext) else { return }
        guard let groupID = groupFeedPost.groupId else { return }

        guard let thread = chatThread(type: .groupFeed, id: groupID, in: managedObjectContext) else { return }

        guard thread.lastFeedId == id else { return }

        thread.lastFeedStatus = .retracted

        mainDataStore.save(managedObjectContext)
    }

    // MARK: - Group rerequests

    // TODO: murali@: Why are we syncing after every group event.
    // This is very inefficient: we should not be doing this!
    // We should just follow our own state of groupEvents and do a weekly sync of all our groups.
    public func getAndSyncGroup(groupId: GroupID) {
        DDLogDebug("CoreChatData/group/getAndSyncGroupInfo/group \(groupId)")
        service.getGroupInfo(groupID: groupId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let group):
                self.syncGroup(group)
            case .failure(let error):
                switch error {
                case .serverError(let reason):
                    switch reason {
                    case "not_member":
                        DDLogInfo("CoreChatData/group/getGroupInfo/error/not_member/removing user")
                        self.mainDataStore.performSeriallyOnBackgroundContext { context in
                            self.deleteChatGroupMember(groupId: groupId, memberUserId: self.userData.userId, in: context)
                        }
                    default:
                        DDLogError("CoreChatData/group/getGroupInfo/error \(error)")
                    }
                default:
                    DDLogError("CoreChatData/group/getGroupInfo/error \(error)")
                }
            }
        }
    }

    // Sync group crypto state and remove non-members in sender-states and pendingUids string.
    public func syncGroup(_ xmppGroup: XMPPGroup) {
        let groupID = xmppGroup.groupId
        DDLogInfo("CoreChatData/group: \(groupID)/syncGroupInfo")

        let memberUserIDs = xmppGroup.members?.map { $0.userId } ?? []
        updateChatGroup(with: xmppGroup.groupId, block: { [weak self] (chatGroup) in
            guard let self = self else { return }
            chatGroup.lastSync = Date()

            if chatGroup.name != xmppGroup.name {
                chatGroup.name = xmppGroup.name
                self.updateChatThread(type: .groupFeed, for: xmppGroup.groupId) { (chatThread) in
                    chatThread.title = xmppGroup.name
                }
            }
            if chatGroup.desc != xmppGroup.description {
                chatGroup.desc = xmppGroup.description
            }
            if chatGroup.avatarID != xmppGroup.avatarID {
                chatGroup.avatarID = xmppGroup.avatarID
                if let avatarID = xmppGroup.avatarID {
                    AppContext.shared.avatarStore.updateOrInsertGroupAvatar(for: chatGroup.id, with: avatarID)
                }
            }
            if chatGroup.background != xmppGroup.background {
                chatGroup.background = xmppGroup.background
            }

            if let expirationType = xmppGroup.expirationType, chatGroup.expirationType != expirationType {
                chatGroup.expirationType = expirationType
            }

            if let expirationTime = xmppGroup.expirationTime, chatGroup.expirationTime != expirationTime {
                chatGroup.expirationTime = expirationTime
            }

            // look for users that are not members anymore
            chatGroup.orderedMembers.forEach { currentMember in
                let foundMember = xmppGroup.members?.first(where: { $0.userId == currentMember.userID })

                if foundMember == nil {
                    chatGroup.managedObjectContext!.delete(currentMember)
                }
            }

            var contactNames = [UserID:String]()

            // see if there are new members added or needs to be updated
            xmppGroup.members?.forEach { inboundMember in
                let foundMember = chatGroup.members?.first(where: { $0.userID == inboundMember.userId })

                // member already exists
                if let member = foundMember {
                    if let inboundType = inboundMember.type {
                        if member.type != inboundType {
                            member.type = inboundType
                        }
                    }
                } else {
                    DDLogDebug("CoreChatData/group: \(groupID)/syncGroupInfo/new/add-member [\(inboundMember.userId)]")
                    self.processGroupAddMemberAction(chatGroup: chatGroup, xmppGroupMember: inboundMember, in: chatGroup.managedObjectContext!)
                }

                // add to pushnames
                if let name = inboundMember.name, !name.isEmpty {
                    contactNames[inboundMember.userId] = name
                }
            }

            if !contactNames.isEmpty {
                UserProfile.updateNames(with: contactNames)
            }

        }, performAfterSave: {
            AppContext.shared.messageCrypter.syncGroupSession(in: groupID, members: memberUserIDs)
            DDLogInfo("CoreChatData/group: \(groupID)/syncGroupInfo/done")
        })
    }

    public func processGroupAddMemberAction(chatGroup: Group, xmppGroupMember: XMPPGroupMember, in managedObjectContext: NSManagedObjectContext) {
        DDLogDebug("CoreChatData/group/processGroupAddMemberAction/member [\(xmppGroupMember.userId)]")
        guard let xmppGroupMemberType = xmppGroupMember.type else { return }
        if let existingMember = chatGroupMember(groupId: chatGroup.id, memberUserId: xmppGroupMember.userId, in: managedObjectContext) {
            switch xmppGroupMemberType {
            case .member:
                existingMember.type = .member
            case .admin:
                existingMember.type = .admin
            }
        } else {
            let member = GroupMember(context: managedObjectContext)
            member.groupID = chatGroup.id
            member.userID = xmppGroupMember.userId
            switch xmppGroupMemberType {
            case .member:
                member.type = .member
            case .admin:
                member.type = .admin
            }
            member.group = chatGroup
        }
    }

    public func deleteChatGroupMember(groupId: GroupID, memberUserId: UserID, in managedObjectContext: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<GroupMember>(entityName: GroupMember.entity().name!)
        fetchRequest.predicate = NSPredicate(format: "groupID = %@ && userID = %@", groupId, memberUserId)

        do {
            let chatGroupMembers = try managedObjectContext.fetch(fetchRequest)
            DDLogInfo("CoreChatData/group/deleteChatGroupMember/begin count=[\(chatGroupMembers.count)]")
            chatGroupMembers.forEach {
                managedObjectContext.delete($0)
            }
        }
        catch {
            DDLogError("CoreChatData/group/deleteChatGroupMember/error  [\(error)]")
            return
        }
    }

    public func updateChatGroup(with groupId: GroupID, block: @escaping (Group) -> (), performAfterSave: (() -> ())? = nil) {
        mainDataStore.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            defer {
                if let performAfterSave = performAfterSave {
                    performAfterSave()
                }
            }
            guard let self = self else { return }
            guard let chatGroup = self.chatGroup(groupId: groupId, in: managedObjectContext) else {
                DDLogError("CoreChatData/group/updateChatGroup/missing [\(groupId)]")
                return
            }
            DDLogVerbose("CoreChatData/group/updateChatGroup [\(groupId)]")
            block(chatGroup)
            if managedObjectContext.hasChanges {
                self.mainDataStore.save(managedObjectContext)
            }
        }
    }

    public func updateChatThread(type: ChatType, for id: String, block: @escaping (CommonThread) -> Void, performAfterSave: (() -> ())? = nil) {
        mainDataStore.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            defer {
                if let performAfterSave = performAfterSave {
                    performAfterSave()
                }
            }
            guard let self = self else { return }
            guard let chatThread = self.chatThread(type: type, id: id, in: managedObjectContext) else {
                DDLogError("CoreChatData/update-chatThread/missing-thread [\(id)]")
                return
            }
            block(chatThread)
            if managedObjectContext.hasChanges {
                DDLogVerbose("CoreChatData/update-chatThread [\(id)]")
                self.mainDataStore.save(managedObjectContext)
            }
        }
    }

    // MARK: Chat group member

    public func chatGroupMembers(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext) -> [GroupMember] {
        let fetchRequest: NSFetchRequest<GroupMember> = GroupMember.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let chatGroupMembers = try managedObjectContext.fetch(fetchRequest)
            return chatGroupMembers
        }
        catch {
            DDLogError("CoreChatData/group/fetchGroupMembers/error  [\(error)]")
            fatalError("Failed to fetch chat group members")
        }
    }

    public func chatGroupMemberUserIDs(groupID: GroupID, in context: NSManagedObjectContext) -> [UserID] {
        return chatGroupMembers(predicate: NSPredicate(format: "groupID == %@", groupID), in: context).map(\.userID)
    }

    public func chatGroupMember(groupId id: GroupID, memberUserId: UserID, in managedObjectContext: NSManagedObjectContext) -> GroupMember? {
        return chatGroupMembers(predicate: NSPredicate(format: "groupID == %@ && userID == %@", id, memberUserId), in: managedObjectContext).first
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
                DDLogError("CoreChatData/handleRerequest/\(messageID)/error user mismatch [original: \(String(describing: chatMessage.toUserId))] [rerequest: \(userID)]")
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

    public func handleRerequest(for messageID: String, in groupID: GroupID, from userID: UserID, ack: (() -> Void)?) {
        handleRerequest(for: messageID, in: groupID, from: userID) { result in
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

    public func handleRerequest(for contentID: String, in groupID: GroupID, from userID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        mainDataStore.saveSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else {
                completion(.failure(.aborted))
                return
            }
            let resendInfo = self.mainDataStore.fetchContentResendInfo(for: contentID, userID: userID, in: managedObjectContext)
            resendInfo.retryCount += 1
            // retryCount indicates number of times content has been rerequested until now: increment and use it when sending.
            let rerequestCount = resendInfo.retryCount
            DDLogInfo("CoreChatData/handleRerequest/\(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount)")
            guard rerequestCount <= 5 else {
                DDLogError("CoreChatData/handleRerequest/\(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount) - aborting")
                completion(.failure(.aborted))
                return
            }

            guard let chatMessage = self.chatMessage(with: contentID, in: managedObjectContext) else {
                DDLogError("CoreChatData/handleRerequest/\(contentID)/error could not find message")
                self.service.sendContentMissing(id: contentID, type: .groupChat, to: userID) { result in
                    completion(result)
                }
                return
            }
            guard groupID == chatMessage.toGroupId else {
                DDLogError("CoreChatData/handleRerequest/\(contentID)/error group mismatch [original: \(String(describing: chatMessage.toGroupId))] [rerequest: \(groupID)]")
                completion(.failure(.aborted))
                return
            }

            switch chatMessage.outgoingStatus {
            case .retracted, .retracting:
                let retractID = chatMessage.retractID ?? PacketID.generate()
                chatMessage.retractID = retractID
                self.service.retractGroupChatMessage(messageID: retractID, groupID: groupID, to: userID, messageToRetractID: contentID, completion: completion)
            default:
                let xmppChatMessage = XMPPChatMessage(chatMessage: chatMessage)
                self.service.resendGroupChatMessage(xmppChatMessage, groupId: groupID, to: userID, rerequestCount: resendInfo.retryCount, completion: completion)
            }
        }
    }

    public func handleReactionRerequest(for reactionID: String, from userID: UserID, ack: (() -> Void)?) {
        handleReactionRerequest(for: reactionID, from: userID) { result in
            switch result {
            case .failure(let error):
                DDLogError("CoreChatData/handleReactionRerequest/\(reactionID)/error: \(error)/from: \(userID)")
                if error.canAck {
                    ack?()
                }
            case .success:
                DDLogInfo("CoreChatData/handleReactionRerequest/\(reactionID)/success/from: \(userID)")
                ack?()
            }
        }
    }

    public func handleReactionRerequest(for reactionID: String, from userID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        mainDataStore.saveSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else {
                completion(.failure(.aborted))
                return
            }
            guard let chatReaction = self.commonReaction(with: reactionID, in: managedObjectContext) else {
                DDLogError("CoreChatData/handleReactionRerequest/\(reactionID)/error could not find message")
                self.service.sendContentMissing(id: reactionID, type: .chatReaction, to: userID) { result in
                    completion(result)
                }
                return
            }
            guard userID == chatReaction.toUserID else {
                DDLogError("CoreChatData/handleReactionRerequest/\(reactionID)/error user mismatch [original: \(String(describing: chatReaction.toUserID))] [rerequest: \(userID)]")
                completion(.failure(.aborted))
                return
            }
            guard chatReaction.resendAttempts < 5 else {
                DDLogInfo("CoreChatData/handleReactionRerequest/\(reactionID)/skipping (\(chatReaction.resendAttempts) resend attempts)")
                completion(.failure(.aborted))
                return
            }
            chatReaction.resendAttempts += 1

            switch chatReaction.outgoingStatus {
            case .retracted, .retracting:
                let retractID = chatReaction.retractID.isEmpty ? PacketID.generate() : chatReaction.retractID
                chatReaction.retractID = retractID
                self.service.retractChatMessage(messageID: retractID, toUserID: userID, messageToRetractID: reactionID, completion: completion)
            default:
                guard let xmppReaction = XMPPReaction(chatReaction: chatReaction) else {
                    DDLogError("CoreChatData/handleReactionRerequest/\(reactionID)/could not create XMPP reaction to send")
                    completion(.failure(.aborted))
                    return
                }
                self.service.sendChatMessage(xmppReaction, completion: completion)
            }
        }
    }

    public func handleReactionRerequest(for reactionID: String, in groupID: GroupID, from userID: UserID, ack: (() -> Void)?) {
        handleReactionRerequest(for: reactionID, in: groupID, from: userID) { result in
            switch result {
            case .failure(let error):
                DDLogError("CoreChatData/handleReactionRerequest/\(reactionID)/error: \(error)/from: \(userID)")
                if error.canAck {
                    ack?()
                }
            case .success:
                DDLogInfo("CoreChatData/handleReactionRerequest/\(reactionID)/success/from: \(userID)")
                ack?()
            }
        }
    }

    public func handleReactionRerequest(for reactionID: String, in groupID: GroupID, from userID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        mainDataStore.saveSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else {
                completion(.failure(.aborted))
                return
            }
            let resendInfo = self.mainDataStore.fetchContentResendInfo(for: reactionID, userID: userID, in: managedObjectContext)
            resendInfo.retryCount += 1
            // retryCount indicates number of times content has been rerequested until now: increment and use it when sending.
            let rerequestCount = resendInfo.retryCount
            DDLogInfo("CoreChatData/handleReactionRerequest/\(reactionID)/userID: \(userID)/rerequestCount: \(rerequestCount)")
            guard rerequestCount <= 5 else {
                DDLogError("CoreChatData/handleReactionRerequest/\(reactionID)/userID: \(userID)/rerequestCount: \(rerequestCount) - aborting")
                completion(.failure(.aborted))
                return
            }

            guard let chatReaction = self.commonReaction(with: reactionID, in: managedObjectContext) else {
                DDLogError("CoreChatData/handleReactionRerequest/\(reactionID)/error could not find message")
                self.service.sendContentMissing(id: reactionID, type: .groupChatReaction, to: userID) { result in
                    completion(result)
                }
                return
            }
            guard groupID == chatReaction.toGroupID else {
                DDLogError("CoreChatData/handleReactionRerequest/\(reactionID)/error group mismatch [original: \(String(describing: chatReaction.toGroupID))] [rerequest: \(groupID)]")
                completion(.failure(.aborted))
                return
            }

            switch chatReaction.outgoingStatus {
            case .retracted, .retracting:
                let retractID = chatReaction.retractID.isEmpty ? PacketID.generate() : chatReaction.retractID
                chatReaction.retractID = retractID
                self.service.retractGroupChatMessage(messageID: retractID, groupID: groupID, to: userID, messageToRetractID: reactionID, completion: completion)
            default:
                guard let xmppReaction = XMPPReaction(chatReaction: chatReaction) else {
                    DDLogError("CoreChatData/handleReactionRerequest/\(reactionID)/could not create XMPP reaction to send")
                    completion(.failure(.aborted))
                    return
                }
                self.service.resendGroupChatMessage(xmppReaction, groupId: groupID, to: userID, rerequestCount: resendInfo.retryCount, completion: completion)
            }
        }
    }

    // MARK: Handle whisper messages
    // This part is not great and should be in CoreModule - but since the groups list is stored in ChatData.
    // This code is ending up here for now - should fix this soon.
    private func handleIncomingWhisperMessage(_ whisperMessage: WhisperMessage) {
        DDLogInfo("CoreChatData/handleIncomingWhisperMessage/begin")
        switch whisperMessage {
        case .update(let userID, _):
            DDLogInfo("CoreChatData/handleIncomingWhisperMessage/execute update for \(userID)")
            mainDataStore.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                guard let self = self else { return }
                let groupIds = self.chatGroupIds(for: userID, in: managedObjectContext)
                groupIds.forEach { groupId in
                    DDLogInfo("CoreChatData/handleIncomingWhisperMessage/updateWhisperSession/addToPending \(userID) in \(groupId)")
                    AppContext.shared.messageCrypter.addMembers(userIds: [userID], in: groupId)
                }

                self.recordNewChatEvent(userID: userID, type: .whisperKeysChange)
            }
        default:
            DDLogInfo("CoreChatData/handleIncomingWhisperMessage/ignore")
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
            case .album, .text, .voiceNote, .location, .files, .unsupported:
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
            chatMessage.chatMessageRecipient = tombstone.chatMessageRecipient
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
            chatMessage.chatMessageRecipient = chatMessageProtocol.chatMessageRecipient
            chatMessage.fromUserId = chatMessageProtocol.fromUserId
            chatMessage.user = UserProfile.findOrCreate(with: chatMessageProtocol.fromUserId, in: context)
            chatMessage.feedPostId = chatMessageProtocol.context.feedPostID
            chatMessage.feedPostMediaIndex = chatMessageProtocol.context.feedPostMediaIndex

            chatMessage.chatReplyMessageID = chatMessageProtocol.context.chatReplyMessageID
            chatMessage.chatReplyMessageSenderID = chatMessageProtocol.context.chatReplyMessageSenderID
            chatMessage.chatReplyMessageMediaIndex = chatMessageProtocol.context.chatReplyMessageMediaIndex
            chatMessage.forwardCount = chatMessageProtocol.context.forwardCount

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
            case .album(let mentionText, let media):
                chatMessage.rawText = mentionText.collapsedText
                chatMessage.mentions = mentionText.mentionsArray
                if let mediaType = media.first?.mediaType {
                    lastMsgMediaType = CommonThread.lastMediaType(for: mediaType)
                } else {
                    lastMsgMediaType = .none
                }
            case .voiceNote(let xmppMedia):
                guard (xmppMedia.url) != nil else { break }
                chatMessage.rawText = ""
                lastMsgMediaType = .audio
            case .text(let mentionText, _):
                chatMessage.rawText = mentionText.collapsedText
                chatMessage.mentions = mentionText.mentionsArray
            case .reaction(let emoji):
                DDLogDebug("CoreChatData/saveChatMessage/processing reaction as message")
                chatMessage.rawText = emoji
            case .location(let chatLocation):
                chatMessage.location = CommonLocation(chatLocation: chatLocation, context: context)
                lastMsgMediaType = .location
            case .files:
                chatMessage.rawText = ""
                lastMsgMediaType = .document
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
                chatMedia.name = media.name
                chatMedia.message = chatMessage
            }

            // Process quoted content.
            if let feedPostId = chatMessageProtocol.context.feedPostID {
                // Process Quoted Feedpost
                if let quotedFeedPost = AppContext.shared.coreFeedData.feedPost(with: feedPostId, in: context) {
                    if quotedFeedPost.isMoment {
                        Self.copyQuotedMoment(to: chatMessage,
                                            from: quotedFeedPost,
                                   selfieLeading: quotedFeedPost.isMomentSelfieLeading,
                                           using: context)
                    } else {
                        Self.copyQuoted(to: chatMessage, from: quotedFeedPost, using: context)
                    }
                }
            } else if let chatReplyMsgId = chatMessageProtocol.context.chatReplyMessageID {
                // Process Quoted Message
                if let quotedChatMessage = self.chatMessage(with: chatReplyMsgId, in: context) {
                    Self.copyQuoted(to: chatMessage, from: quotedChatMessage, using: context)
                }
            }

            // Update Chat Thread
            if let recipientId = chatMessage.chatMessageRecipient.recipientId {
                if let chatThread = self.chatThread(type: chatMessage.chatMessageRecipient.chatType, id: recipientId, in: context) {
                    chatThread.lastMsgTimestamp = chatMessage.timestamp
                    chatThread.lastMsgId = chatMessage.id
                    chatThread.lastMsgUserId = chatMessage.fromUserId
                    let mentionText = UserProfile.text(with: chatMessage.orderedMentions, collapsedText: chatMessage.rawText, in: context)

                    chatThread.lastMsgText = mentionText?.string
                    chatThread.lastMsgMediaType = lastMsgMediaType
                    chatThread.lastMsgStatus = .none
                    chatThread.lastMsgTimestamp = chatMessage.timestamp
                    chatThread.unreadCount = chatThread.unreadCount + 1
                } else {
                    let chatThread = CommonThread(context: context)
                    DDLogInfo("CoreChatData/saveChatMessage/ creating new thread type: \(chatMessage.chatMessageRecipient.chatType) recipient: \(chatMessage.chatMessageRecipient.recipientId ?? "")")
                    switch chatMessage.chatMessageRecipient.chatType {
                    case .oneToOne:
                        chatThread.userID = chatMessage.chatMessageRecipient.recipientId
                        chatThread.groupId = nil
                        chatThread.type = chatMessage.chatMessageRecipient.chatType
                    case .groupChat:
                        chatThread.userID = nil
                        chatThread.groupId = chatMessage.chatMessageRecipient.toGroupId
                        chatThread.type = chatMessage.chatMessageRecipient.chatType
                    default:
                        break
                    }
                    chatThread.lastMsgId = chatMessage.id
                    chatThread.lastMsgUserId = chatMessage.fromUserId
                    let mentionText = UserProfile.text(with: chatMessage.orderedMentions, collapsedText: chatMessage.rawText, in: context)

                    chatThread.lastMsgText = mentionText?.string
                    chatThread.lastMsgMediaType = lastMsgMediaType
                    chatThread.lastMsgStatus = .none
                    chatThread.lastMsgTimestamp = chatMessage.timestamp
                    chatThread.unreadCount = 1
                }
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

            // Remove reaction from the same author on the same content if any.
            if let chatReplyMsgId = chatMessageProtocol.context.chatReplyMessageID {
                if let duplicateReaction = self.commonReaction(from: chatMessageProtocol.fromUserId, on: chatReplyMsgId, in: context) {
                    context.delete(duplicateReaction)
                    DDLogInfo("CoreChatData/saveReaction/remove-old-reaction/reactionID [\(duplicateReaction.id)]")
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
            commonReaction.chatMessageRecipient = chatMessageProtocol.chatMessageRecipient
            commonReaction.fromUserID = chatMessageProtocol.fromUserId
            switch chatMessageProtocol.content {
            case .reaction(let emoji):
                commonReaction.emoji = emoji
            case .album, .text, .voiceNote, .location, .files, .unsupported:
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
    public static func copyQuoted(to chatMessage: ChatMessage, from chatQuoted: ChatQuotedProtocol, using managedObjectContext: NSManagedObjectContext) {
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

            copyMediaToQuotedMedia(fromDir: chatQuotedMediaItem.mediaDirectory,
                                  fromPath: chatQuotedMediaItem.relativeFilePath,
                                        to: quotedMedia)
        }
    }

    public static func copyQuotedMoment(to chatMessage: ChatMessage,
                                        from chatQuoted: ChatQuotedProtocol,
                                        selfieLeading: Bool,
                                        using context: NSManagedObjectContext) {

        DDLogInfo("CoreChatData/copyQuotedMoment/\(chatMessage.id)")
        let quoted = ChatQuoted(context: context)
        quoted.type = chatQuoted.type
        quoted.userID = chatQuoted.userId
        quoted.rawText = quoted.rawText
        quoted.mentions = quoted.mentions
        quoted.message = chatMessage

        guard let first = chatQuoted.mediaList.first(where: { $0.order == 0 }) else {
            return
        }

        let quotedMedia = CommonMedia(context: context)
        quotedMedia.id = "\(quoted.message?.id ?? UUID().uuidString)-quoted-moment"
        quotedMedia.type = .image
        quotedMedia.order = 0
        quotedMedia.chatQuoted = quoted

        if chatQuoted.mediaList.count > 1, let second = chatQuoted.mediaList.first(where: { $0.order == 1 }) {
            let leadingMedia = selfieLeading ? second : first
            let trailingMedia = selfieLeading ? first : second

            DDLogInfo("CoreChatData/copyQuotedMoment/dual image")
            createDualMomentPreview(directory: leadingMedia.mediaDirectory,
                                  leadingPath: leadingMedia.relativeFilePath,
                                 trailingPath: trailingMedia.relativeFilePath,
                                  quotedMedia: quotedMedia)
        } else {
            DDLogInfo("CoreChatData/copyQuotedMoment/single image")
            copyMediaToQuotedMedia(fromDir: first.mediaDirectory, fromPath: first.relativeFilePath, to: quotedMedia)
        }
    }

    public static func copyMediaToQuotedMedia(fromDir: MediaDirectory, fromPath: String?, to quotedMedia: CommonMedia) {
        guard let fromRelativePath = fromPath else {
            return
        }

        let fromURL = fromDir.fileURL(forRelativePath: fromRelativePath)
        DDLogInfo("ChatData/copyMediaToQuotedMedia/fromURL: \(fromURL)")

        // Store references to the quoted media directory and file path.
        quotedMedia.relativeFilePath = fromRelativePath
        quotedMedia.mediaDirectory = fromDir

        // Generate thumbnail for the media: so that each message can have its own copy.
        let previewImage: UIImage?
        switch quotedMedia.type {
        case .image:
            previewImage = UIImage(contentsOfFile: fromURL.path)
        case .video:
            previewImage = VideoUtils.videoPreviewImage(url: fromURL)
        case .audio:
            previewImage = nil // no image to preview
        case .document:
            previewImage = nil // not currently showing preview in quoted panel
        }

        guard let previewImage else {
            DDLogError("ChatData/copyMediaToQuotedMedia/unable to generate thumbnail image for media url: \(fromURL)")
            return
        }

        quotedMedia.previewData = VideoUtils.previewImageData(image: previewImage)
    }

    private static func createDualMomentPreview(directory: MediaDirectory, leadingPath: String?, trailingPath: String?, quotedMedia: CommonMedia) {
        guard
            let leadingPath,
            let trailingPath,
            let leadingImage = UIImage(contentsOfFile: directory.fileURL(forRelativePath: leadingPath).path),
            let trailingImage = UIImage(contentsOfFile: directory.fileURL(forRelativePath: trailingPath).path),
            let composited = UIImage.combine(leading: leadingImage, trailing: trailingImage, maximumLength: 128)
        else {
            DDLogError("CoreChatData/createDualMomentPreview/failed with leading [\(leadingPath ?? "nil")] trailing [\(trailingPath ?? "nil")]")
            return
        }

        quotedMedia.previewData = composited.jpegData(compressionQuality: 0.5)
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

    public func commonReaction(from userID: UserID, on messageID: ChatMessageID, in managedObjectContext: NSManagedObjectContext) -> CommonReaction? {
        let fetchRequest: NSFetchRequest<CommonReaction> = CommonReaction.fetchRequest()

        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "fromUserID == %@ && message.id == %@", userID, messageID)
        ])
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let reactions = try managedObjectContext.fetch(fetchRequest)
            return reactions.first
        } catch {
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
        switch type {
        case .oneToOne:
            return chatThreads(predicate: NSPredicate(format: "userID == %@", id), in: managedObjectContext).first
        case .groupChat, .groupFeed:
            return chatThreads(predicate: NSPredicate(format: "groupID == %@ && typeValue = %d", id, type.rawValue), in: managedObjectContext).first
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
            DDLogError("CoreChatData/fetch-messages/error  [\(error)]")
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

    // MARK: - Util

    private static func quotedMediaPreviewData(mediaDirectory: MediaDirectory, path: String?, type: CommonMediaType) -> Data? {
        guard let path = path else {
            return nil
        }

        let mediaURL = mediaDirectory.fileURL(forRelativePath: path)

        let previewImage: UIImage?
        switch type {
        case .image:
            previewImage = UIImage(contentsOfFile: mediaURL.path)
        case .video:
            previewImage = VideoUtils.videoPreviewImage(url: mediaURL)
        case .audio, .document:
            previewImage = nil // No image to preview
        }

        return previewImage.flatMap { VideoUtils.previewImageData(image: $0) }
    }
}


// MARK: Chat Events
extension CoreChatData {

    public func recordNewChatEvent(userID: UserID, type: ChatEventType) {
        mainDataStore.saveSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            DDLogInfo("CoreChatData/recordNewChatEvent/for: \(userID)")

            let appUserID = AppContext.shared.userData.userId
            let predicate = NSPredicate(format: "(fromUserID = %@ AND toUserID = %@) || (toUserID = %@ AND fromUserID = %@)", userID, appUserID, userID, appUserID)
            guard self.chatMessages(predicate: predicate, limit: 1, in: managedObjectContext).count > 0 else {
                DDLogInfo("CoreChatData/recordNewChatEvent/\(userID)/no messages yet, skip recording keys change event")
                return
            }

            let chatEvent = ChatEvent(context: managedObjectContext)
            chatEvent.userID = userID
            chatEvent.type = type
            chatEvent.timestamp = Date()
        }
    }

    public func deleteChatEvents(userID: UserID) {
        DDLogInfo("CoreChatData/deleteChatEvents")
        mainDataStore.saveSeriallyOnBackgroundContext { (managedObjectContext) in
            let fetchRequest = NSFetchRequest<ChatEvent>(entityName: ChatEvent.entity().name!)
            fetchRequest.predicate = NSPredicate(format: "userID = %@", userID)

            do {
                let events = try managedObjectContext.fetch(fetchRequest)
                DDLogInfo("CoreChatData/events/deleteChatEvents/count=[\(events.count)]")
                events.forEach {
                    managedObjectContext.delete($0)
                }
            }
            catch {
                DDLogError("CoreChatData/events/deleteChatEvents/error  [\(error)]")
                return
            }
        }
    }

    public func processGroupHistoryPayload(historyPayload: Clients_GroupHistoryPayload?, withGroupMessage group: HalloGroup) {
        guard let sender = group.sender else {
            DDLogError("ChatData/didReceiveHistoryPayload/invalid group here: \(group)")
            return
        }
        let groupID = group.groupId

        // Check if self is a newly added member to the group
        let memberDetails = historyPayload?.memberDetails
        let ownUserID = userData.userId
        let isSelfANewMember = memberDetails?.contains(where: { $0.uid == Int64(ownUserID) }) ?? false

        // If self is a new member then we can just ignore.
        // Nothing to share with anyone else.
        if isSelfANewMember {
            DDLogInfo("ChatData/didReceiveHistoryPayload/\(groupID)/self is newly added member - ignore historyResend stanza")
            let numExpected = historyPayload?.contentDetails.count ?? 0
            AppContext.shared.cryptoData.resetFeedHistory(groupID: groupID, timestamp: Date(), numExpected: numExpected)
            if let contentDetails = historyPayload?.contentDetails {
                AppContext.shared.coreFeedData.createTombstones(for: groupID, with: contentDetails)
            }

        } else if let historyPayload = historyPayload,
                  sender != userData.userId {
            // Members of the group on receiving a historyPayload stanza
            // Must verify keys and hashes and then share the content.
            DDLogInfo("ChatData/didReceiveHistoryPayload/\(groupID)/from: \(sender)/processing")
            processGroupFeedHistoryResend(historyPayload, for: group.groupId, fromUserID: sender)

        } else if sender == userData.userId {
            // For admin who added the members
            // share authored group feed history to all new member uids.
            let newlyAddedMembers = group.members?.filter { $0.action == .add } ?? []
            let newMemberUids = newlyAddedMembers.map{ $0.userId }

            mainDataStore.performSeriallyOnBackgroundContext { managedObjectContext in
                let (postsData, commentsData) = AppContext.shared.coreFeedData.authoredFeedHistory(for: groupID, in: managedObjectContext)

                DDLogInfo("ChatData/didReceiveHistoryPayload/\(groupID)/from self/processing")
                self.shareGroupFeedItems(posts: postsData, comments: commentsData, in: groupID, to: newMemberUids)
            }
        } else {
            DDLogInfo("ChatData/didReceiveHistoryPayload/\(groupID)/error - unexpected stanza")
        }

    }

    public func processGroupFeedHistoryResend(_ historyPayload: Clients_GroupHistoryPayload, for groupID: GroupID, fromUserID: UserID) {
        // Check if sender is a friend.
        // If yes - then verify the hash of the contents and send them to the new members.
        // Else - log and return

        mainDataStore.performSeriallyOnBackgroundContext { managedObjectContext in
            let isFriend = UserProfile.find(with: fromUserID, in: managedObjectContext)?.friendshipStatus ?? .none == .friends

            guard isFriend else {
                DDLogInfo("ChatData/processGroupFeedHistory/\(groupID)/sendingAdmin is not friend - ignore historyResend stanza")
                return
            }

            let contentsDetails = historyPayload.contentDetails
            var contentsHashDict = [String: Data]()
            contentsDetails.forEach { contentDetails in
                switch contentDetails.contentID {
                case .postIDContext(let postIdContext):
                    contentsHashDict[postIdContext.feedPostID] = contentDetails.contentHash
                case .commentIDContext(let commentIdContext):
                    contentsHashDict[commentIdContext.commentID] = contentDetails.contentHash
                case .none:
                    break
                }
            }

            let (postsData, commentsData) = AppContext.shared.coreFeedData.authoredFeedHistory(for: groupID, in: managedObjectContext)
            var postsToShare: [PostData] = []
            var commentsToShare: [CommentData] = []
            do {
                for post in postsData {
                    let contentData = try post.clientContainer.serializedData()
                    let actualHash = SHA256.hash(data: contentData).data
                    let expectedHash = contentsHashDict[post.id]
                    if let expectedHash = expectedHash,
                       expectedHash == actualHash {
                        postsToShare.append(post)
                    } else {
                        DDLogError("ChatData/processGroupFeedHistory/\(groupID)/post: \(post.id)/hash mismatch/expected: \(String(describing: expectedHash))/actual: \(actualHash)")
                    }
                }
                for comment in commentsData {
                    let contentData = try comment.clientContainer.serializedData()
                    let actualHash = SHA256.hash(data: contentData).data
                    let expectedHash = contentsHashDict[comment.id]
                    if let expectedHash = expectedHash,
                       expectedHash == actualHash {
                        commentsToShare.append(comment)
                    } else {
                        DDLogError("ChatData/processGroupFeedHistory/\(groupID)/comment: \(comment.id)/hash mismatch/expected: \(String(describing: expectedHash))/actual: \(actualHash)")
                    }
                }

                // Fetch identity keys of new members and compare with received keys.
                var numberOfFailedVerifications = 0
                let verifyKeysGroup = DispatchGroup()
                var newMemberUids: [UserID] = []
                let totalNewMemberUids = historyPayload.memberDetails.count
                historyPayload.memberDetails.forEach { memberDetails in
                    verifyKeysGroup.enter()
                    let memberUid = UserID(memberDetails.uid)
                    AppContext.shared.messageCrypter.setupOutbound(for: memberUid) { result in
                        switch result {
                        case .success(let keyBundle):
                            let expected = keyBundle.inboundIdentityPublicEdKey
                            let actual = memberDetails.publicIdentityKey
                            if expected == actual {
                                DDLogInfo("ChatData/processGroupFeedHistory/\(groupID)/verified \(memberUid) successfully")
                                newMemberUids.append(memberUid)
                            } else {
                                DDLogError("ChatData/processGroupFeedHistory/\(groupID)/failed verification of \(memberUid)/expected: \(expected.bytes.prefix(4))/actual: \(actual.bytes.prefix(4))")
                                numberOfFailedVerifications += 1
                            }
                        case .failure(let error):
                            DDLogError("ChatData/processGroupFeedHistory/\(groupID)/failed to verify \(memberUid)/\(error)")
                            numberOfFailedVerifications += 1
                        }
                        verifyKeysGroup.leave()
                    }
                }

                // After verification - share group feed items to the verified new members.
                verifyKeysGroup.notify(queue: .main) { [weak self] in
                    guard let self = self else { return }
                    if numberOfFailedVerifications > 0 {
                        DDLogError("ProtoServiceCore/modifyGroup/\(groupID)/fetchMemberKeysCompletion/error - num: \(numberOfFailedVerifications)/\(totalNewMemberUids)")
                    }

                    // Now encrypt and send the stanza to the verified members.
                    DDLogInfo("ChatData/processGroupFeedHistory/\(groupID)/postsToShare: \(postsToShare.count)/commentsToShare: \(commentsToShare.count)")
                    self.shareGroupFeedItems(posts: postsToShare, comments: commentsToShare, in: groupID, to: newMemberUids)
                }
            } catch {
                DDLogError("ChatData/processGroupFeedHistory/\(groupID)/failed serializing content: \(error)")
            }
        }
    }

    public func shareGroupFeedItems(posts: [PostData], comments: [CommentData], in groupID: GroupID, to memberUids: [UserID]) {
        var groupFeedItemsToShare: [Server_GroupFeedItem] = []
        for post in posts {
            if let serverPost = post.serverPost {
                var serverGroupFeedItem = Server_GroupFeedItem()
                switch post.content {
                case .unsupported, .waiting, .moment:
                    // This cannot happen - since we are always sharing our own content.
                    // our own content can never be unsupported or waiting
                    // moments are only for the home feed
                    DDLogError("ChatData/shareGroupFeedItems/\(groupID)/post: \(post.id)/invalid content here: \(post.content)")
                    continue
                case .retracted:
                    serverGroupFeedItem.action = .retract
                case .album, .text, .voiceNote:
                    serverGroupFeedItem.action = .publish
                }
                serverGroupFeedItem.expiryTimestamp = post.expiration.flatMap { Int64($0.timeIntervalSince1970) } ?? -1
                serverGroupFeedItem.post = serverPost
                serverGroupFeedItem.isResentHistory = true
                groupFeedItemsToShare.append(serverGroupFeedItem)
            } else {
                DDLogError("ChatData/shareGroupFeedItems/\(groupID)/post: \(post.id)/invalid proto")
            }
        }
        for comment in comments {
           if let serverComment = comment.serverComment {
                var serverGroupFeedItem = Server_GroupFeedItem()
               switch comment.content {
               case .unsupported, .waiting:
                   // This cannot happen - since we are always sharing our own content.
                   // our own content can never be unsupported or waiting
                   DDLogError("ChatData/shareGroupFeedItems/\(groupID)/comment: \(comment.id)/invalid content here: \(comment.content)")
                   continue
               case .retracted:
                   serverGroupFeedItem.action = .retract
               case .album, .text, .reaction, .voiceNote:
                   serverGroupFeedItem.action = .publish
               }
                serverGroupFeedItem.comment = serverComment
               serverGroupFeedItem.isResentHistory = true
                groupFeedItemsToShare.append(serverGroupFeedItem)
            } else {
                DDLogError("ChatData/shareGroupFeedItems/\(groupID)/comment: \(comment.id)/invalid proto")
            }
        }
        DDLogInfo("ChatData/shareGroupFeedItems/\(groupID)/items count: \(groupFeedItemsToShare.count)")
        var groupFeedItemsStanza = Server_GroupFeedItems()
        groupFeedItemsStanza.gid = groupID
        groupFeedItemsStanza.items = groupFeedItemsToShare
        // We need to encrypt this stanza and send it to all the new member uids.
        memberUids.forEach { memberUid in
            service.shareGroupHistory(items: groupFeedItemsStanza, with: memberUid) { result in
                switch result {
                case .success:
                    DDLogInfo("ChatData/shareGroupFeedItems/\(groupID)/sent successfully to \(memberUid)")
                case .failure(let error):
                    DDLogError("ChatData/shareGroupFeedItems/\(groupID)/failed sending to \(memberUid)/error: \(error)")
                }
            }
        }
    }

    // MARK: Groups
    public func processIncomingXMPPGroup(_ group: XMPPGroup) {
        mainDataStore.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            self.processIncomingGroup(xmppGroup: group, using: managedObjectContext)
        }
    }

    public func processIncomingGroup(xmppGroup: XMPPGroup, using managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/processIncomingGroup")

        var contactNames = [UserID:String]()
        // Update push names for member userids on any events received.
        xmppGroup.members?.forEach { inboundMember in
            // add to pushnames
            if let name = inboundMember.name, !name.isEmpty {
                contactNames[inboundMember.userId] = name
            }
        }
        UserProfile.updateNames(with: contactNames)
        // Saving push names early on will help us show push names for events/content from these users.

        switch xmppGroup.action {
        case .create:
            processGroupCreateAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .join:
            processGroupJoinAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .leave:
            processGroupLeaveAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .modifyMembers, .modifyAdmins, .autoPromoteAdmins:
            processGroupModifyMembersAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .changeName:
            processGroupChangeNameAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .changeDescription:
            processGroupChangeDescriptionAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .changeAvatar:
            processGroupChangeAvatarAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .setBackground:
            processGroupSetBackgroundAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .get:
            // Sync group if we get a message from the server.
            syncGroup(xmppGroup)
        case .changeExpiry:
            processGroupChangeExpiryAction(xmppGroup: xmppGroup, in: managedObjectContext)

        default: break
        }

        mainDataStore.save(managedObjectContext)
    }

    public func processGroupCreateAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext, recordEvent: Bool = true) {

        let chatGroup = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)

        var contactNames = [UserID:String]()

        // Add Group Creator
        if let existingCreator = chatGroupMember(groupId: xmppGroup.groupId, memberUserId: xmppGroup.sender ?? "", in: managedObjectContext) {
            existingCreator.type = .admin
        } else {
            guard let sender = xmppGroup.sender else { return }
            let groupCreator =  GroupMember(context: managedObjectContext)
            groupCreator.groupID = xmppGroup.groupId
            groupCreator.userID = sender
            groupCreator.type = .admin
            groupCreator.group = chatGroup

            if let name = xmppGroup.senderName {
                contactNames[sender] = name
            }
        }

        // Add new Group members to database
        for xmppGroupMember in xmppGroup.members ?? [] {
            DDLogDebug("ChatData/group/process/new/add-member [\(xmppGroupMember.userId)]")
            processGroupAddMemberAction(chatGroup: chatGroup, xmppGroupMember: xmppGroupMember, in: managedObjectContext)

            // add to pushnames
            if let name = xmppGroupMember.name, !name.isEmpty {
                contactNames[xmppGroupMember.userId] = name
            }
        }

        if !contactNames.isEmpty {
            UserProfile.updateNames(with: contactNames)
        }
        if recordEvent {
            recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
        }
    }

    public func processGroupJoinAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext, recordEvent: Bool = true) {
        DDLogInfo("ChatData/group/processGroupJoinAction")
        let group = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)

        var membersAdded: [UserID] = []
        for xmppGroupMember in xmppGroup.members ?? [] {
            guard xmppGroupMember.action == .join else { continue }

            membersAdded.append(xmppGroupMember.userId)
            // add pushname first before recording message since user could be new
            var contactNames = [UserID:String]()
            if let name = xmppGroupMember.name, !name.isEmpty {
                contactNames[xmppGroupMember.userId] = name
            }
            if !contactNames.isEmpty {
                UserProfile.updateNames(with: contactNames)
            }

            processGroupAddMemberAction(chatGroup: group, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
            if recordEvent {
                recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
            }
        }

        // Update group crypto state.
        if !membersAdded.isEmpty {
            AppContext.shared.messageCrypter.addMembers(userIds: membersAdded, in: xmppGroup.groupId)
        }
        getAndSyncGroup(groupId: xmppGroup.groupId)
    }

    public func processGroupLeaveAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext, recordEvent: Bool = true) {
        // If the group no longer exists, and we're the removed member, we've likely deleted the group.  Do not attempt to recreate or add events.
        if chatGroup(groupId: xmppGroup.groupId, in: managedObjectContext) == nil,
           xmppGroup.members?.count == 1, let member = xmppGroup.members?.first, member.action == .leave, member.userId == userData.userId {
            DDLogDebug("ChatData/group/process/new/skip-leave-member [\(xmppGroup.groupId)]")
            return
        }

        _ = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)

        var membersRemoved: [UserID] = []
        for xmppGroupMember in xmppGroup.members ?? [] {
            DDLogDebug("ChatData/group/process/new/leave-member [\(xmppGroupMember.userId)]")
            guard xmppGroupMember.action == .leave else { continue }
            deleteChatGroupMember(groupId: xmppGroup.groupId, memberUserId: xmppGroupMember.userId, in: managedObjectContext)

            membersRemoved.append(xmppGroupMember.userId)
            if xmppGroupMember.userId != AppContext.shared.userData.userId {
                getAndSyncGroup(groupId: xmppGroup.groupId)
            }
            if recordEvent {
                recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
            }
        }

        // Update group crypto state.
        if !membersRemoved.isEmpty {
            AppContext.shared.messageCrypter.removeMembers(userIds: membersRemoved, in: xmppGroup.groupId)
        }
        // TODO: murali@: should we clear our crypto session here?
        // but what if messages arrive out of order from the server.
    }

    public func processGroupModifyMembersAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext, recordEvent: Bool = true) {
        DDLogDebug("ChatData/group/processGroupModifyMembersAction")
        let group = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)

        var membersAdded: [UserID] = []
        var membersRemoved: [UserID] = []
        for xmppGroupMember in xmppGroup.members ?? [] {
            DDLogDebug("ChatData/group/process/modifyMembers [\(xmppGroupMember.userId)]/action: \(String(describing: xmppGroupMember.action))")

            // add pushname first before recording message since user could be new
            var contactNames = [UserID:String]()
            if let name = xmppGroupMember.name, !name.isEmpty {
                contactNames[xmppGroupMember.userId] = name
            }
            if !contactNames.isEmpty {
                UserProfile.updateNames(with: contactNames)
            }

            switch xmppGroupMember.action {
            case .add:
                membersAdded.append(xmppGroupMember.userId)
                processGroupAddMemberAction(chatGroup: group, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
            case .remove:
                membersRemoved.append(xmppGroupMember.userId)
                deleteChatGroupMember(groupId: xmppGroup.groupId, memberUserId: xmppGroupMember.userId, in: managedObjectContext)
            case .promote:
                if let foundMember = group.members?.first(where: { $0.userID == xmppGroupMember.userId }) {
                    foundMember.type = .admin
                }
            case .demote:
                if let foundMember = group.members?.first(where: { $0.userID == xmppGroupMember.userId }) {
                    foundMember.type = .member
                }
            default:
                break
            }

            if recordEvent {
                recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
            }
        }

        // Always add members to group crypto session first and then remove members.
        // This ensures that we clear our outgoing state for sure!
        if !membersAdded.isEmpty {
            AppContext.shared.messageCrypter.addMembers(userIds: membersAdded, in: xmppGroup.groupId)
        }
        if !membersRemoved.isEmpty {
            AppContext.shared.messageCrypter.removeMembers(userIds: membersRemoved, in: xmppGroup.groupId)
        }
        getAndSyncGroup(groupId: xmppGroup.groupId)
    }

    public func processGroupChangeNameAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext, recordEvent: Bool = true) {
        DDLogInfo("ChatData/group/processGroupChangeNameAction")
        let group = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        group.name = xmppGroup.name
        updateChatThread(type: xmppGroup.groupType, for: xmppGroup.groupId) { (chatThread) in
            chatThread.title = xmppGroup.name
        }
        if recordEvent {
            recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
        }
        getAndSyncGroup(groupId: xmppGroup.groupId)
    }

    public func processGroupChangeDescriptionAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext, recordEvent: Bool = true) {
        DDLogInfo("ChatData/group/processGroupChangeDescriptionAction")
        let group = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        group.desc = xmppGroup.description
        mainDataStore.save(managedObjectContext)
        if recordEvent {
            recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
        }
        getAndSyncGroup(groupId: xmppGroup.groupId)
    }

    public func processGroupChangeAvatarAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext, recordEvent: Bool = true) {
        DDLogInfo("ChatData/group/processGroupChangeAvatarAction")
        let group = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        group.avatarID = xmppGroup.avatarID
        if let avatarID = xmppGroup.avatarID {
            AppContext.shared.avatarStore.updateOrInsertGroupAvatar(for: group.id, with: avatarID)
        }
        if recordEvent {
            recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
        }
        getAndSyncGroup(groupId: xmppGroup.groupId)
    }

    public func processGroupSetBackgroundAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext, recordEvent: Bool = true) {
        DDLogInfo("ChatData/group/processGroupSetBackgroundAction")
        let group = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        group.background = xmppGroup.background
        mainDataStore.save(managedObjectContext)
        if recordEvent {
            recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
        }
        getAndSyncGroup(groupId: xmppGroup.groupId)
    }

    public func processGroupCreateIfNotExist(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) -> Group {
        DDLogDebug("ChatData/group/processGroupCreateIfNotExist/ [\(xmppGroup.groupId)]")
        if let existingChatGroup = chatGroup(groupId: xmppGroup.groupId, in: managedObjectContext) {
            DDLogDebug("ChatData/group/processGroupCreateIfNotExist/groupExist [\(xmppGroup.groupId)]")
            return existingChatGroup
        } else {
            return addGroup(xmppGroup: xmppGroup, in: managedObjectContext)
        }
    }

    public func processGroupChangeExpiryAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext, recordEvent: Bool = true) {
        DDLogInfo("ChatData/group/processGroupChangeExpiry")
        guard let expirationType = xmppGroup.expirationType, let expirationTime = xmppGroup.expirationTime else {
            DDLogInfo("ChatData/group/processGroupChangeExpiry/Did not get a valid expirationType")
            return
        }
        let group = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        group.expirationType = expirationType
        group.expirationTime = expirationTime
        mainDataStore.save(managedObjectContext)
        if recordEvent {
            recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
        }
        getAndSyncGroup(groupId: xmppGroup.groupId)
    }

    public func addGroup(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) -> Group {
        DDLogDebug("ChatData/group/addGroup/new [\(xmppGroup.groupId)]")

        // Add Group to database
        let chatGroup = Group(context: managedObjectContext)
        chatGroup.id = xmppGroup.groupId
        chatGroup.name = xmppGroup.name
        chatGroup.type = xmppGroup.groupType
        chatGroup.lastUpdate = Date()
        if let expirationTime = xmppGroup.expirationTime, let expirationType = xmppGroup.expirationType {
            chatGroup.expirationTime = expirationTime
            chatGroup.expirationType = expirationType
        } else {
            chatGroup.expirationTime = .thirtyDays
            chatGroup.expirationType = .expiresInSeconds
        }

        // Add Chat Thread
        if chatThread(type: xmppGroup.groupType, id: chatGroup.id, in: managedObjectContext) == nil {
            let chatThread = CommonThread(context: managedObjectContext)
            chatThread.type = xmppGroup.groupType
            chatThread.groupId = chatGroup.id
            chatThread.title = chatGroup.name
            chatThread.lastMsgTimestamp = Date()
        }
        return chatGroup
    }

    func groupFeedEvents(with groupID: GroupID, in managedObjectContext: NSManagedObjectContext) -> [GroupEvent] {
        let cutOffDate = Date(timeIntervalSinceNow: -Date.days(31))
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \GroupEvent.timestamp, ascending: true)
        ]

        let fetchRequest = GroupEvent.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "groupID == %@ && timestamp >= %@", groupID, cutOffDate as NSDate)
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let events = try managedObjectContext.fetch(fetchRequest)
            return events
        }
        catch {
            DDLogError("ChatData/group/fetch-events/error  [\(error)]")
            return []
        }
    }

    private func recordGroupMessageEvent(xmppGroup: XMPPGroup, xmppGroupMember: XMPPGroupMember?, in managedObjectContext: NSManagedObjectContext) {
        DDLogVerbose("ChatData/recordGroupMessageEvent/groupID/\(xmppGroup.groupId)")

        // hack: skip recording the event(s) of an avatar change and/or description change if the changes are done at group creation,
        // since server api require separate requests for them but we want to show only the group creation event
        // rough check by comparing if the last event (also first) was a group creation event and if avatar/description changes happened right after
        let groupFeedEventsList = groupFeedEvents(with: xmppGroup.groupId, in: managedObjectContext)
        if let lastEvent = groupFeedEventsList.last,
           [.create].contains(lastEvent.action),
           lastEvent.memberUserID == xmppGroupMember?.userId,
           [.changeAvatar, .changeDescription].contains(xmppGroup.action),
           let diff = Calendar.current.dateComponents([.second], from: lastEvent.timestamp, to: Date()).second,
           diff < 3 {
            return
        }

        let event = GroupEvent(context: managedObjectContext)
        event.senderUserID = xmppGroup.sender
        event.memberUserID = xmppGroupMember?.userId
        event.groupName = xmppGroup.name
        event.groupID = xmppGroup.groupId
        event.timestamp = Date()

        if let expirationType = xmppGroup.expirationType {
            event.groupExpirationType = expirationType
            event.groupExpirationTime = xmppGroup.expirationTime ?? 0
        }

        event.action = {
            switch xmppGroup.action {
            case .create: return .create
            case .join: return .join
            case .leave: return .leave
            case .delete: return .delete
            case .changeName: return .changeName
            case .changeDescription: return .changeDescription
            case .changeAvatar: return .changeAvatar
            case .setBackground: return .setBackground
            case .modifyAdmins: return .modifyAdmins
            case .modifyMembers: return .modifyMembers
            case .changeExpiry: return .changeExpiry
            case .autoPromoteAdmins: return .autoPromoteAdmins
            default: return .none
            }
        }()

        event.memberAction = {
            switch xmppGroupMember?.action {
            case .add: return .add
            case .remove: return .remove
            case .promote: return .promote
            case .demote: return .demote
            case .leave: return .leave
            default: return .none
            }
        }()

        if let chatThread = self.chatThread(type: xmppGroup.groupType, id: event.groupID, in: managedObjectContext) {

            chatThread.lastFeedUserID = event.senderUserID
            chatThread.lastFeedTimestamp = event.timestamp
            chatThread.lastFeedText = event.text

            // nb: unreadFeedCount is not incremented for group event messages
            // and NUX zero zone unread welcome post count is recorded in NUX userDefaults, not unreadFeedCount
        }

        mainDataStore.save(managedObjectContext)
    }
}
