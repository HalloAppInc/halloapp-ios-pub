//
//  ProtoService.swift
//  HalloApp
//
//  Created by Garrett on 8/27/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import SwiftProtobuf
import XMPPFramework

fileprivate let userDefaultsKeyForAPNSToken = "apnsPushToken"
fileprivate let userDefaultsKeyForNameSync = "xmpp.name-sent"

enum ProtoServiceError: Error {
    case unexpectedResponseFormat
}

final class ProtoService: ProtoServiceCore {

    public required init(userData: UserData) {
        super.init(userData: userData)

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

        if hasValidAPNSPushToken {
            sendCurrentAPNSTokenIfPossible()
        }

        resendNameIfNecessary()
        resendAvatarIfNecessary()
        resendAllPendingReceipts()
        queryAvatarForCurrentUserIfNecessary()
        requestServerPropertiesIfNecessary()
        NotificationSettings.current.sendConfigIfNecessary(using: self)
        MainAppContext.shared.startReportingEvents()
        userData.migratePasswordToKeychain()
    }

    override func authenticationSucceeded(with authResult: Server_AuthResult) {
        // Update props hash before calling super so it's available for `performOnConnect`
        propsHash = authResult.propsHash.toHexString()

        super.authenticationSucceeded(with: authResult)
    }

    private var cancellableSet = Set<AnyCancellable>()

    weak var chatDelegate: HalloChatDelegate?
    weak var feedDelegate: HalloFeedDelegate?
    weak var keyDelegate: HalloKeyDelegate?

    let didGetNewChatMessage = PassthroughSubject<ChatMessageProtocol, Never>()
    let didGetChatAck = PassthroughSubject<ChatAck, Never>()
    let didGetPresence = PassthroughSubject<ChatPresenceInfo, Never>()
    let didGetChatState = PassthroughSubject<ChatStateInfo, Never>()
    let didGetChatRetract = PassthroughSubject<ChatRetractInfo, Never>()

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
    private let receiptsQueue = DispatchQueue(label: "com.halloapp.proto.receipts", qos: .default)

    /// Maps message ID of outgoing receipts to receipt data in case we need to resend. Should only be accessed on receiptsQueue.
    private var unackedReceipts: [ String : ReceiptData ] = [:]

    private func resendAllPendingReceipts() {
        receiptsQueue.async {
            for (messageID, receiptData) in self.unackedReceipts {
                self._sendReceipt(receiptData.receipt, to: receiptData.userID, messageID: messageID)
            }
        }
    }

    private func sendReceipt(_ receipt: HalloReceipt, to toUserID: UserID, messageID: String = UUID().uuidString) {
        receiptsQueue.async {
            self._sendReceipt(receipt, to: toUserID, messageID: messageID)
        }
    }

