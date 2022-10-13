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

    // MARK: Chat messgage upload and posting

    public func sendMessage(chatMessageRecipient: ChatMessageRecipient,
                            text: String,
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
                               text: text,
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
                              text: String,
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
        chatMessage.rawText = text
        chatMessage.feedPostId = feedPostId
        chatMessage.feedPostMediaIndex = feedPostMediaIndex
        chatMessage.chatReplyMessageID = chatReplyMessageID
        chatMessage.chatReplyMessageSenderID = chatReplyMessageSenderID
        chatMessage.chatReplyMessageMediaIndex = chatReplyMessageMediaIndex
        chatMessage.forwardCount = forwardCount
        chatMessage.incomingStatus = .none
        chatMessage.outgoingStatus = isMsgToYourself ? .seen : .pending
        chatMessage.timestamp = Date()
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

        if isMomentReply, let _ = feedPostId {
            // quoted moment; feed post has already been deleted at this point
            let quoted = ChatQuoted(context: context)
            quoted.type = .moment
            quoted.userID = toUserId
            quoted.message = chatMessage
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

    public func updateChatThreadOnMessageCreate(chatMessageRecipient: ChatMessageRecipient, chatMessage: ChatMessage, isMsgToYourself:Bool, lastMsgMediaType: CommonThread.LastMediaType, lastMsgText: String?, using context: NSManagedObjectContext) {
        guard let recipientId = chatMessageRecipient.recipientId else {
            DDLogError("CoreChatData/updateChatThread/ unable to update chat thread chatMessageId: \(chatMessage.id)")
            return
        }
        var chatThread: CommonThread
        let isIncomingMsg = chatMessage.fromUserID != userData.userId
        let isCurrentlyChattingWithUser = isCurrentlyChatting(with: recipientId)
        if let existingChatThread = self.chatThread(type: chatMessageRecipient.chatType, id: recipientId, in: context) {
            DDLogDebug("CoreChatData/updateChatThread/ update-thread")
            chatThread = existingChatThread
            if isIncomingMsg {
                chatThread.unreadCount = isCurrentlyChattingWithUser ? 0 : chatThread.unreadCount + 1
            } else if isCurrentlyChattingWithUser {
                // Sending a message always clears out the unread count when currently chatting with user
                chatThread.unreadCount = 0
            }
        } else {
            DDLogDebug("CoreChatData/updateChatThread/\(chatMessage.id)/new-thread")
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
            } else if isCurrentlyChattingWithUser {
                // Sending a message always clears out the unread count when currently chatting with user
                chatThread.unreadCount = 0
            }
        }

        chatThread.lastMsgId = chatMessage.id
        chatThread.lastMsgUserId = chatMessage.fromUserId
        chatThread.lastMsgText = lastMsgText
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

    public func getCurrentlyChattingWithUserId() -> String? {
        return currentlyChattingWithUserId
    }

    public func isCurrentlyChatting(with userId: UserID) -> Bool {
        if let currentlyChattingWithUserId = self.currentlyChattingWithUserId {
            if userId == currentlyChattingWithUserId {
                return true
            }
        }
        return false
    }

    public func beginMediaUploadAndSend(chatMessage: ChatMessage, didBeginUpload: ((Result<ChatMessageID, Error>) -> Void)? = nil) {
        let mediaToUpload = chatMessage.allAssociatedMedia.filter { [.none, .readyToUpload, .processedForUpload, .uploading, .uploadError].contains($0.status) }
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

            let media = chatMessage.allAssociatedMedia

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
        if #available(iOS 14.0, *) {
            var name = ""
            contactStore.performOnBackgroundContextAndWait { managedObjectContext in
                name = self.contactStore.fullNameIfAvailable(for: toUserId, ownName: nil, in: managedObjectContext) ?? ""
            }

            let recipient = INSpeakableString(spokenPhrase: name)
            let sendMessageIntent = INSendMessageIntent(recipients: nil,
                                                        content: nil,
                                                        speakableGroupName: recipient,
                                                        conversationIdentifier: ConversationID(id: toUserId, type: .chat).description,
                                                        serviceName: nil, sender: nil)

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

    // MARK: - Thread Updates

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

        var mentionText: NSAttributedString?
        contactStore.performOnBackgroundContextAndWait { contactsManagedObjectContext in
            mentionText = contactStore.textWithMentions(groupFeedPost.rawText, mentions: groupFeedPost.orderedMentions, in: contactsManagedObjectContext)
        }

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
                self.contactStore.addPushNames(contactNames)
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
            DDLogInfo("FeedData/handleRerequest/\(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount)")
            guard rerequestCount <= 5 else {
                DDLogError("FeedData/handleRerequest/\(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount) - aborting")
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
                let xmppReaction = XMPPReaction(reaction: chatReaction)
                self.service.sendChatMessage(xmppReaction, completion: completion)
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
            var lastMsgTextFallback: String?
            // Process chat content
            switch chatMessageProtocol.content {
            case .album(let text, let media):
                chatMessage.rawText = text
                if let mediaType = media.first?.mediaType {
                    lastMsgMediaType = CommonThread.lastMediaType(for: mediaType)
                } else {
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
            case .files(let files):
                chatMessage.rawText = ""
                lastMsgMediaType = .document
                lastMsgTextFallback = files.first?.name
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
            let lastMsgText = (chatMessage.rawText ?? "").isEmpty ? lastMsgTextFallback : chatMessage.rawText
            if let chatThread = self.chatThread(type: ChatType.oneToOne, id: chatMessage.fromUserId, in: context) {
                chatThread.lastMsgTimestamp = chatMessage.timestamp
                chatThread.lastMsgId = chatMessage.id
                chatThread.lastMsgUserId = chatMessage.fromUserId
                chatThread.lastMsgText = lastMsgText
                chatThread.lastMsgMediaType = lastMsgMediaType
                chatThread.lastMsgStatus = .none
                chatThread.lastMsgTimestamp = chatMessage.timestamp
                chatThread.unreadCount = chatThread.unreadCount + 1
            } else {
                let chatThread = CommonThread(context: context)
                chatThread.userID = chatMessage.fromUserId
                chatThread.lastMsgId = chatMessage.id
                chatThread.lastMsgUserId = chatMessage.fromUserId
                chatThread.lastMsgText = lastMsgText
                chatThread.lastMsgMediaType = lastMsgMediaType
                chatThread.lastMsgStatus = .none
                chatThread.lastMsgTimestamp = chatMessage.timestamp
                chatThread.type = .oneToOne
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

}
