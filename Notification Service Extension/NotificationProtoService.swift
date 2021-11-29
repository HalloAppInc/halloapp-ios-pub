//
//  NotificationProtoService.swift
//  Notification Service Extension
//
//  Created by Murali Balusu on 11/13/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift
import Combine
import Core
import SwiftProtobuf

final class NotificationProtoService: ProtoServiceCore {

    private lazy var dataStore = DataStore()
    private lazy var downloadManager: FeedDownloadManager = {
        let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let downloadManager = FeedDownloadManager(mediaDirectoryURL: tempDirectoryURL)
        downloadManager.delegate = self
        return downloadManager
    }()
    // List of notifications presented: used to update notification content after downloading media.
    private var pendingNotificationContent = [String: UNNotificationContent]()

    public required init(credentials: Credentials?, passiveMode: Bool = false, automaticallyReconnect: Bool = false) {
        super.init(credentials: credentials, passiveMode: passiveMode, automaticallyReconnect: automaticallyReconnect)
    }

    override func performOnConnect() {
        super.performOnConnect()
        resendAllPendingAcks()
    }

    override func authenticationFailed(with authResult: Server_AuthResult) {
        super.authenticationFailed(with: authResult)
    }

    private var cancellableSet = Set<AnyCancellable>()
    private let serviceQueue = DispatchQueue(label: "com.halloapp.proto.service", qos: .default)

    private func sendAck(messageID: String) {
        serviceQueue.async {
            self._sendAcks(messageIDs: [messageID])
        }
    }

    /// Should only be called on serviceQueue
    private func _sendAcks(messageIDs: [String]) {
        guard self.isConnected else {
            DDLogInfo("proto/_sendAcks/enqueueing (disconnected) [\(messageIDs.joined(separator: ","))]")
            self.pendingAcks += messageIDs
            return
        }

        let packets: [Server_Packet] = Set(messageIDs).map {
            var ack = Server_Ack()
            ack.id = $0
            var packet = Server_Packet()
            packet.stanza = .ack(ack)
            return packet
        }
        for packet in packets {
            if let data = try? packet.serializedData() {
                DDLogInfo("ProtoService/_sendAcks/\(packet.ack.id)/sending")
                send(data)
            } else {
                DDLogError("ProtoService/_sendAcks/\(packet.ack.id)/error could not serialize packet")
            }
        }
    }

    /// IDs for messages that we need to ack once we've connected. Should only be accessed on serviceQueue.
    private var pendingAcks = [String]()

    private func resendAllPendingAcks() {
        serviceQueue.async {
            guard self.isConnected else {
                DDLogInfo("proto/resendPendingAcks/skipping (disconnected)")
                return
            }
            guard !self.pendingAcks.isEmpty else {
                DDLogInfo("proto/resendPendingAcks/skipping (empty)")
                return
            }
            let acksToSend = self.pendingAcks
            self.pendingAcks.removeAll()
            self._sendAcks(messageIDs: acksToSend)
        }
    }


    override func didReceive(packet: Server_Packet) {
        super.didReceive(packet: packet)

        let requestID = packet.requestID ?? "unknown-id"

        switch packet.stanza {
        case .msg(let msg):
            handleMessage(msg)
        default:
            DDLogError("proto/didReceive/unknown-packet \(requestID)")
        }

    }


    // MARK: Message

