//
//  ProtoService.swift
//  HalloApp
//
//  Created by Garrett on 8/27/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CryptoKit
import CryptoSwift
import SwiftProtobuf

fileprivate let userDefaultsKeyForAPNSToken = "apnsPushToken"
fileprivate let userDefaultsKeyForVOIPToken = "VoipPushToken"
fileprivate let userDefaultsKeyForLangID = "langId"
fileprivate let userDefaultsKeyForAPNSSyncTime = "apnsSyncTime"
fileprivate let userDefaultsKeyForVOIPSyncTime = "voipSyncTime"
fileprivate let userDefaultsKeyForNameSync = "xmpp.name-sent"
fileprivate let userDefaultsKeyForSilentRerequestRecords = "silentRerequestRecords"

fileprivate let shareURLPrefix = "https://share.halloapp.com/"

final class ProtoService: ProtoServiceCore {

    var readyToHandleCallMessages = false {
        didSet {
            DDLogInfo("protoService/didSet/readyToHandleCallMessages: \(readyToHandleCallMessages)")
            if readyToHandleCallMessages {
                handlePendingCallMessages()
            }
        }
    }
    var pendingCallMessages = [CallID: [Server_Msg]]()

    public required init(credentials: Credentials?, passiveMode: Bool = false, automaticallyReconnect: Bool = true, resource: ResourceType = .iphone) {
        super.init(credentials: credentials, passiveMode: passiveMode, automaticallyReconnect: automaticallyReconnect, resource: resource)
        self.cancellableSet.insert(
            didDisconnect.sink {
                // reset our call handling state if no calls are active.
                if !MainAppContext.shared.callManager.isAnyCallActive {
                    self.readyToHandleCallMessages = false
                }
            })
    }

    override func performOnConnect() {
        super.performOnConnect()

        // Check on every connection if we have to send the apns token to the server.
        if hasValidAPNSPushToken {
            let token = UserDefaults.standard.string(forKey: userDefaultsKeyForAPNSToken)
            sendAPNSTokenIfNecessary(token)
        }

        if hasValidVOIPPushToken {
            let token = UserDefaults.standard.string(forKey: userDefaultsKeyForVOIPToken)
            sendVOIPTokenIfNecessary(token)
        }

        resendNameIfNecessary()
        resendAvatarIfNecessary()
        resendAllPendingReceipts()
        resendAllPendingAcks()
        queryAvatarForCurrentUserIfNecessary()
        requestServerPropertiesIfNecessary()
        NotificationSettings.current.sendConfigIfNecessary(using: self)
        MainAppContext.shared.startReportingEvents()
        clearSilentChatRerequestRecords()
        uploadLogsToServerIfNecessary()
    }

    override func authenticationSucceeded(with authResult: Server_AuthResult) {
        // Update props hash before calling super so it's available for `performOnConnect`
        propsHash = authResult.propsHash.toHexString()

        super.authenticationSucceeded(with: authResult)
    }

