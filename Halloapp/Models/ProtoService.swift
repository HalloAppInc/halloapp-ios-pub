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
import SwiftProtobuf

fileprivate let userDefaultsKeyForAPNSToken = "apnsPushToken"
fileprivate let userDefaultsKeyForLangID = "langId"
fileprivate let userDefaultsKeyForAPNSSyncTime = "apnsSyncTime"
fileprivate let userDefaultsKeyForNameSync = "xmpp.name-sent"
fileprivate let userDefaultsKeyForSilentRerequestRecords = "silentRerequestRecords"

final class ProtoService: ProtoServiceCore {

    public required init(userData: UserData, passiveMode: Bool = false, automaticallyReconnect: Bool = true) {
        super.init(userData: userData, passiveMode: passiveMode, automaticallyReconnect: automaticallyReconnect)

        self.cancellableSet.insert(
            userData.didLogIn.sink {
                DDLogInfo("proto/userdata/didLogIn")
                self.configureStream(with: self.userData)
                self.connect()
            })
        self.cancellableSet.insert(
            userData.didLogOff.sink {
                DDLogInfo("proto/userdata/didLogOff")
                self.disconnectImmediately() // this is only necessary when manually logging out from a developer menu.
                self.configureStream(with: nil)
            })
    }

    override func performOnConnect() {
        super.performOnConnect()

        // Check on every connection if we have to send the apns token to the server.
        if hasValidAPNSPushToken {
            let token = UserDefaults.standard.string(forKey: userDefaultsKeyForAPNSToken)
            sendAPNSTokenIfNecessary(token)
        }

        resendNameIfNecessary()
        resendAvatarIfNecessary()
        resendAllPendingReceipts()
        resendAllPendingAcks()
        queryAvatarForCurrentUserIfNecessary()
        requestServerPropertiesIfNecessary()
        NotificationSettings.current.sendConfigIfNecessary(using: self)
        MainAppContext.shared.startReportingEvents()
        pruneSilentChatRerequestRecords()
    }

    override func authenticationSucceeded(with authResult: Server_AuthResult) {
        // Update props hash before calling super so it's available for `performOnConnect`
        propsHash = authResult.propsHash.toHexString()

        super.authenticationSucceeded(with: authResult)
    }

    override func authenticationFailed(with authResult: Server_AuthResult) {
        // Clear push token sync time on authentication failure.
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyForAPNSSyncTime)