    private func handleMessage(_ msg: Server_Msg) {
        let ack = { self.sendAck(messageID: msg.id) }
        var hasAckBeenDelegated = false
        defer {
            // Ack any message where we haven't explicitly delegated the ack to someone else
            if !hasAckBeenDelegated {
                ack()
            }
        }

        let serverMsgPb: Data
        do {
            serverMsgPb = try msg.serializedData()
        } catch {
            DDLogError("NotificationMetadata/init/msg - unable to serialize it.")
            return
        }

        // Extract notification related metadata from message if possible.
        // Else, just ack and store the message to process this later.
        guard let metadata = NotificationMetadata(msg: msg),
              !metadata.contentId.isEmpty else {
            DDLogDebug("didReceiveRequest/error missing messageId [\(msg)]")
            // TODO: murali: we need to handle some silent push messages here like: uploadLogs/rerequests/contactHash etc.
            // We need to migrate everything to shared container for some of these. revisit then.
            dataStore.saveServerMsg(contentId: msg.id, serverMsgPb: serverMsgPb)
            return
        }

        switch metadata.contentType {
        case .feedPost:
            guard let postData = metadata.postData() else {
                DDLogError("didReceiveRequest/error Invalid fields in metadata.")
                return
            }
            if let sharedPost = dataStore.sharedFeedPost(for: metadata.contentId), sharedPost.status == .received {
                DDLogError("didReceiveRequest/error duplicate feedPost [\(metadata.contentId)]")
                return
            }
            hasAckBeenDelegated = true
            processPostData(postData: postData, status: .received, metadata: metadata, ack: ack)

        case .feedComment:
            guard let commentData = metadata.commentData() else {
                DDLogError("didReceiveRequest/error Invalid fields in metadata.")
                return
            }
            if let sharedComment = dataStore.sharedFeedComment(for: metadata.contentId), sharedComment.status == .received {
                DDLogError("didReceiveRequest/error duplicate feedComment [\(metadata.contentId)]")
                return
            }
            hasAckBeenDelegated = true
            processCommentData(commentData: commentData, status: .received, metadata: metadata, ack: ack)

        // Separate out groupFeedItems: we need to decrypt them, process and populate content accordingly.
        case .groupFeedPost, .groupFeedComment:
            let contentType: FeedElementType
            if metadata.contentType == .groupFeedPost {
                contentType = .post
            } else {
                contentType = .comment
            }

            if let sharedPost = dataStore.sharedFeedPost(for: metadata.contentId), sharedPost.status == .received {
                DDLogError("didReceiveRequest/error duplicate groupFeedPost [\(metadata.contentId)]")
                return
            } else if let sharedComment = dataStore.sharedFeedComment(for: metadata.contentId), sharedComment.status == .received {
                DDLogError("didReceiveRequest/error duplicate groupFeedComment [\(metadata.contentId)]")
                return
            }

            // Decrypt and process the payload now
            do {
                guard let serverGroupFeedItemPb = metadata.serverGroupFeedItemPb else {
                    DDLogError("MetadataError/could not find serverGroupFeedItem stanza, contentId: \(metadata.contentId), contentType: \(metadata.contentType)")
                    return
                }
                let serverGroupFeedItem = try Server_GroupFeedItem(serializedData: serverGroupFeedItemPb)
                DDLogInfo("NotificationExtension/requesting decryptGroupFeedItem \(metadata.contentId)")
                hasAckBeenDelegated = true
                decryptAndProcessGroupFeedItem(contentID: metadata.contentId, contentType: contentType, item: serverGroupFeedItem, metadata: metadata, ack: ack)
            } catch {
                DDLogError("NotificationExtension/ChatMessage/Failed serverChatStanzaStr: \(String(describing: metadata.serverChatStanzaPb)), error: \(error)")
            }

        case .chatMessage:
            let messageId = metadata.messageId
            // Check if message has already been received and decrypted successfully.
            // If yes - then dismiss notification, else continue processing.
            if let sharedChatMessage = dataStore.sharedChatMessage(for: messageId), sharedChatMessage.status == .received {
                DDLogError("didReceiveRequest/error duplicate message ID that was already decrypted[\(String(describing: metadata.messageId))]")
                return
            }
            do {
                guard let serverChatStanzaPb = metadata.serverChatStanzaPb else {
                    DDLogError("MetadataError/could not find server_chat stanza, contentId: \(metadata.contentId), contentType: \(metadata.contentType)")
                    return
                }
                let serverChatStanza = try Server_ChatStanza(serializedData: serverChatStanzaPb)
                DDLogInfo("NotificationExtension/requesting decryptChat \(metadata.contentId)")
                hasAckBeenDelegated = true
                // this function acks and sends rerequests accordingly.
                decryptAndProcessChat(messageId: messageId, serverChatStanza: serverChatStanza, metadata: metadata)
            } catch {
                DDLogError("NotificationExtension/ChatMessage/Failed serverChatStanzaStr: \(String(describing: metadata.serverChatStanzaPb)), error: \(error)")
            }

        case .newInvitee, .newFriend, .newContact, .groupAdd:
            // save server message stanzas to process for these notifications.
            presentNotification(for: metadata)
            dataStore.saveServerMsg(notificationMetadata: metadata)

        case .chatMessageRetract, .feedCommentRetract, .feedPostRetract, .groupFeedPostRetract, .groupFeedCommentRetract, .groupChatMessageRetract:
            removeNotification(id: metadata.contentId)
            dataStore.saveServerMsg(contentId: msg.id, serverMsgPb: serverMsgPb)

        default:
            dataStore.saveServerMsg(contentId: msg.id, serverMsgPb: serverMsgPb)

        }
    }