    override func authenticationFailed(with authResult: Server_AuthResult) {
        // Clear push token sync time on authentication failure.
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyForAPNSSyncTime)
        // Clear voip push token sync time on auth failure.
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyForVOIPSyncTime)

        super.authenticationFailed(with: authResult)
    }

    private var cancellableSet = Set<AnyCancellable>()

    weak var chatDelegate: HalloChatDelegate?
    weak var feedDelegate: HalloFeedDelegate?
    weak var callDelegate: HalloCallDelegate?

    let didGetNewChatMessage = PassthroughSubject<IncomingChatMessage, Never>()
    let didGetNewWhisperMessage = PassthroughSubject<WhisperMessage, Never>()
    let didGetChatAck = PassthroughSubject<ChatAck, Never>()
    let didGetPresence = PassthroughSubject<ChatPresenceInfo, Never>()
    let didGetChatState = PassthroughSubject<ChatStateInfo, Never>()
    let didGetChatRetract = PassthroughSubject<ChatRetractInfo, Never>()

    private let serviceQueue = DispatchQueue(label: "com.halloapp.proto.service", qos: .default)

    // MARK: Server Properties

    private var propsHash: String?

    private func requestServerPropertiesIfNecessary() {
        guard ServerProperties.shouldQuery(forVersion: propsHash) else {
            DDLogInfo("proto/serverprops/skipping [\(propsHash ?? "hash unavailable")]")
            return
        }

        DDLogInfo("proto/serverprops/request")
        getServerProperties { (result) in
            switch result {
            case .success(let (version, properties)):
                DDLogDebug("proto/serverprops/request/success version=[\(version)]")
                ServerProperties.update(withProperties: properties, version: version)

            case .failure(let error):
                DDLogError("proto/serverprops/request/error [\(error)]")
            }
        }
    }

    // MARK: Receipts

    typealias ReceiptData = (receipt: HalloReceipt, userID: UserID)

    /// Maps message ID of outgoing receipts to receipt data in case we need to resend. Should only be accessed on serviceQueue.
    private var unackedReceipts: [ String : ReceiptData ] = [:]

    private func resendAllPendingReceipts() {
        serviceQueue.async {
            for (messageID, receiptData) in self.unackedReceipts {
                self._sendReceipt(receiptData.receipt, to: receiptData.userID, messageID: messageID)
            }
        }
    }

    private func sendReceipt(_ receipt: HalloReceipt, to toUserID: UserID, messageID: String = PacketID.generate()) {
        serviceQueue.async {
            self._sendReceipt(receipt, to: toUserID, messageID: messageID)
        }
    }

    /// Handles ack if it corresponds to an unacked receipt. Calls completion block on main thread.
    private func handlePossibleReceiptAck(id: String, didFindReceipt: @escaping (Bool) -> Void) {
        serviceQueue.async {
            var wasReceiptFound = false
            if let (receipt, _) = self.unackedReceipts[id] {
                DDLogInfo("proto/ack/\(id)/receipt found [\(receipt.itemId)]")
                wasReceiptFound = true
                self.unackedReceipts[id] = nil
                switch receipt.thread {
                case .feed:
                    self.feedDelegate?.halloService(self, didSendFeedReceipt: receipt)
                case .none, .group:
                    self.chatDelegate?.halloService(self, didSendMessageReceipt: receipt)
                }
            }
            DispatchQueue.main.async {
                didFindReceipt(wasReceiptFound)
            }
        }
    }

    /// Should only be called on serviceQueue.
    private func _sendReceipt(_ receipt: HalloReceipt, to toUserID: UserID, messageID: String = PacketID.generate()) {
        unackedReceipts[messageID] = (receipt, toUserID)

        let threadID: String = {
            switch receipt.thread {
            case .group(let threadID): return threadID
            case .feed: return "feed"
            case .none: return ""
            }
        }()

        let payloadContent: Server_Msg.OneOf_Payload = {
            switch receipt.type {
            case .delivery:
                var deliveryReceipt = Server_DeliveryReceipt()
                deliveryReceipt.id = receipt.itemId
                deliveryReceipt.threadID = threadID
                return .deliveryReceipt(deliveryReceipt)
            case .read:
                var seenReceipt = Server_SeenReceipt()
                seenReceipt.id = receipt.itemId
                seenReceipt.threadID = threadID
                return .seenReceipt(seenReceipt)
            case .played:
                var playedReceipt = Server_PlayedReceipt()
                playedReceipt.id = receipt.itemId
                playedReceipt.threadID = threadID
                return .playedReceipt(playedReceipt)
            }
        }()

        let packet = Server_Packet.msgPacket(
            from: receipt.userId,
            to: toUserID,
            id: messageID,
            payload: payloadContent)

        if let data = try? packet.serializedData(), self.isConnected {
            DDLogInfo("proto/_sendReceipt/\(receipt.itemId)/sending")
            send(data)
        } else {
            DDLogInfo("proto/_sendReceipt/\(receipt.itemId)/skipping (disconnected)")
        }
    }

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
        serviceQueue.async {
            // Mark .active messages as .processed (leave .rerequested messages as-is)
            messageIDs
                .filter { self.messageStatus[$0] == .active }
                .forEach { self.messageStatus[$0] = .processed }
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

    /// Message processing status. Should only be accessed on serviceQueue.
    private var messageStatus = [String: MessageStatus]()

    private func updateMessageStatus(id: String, status: MessageStatus) {
        serviceQueue.async {
            self.messageStatus[id] = status
        }
    }

    private func retrieveMessageStatus(id: String) -> MessageStatus {
        serviceQueue.sync {
            return self.messageStatus[id] ?? .new
        }
    }

    private func handleReceivedReceipt(receipt: ReceivedReceipt, from: UserID, messageID: String, ack: (() -> Void)?) {
        let ts = TimeInterval(receipt.timestamp)
        let thread: HalloReceipt.Thread = {
            switch receipt.threadID {
            case "feed": return .feed
            case "": return .none
            default: return .group(receipt.threadID)
            }
        }()
        let receipt = HalloReceipt(
            itemId: receipt.id,
            userId: from,
            type: receipt.receiptType,
            timestamp: Date(timeIntervalSince1970: ts),
            thread: thread)
        if thread == .feed, let delegate = feedDelegate {
            delegate.halloService(self, didReceiveFeedReceipt: receipt, ack: ack)
        } else if thread != .feed, let delegate = chatDelegate {
            delegate.halloService(self, didReceiveMessageReceipt: receipt, ack: ack)
        } else {
            ack?()
        }
    }

    // MARK: Silent Chats

    private func clearSilentChatRerequestRecords() {
        serviceQueue.async {
            // Remove records for silent chats (no longer used)
            MainAppContext.shared.userDefaults.set(nil, forKey: userDefaultsKeyForSilentRerequestRecords)
        }
    }

    // MARK: Feed

    private func handleHomeFeedItems(_ items: [Server_FeedItem], isEligibleForNotification: Bool, ack: @escaping () -> Void) {
        guard let delegate = feedDelegate else {
            ack()
            return
        }
        var elements = [FeedElement]()
        var retracts = [FeedRetract]()
        items.forEach { pbFeedItem in
            switch pbFeedItem.item {
            case .post(let serverPost):
                switch pbFeedItem.action {
                case .publish, .share:
                    if let post = PostData(serverPost, status: .received, itemAction: pbFeedItem.itemAction, isShared: pbFeedItem.action == .share) {
                        elements.append(.post(post))
                    }
                case .retract:
                    retracts.append(.post(serverPost.id))
                case .UNRECOGNIZED(let action):
                    DDLogError("ProtoService/handleHomeFeedItems/error unrecognized post action \(action)")
                }
            case .comment(let serverComment):
                switch pbFeedItem.action {
                case .publish, .share:
                    if let comment = CommentData(serverComment, status: .received, itemAction: pbFeedItem.itemAction) {
                        elements.append(.comment(comment, publisherName: serverComment.publisherName))
                    }
                case .retract:
                    retracts.append(.comment(serverComment.id))
                case .UNRECOGNIZED(let action):
                    DDLogError("ProtoService/handleHomeFeedItems/error unrecognized comment action \(action)")
                }
            case .none:
                DDLogError("ProtoService/handleHomeFeedItems/error missing item")
            }
        }
        if !elements.isEmpty {
            let payload = HalloServiceFeedPayload(content: .newItems(elements), group: nil, isEligibleForNotification: isEligibleForNotification)
            delegate.halloService(self, didReceiveFeedPayload: payload, ack: ack)
        }
        if !retracts.isEmpty {
            let payload = HalloServiceFeedPayload(content: .retracts(retracts), group: nil, isEligibleForNotification: isEligibleForNotification)
            delegate.halloService(self, didReceiveFeedPayload: payload, ack: ack)
        }
        if elements.isEmpty && retracts.isEmpty {
            ack()
        }
    }

    // TODO: murali@: it is a bit confusing to pass status for all feed items here - should improve this.
    private func payloadContents(for items: [Server_GroupFeedItem], status: FeedItemStatus) -> [FeedContent] {

        // NB: This function should not assume group fields are populated! [gid, name, avatarID]
        // They aren't included on each child when server sends a `Server_GroupFeedItems` stanza.

        var retracts = [FeedRetract]()
        var elements = [FeedElement]()

        // This function is used for groupFeedItems from server and for fallback to unencrypted payload.
        // So, use serverProp value to decide whether to fallback to plainTextContent when status is .rerequesting
        let fallback: Bool = status == .rerequesting ? ServerProperties.useClearTextGroupFeedContent : true
        for item in items {
            let isShared: Bool = item.isResentHistory ? true : item.action == .share
            switch item.item {
            case .post(let serverPost):
                if !isShared && item.action == .retract {
                    retracts.append(.post(serverPost.id))
                } else {
                    guard let post = PostData(serverPost, status: status, itemAction: item.itemAction,
                                              usePlainTextPayload: fallback, isShared: isShared) else {
                        DDLogError("proto/payloadContents/\(serverPost.id)/error could not make post object")
                        continue
                    }
                    elements.append(.post(post))
                }
            case .comment(let serverComment):
                if !isShared && item.action == .retract {
                    retracts.append(.comment(serverComment.id))
                } else {
                    guard let comment = CommentData(serverComment, status: status, itemAction: item.itemAction,
                                                    usePlainTextPayload: fallback, isShared: isShared) else {
                        DDLogError("proto/payloadContents/\(serverComment.id)/error could not make comment object")
                        continue
                    }
                    elements.append(.comment(comment, publisherName: serverComment.publisherName))
                }
            case .none:
                DDLogError("ProtoService/payloadContents/error missing item")
            }
        }

        switch (elements.isEmpty, retracts.isEmpty) {
        case (true, true): return []
        case (true, false): return [.retracts(retracts)]
        case (false, true): return [.newItems(elements)]
        case (false, false): return [.retracts(retracts), .newItems(elements)]
        }

    }

    // Checks if the message is decrypted and saved in the main app's data store.
    // TODO: discuss with garrett on other options here.
    // We should move the cryptoData keystore to be accessible by all extensions and the main app.
    // It would be cleaner that way - having these checks after merging still leads to some flakiness in my view.
    private func isMessageDecryptedAndSaved(msgId: String) -> Bool {
        var isMessageAlreadyInLocalStore = false

        MainAppContext.shared.chatData.performOnBackgroundContextAndWait { managedObjectContext in
            if let message = MainAppContext.shared.chatData.chatMessage(with: msgId, in: managedObjectContext), message.incomingStatus != .rerequesting {
                DDLogInfo("ProtoService/isMessageDecryptedAndSaved/msgId \(msgId) - message is available in local store.")
                isMessageAlreadyInLocalStore = true
            }
        }

        if isMessageAlreadyInLocalStore {
            return true
        }

        if let message = MainAppContext.shared.shareExtensionDataStore.sharedChatMessage(for: msgId), message.status != .rerequesting {
            DDLogInfo("ProtoService/isMessageDecryptedAndSaved/msgId \(msgId) - message needs to be stored from nse.")
            return true
        }
        DDLogInfo("ProtoService/isMessageDecryptedAndSaved/msgId \(msgId) - message is missing.")
        return false
    }

    private func rerequestMessageIfNecessary(_ message: Server_Msg, failedEphemeralKey: Data?, ack: (() -> Void)?) {
        // Dont rerequest messages that were already decrypted and saved.
        if !isMessageDecryptedAndSaved(msgId: message.id) {
            updateStatusAndRerequestMessage(message, failedEphemeralKey: failedEphemeralKey, ack: ack)
        }
    }

    private func updateStatusAndRerequestMessage(_ message: Server_Msg, failedEphemeralKey: Data?, ack: (() -> Void)?) {
        self.updateMessageStatus(id: message.id, status: .rerequested)
        let fromUserID = UserID(message.fromUid)
        DDLogInfo("ProtoService/rerequestMessage/\(message.id) rerequesting")
        rerequestMessage(message.id, senderID: fromUserID, failedEphemeralKey: failedEphemeralKey, contentType: .chat) { result in
            switch result {
            case .success(_):
                DDLogInfo("ProtoService/rerequestMessage/\(message.id)/success")
                ack?()
            case .failure(let error):
                DDLogError("ProtoService/rerequestMessage/\(message.id)/failure, error: \(error)")
            }
        }
    }

    override func didReceive(packet: Server_Packet) {
        super.didReceive(packet: packet)

        let requestID = packet.requestID ?? "unknown-id"

        switch packet.stanza {
        case .ack(let ack):
            let timestamp = Date(timeIntervalSince1970: TimeInterval(ack.timestamp))
            handlePossibleReceiptAck(id: ack.id) { wasReceiptFound in
                guard !wasReceiptFound else {
                    // Ack has been handled, no need to proceed further
                    return
                }

                // Not a receipt, must be a chat ack
                self.didGetChatAck.send((id: ack.id, timestamp: timestamp))
            }
        case .msg(let msg):
            // We now use contentId to eliminate push notifications: so here, we assume all content is worth notifying.
            // TODO: murali@: since this is always true, lets try and remove this argument.
            handleMessage(msg, isEligibleForNotification: true)
        case .haError(let error):
            DDLogError("proto/didReceive/\(requestID) received packet with error \(error)")
        case .presence(let pbPresence):
            DDLogInfo("proto/presence/received [\(pbPresence.fromUid)] [\(pbPresence.type)]")
            // Dispatch to main thread because ChatViewController updates UI in response
            DispatchQueue.main.async {
                self.didGetPresence.send(
                    (userID: UserID(pbPresence.fromUid),
                     presence: PresenceType(pbPresence.type),
                     lastSeen: Date(timeIntervalSince1970: TimeInterval(pbPresence.lastSeen))))
            }
        case .chatState(let pbChatState):
            DispatchQueue.main.async {
                self.didGetChatState.send((
                                            from: UserID(pbChatState.fromUid),
                                            threadType: pbChatState.threadType == .chat ? .oneToOne : .group,
                                            threadID: pbChatState.threadID,
                                            type: pbChatState.type == .typing ? .typing : .available,
                                            timestamp: Date()))
            }
        case .iq:
            // NB: Only respond to pings (other IQ should be responses handled by superclass)
            if case .ping(let ping) = packet.iq.payload {
                DDLogInfo("proto/ping/\(requestID)")
                var pong = Server_Packet()
                pong.iq.type = .result
                pong.iq.id = packet.iq.id
                pong.iq.ping = ping
                do {
                    try send(pong.serializedData())
                    DDLogInfo("proto/ping/\(requestID)/pong")
                } catch {
                    DDLogError("proto/ping/\(requestID)/error could not serialize pong")
                }
            }
        case nil:
            DDLogError("proto/didReceive/unknown-packet \(requestID)")
        }

    }
    // MARK: User Name

    private func resendNameIfNecessary() {
        guard !UserDefaults.standard.bool(forKey: userDefaultsKeyForNameSync) else { return }
        guard !AppContext.shared.userData.name.isEmpty else { return }
        updateUsername(AppContext.shared.userData.name)
    }

    // MARK: Message

    private func handleMessage(_ msg: Server_Msg, isEligibleForNotification: Bool) {

        let ack = { self.sendAck(messageID: msg.id) }

        var hasAckBeenDelegated = false
        defer {
            // Ack any message where we haven't explicitly delegated the ack to someone else
            if !hasAckBeenDelegated {
                ack()
            }
        }

        guard let payload = msg.payload else {
            DDLogError("proto/didReceive/\(msg.id)/error missing payload")
            return
        }

        switch retrieveMessageStatus(id: msg.id) {
        case .new, .rerequested:
            DDLogInfo("proto/didReceive/\(msg.id)/processing")
            updateMessageStatus(id: msg.id, status: .active)
        case .active:
            DDLogInfo("proto/didReceive/\(msg.id)/skipping (actively being processed)")
            hasAckBeenDelegated = true
            return
        case .processed:
            DDLogInfo("proto/didReceive/\(msg.id)/acking (already processed)")
            return
        }

        switch payload {
        case .contactList(let pbContactList):
            let contacts = pbContactList.contacts.compactMap { HalloContact($0) }
            hasAckBeenDelegated = true
            MainAppContext.shared.syncManager.processNotification(contacts: contacts) {
                ack()
                // client might be disconnected - if we generate one and dont send an ack, server will also send one notification.
                // todo(murali@): check with the team about this.
                if isEligibleForNotification {
                    self.showContactNotification(for: msg)
                }
            }

            if pbContactList.type == .inviterNotice {
                contacts.forEach {
                    if let userID = $0.userid {
                        MainAppContext.shared.chatData.updateThreadWithInvitedUserPreview(for: userID)
                    }
                }
            }
        case .avatar(let pbAvatar):
            avatarDelegate?.service(self, didReceiveAvatarInfo: (userID: UserID(pbAvatar.uid), avatarID: pbAvatar.id))
        case .whisperKeys(let pbKeys):
            if let whisperMessage = WhisperMessage(pbKeys) {
                keyDelegate?.service(self, didReceiveWhisperMessage: whisperMessage)
                didGetNewWhisperMessage.send(whisperMessage)
            } else {
                DDLogError("proto/didReceive/\(msg.id)/error could not read whisper message")
            }
        case .seenReceipt(let pbReceipt):
            handleReceivedReceipt(receipt: pbReceipt, from: UserID(msg.fromUid), messageID: msg.id, ack: ack)
            hasAckBeenDelegated = true
        case .deliveryReceipt(let pbReceipt):
            handleReceivedReceipt(receipt: pbReceipt, from: UserID(msg.fromUid), messageID: msg.id, ack: ack)
            hasAckBeenDelegated = true
        case .playedReceipt(let pbReceipt):
            handleReceivedReceipt(receipt: pbReceipt, from: UserID(msg.fromUid), messageID: msg.id, ack: ack)
            hasAckBeenDelegated = true
        case .chatStanza(let serverChat):
            if !serverChat.senderName.isEmpty {
                MainAppContext.shared.contactStore.addPushNames([ UserID(msg.fromUid) : serverChat.senderName ])
            }
            if !serverChat.senderPhone.isEmpty {
                MainAppContext.shared.contactStore.addPushNumbers([ UserID(msg.fromUid) : serverChat.senderPhone ])
            }
            // Dont process messages that were already decrypted and saved.
            if isMessageDecryptedAndSaved(msgId: msg.id) {
                return
            }

            let receiptTimestamp = Date()
            decryptChat(serverChat, from: UserID(msg.fromUid)) { (content, context, decryptionFailure) in
                if let content = content, let context = context {
                    let chatMessage = XMPPChatMessage(content: content, context: context, timestamp: serverChat.timestamp, from: UserID(msg.fromUid), to: UserID(msg.toUid), id: msg.id, retryCount: msg.retryCount, rerequestCount: msg.rerequestCount)
                    switch chatMessage.content {
                    case .album(let text, let media):
                        DDLogInfo("proto/didReceive/\(msg.id)/chat/user/\(chatMessage.fromUserId)/album [length=\(text?.count ?? 0)] [media=\(media.count)]")
                    case .text(let text, let linkPreviewData):
                        DDLogInfo("proto/didReceive/\(msg.id)/chat/user/\(chatMessage.fromUserId)/text [length=\(text.count)] [linkPreviewCount=\(linkPreviewData.count)]")
                    case .voiceNote(_):
                        DDLogInfo("proto/didReceive/\(msg.id)/chat/user/\(chatMessage.fromUserId)/voiceNote")
                    case .unsupported(let data):
                        DDLogInfo("proto/didReceive/\(msg.id)/chat/user/\(chatMessage.fromUserId)/unsupported [length=\(data.count)] [data=\(data.bytes.prefix(4))...]")
                    }
                    self.didGetNewChatMessage.send(.decrypted(chatMessage))
                } else {
                    self.didGetNewChatMessage.send(
                        .notDecrypted(
                            ChatMessageTombstone(
                                id: msg.id,
                                from: UserID(msg.fromUid),
                                to: UserID(msg.toUid),
                                timestamp: Date(timeIntervalSince1970: TimeInterval(serverChat.timestamp))
                            )))
                }
                if let failure = decryptionFailure {
                    DDLogError("proto/didReceive/\(msg.id)/decrypt/error \(failure.error)")
                    AppContext.shared.errorLogger?.logError(failure.error)
                    hasAckBeenDelegated = true
                    self.rerequestMessageIfNecessary(msg, failedEphemeralKey: failure.ephemeralKey, ack: ack)
                } else {
                    DDLogInfo("proto/didReceive/\(msg.id)/decrypt/success")
                }
                if !serverChat.senderClientVersion.isEmpty {
                    DDLogInfo("proto/didReceive/\(msg.id)/senderClient [\(serverChat.senderClientVersion)]")
                }
                if !serverChat.senderLogInfo.isEmpty {
                    DDLogInfo("proto/didReceive/\(msg.id)/senderLog [\(serverChat.senderLogInfo)]")
                }
                self.reportDecryptionResult(
                    error: decryptionFailure?.error,
                    messageID: msg.id,
                    timestamp: receiptTimestamp,
                    sender: UserAgent(string: serverChat.senderClientVersion),
                    rerequestCount: Int(msg.rerequestCount),
                    isSilent: false)
            }
        case .silentChatStanza(let silent):
            let receiptTimestamp = Date()
            // We ignore message content from silent messages (only interested in decryption success)
            decryptChat(silent.chatStanza, from: UserID(msg.fromUid)) { (_, _, decryptionFailure) in
                if let failure = decryptionFailure {
                    DDLogError("proto/didReceive/\(msg.id)/silent-decrypt/error \(failure.error)")
                    AppContext.shared.errorLogger?.logError(failure.error)
                    hasAckBeenDelegated = true
                    self.updateStatusAndRerequestMessage(msg, failedEphemeralKey: failure.ephemeralKey, ack: ack)
                } else {
                    DDLogInfo("proto/didReceive/\(msg.id)/silent-decrypt/success")
                }
                if !silent.chatStanza.senderClientVersion.isEmpty {
                    DDLogInfo("proto/didReceive/\(msg.id)/senderClient [\(silent.chatStanza.senderClientVersion)]")
                }
                if !silent.chatStanza.senderLogInfo.isEmpty {
                    DDLogInfo("proto/didReceive/\(msg.id)/senderLog [\(silent.chatStanza.senderLogInfo)]")
                }
                self.reportDecryptionResult(
                    error: decryptionFailure?.error,
                    messageID: msg.id,
                    timestamp: receiptTimestamp,
                    sender: UserAgent(string: silent.chatStanza.senderClientVersion),
                    rerequestCount: Int(msg.rerequestCount),
                    isSilent: true)
            }
        case .rerequest(let rerequest):
            let userID = UserID(msg.fromUid)

            // Check key integrity
            MainAppContext.shared.keyData.service(self, didReceiveRerequestWithRerequestCount: Int(msg.rerequestCount))

            // Protobuf object will contain a 0 if no one time pre key was used
            let oneTimePreKeyID: Int? = rerequest.oneTimePreKeyID > 0 ? Int(rerequest.oneTimePreKeyID) : nil

            AppContext.shared.messageCrypter.receivedRerequest(
                RerequestData(
                    identityKey: rerequest.identityKey,
                    signedPreKeyID: Int(rerequest.signedPreKeyID),
                    oneTimePreKeyID: oneTimePreKeyID,
                    sessionSetupEphemeralKey: rerequest.sessionSetupEphemeralKey,
                    messageEphemeralKey: rerequest.messageEphemeralKey),
                from: userID)
            DDLogInfo("proto/didReceive/\(msg.id)/rerequest/contentType: \(rerequest.contentType)")
            if let chatDelegate = chatDelegate, rerequest.contentType == .chat {
                chatDelegate.halloService(self, didRerequestMessage: rerequest.id, from: userID, ack: ack)
                hasAckBeenDelegated = true
            } else if let feedDelegate = feedDelegate, rerequest.contentType == .groupHistory {
                feedDelegate.halloService(self, didRerequestGroupFeedHistory: rerequest.id, from: userID, ack: ack)
                hasAckBeenDelegated = true
            }
        case .chatRetract(let pbChatRetract):
            let fromUserID = UserID(msg.fromUid)
            DispatchQueue.main.async {
                self.didGetChatRetract.send((
                    from: fromUserID,
                    threadType: .oneToOne,
                    threadID: fromUserID,
                    messageID: pbChatRetract.id
                ))
            }
        case .groupchatRetract(let pbGroupChatRetract):
            let fromUserID = UserID(msg.fromUid)
            DispatchQueue.main.async {
                self.didGetChatRetract.send((
                    from: fromUserID,
                    threadType: .group,
                    threadID: pbGroupChatRetract.gid,
                    messageID: pbGroupChatRetract.id
                ))
            }
        case .feedItem(let pbFeedItem):
            handleHomeFeedItems([pbFeedItem], isEligibleForNotification: isEligibleForNotification, ack: ack)
            hasAckBeenDelegated = true
        case .feedItems(let pbFeedItems):
            handleHomeFeedItems(pbFeedItems.items, isEligibleForNotification: isEligibleForNotification, ack: ack)
            hasAckBeenDelegated = true
        case .groupFeedItem(let item):
            guard let delegate = feedDelegate else {
                DDLogError("proto/handleGroupFeedItem/delegate missing")
                break
            }

            let itemType: FeedElementType
            let contentID: String
            switch item.item {
            case .post(let serverPost):
                itemType = .post
                contentID = serverPost.id
            case .comment(let serverComment):
                itemType = .comment
                contentID = serverComment.id
            default:
                DDLogError("proto/handleGroupFeedItem/\(msg.id)/decrypt/invalid content")
                return
            }

            let group = HalloGroup(id: item.gid, name: item.name, avatarID: item.avatarID)

            switch item.action {
            case .publish:
                // Dont process groupFeedItems that were already decrypted and saved.
                if isGroupFeedItemDecryptedAndSaved(contentID: contentID) {
                    DDLogInfo("proto/didReceive/\(msg.id)/isGroupFeedItemDecryptedAndSaved/\(contentID)/already saved - skip")
                    return
                }
                hasAckBeenDelegated = true
                decryptGroupFeedPayload(for: item, in: item.gid) { content, groupDecryptionFailure in
                    let receiptTimestamp = Date()
                    if let content = content {
                        DDLogInfo("proto/handleGroupFeedItem/\(msg.id)/\(contentID)/successfully decrypted content")
                        let payload = HalloServiceFeedPayload(content: content, group: group, isEligibleForNotification: isEligibleForNotification)

                        delegate.halloService(self, didReceiveFeedPayload: payload, ack: ack)
                    } else {
                        DDLogError("proto/handleGroupFeedItem/\(msg.id)/\(contentID)/failed to decrypt/using unencrypted content")
                        // fallback to existing logic of using unencrypted payload
                        let contents = self.payloadContents(for: [item], status: .rerequesting)
                        if contents.isEmpty {
                            ack()
                        } else {
                            // TODO(murali@): why are we sending multiple acks if at all here?
                            for content in contents  {
                                let payload = HalloServiceFeedPayload(content: content, group: group, isEligibleForNotification: isEligibleForNotification)
                                delegate.halloService(self, didReceiveFeedPayload: payload, ack: ack)
                            }
                        }
                    }
                    if let failure = groupDecryptionFailure,
                       let contentType = item.contentType {
                        DDLogError("proto/handleGroupFeedItem/\(msg.id)/\(contentID)/decrypt/error \(failure.error)")
                        self.rerequestGroupFeedItemIfNecessary(id: contentID, groupID: item.gid, contentType: contentType, failure: failure) { result in
                            switch result {
                            case .success:
                                self.updateMessageStatus(id: msg.id, status: .rerequested)
                            case .failure(let error):
                                DDLogError("proto/handleGroupFeedItem/\(msg.id)/\(contentID)/failed rerequesting: \(error)")
                            }
                        }
                    } else {
                        DDLogError("proto/handleGroupFeedItem/\(msg.id)/\(contentID)/decrypt/success")
                    }
                    self.reportGroupDecryptionResult(
                        error: groupDecryptionFailure?.error,
                        contentID: contentID,
                        contentType: itemType.rawString,
                        groupID: item.gid,
                        timestamp: receiptTimestamp,
                        sender: UserAgent(string: item.senderClientVersion),
                        rerequestCount: Int(msg.rerequestCount))
                }

            case .retract:
                hasAckBeenDelegated = true
                processGroupFeedRetract(for: item, in: item.gid) {
                    let contents = self.payloadContents(for: [item], status: .received)
                    if contents.isEmpty {
                        ack()
                    } else {
                        for content in contents  {
                            let payload = HalloServiceFeedPayload(content: content, group: group, isEligibleForNotification: isEligibleForNotification)
                            delegate.halloService(self, didReceiveFeedPayload: payload, ack: ack)
                        }
                    }
                }

            default:
                break
            }

        case .groupFeedRerequest(let rerequest):
            guard let delegate = feedDelegate else {
                DDLogError("proto/handleGroupFeedRerequest/delegate missing")
                break
            }
            let userID = UserID(msg.fromUid)

            // Check key integrity -- do we need this?
            // MainAppContext.shared.keyData.service(self, didReceiveRerequestWithRerequestCount: Int(msg.rerequestCount))

            switch rerequest.rerequestType {
            case .payload:
                delegate.halloService(self, didRerequestGroupFeedItem: rerequest.id, contentType: rerequest.contentType, from: userID, ack: ack)
                hasAckBeenDelegated = true
            case .senderState:
                hasAckBeenDelegated = true
                AppContext.shared.messageCrypter.resetWhisperSession(for: userID)
                // we are acking the message here - what if we fail to reset the session properly
                delegate.halloService(self, didRerequestGroupFeedItem: rerequest.id, contentType: rerequest.contentType, from: userID, ack: ack)
            case .UNRECOGNIZED(_):
                return
            }

        case .groupFeedItems(let items):
            guard let delegate = feedDelegate else {
                break
            }
            let group = HalloGroup(id: items.gid, name: items.name, avatarID: items.avatarID)
            for content in payloadContents(for: items.items, status: .received) {
                // TODO: Wait until all payloads have been processed before acking.
                let payload = HalloServiceFeedPayload(content: content, group: group, isEligibleForNotification: isEligibleForNotification)
                delegate.halloService(self, didReceiveFeedPayload: payload, ack: ack)
                hasAckBeenDelegated = true
            }

        case .contactHash(let pbContactHash):
            if pbContactHash.hash.isEmpty {
                // Trigger full sync
                MainAppContext.shared.syncManager.requestSync(forceFullSync: true)
            } else if let decodedData = Data(base64Encoded: pbContactHash.hash) {
                // Legacy Base64 protocol
                MainAppContext.shared.syncManager.processNotification(contactHashes: [decodedData], completion: ack)
                hasAckBeenDelegated = true
            } else {
                // Binary protocol
                MainAppContext.shared.syncManager.processNotification(contactHashes: [pbContactHash.hash], completion: ack)
                hasAckBeenDelegated = true
            }
        case .groupStanza(let pbGroup):
            if let group = HalloGroup(protoGroup: pbGroup, msgId: msg.id, retryCount: msg.retryCount) {
                hasAckBeenDelegated = true
                processGroupStanza(for: pbGroup, in: pbGroup.gid) { [weak self] (groupHistoryPayload, shouldSendAck) in
                    guard let self = self else { return }
                    DDLogInfo("proto/didReceive/\(msg.id)/processGroupStanza/notify chat delegate to update group")
                    self.chatDelegate?.halloService(self, didReceiveGroupMessage: group)
                    DDLogInfo("proto/didReceive/\(msg.id)/processGroupStanza/notify chat delegate to share group feed history")
                    self.chatDelegate?.halloService(self, didReceiveHistoryResendPayload: groupHistoryPayload, withGroupMessage: group)
                    DDLogInfo("proto/didReceive/\(msg.id)/processGroupStanza/finished processing")

                    // observe things around here and enable this.
                    if !shouldSendAck {
                        DDLogError("proto/didReceive/\(msg.id)/skipping an ack here - failed to process groupStanza")
                    } else {
                        ack()
                    }
                }
            } else {
                DDLogError("proto/didReceive/\(msg.id)/error could not read group stanza")
            }
        case .historyResend(let historyResend):
            // Dont process historyResend that was already decrypted and saved.
            if isGroupFeedItemDecryptedAndSaved(contentID: historyResend.id) {
                DDLogInfo("proto/didReceive/\(msg.id)/isGroupFeedItemDecryptedAndSaved/\(historyResend.id)/already saved - skip")
                return
            }
            processHistoryResendStanza(historyResend: historyResend, fromUserId: UserID(msg.fromUid), rerequestCount: msg.rerequestCount) { [weak self] (groupHistoryPayload, shouldSendAck) in
                guard let self = self else { return }
                DDLogInfo("proto/didReceive/\(msg.id)/processGroupStanza/notify chat delegate to share group feed history")
                if let groupHistoryPayload = groupHistoryPayload {
                    self.chatDelegate?.halloService(self, didReceiveHistoryResendPayload: groupHistoryPayload, for: historyResend.gid, from: UserID(msg.fromUid))
                } else {
                    DDLogError("proto/didReceive/\(msg.id)/unexpected - empty groupHistoryPayload")
                }
                // observe things around here and enable this.
                if !shouldSendAck {
                    DDLogError("proto/didReceive/\(msg.id)/skipping an ack here - failed to process groupStanza")
                } else {
                    ack()
                }
            }
        case .groupFeedHistory(let groupFeedHistory):
            DDLogInfo("proto/didReceive/\(msg.id)/groupFeedHistory/\(groupFeedHistory.gid)/begin")
            let fromUserID = UserID(msg.fromUid)
            let groupID = groupFeedHistory.gid
            // Dont process groupFeedHistory that was already decrypted and saved.
            if isOneToOneContentDecryptedAndSaved(contentID: groupFeedHistory.id) {
                DDLogInfo("proto/didReceive/\(msg.id)/groupFeedHistory/\(groupFeedHistory.gid)/already saved - skip")
                return
            }
            hasAckBeenDelegated = true
            decryptGroupFeedHistory(groupFeedHistory, from: fromUserID) { [weak self] result in
                guard let self = self else { return }
                var decryptionFailure: DecryptionFailure?
                switch result {
                case .failure(let failure):
                    DDLogError("proto/didReceive/\(msg.id)/groupFeedHistory/\(groupID)/ failed decryption: \(failure)")
                    self.rerequestMessage(groupFeedHistory.id,
                                          senderID: fromUserID,
                                          failedEphemeralKey: failure.ephemeralKey,
                                          contentType: .groupHistory) { result in
                        switch result {
                        case .success:
                            DDLogInfo("ProtoService/rerequest-groupFeedHistory/\(groupID)/success")
                            ack()
                        case .failure(let error):
                            DDLogError("ProtoService/rerequest-groupFeedHistory/\(groupID)/failure, error: \(error)")
                        }
                    }
                    decryptionFailure = failure
                case .success(let items):
                    DDLogInfo("proto/didReceive/\(msg.id)/groupFeedHistory/success/begin processing items, count: \(items.items.count)")
                    let group = HalloGroup(id: items.gid, name: items.name, avatarID: items.avatarID)
                    for content in self.payloadContents(for: items.items, status: .received) {
                        let payload = HalloServiceFeedPayload(content: content, group: group, isEligibleForNotification: isEligibleForNotification)
                        self.feedDelegate?.halloService(self, didReceiveFeedPayload: payload, ack: nil)
                    }
                    DDLogInfo("proto/didReceive/\(msg.id)/groupFeedHistory/success/finished processing items, count: \(items.items.count)")
                    ack()
                    decryptionFailure = nil
                }
                self.reportDecryptionResult(
                    error: decryptionFailure?.error,
                    messageID: groupFeedHistory.id,
                    timestamp: Date(),
                    sender: UserAgent(string: groupFeedHistory.senderClientVersion),
                    rerequestCount: Int(msg.rerequestCount),
                    isSilent: false)
            }
        case .groupChat(let pbGroupChat):
            if HalloGroupChatMessage(pbGroupChat, id: msg.id, retryCount: msg.retryCount) != nil {
                DDLogError("proto/didReceive/\(msg.id)/group chat message - ignore")
            } else {
                DDLogError("proto/didReceive/\(msg.id)/error could not read group chat message")
            }
        case .name(let pbName):
            if !pbName.name.isEmpty {
                // TODO: Is this necessary? Should we clear push name if name is empty?
                MainAppContext.shared.contactStore.addPushNames([ UserID(pbName.uid): pbName.name ])
            }
        case .requestLogs(_):
            DDLogInfo("proto/didReceive/\(msg.id)/request logs")
            uploadLogsToServer()
        case .wakeup(_):
            DDLogInfo("proto/didReceive/\(msg.id)/wakeup")
        case .endOfQueue(let endOfQueue):
            DDLogInfo("proto/didReceive/\(msg.id)/endOfQueue/trimmed: \(endOfQueue.trimmed)")
            readyToHandleCallMessages = true
        case .errorStanza(let error):
            DDLogError("proto/didReceive/\(msg.id) received message with error \(error)")

        case .incomingCall(let incomingCall):
            // If incomingCall is not late - then start ringing immediately.
            // Else - we need to record this as a missed call.
            if !incomingCall.isTooLate {
                DDLogInfo("proto/didReceive/\(msg.id)/incomingCall/\(incomingCall.callID)")
                callDelegate?.halloService(self, from: UserID(msg.fromUid), didReceiveIncomingCall: incomingCall)
                readyToHandleCallMessages = true
            } else {
                DDLogInfo("proto/didReceive/\(msg.id)/incomingCall/\(incomingCall.callID)/missedCall")
                guard let callType = incomingCall.callType.callType else {
                    DDLogError("proto/didReceive/\(msg.id)/incomingCall/\(incomingCall.callID)/invalid CallType")
                    return
                }
                let timestamp = Date(timeIntervalSince1970: Double(incomingCall.timestampMs) / 1000.0)
                MainAppContext.shared.mainDataStore.saveMissedCall(callID: incomingCall.callID, peerUserID: UserID(msg.fromUid), type: callType, timestamp: timestamp)
            }

        case .answerCall(let answerCall):
            if !readyToHandleCallMessages {
                DDLogInfo("proto/didReceive/\(msg.id)/answerCall/\(answerCall.callID)/addedToPending")
                var pendingMsgs = pendingCallMessages[answerCall.callID] ?? []
                pendingMsgs.append(msg)
                pendingCallMessages[answerCall.callID] = pendingMsgs
            } else {
                DDLogInfo("proto/didReceive/\(msg.id)/answerCall/\(answerCall.callID)")
                callDelegate?.halloService(self, from: UserID(msg.fromUid), didReceiveAnswerCall: answerCall)
            }

        case .callRinging(let callRinging):
            if !readyToHandleCallMessages {
                DDLogInfo("proto/didReceive/\(msg.id)/callRinging/\(callRinging.callID)/addedToPending")
                var pendingMsgs = pendingCallMessages[callRinging.callID] ?? []
                pendingMsgs.append(msg)
                pendingCallMessages[callRinging.callID] = pendingMsgs
            } else {
                DDLogInfo("proto/didReceive/\(msg.id)/callRinging/\(callRinging.callID)")
                callDelegate?.halloService(self, from: UserID(msg.fromUid), didReceiveCallRinging: callRinging)
            }

        case .endCall(let endCall):
            if !readyToHandleCallMessages {
                DDLogInfo("proto/didReceive/\(msg.id)/endCall/\(endCall.callID)/clear all call messages")
                pendingCallMessages[endCall.callID] = nil
            } else {
                DDLogInfo("proto/didReceive/\(msg.id)/endCall/\(endCall.callID)")
                callDelegate?.halloService(self, from: UserID(msg.fromUid), didReceiveEndCall: endCall)
            }

        case .iceCandidate(let iceCandidate):
            if !readyToHandleCallMessages {
                DDLogInfo("proto/didReceive/\(msg.id)/iceCandidate/\(iceCandidate.callID)/addedToPending")
                var pendingMsgs = pendingCallMessages[iceCandidate.callID] ?? []
                pendingMsgs.append(msg)
                pendingCallMessages[iceCandidate.callID] = pendingMsgs
            } else {
                DDLogInfo("proto/didReceive/\(msg.id)/iceCandidate/\(iceCandidate.callID)")
                callDelegate?.halloService(self, from: UserID(msg.fromUid), didReceiveIceCandidate: iceCandidate)
            }

        case .iceRestartOffer(let iceOffer):
            if !readyToHandleCallMessages {
                DDLogInfo("proto/didReceive/\(msg.id)/iceRestartOffer/\(iceOffer.callID)/addedToPending")
                var pendingMsgs = pendingCallMessages[iceOffer.callID] ?? []
                pendingMsgs.append(msg)
                pendingCallMessages[iceOffer.callID] = pendingMsgs
            } else {
                DDLogInfo("proto/didReceive/\(msg.id)/iceRestartOffer/\(iceOffer.callID)")
                callDelegate?.halloService(self, from: UserID(msg.fromUid), didReceiveIceOffer: iceOffer)
            }

        case .iceRestartAnswer(let iceAnswer):
            if !readyToHandleCallMessages {
                DDLogInfo("proto/didReceive/\(msg.id)/iceRestartAnswer/\(iceAnswer.callID)/addedToPending")
                var pendingMsgs = pendingCallMessages[iceAnswer.callID] ?? []
                pendingMsgs.append(msg)
                pendingCallMessages[iceAnswer.callID] = pendingMsgs
            } else {
                DDLogInfo("proto/didReceive/\(msg.id)/iceRestartAnswer/\(iceAnswer.callID)")
                callDelegate?.halloService(self, from: UserID(msg.fromUid), didReceiveIceAnswer: iceAnswer)
            }

        case .holdCall(let holdCall):
            if !readyToHandleCallMessages {
                DDLogInfo("proto/didReceive/\(msg.id)/holdCall/\(holdCall.callID)/addedToPending")
                var pendingMsgs = pendingCallMessages[holdCall.callID] ?? []
                pendingMsgs.append(msg)
                pendingCallMessages[holdCall.callID] = pendingMsgs
            } else {
                DDLogInfo("proto/didReceive/\(msg.id)/holdCall/\(holdCall.callID)")
                callDelegate?.halloService(self, from: UserID(msg.fromUid), didReceiveHoldCall: holdCall)
            }

        case .muteCall(let muteCall):
            if !readyToHandleCallMessages {
                DDLogInfo("proto/didReceive/\(msg.id)/muteCall/\(muteCall.callID)/addedToPending")
                var pendingMsgs = pendingCallMessages[muteCall.callID] ?? []
                pendingMsgs.append(msg)
                pendingCallMessages[muteCall.callID] = pendingMsgs
            } else {
                DDLogInfo("proto/didReceive/\(msg.id)/muteCall/\(muteCall.callID)")
                callDelegate?.halloService(self, from: UserID(msg.fromUid), didReceiveMuteCall: muteCall)
            }

        case .inviteeNotice:
            DDLogError("proto/didReceive/\(msg.id)/error unsupported-payload [\(payload)]")
        case .homeFeedRerequest(_):
            DDLogError("proto/didReceive/\(msg.id)/error unsupported-payload [\(payload)]")
        case .marketingAlert(_):
            DDLogError("proto/didReceive/\(msg.id)/error unsupported-payload [\(payload)]")
        case .preAnswerCall(_):
            DDLogError("proto/didReceive/\(msg.id)/error unsupported-payload [\(payload)]")
        }
    }

    // We want to wait handling certain call messages until end of queue is received.
    // Else - we could start ringing for a call that was already ended on the remote side.
    private func handlePendingCallMessages() {
        pendingCallMessages.forEach { (callID, pendingMsgs) in
            pendingMsgs.forEach { pendingMsg in
                DDLogInfo("proto/handlePendingCallMessages/callID: \(callID)/msg: \(pendingMsg.id)")
                switch pendingMsg.payload {
                case .incomingCall(let incomingCall):
                    callDelegate?.halloService(self, from: UserID(pendingMsg.fromUid), didReceiveIncomingCall: incomingCall)
                case .answerCall(let answerCall):
                    callDelegate?.halloService(self, from: UserID(pendingMsg.fromUid), didReceiveAnswerCall: answerCall)
                case .callRinging(let callRinging):
                    callDelegate?.halloService(self, from: UserID(pendingMsg.fromUid), didReceiveCallRinging: callRinging)
                case .iceCandidate(let iceCandidate):
                    callDelegate?.halloService(self, from: UserID(pendingMsg.fromUid), didReceiveIceCandidate: iceCandidate)
                case .iceRestartOffer(let iceOffer):
                    callDelegate?.halloService(self, from: UserID(pendingMsg.fromUid), didReceiveIceOffer: iceOffer)
                case .iceRestartAnswer(let iceAnswer):
                    callDelegate?.halloService(self, from: UserID(pendingMsg.fromUid), didReceiveIceAnswer: iceAnswer)
                case .holdCall(let holdCall):
                    callDelegate?.halloService(self, from: UserID(pendingMsg.fromUid), didReceiveHoldCall: holdCall)
                case .muteCall(let muteCall):
                    callDelegate?.halloService(self, from: UserID(pendingMsg.fromUid), didReceiveMuteCall: muteCall)
                default:
                    DDLogError("proto/didReceive/unexpected call message: \(String(describing: pendingMsg.payload))")
                    break
                }
            }
        }
        pendingCallMessages.removeAll()
    }

    // MARK: Avatar

    private func queryAvatarForCurrentUserIfNecessary() {
        guard !UserDefaults.standard.bool(forKey: AvatarStore.Keys.userDefaultsDownload) else { return }
        guard let userID = credentials?.userID else { return }
        DDLogInfo("proto/queryAvatarForCurrentUserIfNecessary start")

        let request = ProtoAvatarRequest(userID: userID) { result in
            switch result {
            case .success(let avatarInfo):
                UserDefaults.standard.set(true, forKey: AvatarStore.Keys.userDefaultsDownload)
                DDLogInfo("proto/queryAvatarForCurrentUserIfNecessary/success avatarId=\(avatarInfo.avatarID)")
                MainAppContext.shared.avatarStore.save(avatarId: avatarInfo.avatarID, forUserId: avatarInfo.userID)
            case .failure(let error):
                DDLogError("proto/queryAvatarForCurrentUserIfNecessary/error \(error)")
            }
        }

        self.enqueue(request: request)
    }

    private func resendAvatarIfNecessary() {
        guard UserDefaults.standard.bool(forKey: AvatarStore.Keys.userDefaultsUpload) else { return }
        guard let userID = credentials?.userID else { return }

        let userAvatar = MainAppContext.shared.avatarStore.userAvatar(forUserId: userID)
        guard userAvatar.isEmpty || userAvatar.data != nil else {
            DDLogError("ProtoService/resendAvatarIfNecessary/upload/error avatar data is not ready")
            return
        }

        updateAvatar(userAvatar.data)
    }

    private func reportDecryptionResult(error: DecryptionError?, messageID: String, timestamp: Date, sender: UserAgent?, rerequestCount: Int, isSilent: Bool) {
        AppContext.shared.eventMonitor.count(.decryption(error: error, sender: sender))

        if let sender = sender {
            MainAppContext.shared.cryptoData.update(
                messageID: messageID,
                timestamp: timestamp,
                result: error?.rawValue ?? "success",
                rerequestCount: rerequestCount,
                sender: sender,
                isSilent: isSilent)
        } else {
            DDLogError("proto/didReceive/\(messageID)/decrypt/stats/error missing sender user agent")
        }
    }

    // i dont think this is the right place to generate local notifications.
    // todo(murali@): fix this!
    private func showContactNotification(for msg: Server_Msg) {
        DDLogVerbose("ProtoService/showContactNotification")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch UIApplication.shared.applicationState {
            case .background, .inactive:
                self.presentLocalContactNotifications(for: msg)
            case .active:
                return
            @unknown default:
                self.presentLocalContactNotifications(for: msg)
            }
        }
    }

    private func presentLocalContactNotifications(for msg: Server_Msg) {
        DDLogDebug("ProtoService/presentLocalContactNotifications")
        var notifications: [UNMutableNotificationContent] = []
        guard let metadata = NotificationMetadata(msg: msg) else {
            return
        }

        AppContext.shared.notificationStore.runIfNotificationWasNotPresented(for: metadata.contentId) {
            let notification = UNMutableNotificationContent()
            notification.populate(from: metadata, contactStore: MainAppContext.shared.contactStore)
            notifications.append(notification)

            let notificationCenter = UNUserNotificationCenter.current()
            notifications.forEach { (notificationContent) in
                notificationCenter.add(UNNotificationRequest(identifier: UUID().uuidString, content: notificationContent, trigger: nil))
                AppContext.shared.notificationStore.save(id: metadata.contentId, type: metadata.contentType.rawValue)
            }
        }
    }
}

