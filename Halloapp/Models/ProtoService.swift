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
    case unimplemented
    case unexpectedResponseFormat
}

final class ProtoService: ProtoServiceCore {

    public required init(userData: UserData) {
        super.init(userData: userData)

        self.cancellableSet.insert(
            userData.didLogIn.sink {
                DDLogInfo("xmpp/userdata/didLogIn")
                self.stream.myJID = self.userData.userJID
                self.connect()
            })
        self.cancellableSet.insert(
            userData.didLogOff.sink {
                DDLogInfo("xmpp/userdata/didLogOff")
                self.stream.disconnect() // this is only necessary when manually logging out from a developer menu.
                self.stream.myJID = nil
            })
    }

    private var cancellableSet = Set<AnyCancellable>()

    weak var chatDelegate: HalloChatDelegate?
    weak var feedDelegate: HalloFeedDelegate?
    weak var keyDelegate: HalloKeyDelegate?

    let didGetNewChatMessage = PassthroughSubject<ChatMessageProtocol, Never>()
    let didGetChatAck = PassthroughSubject<ChatAck, Never>()
    let didGetPresence = PassthroughSubject<ChatPresenceInfo, Never>()

    // MARK: Server Properties

    private func requestServerPropertiesIfNecessary() {
        // TODO: Only check when necessary (requires setting serverPropertiesVersion in handleAuth)
        //guard ServerProperties.shouldQuery(forVersion: stream.serverPropertiesVersion) else {
        //    return
        //}
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

    typealias ReceiptData = (HalloReceipt, UserID)
    private var sentReceipts: [ String : HalloReceipt ] = [:] // Key is message's id - it would be the same as "id" in ack.
    private var unackedReceipts: [ String : ReceiptData ] = [:]

    private func sendAck(messageID: String) {
        var ack = PBha_ack()
        ack.id = messageID
        var packet = PBpacket()
        packet.stanza = .ack(ack)
        if let data = try? packet.serializedData() {
            stream.send(data)
        }
    }

    private func handleChatReceipt(receipt: ReceivedReceipt, from: UserID, messageID: String) {
        let ts = TimeInterval(receipt.timestamp)
        let receipt = HalloReceipt(
            itemId: receipt.id,
            userId: from,
            type: receipt.receiptType,
            timestamp: Date(timeIntervalSince1970: ts),
            thread: receipt.threadID.isEmpty ? .none : .group(receipt.threadID))
        if let delegate = chatDelegate {
            delegate.halloService(self, didReceiveMessageReceipt: receipt, ack: { self.sendAck(messageID: messageID) })
        } else {
            sendAck(messageID: messageID)
        }
    }

    private func handleFeedItems(_ items: [PBfeed_item], messageID: String) {
        guard let delegate = feedDelegate else {
            sendAck(messageID: messageID)
            return
        }
        var elements = [FeedElement]()
        var retracts = [FeedRetract]()
        items.forEach { pbFeedItem in
            switch pbFeedItem.item {
            case .post(let pbPost):
                switch pbFeedItem.action {
                case .publish, .share:
                    guard let post = XMPPFeedPost(pbPost) else { return }
                    elements.append(.post(post))
                case .retract:
                    retracts.append(.post(pbPost.id))
                case .UNRECOGNIZED(let action):
                        DDLogError("ProtoService/handleFeedItems/error unrecognized post action \(action)")
                }
            case .comment(let pbComment):
                switch pbFeedItem.action {
                case .publish, .share:
                    guard let comment = XMPPComment(pbComment) else { return }
                    elements.append(.comment(comment, publisherName: pbComment.publisherName))
                case .retract:
                    retracts.append(.comment(pbComment.id))
                case .UNRECOGNIZED(let action):
                    DDLogError("ProtoService/handleFeedItems/error unrecognized comment action \(action)")
                }
            case .none:
                DDLogError("ProtoService/handleFeedItems/error missing item")
            }
        }
        if !elements.isEmpty {
            delegate.halloService(self, didReceiveFeedItems: elements, ack: { self.sendAck(messageID: messageID) })
        }
        if !retracts.isEmpty {
            delegate.halloService(self, didReceiveFeedRetracts: retracts, ack: { self.sendAck(messageID: messageID) })
        }
        if elements.isEmpty && retracts.isEmpty {
            sendAck(messageID: messageID)
        }
    }

    override func didReceive(packet: PBpacket, requestID: String) {
        super.didReceive(packet: packet, requestID: requestID)

        switch packet.stanza {
        case .ack(let ack):
            let timestamp = Date(timeIntervalSince1970: TimeInterval(ack.timestamp))
            if let receipt = sentReceipts[ack.id] {
                switch receipt.thread {
                case .feed:
                    if let delegate = feedDelegate {
                        delegate.halloService(self, didReceiveFeedReceipt: receipt, ack: { self.sendAck(messageID: ack.id) })
                    } else {
                        sendAck(messageID: ack.id)
                    }
                case .none, .group:
                    if let delegate = chatDelegate {
                        delegate.halloService(self, didReceiveMessageReceipt: receipt, ack: { self.sendAck(messageID: ack.id) })
                    } else {
                        sendAck(messageID: ack.id)
                    }
                }
            } else {
                // If not a receipt, must be a chat ack.
                didGetChatAck.send((id: ack.id, timestamp: timestamp))
            }
        case .msg(let msg):
            guard let payload = msg.payload.content else {
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
            case .seen(let pbReceipt):
                handleChatReceipt(receipt: pbReceipt, from: UserID(msg.fromUid), messageID: msg.id)
            case .delivery(let pbReceipt):
                handleChatReceipt(receipt: pbReceipt, from: UserID(msg.fromUid), messageID: msg.id)
            case .chat(let pbChat):
                if let chat = XMPPChatMessage(pbChat, from: UserID(msg.fromUid), to: UserID(msg.toUid), id: msg.id) {
                    didGetNewChatMessage.send(chat)
                } else {
                    DDLogError("ProtoService/didReceive/\(requestID)/error could not read chat")
                }
                sendAck(messageID: msg.id)
            case .feedItem(let pbFeedItem):
                handleFeedItems([pbFeedItem], messageID: msg.id)
            case .feedItems(let pbFeedItems):
                handleFeedItems(pbFeedItems.items, messageID: msg.id)
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
                if let group = HalloGroup(protoGroup: pbGroup) {
                    chatDelegate?.halloService(self, didReceiveGroupMessage: group)
                } else {
                    DDLogError("ProtoService/didReceive/\(requestID)/error could not read group stanza")
                }
                sendAck(messageID: msg.id)
            case .groupChat(let pbGroupChat):
                if let groupChatMessage = HalloGroupChatMessage(pbGroupChat, id: msg.id) {
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
            case .error(let error):
                DDLogError("proto/didReceive/\(requestID) received message with error \(error)")
            }
        case .error(let error):
            DDLogError("proto/didReceive/\(requestID) received packet with error \(error)")
        case .presence:
            // TODO
            break
        case .chatState:
            // TODO
            break
        case .iq:
            // NB: Should be handled by superclass implementation
            break
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

    func requestWhisperKeyBundle(userID: UserID, completion: @escaping ServiceRequestCompletion<WhisperKeyBundle>) {
        enqueue(request: ProtoWhisperGetBundleRequest(targetUserId: userID, completion: completion))
    }

    func sendReceipt(itemID: String, thread: HalloReceipt.Thread, type: HalloReceipt.`Type`, fromUserID: UserID, toUserID: UserID) {
        let receipt = HalloReceipt(itemId: itemID, userId: fromUserID, type: type, timestamp: nil, thread: thread)

        // TODO: implement receipt management logic
        let messageID = UUID().uuidString
        sentReceipts[messageID] = receipt
        unackedReceipts[messageID] = (receipt, toUserID)

        enqueue(request: ProtoSendReceipt(
            messageID: messageID,
            itemID: itemID,
            thread: thread,
            type: type,
            fromUserID: fromUserID,
            toUserID: toUserID) { _ in
                self.unackedReceipts[messageID] = nil
            }
        )
    }

    func sendPresenceIfPossible(_ presenceType: PresenceType) {
        guard isConnected else { return }
        enqueue(request: ProtoPresenceUpdate(status: presenceType) { _ in })
    }

    func subscribeToPresenceIfPossible(to userID: UserID) -> Bool {
        guard isConnected else { return false }
        enqueue(request: ProtoPresenceSubscribeRequest(userID: userID) { _ in })
        return true
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
        completion(.failure(ProtoServiceError.unimplemented))
    }

    func checkVersionExpiration(completion: @escaping ServiceRequestCompletion<TimeInterval>) {
        enqueue(request: ProtoClientVersionCheck(version: AppContext.appVersionForXMPP, completion: completion))
    }

    func getServerProperties(completion: @escaping ServiceRequestCompletion<ServerPropertiesResponse>) {
        enqueue(request: ProtoGetServerPropertiesRequest(completion: completion))
    }

    func sendGroupChatMessage(_ message: HalloGroupChatMessage, completion: @escaping ServiceRequestCompletion<Void>) {
        completion(.failure(ProtoServiceError.unimplemented))
    }

    func createGroup(name: String, members: [UserID], completion: @escaping ServiceRequestCompletion<Void>) {
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
}

private protocol ReceivedReceipt {
    var id: String { get }
    var threadID: String { get }
    var timestamp: Int64 { get }
    var receiptType: HalloReceipt.`Type` { get }
}

extension PBdelivery_receipt: ReceivedReceipt {
    var receiptType: HalloReceipt.`Type` { .delivery }
}

extension PBseen_receipt: ReceivedReceipt {
    var receiptType: HalloReceipt.`Type` { .read }
}