    // MARK: Handle Post or Comment content.

    private func processPostData(postData: PostData?, status: SharedFeedPost.Status, metadata: NotificationMetadata, ack: @escaping () -> ()) {
        dataStore.save(postData: postData, status: status, notificationMetadata: metadata) { sharedFeedPost in
            ack()
            // If we failed to get postData successfully - then just return!
            guard let postData = postData else {
                DDLogError("NotificationExtension/processPostDataAndInvokeHandler/failed to get postData, contentId: \(metadata.contentId)")
                return
            }
            self.presentPostNotification(for: metadata, using: postData)
            if let firstMediaItem = sharedFeedPost.orderedMedia.first as? SharedMedia {
                let downloadTask = self.startDownloading(media: firstMediaItem)
                downloadTask?.feedMediaObjectId = firstMediaItem.objectID
            }
        }
    }

    private func processCommentData(commentData: CommentData?, status: SharedFeedComment.Status, metadata: NotificationMetadata, ack: @escaping () -> ()) {
        dataStore.save(commentData: commentData, status: status, notificationMetadata: metadata) { sharedFeedComment in
            ack()
            // If we failed to get commentData successfully - then just return!
            guard let commentData = commentData else {
                DDLogError("NotificationExtension/processCommentDataAndInvokeHandler/failed to get postData, contentId: \(metadata.contentId)")
                return
            }
            self.presentCommentNotification(for: metadata, using: commentData)
        }
    }

    // MARK: Handle GroupFeed Items.

    // Decrypt, process and ack group feed items
    private func decryptAndProcessGroupFeedItem(contentID: String, contentType: FeedElementType,
                                                item: Server_GroupFeedItem, metadata: NotificationMetadata, ack: @escaping () -> ()) {
        decryptGroupFeedPayload(for: item, in: item.gid) { content, groupDecryptionFailure in
            if let content = content, groupDecryptionFailure == nil {
                DDLogError("NotificationExtension/decryptAndProcessGroupFeedItem/contentID/\(contentID)/success")
                switch content {
                case .newItems(let newItems):
                    guard let newItem = newItems.first, newItems.count == 1 else {
                        DDLogError("NotificationExtension/decryptAndProcessGroupFeedItem/contentID/\(contentID)/too many items - invalid decrypted payload.")
                        ack()
                        return
                    }
                    switch newItem {
                    case .post(let postData):
                        self.processPostData(postData: postData, status: .received, metadata: metadata, ack: ack)
                    case .comment(let commentData, _):
                        self.processCommentData(commentData: commentData, status: .received, metadata: metadata, ack: ack)
                    }
                case .retracts(_):
                    // This is not possible - since these are never encrypted in the first place as of now.
                    ack()
                    return
                }
            } else {
                DDLogError("NotificationExtension/decryptAndProcessGroupFeedItem/contentID/\(contentID)/failure \(groupDecryptionFailure.debugDescription)")
                if let groupId = metadata.groupId,
                   let decryptionFailure = groupDecryptionFailure {
                    self.rerequestGroupFeedItemIfNecessary(id: contentID, groupID: groupId, failure: decryptionFailure) { result in
                        switch result {
                        case .success: break
                        case .failure(let error):
                            DDLogError("NotificationExtension/decryptAndProcessGroupFeedItem/contentID/\(contentID)/failed rerequest: \(error)")
                        }
                        switch contentType {
                        case .post:
                            self.processPostData(postData: metadata.postData(status: .rerequesting), status: .decryptionError, metadata: metadata, ack: ack)
                        case .comment:
                            self.processCommentData(commentData: metadata.commentData(status: .rerequesting), status: .decryptionError, metadata: metadata, ack: ack)
                        }
                    }
                }
            }
            self.reportGroupDecryptionResult(
                error: groupDecryptionFailure?.error,
                contentID: contentID,
                itemType: contentType,
                groupID: item.gid,
                timestamp: Date(),
                sender: UserAgent(string: item.senderClientVersion),
                rerequestCount: Int(metadata.rerequestCount))
        }
    }