extension ProtoService: HalloService {

    func updateUsername(_ name: String) {
        UserDefaults.standard.set(false, forKey: userDefaultsKeyForNameSync)
        enqueue(request: ProtoSendNameRequest(name: name) { result in
            if case .success = result {
                UserDefaults.standard.set(true, forKey: userDefaultsKeyForNameSync)
            }
        })
    }

    func updateAvatar(_ data: Data?) {
        guard let userID = credentials?.userID else { return }
        UserDefaults.standard.set(true, forKey: AvatarStore.Keys.userDefaultsUpload)
        let logAction = data == nil ? "removed" : "uploaded"
        enqueue(request: ProtoUpdateAvatarRequest(data: data) { result in
            switch result {
            case .success(let avatarID):
                DDLogInfo("ProtoService/updateAvatar avatar has been \(logAction)")
                UserDefaults.standard.set(false, forKey: AvatarStore.Keys.userDefaultsUpload)

                if let avatarID = avatarID {
                    DDLogInfo("ProtoService/updateAvatar received new avatarID [\(avatarID)]")
                    MainAppContext.shared.avatarStore.update(avatarId: avatarID, forUserId: userID)
                }

            case .failure(let error):
                DDLogError("ProtoService/updateAvatar/error avatar not \(logAction): \(error)")
            }
        })
    }