        super.authenticationFailed(with: authResult)
    }

    private var cancellableSet = Set<AnyCancellable>()

    weak var chatDelegate: HalloChatDelegate?
    weak var feedDelegate: HalloFeedDelegate?

    let didGetNewChatMessage = PassthroughSubject<IncomingChatMessage, Never>()
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

    struct SilentRerequestRecord: Codable {
        var resendCount: Int32
        var lastRerequest: Date
    }

    /// Should only be called on serviceQueue
    private func _loadSilentRerequestRecords() -> [String: SilentRerequestRecord] {
        guard let archive = MainAppContext.shared.userDefaults.data(forKey: userDefaultsKeyForSilentRerequestRecords),
              let records = try? PropertyListDecoder().decode([String: SilentRerequestRecord].self, from: archive) else
        {
            return [:]
        }
        return records
    }

    /// Should only be called on serviceQueue
    private func _saveSilentRerequestRecords(_ records: [String: SilentRerequestRecord]) {
        guard let archive = try? PropertyListEncoder().encode(records) else {
            DDLogError("proto/_saveSilentRerequestRecords/error [encoding]")
            return
        }
        MainAppContext.shared.userDefaults.setValue(archive, forKey: userDefaultsKeyForSilentRerequestRecords)
    }

    private func pruneSilentChatRerequestRecords() {
        serviceQueue.async {
            // Remove records for silent chats that haven't been rerequested for a week
            let allRecords = self._loadSilentRerequestRecords()
            let oneWeek = TimeInterval(60 * 60 * 24 * 7)
            let earliestDateToPreserve = Date().addingTimeInterval(-oneWeek)
            let preservedRecords = allRecords.filter { (k, v) in
                v.lastRerequest > earliestDateToPreserve
            }
            let numberOfRecordsPruned = allRecords.count - preservedRecords.count
            if numberOfRecordsPruned > 0 {
                DDLogInfo("proto/pruneSilentChatRerequestRecords [\(numberOfRecordsPruned)]")
                self._saveSilentRerequestRecords(preservedRecords)
            }
        }
    }

    private func handleSilentChatRerequest(_ id: String) {
        guard var silentChat = SilentChatMessage.fromID(id) else {
            DDLogError("proto/handleSilentChatRerequest/error unable to recreate chat [\(id)]")
            return
        }

        serviceQueue.async {
            var records = self._loadSilentRerequestRecords()

            // Assume this is the first rerequest if no record exists
            let resendCount = records[id]?.resendCount ?? 0

            guard resendCount < 5 else {
                DDLogInfo("proto/handleSilentChatRerequest/\(silentChat.id)/skipping [\(resendCount)]")
                return
            }

            silentChat.rerequestCount = resendCount + 1
            DDLogInfo("proto/handleSilentChatRerequest/\(silentChat.id)/resending [\(silentChat.rerequestCount)]")

            self.sendSilentChatMessage(silentChat) { _ in }

            records[silentChat.id] = SilentRerequestRecord(resendCount: silentChat.rerequestCount, lastRerequest: Date())
            self._saveSilentRerequestRecords(records)
        }
    }

    // MARK: Feed

    private func handleFeedItems(_ items: [Server_FeedItem], isEligibleForNotification: Bool, ack: @escaping () -> Void) {
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
                    if let post = PostData(serverPost) {
                        elements.append(.post(post))
                    }
                case .retract:
                    retracts.append(.post(serverPost.id))
                case .UNRECOGNIZED(let action):
                    DDLogError("ProtoService/handleFeedItems/error unrecognized post action \(action)")
                }
            case .comment(let serverComment):
                switch pbFeedItem.action {
                case .publish, .share:
                    if let comment = CommentData(serverComment) {
                        elements.append(.comment(comment, publisherName: serverComment.publisherName))
                    }
                case .retract:
                    retracts.append(.comment(serverComment.id))
                case .UNRECOGNIZED(let action):
                    DDLogError("ProtoService/handleFeedItems/error unrecognized comment action \(action)")
                }
            case .none:
                DDLogError("ProtoService/handleFeedItems/error missing item")
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

    private func payloadContents(for items: [Server_GroupFeedItem]) -> [HalloServiceFeedPayload.Content] {

        // NB: This function should not assume group fields are populated! [gid, name, avatarID]
        // They aren't included on each child when server sends a `Server_GroupFeedItems` stanza.

        var retracts = [FeedRetract]()
        var elements = [FeedElement]()

        for item in items {
            switch item.item {
            case .post(let serverPost):
                switch item.action {
                case .publish, .share:
                    guard let post = PostData(serverPost) else {
                        DDLogError("proto/payloadContents/\(serverPost.id)/error could not make post object")
                        continue
                    }
                    elements.append(.post(post))
                case .retract:
                    retracts.append(.post(serverPost.id))
                case .UNRECOGNIZED(let action):
                    DDLogError("proto/payloadContents/\(serverPost.id)/error unrecognized post action \(action)")
                }
            case .comment(let serverComment):
                switch item.action {
                case .publish, .share:
                    guard let comment = CommentData(serverComment) else {
                        DDLogError("proto/payloadContents/\(serverComment.id)/error could not make comment object")
                        continue
                    }
                    elements.append(.comment(comment, publisherName: serverComment.publisherName))
                case .retract:
                    retracts.append(.comment(serverComment.id))
                case .UNRECOGNIZED(let action):
                    DDLogError("proto/payloadContents/\(serverComment.id)/error unrecognized comment action \(action)")
                }
            case .none:
                DDLogError("ProtoService/handleFeedItems/error missing item")
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
        if let message = MainAppContext.shared.chatData.chatMessage(with: msgId),
           message.incomingStatus != .rerequesting {
            DDLogInfo("ProtoService/isMessageDecryptedAndSaved/msgId \(msgId) - message is available in local store.")
            return true
        } else if let _ = MainAppContext.shared.shareExtensionDataStore.sharedChatMessage(for: msgId) {
            DDLogInfo("ProtoService/isMessageDecryptedAndSaved/msgId \(msgId) - message needs to be stored from nse.")
            return true
        }
        DDLogInfo("ProtoService/isMessageDecryptedAndSaved/msgId \(msgId) - message is missing.")
        return false
    }

    private func rerequestMessageIfNecessary(_ message: Server_Msg, failedEphemeralKey: Data?) {
        // Dont rerequest messages that were already decrypted and saved.
        if !isMessageDecryptedAndSaved(msgId: message.id) {
            updateStatusAndRerequestMessage(message, failedEphemeralKey: failedEphemeralKey)
        }
    }

    private func updateStatusAndRerequestMessage(_ message: Server_Msg, failedEphemeralKey: Data?) {
        self.updateMessageStatus(id: message.id, status: .rerequested)
        guard let identityKey = AppContext.shared.keyStore.keyBundle()?.identityPublicEdKey else {
            DDLogError("ProtoService/rerequestMessage/\(message.id)/error could not retrieve identity key")
            return
        }

        let fromUserID = UserID(message.fromUid)

        AppContext.shared.messageCrypter.sessionSetupInfoForRerequest(from: fromUserID) { setupInfo in
            let rerequestData = RerequestData(
                identityKey: identityKey,
                signedPreKeyID: 0,
                oneTimePreKeyID: setupInfo?.1,
                sessionSetupEphemeralKey: setupInfo?.0 ?? Data(),
                messageEphemeralKey: failedEphemeralKey)

            DDLogInfo("ProtoService/rerequestMessage/\(message.id) rerequesting")
            self.rerequestMessage(message.id, senderID: fromUserID, rerequestData: rerequestData) { _ in }
        }
    }

    override func didReceive(packet: Server_Packet, requestID: String) {
        super.didReceive(packet: packet, requestID: requestID)

        switch packet.stanza {
        case .ack(let ack):
            let timestamp = Date(timeIntervalSince1970: TimeInterval(ack.timestamp))
            handlePossibleReceiptAck(id: ack.id) { wasReceiptFound in
                guard !wasReceiptFound else {
                    // Ack has been handled, no need to proceed further
                    return
                }
                if SilentChatMessage.isSilentChatID(ack.id) {
                    // No need to update chat data for silent messages
                    DDLogInfo("proto/didReceive/silentAck \(ack.id)")
                } else {
                    // Not a receipt or silent ack, must be a chat ack
                    self.didGetChatAck.send((id: ack.id, timestamp: timestamp))
                }
            }
        case .msg(let msg):
            handleMessage(msg, isEligibleForNotification: msg.retryCount == 0)
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
        guard !userData.name.isEmpty else { return }

        enqueue(request: ProtoSendNameRequest(name: userData.name) { result in
            if case .success = result {
                UserDefaults.standard.set(true, forKey: userDefaultsKeyForNameSync)
            }
        })
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
        case .avatar(let pbAvatar):
            avatarDelegate?.service(self, didReceiveAvatarInfo: (userID: UserID(pbAvatar.uid), avatarID: pbAvatar.id))
        case .whisperKeys(let pbKeys):
            if let whisperMessage = WhisperMessage(pbKeys) {
                keyDelegate?.service(self, didReceiveWhisperMessage: whisperMessage)
            } else {
                DDLogError("proto/didReceive/\(msg.id)/error could not read whisper message")
            }
        case .seenReceipt(let pbReceipt):
            handleReceivedReceipt(receipt: pbReceipt, from: UserID(msg.fromUid), messageID: msg.id, ack: ack)
            hasAckBeenDelegated = true
        case .deliveryReceipt(let pbReceipt):
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
            decryptChat(serverChat, from: UserID(msg.fromUid)) { (clientChat, decryptionFailure) in
                if let clientChat = clientChat {
                    let chatMessage = XMPPChatMessage(clientChat, timestamp: serverChat.timestamp, from: UserID(msg.fromUid), to: UserID(msg.toUid), id: msg.id, retryCount: msg.retryCount, rerequestCount: msg.rerequestCount)
                    DDLogInfo("proto/didReceive/\(msg.id)/chat/user/\(chatMessage.fromUserId) [length=\(chatMessage.text?.count ?? 0)] [media=\(chatMessage.media.count)]")
                    self.didGetNewChatMessage.send(.decrypted(chatMessage))
                } else {
                    self.didGetNewChatMessage.send(
                        .notDecrypted(
                            ChatMessageTombstone(
                                id: msg.id,
                                from: UserID(msg.fromUid),
                                to: UserID(msg.toUid),
                                timestamp: Date()
                            )))
                }
                if let failure = decryptionFailure {
                    DDLogError("proto/didReceive/\(msg.id)/decrypt/error \(failure.error)")
                    AppContext.shared.errorLogger?.logError(failure.error)
                    self.rerequestMessageIfNecessary(msg, failedEphemeralKey: failure.ephemeralKey)
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
            decryptChat(silent.chatStanza, from: UserID(msg.fromUid)) { (_, decryptionFailure) in
                if let failure = decryptionFailure {
                    DDLogError("proto/didReceive/\(msg.id)/silent-decrypt/error \(failure.error)")
                    AppContext.shared.errorLogger?.logError(failure.error)
                    self.updateStatusAndRerequestMessage(msg, failedEphemeralKey: failure.ephemeralKey)
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
            if SilentChatMessage.isSilentChatID(rerequest.id) {
                self.handleSilentChatRerequest(rerequest.id)
            } else {
                DDLogInfo("proto/didReceive/\(msg.id)/rerequest/chat")
                if let delegate = chatDelegate {
                    delegate.halloService(self, didRerequestMessage: rerequest.id, from: userID, ack: ack)
                    hasAckBeenDelegated = true
                }
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
            handleFeedItems([pbFeedItem], isEligibleForNotification: isEligibleForNotification, ack: ack)
            hasAckBeenDelegated = true
        case .feedItems(let pbFeedItems):
            handleFeedItems(pbFeedItems.items, isEligibleForNotification: isEligibleForNotification, ack: ack)
            hasAckBeenDelegated = true
        case .groupFeedItem(let item):
            guard let delegate = feedDelegate else {
                break
            }
            let group = HalloGroup(id: item.gid, name: item.name, avatarID: item.avatarID)
            for content in payloadContents(for: [item]) {
                let payload = HalloServiceFeedPayload(content: content, group: group, isEligibleForNotification: isEligibleForNotification)
                delegate.halloService(self, didReceiveFeedPayload: payload, ack: ack)
                hasAckBeenDelegated = true
            }
        case .groupFeedItems(let items):
            guard let delegate = feedDelegate else {
                break
            }
            let group = HalloGroup(id: items.gid, name: items.name, avatarID: items.avatarID)
            for content in payloadContents(for: items.items) {
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
                chatDelegate?.halloService(self, didReceiveGroupMessage: group)
            } else {
                DDLogError("proto/didReceive/\(msg.id)/error could not read group stanza")
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
        case .endOfQueue:
            DDLogInfo("proto/didReceive/\(msg.id)/endOfQueue")
        case .errorStanza(let error):
            DDLogError("proto/didReceive/\(msg.id) received message with error \(error)")
        case .inviteeNotice, .groupFeedRerequest, .historyResend:
            DDLogError("proto/didReceive/\(msg.id)/error unsupported-payload [\(payload)]")
        }
    }

    // MARK: Avatar

    private func queryAvatarForCurrentUserIfNecessary() {
        guard !UserDefaults.standard.bool(forKey: AvatarStore.Keys.userDefaultsDownload) else { return }

        DDLogInfo("proto/queryAvatarForCurrentUserIfNecessary start")

        let request = ProtoAvatarRequest(userID: userData.userId) { result in
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

        let userAvatar = MainAppContext.shared.avatarStore.userAvatar(forUserId: self.userData.userId)
        guard userAvatar.isEmpty || userAvatar.data != nil else {
            DDLogError("ProtoService/resendAvatarIfNecessary/upload/error avatar data is not ready")
            return
        }

        let logAction = userAvatar.isEmpty ? "removed" : "uploaded"
        enqueue(request: ProtoUpdateAvatarRequest(data: userAvatar.data) { result in
            switch result {
            case .success(let avatarID):
                DDLogInfo("ProtoService/resendAvatarIfNecessary avatar has been \(logAction)")
                UserDefaults.standard.set(false, forKey: AvatarStore.Keys.userDefaultsUpload)

                if let avatarID = avatarID {
                    DDLogInfo("ProtoService/resendAvatarIfNecessary received new avatarID [\(avatarID)]")
                    MainAppContext.shared.avatarStore.update(avatarId: avatarID, forUserId: self.userData.userId)
                }

            case .failure(let error):
                DDLogError("ProtoService/resendAvatarIfNecessary/error avatar not \(logAction): \(error)")
            }
        })
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

        let notification = UNMutableNotificationContent()
        notification.populate(from: metadata, contactStore: MainAppContext.shared.contactStore)
        notifications.append(notification)

        let notificationCenter = UNUserNotificationCenter.current()
        notifications.forEach { (notificationContent) in
            notificationCenter.add(UNNotificationRequest(identifier: UUID().uuidString, content: notificationContent, trigger: nil))
        }
    }
}

extension ProtoService: HalloService {

    func sendCurrentUserNameIfPossible() {
        UserDefaults.standard.set(false, forKey: userDefaultsKeyForNameSync)

        if isConnected {
            resendNameIfNecessary()
        }
    }

    func sendCurrentAvatarIfPossible() {
        UserDefaults.standard.set(true, forKey: AvatarStore.Keys.userDefaultsUpload)

        if isConnected {
            resendAvatarIfNecessary()
        }
    }

    func retractComment(id: FeedPostCommentID, postID: FeedPostID, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoRetractCommentRequest(id: id, postID: postID, completion: completion))
    }

    func retractPost(_ post: FeedPostProtocol, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoRetractPostRequest(id: post.id, completion: completion))
    }

    func sharePosts(postIds: [FeedPostID], with userId: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoSharePostsRequest(postIDs: postIds, userID: userId, completion: completion))
    }

    func sendReceipt(itemID: String, thread: HalloReceipt.Thread, type: HalloReceipt.`Type`, fromUserID: UserID, toUserID: UserID) {
        let receipt = HalloReceipt(itemId: itemID, userId: fromUserID, type: type, timestamp: nil, thread: thread)
        sendReceipt(receipt, to: toUserID)
    }

    func retractChatMessage(messageID: String, toUserID: UserID, messageToRetractID: String) {
        guard let toUID = Int64(toUserID) else {
            return
        }
        guard let fromUID = Int64(userData.userId) else {
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
    
    func sendPresenceIfPossible(_ presenceType: PresenceType) {
        guard isConnected else { return }
        
        var presence = Server_Presence()
        presence.id = PacketID.generate(short: true)
        presence.type = {
            switch presenceType {
            case .away:
                return .away
            case .available:
                return .available
            }
        }()
        if let uid = Int64(AppContext.shared.userData.userId) {
            presence.toUid = uid
        }

        var packet = Server_Packet()
        packet.presence = presence

        guard let packetData = try? packet.serializedData() else {
            DDLogError("ProtoService/sendPresenceIfPossible/error could not serialize")
            return
        }
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

    func sendAPNSTokenIfNecessary(_ token: String?) {
        let langID = Locale.current.halloServiceLangID
        let hasSyncTokenChanged = token != UserDefaults.standard.string(forKey: userDefaultsKeyForAPNSToken)
        let hasLangIDChanged = langID != UserDefaults.standard.string(forKey: userDefaultsKeyForLangID)
        let savedAPNSSyncTime = UserDefaults.standard.object(forKey: userDefaultsKeyForAPNSSyncTime) as? Date
        let isSyncScheduled = Date() > (savedAPNSSyncTime ?? Date.distantPast)

        // Sync push token and langID whenever they change or every 24hrs.
        if (hasSyncTokenChanged || hasLangIDChanged || isSyncScheduled), let token = token {
            execute(whenConnectionStateIs: .connected, onQueue: .main) {
                self.enqueue(request: ProtoPushTokenRequest(token: token, langID: langID) { result in
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



    func updateNotificationSettings(_ settings: [NotificationSettings.ConfigKey : Bool], completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoUpdateNotificationSettingsRequest(settings: settings, completion: completion))
    }

    func getServerProperties(completion: @escaping ServiceRequestCompletion<ServerPropertiesResponse>) {
        enqueue(request: ProtoGetServerPropertiesRequest(completion: completion))
    }
    
    func exportDataStatus(isSetRequest: Bool = false, completion: @escaping ServiceRequestCompletion<Server_ExportData>) {
        enqueue(request: ProtoGetDataExportStatusRequest(isSetRequest: isSetRequest, completion: completion))
    }

    func sendGroupChatMessage(_ message: HalloGroupChatMessage) {
        guard let messageData = try? message.protoContainer.serializedData() else {
            DDLogError("ProtoService/sendGroupChatMessage/\(message.id)/error could not serialize message data")
            return
        }
         guard let fromUID = Int64(userData.userId) else {
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
        sendSilentChats(ServerProperties.silentChatMessages)
    }

    func retractGroupChatMessage(messageID: String, groupID: GroupID, messageToRetractID: String) {
        guard let fromUID = Int64(userData.userId) else {
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
    
    func modifyGroup(groupID: GroupID, with members: [UserID], groupAction: ChatGroupAction,
                     action: ChatGroupMemberAction, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoGroupModifyRequest(
            groupID: groupID,
            members: members,
            groupAction: groupAction,
            action: action,
            completion: completion))
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