    private func reportGroupDecryptionResult(error: DecryptionError?, contentID: String, itemType: FeedElementType, groupID: GroupID, timestamp: Date, sender: UserAgent?, rerequestCount: Int) {
        if (error == .missingPayload) {
            DDLogInfo("NotificationExtension/reportGroupDecryptionResult/\(contentID)/\(itemType)/\(groupID)/payload is missing - not error.")
            return
        }
        let errorString = error?.rawValue ?? ""
        DDLogInfo("NotificationExtension/reportGroupDecryptionResult/\(contentID)/\(itemType)/\(groupID)/error value: \(errorString)")
        AppContext.shared.eventMonitor.count(.groupDecryption(error: error, itemType: itemType, sender: sender))
        AppContext.shared.cryptoData.update(contentID: contentID,
                                            contentType: itemType.rawString,
                                            groupID: groupID,
                                            timestamp: timestamp,
                                            error: errorString,
                                            sender: sender,
                                            rerequestCount: rerequestCount)
    }

    // MARK: Handle Chat Messages.

    // Decrypt, process, save, rerequest and ack chats!
    private func decryptAndProcessChat(messageId: String, serverChatStanza: Server_ChatStanza, metadata: NotificationMetadata) {
        let fromUserID = metadata.fromId
        AppExtensionContext.shared.messageCrypter.decrypt(
            EncryptedData(
                data: serverChatStanza.encPayload,
                identityKey: serverChatStanza.publicKey.isEmpty ? nil : serverChatStanza.publicKey,
                oneTimeKeyId: Int(serverChatStanza.oneTimePreKeyID)),
            from: fromUserID) { result in

            // TODO: Refactor this now that we don't send plaintext (success/failure values mutually exclusive)
            let container: Clients_ChatContainer?
            let messageStatus: SharedChatMessage.Status
            let decryptionFailure: DecryptionFailure?

            switch result {
            case .success(let decryptedData):
                DDLogInfo("NotificationExtension/decryptChat/successful/messageId \(messageId)")
                messageStatus = .received
                decryptionFailure = nil

                if let clientChatContainer = Clients_ChatContainer(containerData: decryptedData) {
                    container = clientChatContainer
                } else {
                    container = nil
                }
            case .failure(let decryptionError):
                self.logChatPushDecryptionError(with: metadata, error: decryptionError.error)
                DDLogError("NotificationExtension/decryptChat/failed decryption, error: \(decryptionError)")
                messageStatus = .decryptionError
                decryptionFailure = decryptionError
                container = nil
            }

            self.dataStore.save(container: container, metadata: metadata, status: messageStatus, failure: decryptionFailure) { sharedChatMessage in
                self.incrementApplicationIconBadgeNumber()
                self.processChat(chatMessage: sharedChatMessage, container: container, metadata: metadata)
            }
        }
    }

    private func incrementApplicationIconBadgeNumber() {
        // Update application badge number.
        let badgeNum = AppExtensionContext.shared.applicationIconBadgeNumber
        let applicationIconBadgeNumber = badgeNum == -1 ? 1 : badgeNum + 1
        AppExtensionContext.shared.applicationIconBadgeNumber = applicationIconBadgeNumber
    }