    func retractComment(id: FeedPostCommentID, postID: FeedPostID, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoRetractCommentRequest(id: id, postID: postID, completion: completion))
    }

    func retractPost(_ id: FeedPostID, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoRetractPostRequest(id: id, completion: completion))
    }

    func retractPost(_ id: FeedPostID, in groupID: GroupID?, completion: @escaping ServiceRequestCompletion<Void>) {
        if let groupID = groupID {
            enqueue(request: ProtoRetractGroupPostRequest(id: id, in: groupID, completion: completion))
        } else {
            enqueue(request: ProtoRetractPostRequest(id: id, completion: completion))
        }
    }

    func retractComment(id: FeedPostCommentID, postID: FeedPostID, in groupID: GroupID?, completion: @escaping ServiceRequestCompletion<Void>) {
        if let groupID = groupID {
            enqueue(request: ProtoRetractGroupCommentRequest(id: id, postID: postID, in: groupID, completion: completion))
        } else {
            enqueue(request: ProtoRetractCommentRequest(id: id, postID: postID, completion: completion))
        }
    }

    func retractPost(_ id: FeedPostID, in groupID: GroupID, to toUserID: UserID) {
        guard let toUID = Int64(toUserID) else {
            return
        }
        guard let userID = credentials?.userID, let fromUID = Int64(userID) else {
            DDLogError("ProtoService/retractPost/error invalid sender uid")
            return
        }

        var packet = Server_Packet()
        packet.msg.toUid = toUID
        packet.msg.fromUid = fromUID
        packet.msg.id = PacketID.generate()
        packet.msg.type = .normal

        var serverPost = Server_Post()
        serverPost.id = id
        serverPost.publisherUid = fromUID
        var groupFeedItem = Server_GroupFeedItem()
        groupFeedItem.action = .retract
        groupFeedItem.item = .post(serverPost)
        groupFeedItem.gid = groupID

        packet.msg.payload = .groupFeedItem(groupFeedItem)

        guard let packetData = try? packet.serializedData() else {
            DDLogError("ProtoService/retractPost/error could not serialize packet")
            return
        }

        DDLogInfo("ProtoService/retractPost/\(id)/group: \(groupID)/to:\(toUserID)")
        send(packetData)
    }

    func retractComment(_ id: FeedPostCommentID, postID: FeedPostID, in groupID: GroupID, to toUserID: UserID) {
        // TODO: murali@: we should add an acknowledgement for all message stanzas
        // currently we only do this for receipts.

        guard let toUID = Int64(toUserID) else {
            return
        }
        guard let userID = credentials?.userID, let fromUID = Int64(userID) else {
            DDLogError("ProtoService/retractComment/error invalid sender uid")
            return
        }

        var packet = Server_Packet()
        packet.msg.toUid = toUID
        packet.msg.fromUid = fromUID
        packet.msg.id = PacketID.generate()
        packet.msg.type = .normal

        var serverComment = Server_Comment()
        serverComment.id = id
        serverComment.postID = postID
        serverComment.publisherUid = fromUID
        var groupFeedItem = Server_GroupFeedItem()
        groupFeedItem.action = .retract
        groupFeedItem.item = .comment(serverComment)
        groupFeedItem.gid = groupID

        packet.msg.payload = .groupFeedItem(groupFeedItem)

        guard let packetData = try? packet.serializedData() else {
            DDLogError("ProtoService/retractComment/error could not serialize packet")
            return
        }

        DDLogInfo("ProtoService/retractComment/\(id)/group: \(groupID)/to:\(toUserID)")
        send(packetData)
    }

    func sharePosts(postIds: [FeedPostID], with userId: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoSharePostsRequest(postIDs: postIds, userID: userId, completion: completion))
    }

    func shareGroupHistory(items: Server_GroupFeedItems, with userID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        let groupID = items.gid
        do {
            DDLogInfo("ProtoService/shareGroupHistory/\(groupID)/begin")
            let payload = try items.serializedData()
            let groupFeedHistoryID = PacketID.generate()
            MainAppContext.shared.mainDataStore.saveGroupHistoryInfo(id: groupFeedHistoryID, groupID: groupID, payload: payload)
            sendGroupFeedHistoryPayload(id: groupFeedHistoryID, groupID: groupID, payload: payload, to: userID, rerequestCount: 0, completion: completion)
        } catch {
            DDLogError("ProtoService/shareGroupHistory/\(groupID)/error could not serialize items")
            completion(.failure(.aborted))
        }
    }

    func uploadPostForExternalShare(_ postID: FeedPostID, completion: @escaping (Result<URL, RequestError>) -> Void) {
        guard let postData = MainAppContext.shared.feedData.feedPost(with: postID)?.postData else {
            DDLogError("ProtoService/UploadPostForExternalShare/Failed find post")
            completion(.failure(RequestError.aborted))
            return
        }
        guard let data = try? postData.clientPostContainer.serializedData() else {
            DDLogError("ProtoService/UploadPostForExternalShare/Could not serialize post")
            completion(.failure(RequestError.aborted))
            return
        }

        var attachmentKey = [UInt8](repeating: 0, count: 15)
        guard SecRandomCopyBytes(kSecRandomDefault, 15, &attachmentKey) == errSecSuccess else {
            DDLogError("ProtoService/UploadPostForExternalShare/Failed to generate key")
            completion(.failure(RequestError.aborted))
            return
        }

        guard let fullKey = try? HKDF(password: attachmentKey, info: "HalloApp Share Post".bytes, keyLength: 80, variant: .sha256).calculate() else {
            DDLogError("ProtoService/UploadPostForExternalShare/Failed to generate key")
            completion(.failure(RequestError.aborted))
            return
        }

        let iv = Array(fullKey[0..<16])
        let aesKey = Array(fullKey[16..<48])
        let hmacKey = Array(fullKey[48..<80])

        guard let encryptedPostData = try? AES(key: aesKey, blockMode: CBC(iv: iv), padding: .pkcs5).encrypt(data.bytes) else {
            DDLogError("ProtoService/UploadPostForExternalShare/Failed to encrypt post data")
            completion(.failure(RequestError.aborted))
            return
        }

        guard let hmac = try? HMAC(key: hmacKey, variant: .sha256).authenticate(encryptedPostData) else {
            DDLogError("ProtoService/UploadPostForExternalShare/Failed to authenticate encryptedPostData")
            completion(.failure(RequestError.aborted))
            return
        }

        let encryptedPayload = Data(encryptedPostData + hmac)
        let expiry = postData.timestamp.addingTimeInterval(-FeedData.postExpiryTimeInterval)

        var ogTagInfo = Server_OgTagInfo()
        if let text = postData.text {
            ogTagInfo.description_p = text
        }

        enqueue(request: ProtoExternalShareRequest(encryptedPostData: encryptedPayload, expiry: expiry, ogTagInfo: ogTagInfo) { result in
            switch result {
            case .success(let blobID):
                if let url = URL(string: "\(shareURLPrefix)\(blobID)?k=\(Data(attachmentKey).base64urlEncodedString())") {
                    completion(.success(url))
                } else {
                    completion(.failure(RequestError.malformedResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        })
    }

    func sendReceipt(itemID: String, thread: HalloReceipt.Thread, type: HalloReceipt.`Type`, fromUserID: UserID, toUserID: UserID) {
        let receipt = HalloReceipt(itemId: itemID, userId: fromUserID, type: type, timestamp: nil, thread: thread)
        sendReceipt(receipt, to: toUserID)
    }

    func retractChatMessage(messageID: String, toUserID: UserID, messageToRetractID: String) {
        guard let toUID = Int64(toUserID) else {
            return
        }
        guard let userID = credentials?.userID, let fromUID = Int64(userID) else {
            DDLogError("ProtoService/retractChatMessage/error invalid sender uid")
            return
        }
        
        var packet = Server_Packet()
        packet.msg.toUid = toUID
        packet.msg.fromUid = fromUID
        packet.msg.id = messageID
        packet.msg.type = .chat

        var chatRetract = Server_ChatRetract()
        chatRetract.id = messageToRetractID

        packet.msg.payload = .chatRetract(chatRetract)
        
        guard let packetData = try? packet.serializedData() else {
            DDLogError("ProtoService/retractChatMessage/error could not serialize packet")
            return
        }

        DDLogInfo("ProtoService/retractChatMessage")
        send(packetData)
    }

    func subscribeToPresenceIfPossible(to userID: UserID) -> Bool {
        guard isConnected else { return false }

        var presence = Server_Presence()
        presence.id = PacketID.generate(short: true)
        presence.type = .subscribe
        if let uid = Int64(userID) {
            presence.toUid = uid
        }

        var packet = Server_Packet()
        packet.stanza = .presence(presence)

        guard let packetData = try? packet.serializedData() else {
            DDLogError("ProtoService/subscribeToPresenceIfPossible/error could not serialize")
            return false
        }
        send(packetData)
   
        return true
    }
    
    func sendChatStateIfPossible(type: ChatType, id: String, state: ChatState) {
        guard isConnected else { return }

        var chatState = Server_ChatState()
        chatState.threadID = id
        chatState.type = {
            switch state {
            case .available: return .available
            case .typing: return .typing
            }
        }()
        chatState.threadType = {
            switch type {
            case .oneToOne: return .chat
            case .group: return .groupChat
            }
        }()
        var packet = Server_Packet()
        packet.chatState = chatState

        guard let packetData = try? packet.serializedData() else {
            DDLogError("ProtoService/sendChatStateIfPossible/error could not serialize \(type) \(id) \(state)")
            return
        }
        send(packetData)
    }
    
    func requestInviteAllowance(completion: @escaping ServiceRequestCompletion<(Int, Date)>) {
        enqueue(request: ProtoGetInviteAllowanceRequest(completion: completion))
    }

    func sendInvites(phoneNumbers: [ABContact.NormalizedPhoneNumber], completion: @escaping ServiceRequestCompletion<InviteResponse>) {
        enqueue(request: ProtoRegisterInvitesRequest(phoneNumbers: phoneNumbers, completion: completion))
    }

    func syncContacts<T>(with contacts: T, type: ContactSyncRequestType, syncID: String, batchIndex: Int?, isLastBatch: Bool?, completion: @escaping ServiceRequestCompletion<[HalloContact]>) where T : Sequence, T.Element == HalloContact {
        enqueue(request: ProtoContactSyncRequest(
            with: contacts,
            type: type,
            syncID: syncID,
            batchIndex: batchIndex,
            isLastBatch: isLastBatch,
            completion: completion))
    }

    func updatePrivacyList(_ update: PrivacyListUpdateProtocol, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoUpdatePrivacyListRequest(update: update, completion: completion))
    }

    func getPrivacyLists(_ listTypes: [PrivacyListType], completion: @escaping ServiceRequestCompletion<([PrivacyListProtocol], PrivacyListType)>) {
        enqueue(request: ProtoGetPrivacyListsRequest(listTypes: listTypes, completion: completion))
    }

    var hasValidAPNSPushToken: Bool {
        if let token = UserDefaults.standard.string(forKey: userDefaultsKeyForAPNSToken) {
            return !token.isEmpty
        }
        return false
    }

    var hasValidVOIPPushToken: Bool {
        if let token = UserDefaults.standard.string(forKey: userDefaultsKeyForVOIPToken) {
            return !token.isEmpty
        }
        return false
    }

    func sendAPNSTokenIfNecessary(_ token: String?) {
        let langID = Locale.current.halloServiceLangID
        let hasSyncTokenChanged = token != UserDefaults.standard.string(forKey: userDefaultsKeyForAPNSToken)
        let hasLangIDChanged = langID != UserDefaults.standard.string(forKey: userDefaultsKeyForLangID)
        let savedAPNSSyncTime = UserDefaults.standard.object(forKey: userDefaultsKeyForAPNSSyncTime) as? Date
        let isSyncScheduled = Date() > (savedAPNSSyncTime ?? Date.distantPast)

        let type: Server_PushToken.TokenType
        #if DEBUG
        type = .iosDev
        #else
        type = .ios
        #endif

        // Sync push token and langID whenever they change or every 24hrs.
        if (hasSyncTokenChanged || hasLangIDChanged || isSyncScheduled), let token = token {
            execute(whenConnectionStateIs: .connected, onQueue: .main) {
                self.enqueue(request: ProtoPushTokenRequest(type: type, token: token, langID: langID) { result in
                    DDLogInfo("proto/push-token/sent")
                    if case .success = result {
                        DDLogInfo("proto/push-token/update local data")
                        self.saveAPNSTokenAndLangID(token: token, langID: langID)
                    } else {
                        DDLogInfo("proto/push-token/failed to set on server")
                    }
                })
            }
        }
    }

    func sendVOIPTokenIfNecessary(_ token: String?) {
        let langID = Locale.current.halloServiceLangID
        let hasVoipTokenChanged = token != UserDefaults.standard.string(forKey: userDefaultsKeyForVOIPToken)
        let hasLangIDChanged = langID != UserDefaults.standard.string(forKey: userDefaultsKeyForLangID)
        let savedVOIPSyncTime = UserDefaults.standard.object(forKey: userDefaultsKeyForVOIPSyncTime) as? Date
        let isSyncScheduled = Date() > (savedVOIPSyncTime ?? Date.distantPast)

        // Sync voip push token and langID whenever they change or every 24hrs.
        if (hasVoipTokenChanged || hasLangIDChanged || isSyncScheduled), let token = token {
            execute(whenConnectionStateIs: .connected, onQueue: .main) {
                self.enqueue(request: ProtoPushTokenRequest(type: .iosVoip, token: token, langID: langID) { result in
                    DDLogInfo("proto/voip-push-token/sent")
                    if case .success = result {
                        DDLogInfo("proto/voip-push-token/update local data")
                        self.saveVoipToken(token: token)
                    } else {
                        DDLogInfo("proto/voip-push-token/failed to set on server")
                    }
                })
            }
        }
    }

    func saveAPNSTokenAndLangID(token: String?, langID: String?) {
        // save token
        if let token = token {
            UserDefaults.standard.set(token, forKey: userDefaultsKeyForAPNSToken)
        } else {
            UserDefaults.standard.removeObject(forKey: userDefaultsKeyForAPNSToken)
        }

        // save langID
        if let langID = langID {
            UserDefaults.standard.set(langID, forKey: userDefaultsKeyForLangID)
        } else {
            UserDefaults.standard.removeObject(forKey: userDefaultsKeyForLangID)
        }

        // save next sync date - after 1 day.
        let nextDate = Date(timeIntervalSinceNow: 60*60*24)
        UserDefaults.standard.set(nextDate, forKey: userDefaultsKeyForAPNSSyncTime)
    }

    func saveVoipToken(token: String?) {
        // save voip token
        if let token = token {
            UserDefaults.standard.set(token, forKey: userDefaultsKeyForVOIPToken)
        } else {
            UserDefaults.standard.removeObject(forKey: userDefaultsKeyForVOIPToken)
        }

        // save next sync date - after 1 day.
        let nextDate = Date(timeIntervalSinceNow: 60*60*24)
        UserDefaults.standard.set(nextDate, forKey: userDefaultsKeyForVOIPSyncTime)
    }



    func updateNotificationSettings(_ settings: [NotificationSettings.ConfigKey : Bool], completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoUpdateNotificationSettingsRequest(settings: settings, completion: completion))
    }

    func getServerProperties(completion: @escaping ServiceRequestCompletion<ServerPropertiesResponse>) {
        enqueue(request: ProtoGetServerPropertiesRequest(completion: completion))
    }
    
    func exportDataStatus(isSetRequest: Bool = false, completion: @escaping ServiceRequestCompletion<Server_ExportData>) {
        enqueue(request: ProtoGetDataExportStatusRequest(isSetRequest: isSetRequest, completion: completion))
    }

    func requestAccountDeletion(phoneNumber: String, feedback: String?, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoDeleteAccountRequest(phoneNumber: phoneNumber, feedback: feedback, completion: completion))
    }

    func sendGroupChatMessage(_ message: HalloGroupChatMessage) {
        guard let messageData = try? message.protoContainer?.serializedData() else {
            DDLogError("ProtoService/sendGroupChatMessage/\(message.id)/error could not serialize message data")
            return
        }
        guard let userID = credentials?.userID, let fromUID = Int64(userID) else {
            DDLogError("ProtoService/sendGroupChatMessage/\(message.id)/error invalid sender uid")
            return
        }

        var packet = Server_Packet()
        packet.msg.fromUid = fromUID
        packet.msg.id = message.id
        packet.msg.type = .groupchat

        var chat = Server_GroupChat()
        chat.payload = messageData
        chat.gid = message.groupId
        if let groupName = message.groupName {
            chat.name = groupName
        }

        packet.msg.payload = .groupChat(chat)
        
        guard let packetData = try? packet.serializedData() else {
            DDLogError("ProtoService/sendGroupChatMessage/\(message.id)/error could not serialize packet")
            return
        }

        DDLogInfo("ProtoService/sendGroupChatMessage/\(message.id) sending (unencrypted)")
        send(packetData)
    }

    func retractGroupChatMessage(messageID: String, groupID: GroupID, messageToRetractID: String) {
        guard let userID = credentials?.userID, let fromUID = Int64(userID) else {
            DDLogError("ProtoService/retractChatGroupMessage/error invalid sender uid")
            return
        }
        
        var packet = Server_Packet()
        packet.msg.fromUid = fromUID
        packet.msg.id = messageID
        packet.msg.type = .groupchat

        var groupChatRetract = Server_GroupChatRetract()
        groupChatRetract.id = messageToRetractID
        groupChatRetract.gid = groupID

        packet.msg.payload = .groupchatRetract(groupChatRetract)
        
        guard let packetData = try? packet.serializedData() else {
            DDLogError("ProtoService/retractChatGroupMessage/error could not serialize packet")
            return
        }

        DDLogInfo("ProtoService/retractChatGroupMessage")
        send(packetData)
    }
    
    func createGroup(name: String, members: [UserID], completion: @escaping ServiceRequestCompletion<String>) {
        enqueue(request: ProtoGroupCreateRequest(name: name, members: members, completion: completion))
    }

    func leaveGroup(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoGroupLeaveRequest(groupID: groupID, completion: completion))
    }

    func getGroupInfo(groupID: GroupID, completion: @escaping ServiceRequestCompletion<HalloGroup>) {
        enqueue(request: ProtoGroupInfoRequest(groupID: groupID, completion: completion))
    }
    
    func getGroupInviteLink(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>) {
        enqueue(request: ProtoGroupInviteLinkRequest(groupID: groupID, completion: completion))
    }

    func resetGroupInviteLink(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>) {
        enqueue(request: ProtoResetGroupInviteLinkRequest(groupID: groupID, completion: completion))
    }
    
    func getGroupsList(completion: @escaping ServiceRequestCompletion<HalloGroups>) {
        enqueue(request: ProtoGroupsListRequest(completion: completion))
    }

    // Get groupMemberIdentityKeys and dispatch work to fetch keys for potential members.
    // After fetching all of that: we have the necessary member info.
    // then fetch group-history data - compute hashes and the construct the history-resend payload.
    // Construct the iq to add members with history-resend and send the data.
    func modifyGroup(groupID: GroupID, with members: [UserID], groupAction: ChatGroupAction,
                     action: ChatGroupMemberAction, completion: @escaping ServiceRequestCompletion<Void>) {
        switch action {
        case .add:
            // Fetch identity keys if necessary for members to be added.
            var newMembersDetails: [Clients_MemberDetails] = []
            var numberOfFailedFetches = 0
            let fetchMemberKeysGroup = DispatchGroup()
            let fetchMemberKeysCompletion: (Result<KeyBundle, EncryptionError>) -> Void = { result in
                switch result {
                case .failure(_):
                    numberOfFailedFetches += 1
                    DDLogError("ProtoServiceCore/modifyGroup/\(groupID)/fetchMemberKeysCompletion/error - num: \(numberOfFailedFetches)")
                default:
                    break
                }
                fetchMemberKeysGroup.leave()
            }

            for member in members {
                guard member != credentials?.userID else {
                    continue
                }
                guard let memberIntUserID = Int64(member) else {
                    continue
                }
                fetchMemberKeysGroup.enter()
                MainAppContext.shared.messageCrypter.setupOutbound(for: member) { result in
                    switch result {
                    case .success(let keyBundle):
                        var memberDetails = Clients_MemberDetails()
                        memberDetails.uid = memberIntUserID
                        memberDetails.publicIdentityKey = keyBundle.inboundIdentityPublicEdKey
                        newMembersDetails.append(memberDetails)
                    case .failure(_):
                        break
                    }
                    fetchMemberKeysCompletion(result)
                }
            }

            fetchMemberKeysGroup.notify(queue: .main) {
                if numberOfFailedFetches > 0 {
                    DDLogError("ProtoServiceCore/modifyGroup/\(groupID)/fetchMemberKeysCompletion/error - num: \(numberOfFailedFetches)")
                    completion(.failure(.aborted))
                } else {
                    // After successfully obtaining the memberKeys
                    // Now fetch feedHistory, compute the hashes and construct the history resend stanza.
                    // Get feedHistory
                    let (postsData, commentsData) = MainAppContext.shared.feedData.feedHistory(for: groupID)

                    DDLogInfo("ProtoServiceCore/modifyGroup/\(groupID)/fetchMemberKeysCompletion/success - \(newMembersDetails.count)")
                    var feedContentDetails: [Clients_ContentDetails] = []
                    do {
                        for post in postsData {
                            var contentDetails = Clients_ContentDetails()
                            var postIdContext = Clients_PostIdContext()
                            postIdContext.feedPostID = post.id
                            contentDetails.postIDContext = postIdContext
                            let contentData = try post.clientContainer.serializedData()
                            contentDetails.contentHash = SHA256.hash(data: contentData).data
                            feedContentDetails.append(contentDetails)
                        }
                        for comment in commentsData {
                            var contentDetails = Clients_ContentDetails()
                            var commentIdContext = Clients_CommentIdContext()
                            commentIdContext.commentID = comment.id
                            commentIdContext.feedPostID = comment.feedPostId
                            if let parentID = comment.parentId {
                                commentIdContext.parentCommentID = parentID
                            }
                            contentDetails.commentIDContext = commentIdContext
                            let contentData = try comment.clientContainer.serializedData()
                            contentDetails.contentHash = SHA256.hash(data: contentData).data
                            feedContentDetails.append(contentDetails)
                        }

                        var groupHistoryPayload = Clients_GroupHistoryPayload()
                        groupHistoryPayload.contentDetails = feedContentDetails
                        groupHistoryPayload.memberDetails = newMembersDetails

                        let payloadData = try groupHistoryPayload.serializedData()
                        let historyResendID = PacketID.generate()
                        MainAppContext.shared.mainDataStore.saveGroupHistoryInfo(id: historyResendID, groupID: groupID, payload: payloadData)

                        // Encrypt the containerPayload
                        AppContext.shared.messageCrypter.encrypt(payloadData, in: groupID, potentialMemberUids: members) { [weak self] result in
                            guard let self = self else {
                                DDLogError("ProtoServiceCore/modifyGroup/\(groupID)/encryptHistoryContainer/error: aborted")
                                completion(.failure(.aborted))
                                return
                            }
                            switch result {
                            case .failure(let error):
                                DDLogError("ProtoServiceCore/modifyGroup/\(groupID)/encryptHistoryContainer/error: \(error)")
                                completion(.failure(.aborted))
                            case .success(let groupEncryptedData):
                                var historyResend = Server_HistoryResend()
                                historyResend.id = historyResendID
                                historyResend.gid = groupID
                                historyResend.senderStateBundles = groupEncryptedData.senderStateBundles
                                historyResend.audienceHash = groupEncryptedData.audienceHash
                                var clientEncryptedPayload = Clients_EncryptedPayload()
                                clientEncryptedPayload.senderStateEncryptedPayload = groupEncryptedData.data
                                guard let encPayload = try? clientEncryptedPayload.serializedData() else {
                                    DDLogError("ProtoServiceCore/modifyGroup/\(groupID)/error could not serialize payload")
                                    completion(.failure(.aborted))
                                    return
                                }
                                historyResend.encPayload = encPayload
                                historyResend.payload = payloadData
                                historyResend.senderClientVersion = AppContext.userAgent
                                DDLogInfo("ProtoServiceCore/modifyGroup/\(groupID)/encryptHistoryContainer/success - enqueuing request")
                                self.enqueue(request: ProtoGroupAddMemberRequest(groupID: groupID,
                                                                                 members: members,
                                                                                 historyResend: historyResend,
                                                                                 completion: completion))
                            }
                        }
                    } catch {
                        DDLogError("ProtoServiceCore/modifyGroup/\(groupID)/fetchHistoryContainer/failed serialization")
                        completion(.failure(.aborted))
                    }
                }
            }
        default:
            enqueue(request: ProtoGroupModifyRequest(
                groupID: groupID,
                members: members,
                groupAction: groupAction,
                action: action,
                completion: completion))
        }
    }

    func changeGroupName(groupID: GroupID, name: String, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoChangeGroupNameRequest(
            groupID: groupID,
            name: name,
            completion: completion))
    }

    func changeGroupAvatar(groupID: GroupID, data: Data?, completion: @escaping ServiceRequestCompletion<String>) {
        enqueue(request: ProtoChangeGroupAvatarRequest(
            groupID: groupID,
            data: data,
            completion: completion))
    }
    
    func changeGroupDescription(groupID: GroupID, description: String, completion: @escaping ServiceRequestCompletion<String>) {
        enqueue(request: ProtoChangeGroupDescriptionRequest(
            groupID: groupID,
            description: description,
            completion: completion))
    }
    
    func setGroupBackground(groupID: GroupID, background: Int32, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoSetGroupBackgroundRequest(
            groupID: groupID,
            background: background,
            completion: completion))
    }

    func mergeData(from sharedDataStore: SharedDataStore, completion: @escaping () -> ()) {
        let sharedServerMessages = sharedDataStore.serverMessages()
        DDLogInfo("ProtoService/mergeData/save sharedServerMessages, count: \(sharedServerMessages.count)")
        sharedServerMessages.forEach{ sharedServerMsg in
            do {
                if let serverMsgPb = sharedServerMsg.msg {
                    let serverMsg = try Server_Msg(serializedData: serverMsgPb)
                    DDLogInfo("ProtoService/mergeData/handle serverMsg: \(serverMsg.id)")
                    handleMessage(serverMsg, isEligibleForNotification: false)
                }
            } catch {
                DDLogError("ProtoService/mergeData/Unable to initialize Server_Msg")
            }
        }
        sharedDataStore.delete(serverMessages: sharedServerMessages, completion: completion)
    }

    func getCallServers(id callID: CallID, for peerUserID: UserID, callType: CallType, completion: @escaping ServiceRequestCompletion<Server_GetCallServersResult>) {
        guard let toUID = Int64(peerUserID) else {
            DDLogError("ProtoService/getCallServers/error invalid to uid: \(peerUserID)")
            completion(.failure(.aborted))
            return
        }
        DDLogInfo("ProtoService/getCallServers/for: \(peerUserID) sending")
        enqueue(request: ProtoGetCallServersRequest(id: callID, for: toUID, callType: callType.serverCallType, completion: completion))
    }

    func startCall(id callID: CallID, to peerUserID: UserID, callType: CallType, payload: Data, completion: @escaping ServiceRequestCompletion<Server_StartCallResult>) {
        AppContext.shared.messageCrypter.encrypt(payload, for: peerUserID) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                DDLogError("ProtoService/startCall/\(callID)/failed encryption: \(peerUserID)/error: \(error)")
                completion(.failure(.aborted))
            case .success((let encryptedData, _)):
                var webRtcOffer = Server_WebRtcSessionDescription()
                webRtcOffer.encPayload = encryptedData.data
                webRtcOffer.publicKey = encryptedData.identityKey ?? Data()
                webRtcOffer.oneTimePreKeyID = Int32(encryptedData.oneTimeKeyId)
                guard let toUID = Int64(peerUserID) else {
                    DDLogError("ProtoService/startCall/\(callID)/error invalid to uid: \(peerUserID)")
                    completion(.failure(.aborted))
                    return
                }
                DDLogInfo("ProtoService/startCall/\(callID) sending")
                self.enqueue(request: ProtoStartCallRequest(id: callID, to: toUID, callType: callType.serverCallType, webRtcOffer: webRtcOffer, completion: completion))
            }
        }
    }

    func iceRestartOfferCall(id callID: CallID, to peerUserID: UserID, payload: Data, iceIdx: Int32, completion: @escaping (Result<Void, RequestError>) -> Void) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            AppContext.shared.messageCrypter.encrypt(payload, for: peerUserID) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    DDLogError("ProtoService/iceRestartOfferCall/\(callID)/failed encryption: \(peerUserID)/error: \(error)")
                    completion(.failure(.aborted))
                case .success((let encryptedData, _)):
                    guard let fromUID = Int64(AppContext.shared.userData.userId) else {
                        DDLogError("ProtoService/iceRestartOfferCall/\(callID)/error invalid sender uid")
                        completion(.failure(.aborted))
                        return
                    }
                    guard let toUID = Int64(peerUserID) else {
                        DDLogError("ProtoService/iceRestartOfferCall/\(callID)/error invalid to uid")
                        completion(.failure(.aborted))
                        return
                    }

                    let msgID = PacketID.generate()
                    var webrtcOffer = Server_WebRtcSessionDescription()
                    webrtcOffer.encPayload = encryptedData.data
                    webrtcOffer.publicKey = encryptedData.identityKey ?? Data()
                    webrtcOffer.oneTimePreKeyID = Int32(encryptedData.oneTimeKeyId)

                    var iceRestartOffer = Server_IceRestartOffer()
                    iceRestartOffer.callID = callID
                    iceRestartOffer.webrtcOffer = webrtcOffer
                    iceRestartOffer.idx = iceIdx

                    var packet = Server_Packet()
                    packet.msg.fromUid = fromUID
                    packet.msg.id = msgID
                    packet.msg.toUid = toUID
                    packet.msg.payload = .iceRestartOffer(iceRestartOffer)

                    guard let packetData = try? packet.serializedData() else {
                        DDLogError("ProtoService/iceRestartOfferCall/\(callID)/error could not serialize packet")
                        return
                    }
                    DDLogInfo("ProtoService/iceRestartOfferCall/\(callID) sending")
                    self.send(packetData)
                    completion(.success(()))
                }
            }
        }
    }

    func answerCall(id callID: CallID, to peerUserID: UserID, payload: Data, completion: @escaping (Result<Void, RequestError>) -> Void) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            AppContext.shared.messageCrypter.encrypt(payload, for: peerUserID) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    DDLogError("ProtoService/startCall/\(callID)/failed encryption: \(peerUserID)/error: \(error)")
                    completion(.failure(.aborted))
                case .success((let encryptedData, _)):
                    guard let fromUID = Int64(AppContext.shared.userData.userId) else {
                        DDLogError("ProtoService/answerCall/\(callID)/error invalid sender uid")
                        completion(.failure(.aborted))
                        return
                    }
                    guard let toUID = Int64(peerUserID) else {
                        DDLogError("ProtoService/answerCall/\(callID)/error invalid to uid")
                        completion(.failure(.aborted))
                        return
                    }

                    let msgID = PacketID.generate()
                    var webrtcAnswer = Server_WebRtcSessionDescription()
                    webrtcAnswer.encPayload = encryptedData.data
                    webrtcAnswer.publicKey = encryptedData.identityKey ?? Data()
                    webrtcAnswer.oneTimePreKeyID = Int32(encryptedData.oneTimeKeyId)

                    var answerCall = Server_AnswerCall()
                    answerCall.callID = callID
                    answerCall.webrtcAnswer = webrtcAnswer
                    var packet = Server_Packet()
                    packet.msg.fromUid = fromUID
                    packet.msg.id = msgID
                    packet.msg.toUid = toUID
                    packet.msg.payload = .answerCall(answerCall)

                    guard let packetData = try? packet.serializedData() else {
                        DDLogError("ProtoService/answerCall/\(callID)/error could not serialize packet")
                        return
                    }
                    DDLogInfo("ProtoService/answerCall/\(callID) sending")
                    self.send(packetData)
                    completion(.success(()))
                }
            }
        }
    }

    func iceRestartAnswerCall(id callID: CallID, to peerUserID: UserID, payload: Data, iceIdx: Int32, completion: @escaping (Result<Void, RequestError>) -> Void) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            AppContext.shared.messageCrypter.encrypt(payload, for: peerUserID) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    DDLogError("ProtoService/iceRestartAnswerCall/\(callID)/failed encryption: \(peerUserID)/error: \(error)")
                    completion(.failure(.aborted))
                case .success((let encryptedData, _)):
                    guard let fromUID = Int64(AppContext.shared.userData.userId) else {
                        DDLogError("ProtoService/iceRestartAnswerCall/\(callID)/error invalid sender uid")
                        completion(.failure(.aborted))
                        return
                    }
                    guard let toUID = Int64(peerUserID) else {
                        DDLogError("ProtoService/iceRestartAnswerCall/\(callID)/error invalid to uid")
                        completion(.failure(.aborted))
                        return
                    }

                    let msgID = PacketID.generate()
                    var webrtcAnswer = Server_WebRtcSessionDescription()
                    webrtcAnswer.encPayload = encryptedData.data
                    webrtcAnswer.publicKey = encryptedData.identityKey ?? Data()
                    webrtcAnswer.oneTimePreKeyID = Int32(encryptedData.oneTimeKeyId)

                    var iceRestartAnswer = Server_IceRestartAnswer()
                    iceRestartAnswer.callID = callID
                    iceRestartAnswer.webrtcAnswer = webrtcAnswer
                    iceRestartAnswer.idx = iceIdx

                    var packet = Server_Packet()
                    packet.msg.fromUid = fromUID
                    packet.msg.id = msgID
                    packet.msg.toUid = toUID
                    packet.msg.payload = .iceRestartAnswer(iceRestartAnswer)

                    guard let packetData = try? packet.serializedData() else {
                        DDLogError("ProtoService/iceRestartAnswerCall/\(callID)/error could not serialize packet")
                        return
                    }
                    DDLogInfo("ProtoService/iceRestartAnswerCall/\(callID) sending")
                    self.send(packetData)
                    completion(.success(()))
                }
            }
        }
    }

    func holdCall(id callID: CallID, to peerUserID: UserID, hold: Bool, completion: @escaping (Result<Void, RequestError>) -> Void) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            guard let fromUID = Int64(AppContext.shared.userData.userId) else {
                DDLogError("ProtoService/holdCall/\(callID)/error invalid sender uid")
                return
            }
            guard let toUID = Int64(peerUserID) else {
                DDLogError("ProtoService/holdCall/\(callID)/error invalid to uid")
                return
            }

            let msgID = PacketID.generate()

            var callHold = Server_HoldCall()
            callHold.callID = callID
            callHold.hold = hold

            var packet = Server_Packet()
            packet.msg.fromUid = fromUID
            packet.msg.id = msgID
            packet.msg.toUid = toUID
            packet.msg.payload = .holdCall(callHold)

            guard let packetData = try? packet.serializedData() else {
                DDLogError("ProtoService/holdCall/\(callID)/error could not serialize packet")
                return
            }

            DDLogInfo("ProtoService/holdCall/\(callID) sending")
            self.send(packetData)
        }
    }

    func muteCall(id callID: CallID, to peerUserID: UserID, muted: Bool, mediaType: Server_MuteCall.MediaType, completion: @escaping (Result<Void, RequestError>) -> Void) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            guard let fromUID = Int64(AppContext.shared.userData.userId) else {
                DDLogError("ProtoService/muteCall/\(callID)/error invalid sender uid")
                return
            }
            guard let toUID = Int64(peerUserID) else {
                DDLogError("ProtoService/muteCall/\(callID)/error invalid to uid")
                return
            }

            let msgID = PacketID.generate()

            var callMute = Server_MuteCall()
            callMute.callID = callID
            callMute.muted = muted
            callMute.mediaType = mediaType

            var packet = Server_Packet()
            packet.msg.fromUid = fromUID
            packet.msg.id = msgID
            packet.msg.toUid = toUID
            packet.msg.payload = .muteCall(callMute)

            guard let packetData = try? packet.serializedData() else {
                DDLogError("ProtoService/muteCall/\(callID)/error could not serialize packet")
                return
            }

            DDLogInfo("ProtoService/muteCall/\(callID) sending")
            self.send(packetData)
        }
    }

    func sendCallRinging(id callID: CallID, to peerUserID: UserID) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            guard let fromUID = Int64(AppContext.shared.userData.userId) else {
                DDLogError("ProtoService/sendCallRinging/\(callID)/error invalid sender uid")
                return
            }
            guard let toUID = Int64(peerUserID) else {
                DDLogError("ProtoService/sendCallRinging/\(callID)/error invalid to uid")
                return
            }

            let msgID = PacketID.generate()

            var callRinging = Server_CallRinging()
            callRinging.callID = callID

            var packet = Server_Packet()
            packet.msg.fromUid = fromUID
            packet.msg.id = msgID
            packet.msg.toUid = toUID
            packet.msg.payload = .callRinging(callRinging)

            guard let packetData = try? packet.serializedData() else {
                DDLogError("ProtoService/sendCallRinging/\(callID)/error could not serialize packet")
                return
            }

            DDLogInfo("ProtoService/sendCallRinging/\(callID) sending")
            self.send(packetData)
        }
    }

    func endCall(id callID: CallID, to peerUserID: UserID, reason: EndCallReason) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            guard let fromUID = Int64(AppContext.shared.userData.userId) else {
                DDLogError("ProtoService/endCall/\(callID)/error invalid sender uid")
                return
            }
            guard let toUID = Int64(peerUserID) else {
                DDLogError("ProtoService/endCall/\(callID)/error invalid to uid")
                return
            }

            let msgID = PacketID.generate()

            var endCall = Server_EndCall()
            endCall.callID = callID
            endCall.reason = reason.serverEndCallReason

            var packet = Server_Packet()
            packet.msg.fromUid = fromUID
            packet.msg.id = msgID
            packet.msg.toUid = toUID
            packet.msg.payload = .endCall(endCall)

            guard let packetData = try? packet.serializedData() else {
                DDLogError("ProtoService/endCall/\(callID)/error could not serialize packet")
                return
            }

            DDLogInfo("ProtoService/endCall/\(callID) sending")
            self.send(packetData)
        }
    }

    func sendIceCandidate(id callID: CallID, to peerUserID: UserID, iceCandidateInfo: IceCandidateInfo) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            guard let fromUID = Int64(AppContext.shared.userData.userId) else {
                DDLogError("ProtoService/sendIceCandidate/\(callID)/error invalid sender uid")
                return
            }
            guard let toUID = Int64(peerUserID) else {
                DDLogError("ProtoService/sendIceCandidate/\(callID)/error invalid to uid")
                return
            }

            let msgID = PacketID.generate()

            var iceCandidate = Server_IceCandidate()
            iceCandidate.callID = callID
            iceCandidate.sdpMediaID = iceCandidateInfo.sdpMid
            iceCandidate.sdpMediaLineIndex = iceCandidateInfo.sdpMLineIndex
            iceCandidate.sdp = iceCandidateInfo.sdpInfo

            var packet = Server_Packet()
            packet.msg.fromUid = fromUID
            packet.msg.id = msgID
            packet.msg.toUid = toUID
            packet.msg.payload = .iceCandidate(iceCandidate)

            guard let packetData = try? packet.serializedData() else {
                DDLogError("ProtoService/sendIceCandidate/\(callID)/error could not serialize packet")
                return
            }

            DDLogInfo("ProtoService/sendIceCandidate/\(callID) sending")
            self.send(packetData)
        }
    }
}