    /// Handles ack if it corresponds to an unacked receipt. Calls completion block on main thread.
    private func handlePossibleReceiptAck(id: String, didFindReceipt: @escaping (Bool) -> Void) {
        receiptsQueue.async {
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

    /// Should only be called on receiptsQueue.
    private func _sendReceipt(_ receipt: HalloReceipt, to toUserID: UserID, messageID: String = UUID().uuidString) {
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
        var ack = Server_Ack()
        ack.id = messageID
        var packet = Server_Packet()
        packet.stanza = .ack(ack)
        if let data = try? packet.serializedData(), isConnected {
            DDLogInfo("ProtoService/sendAck/\(messageID)/sending")
            send(data)
        } else {
            DDLogInfo("ProtoService/sendAck/\(messageID)/skipping (disconnected)")
        }
    }

    private func handleReceivedReceipt(receipt: ReceivedReceipt, from: UserID, messageID: String) {
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
            delegate.halloService(self, didReceiveFeedReceipt: receipt, ack: { self.sendAck(messageID: messageID) })
        } else if thread != .feed, let delegate = chatDelegate {
            delegate.halloService(self, didReceiveMessageReceipt: receipt, ack: { self.sendAck(messageID: messageID) })
        } else {
            sendAck(messageID: messageID)
        }
    }

    private func handleFeedItems(_ items: [Server_FeedItem], message: Server_Msg) {
        let messageID = message.id

        guard let delegate = feedDelegate else {
            sendAck(messageID: messageID)
            return
        }
        var elements = [FeedElement]()
        var retracts = [FeedRetract]()
        items.forEach { pbFeedItem in
            switch pbFeedItem.item {
            case .post(let serverPost):
                switch pbFeedItem.action {
                case .publish, .share:
                    if let post = XMPPFeedPost(serverPost) {
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
                    if let comment = XMPPComment(serverComment) {
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
            let payload = HalloServiceFeedPayload(content: .newItems(elements), group: nil, isPushSent: message.retryCount > 0)
            delegate.halloService(self, didReceiveFeedPayload: payload, ack: { self.sendAck(messageID: messageID) })
        }
        if !retracts.isEmpty {
            let payload = HalloServiceFeedPayload(content: .retracts(retracts), group: nil, isPushSent: message.retryCount > 0)
            delegate.halloService(self, didReceiveFeedPayload: payload, ack: { self.sendAck(messageID: messageID) })
        }
        if elements.isEmpty && retracts.isEmpty {
            sendAck(messageID: messageID)
        }
    }

    private func handleGroupFeedItem(_ item: Server_GroupFeedItem, message: Server_Msg) {
        let messageID = message.id

        guard let delegate = feedDelegate else {
            sendAck(messageID: messageID)
            return
        }
        var group = HalloGroup(id: item.gid, name: item.name)
        group.avatarID = item.avatarID

        var element: FeedElement?
        var retract: FeedRetract?
        switch item.item {
        case .post(let pbPost):
            switch item.action {
            case .publish:
                if let post = XMPPFeedPost(pbPost) {
                    element = .post(post)
                }
            case .retract:
                retract = .post(pbPost.id)
            case .UNRECOGNIZED(let action):
                    DDLogError("ProtoService/handleFeedItems/error unrecognized post action \(action)")
            }
        case .comment(let pbComment):
            switch item.action {
            case .publish:
                if let comment = XMPPComment(pbComment) {
                    element = .comment(comment, publisherName: pbComment.publisherName)
                }
            case .retract:
                retract = .comment(pbComment.id)
            case .UNRECOGNIZED(let action):
                DDLogError("ProtoService/handleFeedItems/error unrecognized comment action \(action)")
            }
        case .none:
            DDLogError("ProtoService/handleFeedItems/error missing item")
        }
        if let element = element {
            let payload = HalloServiceFeedPayload(content: .newItems([ element ]), group: group, isPushSent: message.retryCount > 0)
            delegate.halloService(self, didReceiveFeedPayload: payload, ack: { self.sendAck(messageID: messageID) })
        }
        else if let retract = retract {
            let payload = HalloServiceFeedPayload(content: .retracts([ retract ]), group: group, isPushSent: message.retryCount > 0)
            delegate.halloService(self, didReceiveFeedPayload: payload, ack: { self.sendAck(messageID: messageID) })
        }
        else {
            sendAck(messageID: messageID)
        }
    }

    private func rerequestMessage(_ message: Server_Msg) {
        let keyStore = AppContext.shared.keyStore
        keyStore.performSeriallyOnBackgroundContext { context in
            guard let identityKey = keyStore.keyBundle(in: context)?.identityPublicEdKey else {
                DDLogError("ProtoService/rerequestMessage/\(message.id)/error could not retrieve identity key")
                return
            }
            DDLogInfo("ProtoService/rerequestMessage/\(message.id) rerequesting")
            self.rerequestMessage(message.id, senderID: UserID(message.fromUid), identityKey: identityKey) { _ in }
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
                if SilentChatMessage.forRerequest(incomingID: ack.id) != nil {
                    // No need to update chat data for silent messages
                    DDLogInfo("proto/didReceive/silentAck \(ack.id)")
                } else {
                    // Not a receipt or silent ack, must be a chat ack
                    self.didGetChatAck.send((id: ack.id, timestamp: timestamp))
                }
            }
        case .msg(let msg):
            guard let payload = msg.payload else {
                DDLogError("proto/didReceive/\(requestID)/error missing payload")
                break
            }
            switch payload {
            case .contactList(let pbContactList):
                let contacts = pbContactList.contacts.compactMap { HalloContact($0) }
                MainAppContext.shared.syncManager.processNotification(contacts: contacts) {
                    self.sendAck(messageID: msg.id)
                }
            case .avatar(let pbAvatar):
                avatarDelegate?.service(self, didReceiveAvatarInfo: (userID: UserID(pbAvatar.uid), avatarID: pbAvatar.id))
                sendAck(messageID: msg.id)
            case .whisperKeys(let pbKeys):
                if let whisperMessage = WhisperMessage(pbKeys) {
                    keyDelegate?.halloService(self, didReceiveWhisperMessage: whisperMessage)
                } else {
                    DDLogError("ProtoService/didReceive/\(requestID)/error could not read whisper message")
                }
                self.sendAck(messageID: msg.id)
            case .seenReceipt(let pbReceipt):
                handleReceivedReceipt(receipt: pbReceipt, from: UserID(msg.fromUid), messageID: msg.id)
            case .deliveryReceipt(let pbReceipt):
                handleReceivedReceipt(receipt: pbReceipt, from: UserID(msg.fromUid), messageID: msg.id)
            case .chatStanza(let serverChat):
                decryptChat(serverChat, from: UserID(msg.fromUid)) { (clientChat, decryptionError) in
                    if let clientChat = clientChat {
                        let chatMessage = XMPPChatMessage(clientChat, timestamp: serverChat.timestamp, from: UserID(msg.fromUid), to: UserID(msg.toUid), id: msg.id, retryCount: msg.retryCount)
                        DDLogInfo("proto/didReceive/\(requestID)/chat/user/\(chatMessage.fromUserId) [length=\(chatMessage.text?.count ?? 0)] [media=\(chatMessage.media.count)]")
                        self.didGetNewChatMessage.send(chatMessage)
                    }
                    if let error = decryptionError {
                        DDLogError("ProtoService/didReceive/\(requestID)/decrypt/error \(error)")
                        AppContext.shared.errorLogger?.logError(error)
                        self.rerequestMessage(msg)
                    }
                    AppContext.shared.eventMonitor.observe(.decryption(error: decryptionError))
                    self.sendAck(messageID: msg.id)
                }
            case .silentChatStanza(let silent):
                // We ignore message content from silent messages (only interested in decryption success)
                decryptChat(silent.chatStanza, from: UserID(msg.fromUid)) { (_, decryptionError) in
                    if let error = decryptionError {
                        DDLogError("ProtoService/didReceive/\(requestID)/decrypt-silent/error \(error)")
                        AppContext.shared.errorLogger?.logError(error)
                        self.rerequestMessage(msg)
                    }
                    AppContext.shared.eventMonitor.observe(.decryption(error: decryptionError))
                    self.sendAck(messageID: msg.id)
                }
            case .rerequest(let rerequest):
                if let delegate = chatDelegate {
                    let keyStore = AppContext.shared.keyStore
                    let userID = UserID(msg.fromUid)
                    keyStore.performSeriallyOnBackgroundContext { context in
                        let needsNewIdentityKey: Bool = {
                            guard let savedKey = keyStore.messageKeyBundle(for: userID)?.inboundIdentityPublicEdKey else {
                                DDLogInfo("proto/rerequest/user/\(userID) no saved key")
                                return true
                            }
                            return savedKey != rerequest.identityKey
                        }()
                        if needsNewIdentityKey {
                            DDLogInfo("proto/rerequest/user/\(userID) refreshing keys")
                            keyStore.deleteMessageKeyBundles(for: userID)
                        }
                        DispatchQueue.main.async {
                            if let silentChat = SilentChatMessage.forRerequest(incomingID: rerequest.id) {
                                if silentChat.rerequestCount < 5 {
                                    DDLogInfo("Proto/didReceive/rerequest/silent/\(silentChat.id) resending")
                                    self.sendSilentChatMessage(silentChat, encryption: AppContext.shared.encryptOperation(for: silentChat.toUserId)) { _ in }
                                } else {
                                    DDLogInfo("Proto/didReceive/rerequest/silent/\(silentChat.id) skipping (\(silentChat.rerequestCount) resends)")
                                }
                                self.sendAck(messageID: msg.id)
                            } else {
                                DDLogInfo("Proto/didReceive/\(requestID)/rerequest/chat")
                                delegate.halloService(self, didRerequestMessage: rerequest.id, from: userID) {
                                    self.sendAck(messageID: msg.id)
                                }
                            }
                        }
                    }
                } else {
                    sendAck(messageID: msg.id)
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
                self.sendAck(messageID: msg.id)
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
                self.sendAck(messageID: msg.id)
            case .feedItem(let pbFeedItem):
                handleFeedItems([pbFeedItem], message: msg)
            case .feedItems(let pbFeedItems):
                handleFeedItems(pbFeedItems.items, message: msg)
            case .groupFeedItem(let pbGroupFeedItem):
                handleGroupFeedItem(pbGroupFeedItem, message: msg)
            case .groupFeedItems(_):
                DDLogError("proto/didReceive/\(requestID)/groupFeedItems/error unimplemented")
                sendAck(messageID: msg.id)
            case .contactHash(let pbContactHash):
                if pbContactHash.hash.isEmpty {
                    // Trigger full sync
                    MainAppContext.shared.syncManager.requestFullSync()
                    sendAck(messageID: msg.id)
                } else if let decodedData = Data(base64Encoded: pbContactHash.hash) {
                    // Legacy Base64 protocol
                    MainAppContext.shared.syncManager.processNotification(contactHashes: [decodedData]) {
                        self.sendAck(messageID: msg.id)
                    }
                } else {
                    // Binary protocol
                    MainAppContext.shared.syncManager.processNotification(contactHashes: [pbContactHash.hash]) {
                        self.sendAck(messageID: msg.id)
                    }
                }
            case .groupStanza(let pbGroup):
                if let group = HalloGroup(protoGroup: pbGroup, msgId: msg.id) {
                    chatDelegate?.halloService(self, didReceiveGroupMessage: group)
                } else {
                    DDLogError("ProtoService/didReceive/\(requestID)/error could not read group stanza")
                }
                sendAck(messageID: msg.id)
            case .groupChat(let pbGroupChat):
                if let groupChatMessage = HalloGroupChatMessage(pbGroupChat, id: msg.id, retryCount: msg.retryCount) {
                    chatDelegate?.halloService(self, didReceiveGroupChatMessage: groupChatMessage)
                } else {
                    DDLogError("ProtoService/didReceive/\(requestID)/error could not read group chat message")
                }
                sendAck(messageID: msg.id)
            case .name(let pbName):
                if !pbName.name.isEmpty {
                    // TODO: Is this necessary? Should we clear push name if name is empty?
                    MainAppContext.shared.contactStore.addPushNames([ UserID(pbName.uid): pbName.name ])
                }
                sendAck(messageID: msg.id)
            case .errorStanza(let error):
                DDLogError("proto/didReceive/\(requestID) received message with error \(error)")
            }
        case .haError(let error):
            DDLogError("proto/didReceive/\(requestID) received packet with error \(error)")
        case .presence(let pbPresence):
            DDLogInfo("proto/presence/received [\(pbPresence.uid)] [\(pbPresence.type)]")
            // Dispatch to main thread because ChatViewController updates UI in response
            DispatchQueue.main.async {
                self.didGetPresence.send(
                    (userID: UserID(pbPresence.uid),
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

    // MARK: Decryption

    /// May return a valid message with an error (i.e., there may be plaintext to fall back to even if decryption fails).
    private func decryptChat(_ serverChat: Server_ChatStanza, from fromUserID: UserID, completion: @escaping (Clients_ChatMessage?, DecryptionError?) -> Void) {
        let plainTextMessage = Clients_ChatMessage(containerData: serverChat.payload)
        AppContext.shared.keyStore.decryptPayload(
            for: fromUserID,
            encryptedPayload: serverChat.encPayload,
            publicKey: serverChat.publicKey,
            oneTimeKeyID: Int(serverChat.oneTimePreKeyID)) { result in
            switch result {
            case .success(let decryptedData):
                guard let decryptedMessage = Clients_ChatMessage(containerData: decryptedData) else {
                    // Decryption deserialization failed, fall back to plaintext if possible
                    completion(plainTextMessage, .deserialization)
                    return
                }
                if let plainTextMessage = plainTextMessage, plainTextMessage.text != decryptedMessage.text {
                    // Decrypted message does not match plaintext
                    completion(plainTextMessage, .plaintextMismatch)
                } else {
                    if plainTextMessage == nil {
                        DDLogInfo("proto/decryptChat/plaintext not available")
                    }
                    completion(decryptedMessage, nil)
                }
            case .failure(let error):
                completion(plainTextMessage, error)
            }
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

    func retractFeedItem(_ feedItem: FeedItemProtocol, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoRetractItemRequest(feedItem: feedItem, completion: completion))
    }

    func sharePosts(postIds: [FeedPostID], with userId: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoSharePostsRequest(postIDs: postIds, userID: userId, completion: completion))
    }

    func uploadWhisperKeyBundle(_ bundle: WhisperKeyBundle, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoWhisperUploadRequest(keyBundle: bundle, completion: completion))
    }

    func requestAddOneTimeKeys(_ bundle: WhisperKeyBundle, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoWhisperAddOneTimeKeysRequest(whisperKeyBundle: bundle, completion: completion))
    }

    func requestCountOfOneTimeKeys(completion: @escaping ServiceRequestCompletion<Int32>) {
        enqueue(request: ProtoWhisperGetCountOfOneTimeKeysRequest(completion: completion))
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
        presence.id = Utils().randomString(10)
        presence.type = {
            switch presenceType {
            case .away:
                return .away
            case .available:
                return .available
            }
        }()
        if let uid = Int64(AppContext.shared.userData.userId) {
            presence.uid = uid
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
        presence.id = Utils().randomString(10)
        presence.type = .subscribe
        if let uid = Int64(userID) {
            presence.uid = uid
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

    func setAPNSToken(_ token: String?) {
        if let token = token {
            UserDefaults.standard.set(token, forKey: userDefaultsKeyForAPNSToken)
        } else {
            UserDefaults.standard.removeObject(forKey: userDefaultsKeyForAPNSToken)
        }
    }

    func sendCurrentAPNSTokenIfPossible() {
        if isConnected, let token = UserDefaults.standard.string(forKey: userDefaultsKeyForAPNSToken) {
            let request = ProtoPushTokenRequest(token: token) { (error) in
                DDLogInfo("proto/push-token/sent")
            }
            enqueue(request: request)
        } else {
            DDLogInfo("proto/push-token/could-not-send")
        }
    }

    func updateNotificationSettings(_ settings: [NotificationSettings.ConfigKey : Bool], completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoUpdateNotificationSettingsRequest(settings: settings, completion: completion))
    }

    func checkVersionExpiration(completion: @escaping ServiceRequestCompletion<TimeInterval>) {
        enqueue(request: ProtoClientVersionCheck(version: AppContext.appVersionForService, completion: completion))
    }

    func getServerProperties(completion: @escaping ServiceRequestCompletion<ServerPropertiesResponse>) {
        enqueue(request: ProtoGetServerPropertiesRequest(completion: completion))
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

    func changeGroupAvatar(groupID: GroupID, data: Data, completion: @escaping ServiceRequestCompletion<String>) {
        enqueue(request: ProtoChangeGroupAvatarRequest(
            groupID: groupID,
            data: data,
            completion: completion))
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