    // Process Chats - ack/rerequest/download media if necessary.
    private func processChat(chatMessage: SharedChatMessage, container: Clients_ChatContainer?, metadata: NotificationMetadata) {
        let messageId = metadata.messageId
        // send pending acks for any pending chat messages
        sendPendingAcksAndRerequests(dataStore: dataStore)
        // If we failed to get decrypted chat content successfully - then just return!
        guard let chatContent = container?.chatContent else {
            DDLogError("DecryptionError/decryptChat/failed to get chat content, messageId: \(messageId)")
            return
        }
        presentChatNotification(for: metadata, using: chatContent)
        if let firstMediaItem = chatMessage.orderedMedia.first as? SharedMedia {
            let downloadTask = startDownloading(media: firstMediaItem)
            downloadTask?.feedMediaObjectId = firstMediaItem.objectID
            DDLogInfo("NotificationExtension/decryptChat/downloadingMedia/messageId \(messageId), downloadTask: \(String(describing: downloadTask?.id))")
        }
    }

    // Send acks and rerequests for all pending chat messages.
    private func sendPendingAcksAndRerequests(dataStore: DataStore) {
        // We must first rerequest messages and then ack them.

        // We rerequest messages with status = .decryptionError
        dataStore.getChatMessagesToRerequest() { [self] sharedChatMessagesToRerequest in
            sharedChatMessagesToRerequest.forEach{ sharedChatMessage in
                let msgId = sharedChatMessage.id
                if let failedEphemeralKey = sharedChatMessage.ephemeralKey, let serverMsgPb = sharedChatMessage.serverMsgPb {
                    do {
                        let serverMsg = try Server_Msg(serializedData: serverMsgPb)
                        rerequestMessage(serverMsg, failedEphemeralKey: failedEphemeralKey) { result in
                            switch result {
                            case .success(_):
                                DDLogInfo("sendRerequest/success sent rerequest, msgId: \(msgId)")
                                dataStore.updateMessageStatus(for: msgId, status: .rerequesting)
                            case .failure(let error):
                                DDLogError("sendRerequest/failure sending rerequest, msgId: \(msgId), error: \(error)")
                            }
                        }
                    } catch {
                        DDLogError("sendRerequest/Unable to initialize Server_Msg")
                    }
                }
            }
        }

        // We ack messages only that are successfully decrypted or successfully rerequested.
        dataStore.getChatMessagesToAck() { [self] sharedChatMessagesToAck in
            sharedChatMessagesToAck.forEach{ sharedChatMessage in
                let msgId = sharedChatMessage.id
                sendAck(messageId: msgId) { result in
                    let finalStatus: SharedChatMessage.Status
                    switch sharedChatMessage.status {
                    case .received:
                        finalStatus = .acked
                    case .rerequesting:
                        finalStatus = .rerequesting
                    case .acked, .sendError, .sent, .none, .decryptionError:
                        return
                    }
                    switch result {
                    case .success(_):
                        DDLogInfo("sendAck/success sent ack, msgId: \(msgId)")
                        dataStore.updateMessageStatus(for: msgId, status: finalStatus)
                    case .failure(let error):
                        DDLogError("sendAck/failure sending ack, msgId: \(msgId), error: \(error)")
                    }
                }
            }
        }
    }

    private func logChatPushDecryptionError(with metadata: NotificationMetadata, error: DecryptionError?) {
        let reportUserInfo = [
            "userId": AppExtensionContext.shared.userData.userId,
            "msgId": metadata.messageId,
            "error": "ChatPushDecryptionError",
            "reason": error?.rawValue ?? "unknownError"
        ]
        let customError = NSError.init(domain: "ChatPushDecryptionErrorTest", code: 1004, userInfo: reportUserInfo)
        AppExtensionContext.shared.errorLogger?.logError(customError)
    }

    // MARK: Present or Update Notifications