private protocol ReceivedReceipt {
    var id: String { get }
    var threadID: String { get }
    var timestamp: Int64 { get }
    var receiptType: HalloReceipt.`Type` { get }
}

extension Server_DeliveryReceipt: ReceivedReceipt {
    var receiptType: HalloReceipt.`Type` { .delivery }
}

extension Server_SeenReceipt: ReceivedReceipt {
    var receiptType: HalloReceipt.`Type` { .read }
}

extension Server_PlayedReceipt: ReceivedReceipt {
    var receiptType: HalloReceipt.`Type` { .played }
}

extension PresenceType {
    init?(_ pbPresenceType: Server_Presence.TypeEnum) {
        switch pbPresenceType {
        case .away:
            self = .away
        case .available:
            self = .available
        case .subscribe, .unsubscribe:
            DDLogError("proto/presence/error received invalid presence \(pbPresenceType)")
            return nil
        case .UNRECOGNIZED(let i):
            DDLogError("proto/presence/error received unknown presence \(i)")
            return nil
        }
    }
}

enum MessageStatus {
    /// Not yet processed
    case new

    /// Actively being processed (e.g., awaiting or undergoing decryption)
    case active

    /// Already processed (safe to ack immediately without further processing)
    case processed

    /// Awaiting new copy of message
    case rerequested
}