    private func presentNotification(for metadata: NotificationMetadata, with attachments: [UNNotificationAttachment] = []) {
        runIfNotificationWasNotPresented(for: metadata.contentId) { [self] in
            DDLogDebug("ProtoService/presentNotification")
            let notificationContent = UNMutableNotificationContent()
            notificationContent.populate(from: metadata, contactStore: AppExtensionContext.shared.contactStore)
            notificationContent.attachments = attachments
            notificationContent.badge = AppExtensionContext.shared.applicationIconBadgeNumber as NSNumber?
            notificationContent.sound = UNNotificationSound.default
            self.pendingNotificationContent[metadata.contentId] = notificationContent

            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.add(UNNotificationRequest(identifier: metadata.contentId, content: notificationContent, trigger: nil))
            recordPresentingNotification(for: metadata.contentId, type: metadata.contentType.rawValue)
        }
    }

    private func presentPostNotification(for metadata: NotificationMetadata, using postData: PostData, with attachments: [UNNotificationAttachment] = []) {
        runIfNotificationWasNotPresented(for: metadata.contentId) { [self] in
            DDLogDebug("ProtoService/presentPostNotification")
            let notificationContent = UNMutableNotificationContent()
            notificationContent.populate(from: metadata, contactStore: AppExtensionContext.shared.contactStore)
            notificationContent.populateFeedPostBody(from: postData, using: metadata, contactStore: AppExtensionContext.shared.contactStore)
            notificationContent.attachments = attachments
            notificationContent.badge = AppExtensionContext.shared.applicationIconBadgeNumber as NSNumber?
            notificationContent.sound = UNNotificationSound.default
            self.pendingNotificationContent[metadata.contentId] = notificationContent

            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.add(UNNotificationRequest(identifier: metadata.contentId, content: notificationContent, trigger: nil))
            recordPresentingNotification(for: metadata.contentId, type: metadata.contentType.rawValue)
        }
    }

    private func presentCommentNotification(for metadata: NotificationMetadata, using commentData: CommentData, with attachments: [UNNotificationAttachment] = []) {
        let isUserMentioned = commentData.orderedMentions.contains(where: { mention in
            mention.userID == AppContext.shared.userData.userId
        })
        if metadata.messageTypeRawValue == Server_Msg.TypeEnum.headline.rawValue || isUserMentioned {
            runIfNotificationWasNotPresented(for: metadata.contentId) { [self] in
                DDLogDebug("ProtoService/presentCommentNotification")
                let notificationContent = UNMutableNotificationContent()
                notificationContent.populate(from: metadata, contactStore: AppExtensionContext.shared.contactStore)
                notificationContent.populateFeedCommentBody(from: commentData, using: metadata, contactStore: AppExtensionContext.shared.contactStore)
                notificationContent.attachments = attachments
                notificationContent.badge = AppExtensionContext.shared.applicationIconBadgeNumber as NSNumber?
                notificationContent.sound = UNNotificationSound.default
                self.pendingNotificationContent[metadata.contentId] = notificationContent

                let notificationCenter = UNUserNotificationCenter.current()
                notificationCenter.add(UNNotificationRequest(identifier: metadata.contentId, content: notificationContent, trigger: nil))
                recordPresentingNotification(for: metadata.contentId, type: metadata.contentType.rawValue)
            }
        } else {
            DDLogInfo("ProtoService/Ignoring push for this comment")
        }
    }

    private func presentChatNotification(for metadata: NotificationMetadata, using chatContent: ChatContent, with attachments: [UNNotificationAttachment] = []) {
        runIfNotificationWasNotPresented(for: metadata.contentId) { [self] in
            DDLogDebug("ProtoService/presentChatNotification")
            let notificationContent = UNMutableNotificationContent()
            notificationContent.populate(from: metadata, contactStore: AppExtensionContext.shared.contactStore)
            notificationContent.populateChatBody(from: chatContent, using: metadata, contactStore: AppExtensionContext.shared.contactStore)
            notificationContent.attachments = attachments
            notificationContent.badge = AppExtensionContext.shared.applicationIconBadgeNumber as NSNumber?
            notificationContent.sound = UNNotificationSound.default
            self.pendingNotificationContent[metadata.contentId] = notificationContent

            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.add(UNNotificationRequest(identifier: metadata.contentId, content: notificationContent, trigger: nil))
            recordPresentingNotification(for: metadata.contentId, type: metadata.contentType.rawValue)
        }
    }

    private func updateNotification(for identifier: String, content: UNNotificationContent, with attachments: [UNNotificationAttachment] = []) {
        DispatchQueue.main.async {
            DDLogDebug("ProtoService/updateNotification")
            let notificationContent = UNMutableNotificationContent()
            notificationContent.title = content.title
            notificationContent.subtitle = content.subtitle
            notificationContent.body = content.body
            notificationContent.attachments = attachments
            notificationContent.userInfo = content.userInfo
            notificationContent.badge = AppExtensionContext.shared.applicationIconBadgeNumber as NSNumber?

            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.add(UNNotificationRequest(identifier: identifier, content: notificationContent, trigger: nil))
        }
    }

    private func removeNotification(id identifier: String) {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        }
    }
}

// MARK: Check and Record push notifications

extension NotificationProtoService {

    public func runIfNotificationWasNotPresented(for contentId: String, completion: @escaping () -> Void) {
        AppContext.shared.notificationStore.runIfNotificationWasNotPresented(for: contentId, completion: completion)
    }

    public func recordPresentingNotification(for contentId: String, type: String) {
        AppContext.shared.notificationStore.save(id: contentId, type: type)
    }
}

// MARK: Downloading media items

extension NotificationProtoService: FeedDownloadManagerDelegate {

    /**
      iOS doesn't show more than one attachment and therefore for now only download the first media from the post.

     - returns: Download task if download has started.
     */
    private func startDownloading(media: FeedMediaProtocol) -> FeedDownloadManager.Task? {
        let (taskAdded, task) = downloadManager.downloadMedia(for: media)
        if taskAdded {
            DDLogInfo("media/download/started \(task.id)")
            return task
        }
        return nil
    }

    func feedDownloadManager(_ downloadManager: FeedDownloadManager, didFinishTask task: FeedDownloadManager.Task) {
        DDLogInfo("ProtoService/media/download/finished \(task.id)")

        if let error = task.error {
            DDLogError("ProtoService/media/download/error \(error)")
            return
        }

        let fileURL = downloadManager.fileURL(forRelativeFilePath: task.decryptedFilePath!)
        // Attach media to notification.
        let attachment: UNNotificationAttachment
        do {
            attachment = try UNNotificationAttachment(identifier: task.id, url: fileURL, options: nil)
        } catch {
            DDLogError("ProtoService/media/attachment-create/error \(error)")
            return
        }

        // Copy downloaded media to shared file storage and update db with path to the media.
        if let objectId = task.feedMediaObjectId,
           let feedMediaItem = try? dataStore.sharedMediaObject(forObjectId: objectId) {

            let filename = fileURL.deletingPathExtension().lastPathComponent
            let relativeFilePath = SharedDataStore.relativeFilePath(forFilename: filename, mediaType: feedMediaItem.type)
            do {
                // Try and include this media item in the notification now.
                if let contentId = feedMediaItem.contentOwnerID,
                   let content = pendingNotificationContent[contentId] {
                    updateNotification(for: contentId, content: content, with: [attachment])
                }
                let destinationUrl = dataStore.fileURL(forRelativeFilePath: relativeFilePath)
                SharedDataStore.preparePathForWriting(destinationUrl)

                try FileManager.default.copyItem(at: fileURL, to: destinationUrl)
                DDLogDebug("ProtoService/attach-media/copied [\(fileURL)] to [\(destinationUrl)]")

                feedMediaItem.relativeFilePath = relativeFilePath
                feedMediaItem.status = .downloaded
                dataStore.save(feedMediaItem.managedObjectContext!)
            } catch {
                DDLogError("ProtoService/media/copy-media/error [\(error)]")
            }
        }
    }
}