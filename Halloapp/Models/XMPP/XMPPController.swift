//
//  Jab.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/7/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import Foundation
import SwiftUI
import XMPPFramework

protocol XMPPControllerChatDelegate: AnyObject {
    func xmppController(_ xmppController: XMPPController, didReceiveMessageReceipt receipt: XMPPReceipt, in xmppMessage: XMPPMessage?)
    func xmppController(_ xmppController: XMPPController, didSendMessageReceipt receipt: XMPPReceipt)
    func xmppController(_ xmppController: XMPPController, didReceiveGroupMessage item: XMLElement)
    func xmppController(_ xmppController: XMPPController, didReceiveGroupChatMessage item: XMLElement)
}

protocol XMPPControllerKeyDelegate: AnyObject {
    func xmppController(_ xmppController: XMPPController, didReceiveWhisperMessage item: XMLElement)
}

fileprivate let userDefaultsKeyForAPNSToken = "apnsPushToken"
fileprivate let userDefaultsKeyForNameSync = "xmpp.name-sent"

class XMPPControllerMain: XMPPController {

    // MARK: XMPP Modules
    private let xmppPubSub = XMPPPubSub(serviceJID: XMPPJID(string: "pubsub.s.halloapp.net"))

    // MARK: Feed
    weak var feedDelegate: HalloFeedDelegate?

    // MARK: Chat
    weak var chatDelegate: HalloChatDelegate?
    let didGetNewChatMessage = PassthroughSubject<ChatMessageProtocol, Never>()

    // MARK: Key
    weak var keyDelegate: HalloKeyDelegate?
    
    // MARK: Misc
    let didGetChatAck = PassthroughSubject<ChatAck, Never>()
    let didGetPresence = PassthroughSubject<ChatPresenceInfo, Never>()
    let didGetChatState = PassthroughSubject<ChatStateInfo, Never>()

    private var cancellableSet: Set<AnyCancellable> = []

    required init(userData: UserData) {
        super.init(userData: userData)

        // XMPP Modules
        self.xmppPubSub.addDelegate(self, delegateQueue: DispatchQueue.main)
        self.xmppPubSub.activate(xmppStream)

        self.cancellableSet.insert(
            userData.didLogIn.sink {
                DDLogInfo("xmpp/userdata/didLogIn")
                self.xmppStream.myJID = self.userData.userJID
                self.connect()
            })
        self.cancellableSet.insert(
            userData.didLogOff.sink {
                DDLogInfo("xmpp/userdata/didLogOff")
                self.xmppStream.disconnect() // this is only necessary when manually logging out from a developer menu.
                self.xmppStream.myJID = nil
            })
    }

    // MARK: Push token

    var hasValidAPNSPushToken: Bool {
        get {
            if let token = UserDefaults.standard.string(forKey: userDefaultsKeyForAPNSToken) {
                return !token.isEmpty
            }
            return false
        }
    }

    var apnsToken: String? {
        get {
            return UserDefaults.standard.string(forKey: userDefaultsKeyForAPNSToken)
        }
        set {
            if newValue != nil {
                UserDefaults.standard.set(newValue!, forKey: userDefaultsKeyForAPNSToken)
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKeyForAPNSToken)
            }
        }
    }

    func sendCurrentAPNSTokenIfPossible() {
        if isConnected {
            sendCurrentAPNSToken()
        }
    }

    private func sendCurrentAPNSToken() {
        DDLogInfo("xmpp/push-token/send")
        let request = XMPPPushTokenRequest(token: self.apnsToken!) { (error) in
            DDLogInfo("xmpp/push-token/sent")
        }
        self.enqueue(request: request)
    }

    // MARK: User Name

    private func resendNameIfNecessary() {
        guard !UserDefaults.standard.bool(forKey: userDefaultsKeyForNameSync) else { return }
        guard !self.userData.name.isEmpty else { return }

        let request = XMPPSendNameRequest(name: self.userData.name) { (result) in
            if case .success = result {
                UserDefaults.standard.set(true, forKey: userDefaultsKeyForNameSync)
            }
        }
        self.enqueue(request: request)
    }

    func sendCurrentUserNameIfPossible() {
        UserDefaults.standard.set(false, forKey: userDefaultsKeyForNameSync)

        if isConnected {
            resendNameIfNecessary()
        }
    }
    
    // MARK: Avatar
    
    private func resendAvatarIfNecessary() {
        guard UserDefaults.standard.bool(forKey: AvatarStore.Keys.userDefaultsUpload) else { return }
        
        let userAvatar = MainAppContext.shared.avatarStore.userAvatar(forUserId: self.userData.userId)
        
        var request: XMPPRequest?
        
        if userAvatar.isEmpty { // remove old avatar
            DDLogInfo("XMPPController/resendAvatarIfNecessary/remove avatar will be removed")
            request = XMPPRemoveAvatarRequest { (result) in
                switch result {
                case .success:
                    DDLogInfo("XMPPController/resendAvatarIfNecessary/remove avatar has been removed")
                    UserDefaults.standard.set(false, forKey: AvatarStore.Keys.userDefaultsUpload)
                    
                case .failure(let error):
                    DDLogError("XMPPController/resendAvatarIfNecessary/remove/error while removing avatar got \(error)")
                }
            }
        } else { // upload new avatar
            DDLogInfo("XMPPController/resendAvatarIfNecessary/remove avatar will be uploaded")
            guard let avatarData = userAvatar.data else {
                DDLogError("XMPPController/resendAvatarIfNecessary/upload/error avatar data is not ready")
                return
            }
            
            request = XMPPUploadAvatarRequest(data: avatarData) { (result) in
                switch result {
                case .success(let avatarId):
                    UserDefaults.standard.set(false, forKey: AvatarStore.Keys.userDefaultsUpload)

                    if let avatarId = avatarId {
                        MainAppContext.shared.avatarStore.update(avatarId: avatarId, forUserId: self.userData.userId)
                        DDLogInfo("XMPPController/resendAvatarIfNecessary/upload avatar has been uploaded")
                    }

                case .failure(let error):
                    DDLogError("XMPPController/resendAvatarIfNecessary/upload/error while uploading avatar got \(error)")
                }
            }
        }

        self.enqueue(request: request!)
    }

    func sendCurrentAvatarIfPossible() {
        UserDefaults.standard.set(true, forKey: AvatarStore.Keys.userDefaultsUpload)

        if isConnected {
            resendAvatarIfNecessary()
        }
    }
    
    private func queryAvatarForCurrentUserIfNecessary() {
        guard !UserDefaults.standard.bool(forKey: AvatarStore.Keys.userDefaultsDownload) else { return }
        
        DDLogInfo("XMPPController/queryAvatarForCurrentUserIfNecessary start")
        
        let request = XMPPQueryAvatarRequest(userId: userData.userId) { (result) in
            switch (result) {
            case .success(let avatarId):
                UserDefaults.standard.set(true, forKey: AvatarStore.Keys.userDefaultsDownload)

                guard let avatarId = avatarId else {
                    DDLogInfo("XMPPController/queryAvatarForCurrentUserIfNecessary avatarId is nil")
                    return
                }

                MainAppContext.shared.avatarStore.save(avatarId: avatarId, forUserId: self.userData.userId)
                DDLogInfo("XMPPController/queryAvatarForCurrentUserIfNecessary/success avatarId=\(avatarId)")

            case .failure(let error):
                DDLogError("XMPPController/queryAvatarForCurrentUserIfNecessary/error while query avatar: \(error)")
            }
        }
        
        self.enqueue(request: request)
    }

    // MARK: Receipts

    private var sentSeenReceipts: [ String : XMPPReceipt ] = [:] // Key is message's id - it would be the same as "id" in ack.

    private var unackedReceipts: [ String : XMPPMessage ] = [:]

    func sendSeenReceipt(_ receipt: XMPPReceipt, to userId: UserID) {
        guard !sentSeenReceipts.values.contains(where: { $0 == receipt }) else {
            DDLogWarn("xmpp/seen-receipt/duplicate receipt=[\(receipt)]")
            return
        }
        // TODO: check for duplicates
        let toJID = XMPPJID(user: userId, domain: "s.halloapp.net", resource: nil)
        let messageId = UUID().uuidString
        let message = XMPPMessage(messageType: nil, to: toJID, elementID: messageId, child: receipt.xmlElement)
        let receiptKey = messageId
        self.sentSeenReceipts[receiptKey] = receipt
        self.unackedReceipts[receiptKey] = message
        self.xmppStream.send(message)
    }

    fileprivate func resendAllPendingReceipts() {
        self.unackedReceipts.forEach { self.xmppStream.send($1) }
    }

    // MARK: Server Properties

    private func requestServerPropertiesIfNecessary() {
        guard ServerProperties.shouldQuery(forVersion: xmppStream.serverPropertiesVersion) else {
            return
        }
        DDLogInfo("xmpp/serverprops/request")
        getServerProperties { (result) in
            switch result {
            case .success(let (version, properties)):
                DDLogDebug("xmpp/serverprops/request/success version=[\(version)]")
                ServerProperties.update(withProperties: properties, version: version)

            case .failure(let error):
                DDLogError("xmpp/serverprops/request/error [\(error)]")
            }
        }
    }

    // MARK: XMPPController Overrides

    override func performOnConnect() {
        super.performOnConnect()

        if hasValidAPNSPushToken {
            sendCurrentAPNSToken()
        }

        resendNameIfNecessary()
        resendAvatarIfNecessary()
        resendAllPendingReceipts()
        queryAvatarForCurrentUserIfNecessary()
        requestServerPropertiesIfNecessary()
        NotificationSettings.current.sendConfigIfNecessary(using: self)
        MainAppContext.shared.startReportingEvents()
    }

    override func didReceive(message: XMPPMessage) {
        // Notification about new contact on the app
        if let contactList = message.element(forName: "contact_list") {
            let contacts = contactList.elements(forName: "contact").compactMap({ XMPPContact($0) })
            if !contacts.isEmpty {
                MainAppContext.shared.syncManager.processNotification(contacts: contacts) {
                    self.sendAck(for: message)
                }
                return
            }

            let contactHashStrings = contactList.elements(forName: "contact_hash").compactMap{ $0.stringValue }
            // Special case: empty hash should trigger a full sync.
            if let hashString = contactHashStrings.first, hashString.isEmpty {
                MainAppContext.shared.syncManager.requestFullSync()
                self.sendAck(for: message)
                return
            }

            let contactHashes = contactHashStrings.compactMap({ Data(base64Encoded: $0) }).filter({ !$0.isEmpty })
            if !contactHashes.isEmpty {
                MainAppContext.shared.syncManager.processNotification(contactHashes: contactHashes) {
                    self.sendAck(for: message)
                }
                return
            }

            self.sendAck(for: message)
            return
        }

        // Contact push name change notification
        if let nameElement = message.element(forName: "name"), nameElement.xmlns() == "halloapp:users:name" {
            guard let userId = nameElement.attributeStringValue(forName: "uid"),
                let name = nameElement.stringValue, !name.isEmpty else {
                sendAck(for: message)
                return
            }

            MainAppContext.shared.contactStore.addPushNames([ userId: name ])
            sendAck(for: message)
            return
        }

        // Feed Items
        if let feed = message.element(forName: "feed"), feed.xmlns() == "halloapp:feed",
           let action = feed.attributeStringValue(forName: "action"),
           let delegate = feedDelegate {

            var postsAndComments = feed.elements(forName: "post")
            postsAndComments.append(contentsOf: feed.elements(forName: "comment"))

            let messageRetryCount = message.attributeIntValue(forName: "retry_count")

            if action == "publish" || action == "share" {
                let payload = HalloServiceFeedPayload(content: .newItems(postsAndComments.compactMap { FeedElement($0) }), group: nil, isPushSent: messageRetryCount > 0)
                delegate.halloService(self, didReceiveFeedPayload: payload, ack: { self.sendAck(for: message) })
            } else if action == "retract" {
                let payload = HalloServiceFeedPayload(content: .retracts(postsAndComments.compactMap { FeedRetract($0) }), group: nil, isPushSent: messageRetryCount > 0)
                delegate.halloService(self, didReceiveFeedPayload: payload, ack: { self.sendAck(for: message) })
            } else {
                sendAck(for: message)
            }
            return
        }

        // Group Feed Items
        if let feed = message.element(forName: "group_feed"), feed.xmlns() == "halloapp:group:feed",
           let action = feed.attributeStringValue(forName: "action"),
           let groupId = feed.attributeStringValue(forName: "gid"), let groupName = feed.attributeStringValue(forName: "name"),
           let delegate = feedDelegate {

            var group = HalloGroup(id: groupId, name: groupName)
            group.avatarID = feed.attributeStringValue(forName: "avatar_id")

            var postsAndComments = feed.elements(forName: "post")
            postsAndComments.append(contentsOf: feed.elements(forName: "comment"))

            let messageRetryCount = message.attributeIntValue(forName: "retry_count")

            if action == "publish" || action == "share" {
                let payload = HalloServiceFeedPayload(content: .newItems(postsAndComments.compactMap { FeedElement($0) }), group: group, isPushSent: messageRetryCount > 0)
                delegate.halloService(self, didReceiveFeedPayload: payload, ack: { self.sendAck(for: message) })
            } else if action == "retract" {
                let payload = HalloServiceFeedPayload(content: .retracts(postsAndComments.compactMap { FeedRetract($0) }), group: group, isPushSent: messageRetryCount > 0)
                delegate.halloService(self, didReceiveFeedPayload: payload, ack: { self.sendAck(for: message) })
            } else {
                sendAck(for: message)
            }
            return
        }

        // Delivery receipt.
        if let deliveryReceipt = message.deliveryReceipt {

            // Feed doesn't have delivery receipts.
            if let delegate = self.chatDelegate {
                delegate.halloService(self, didReceiveMessageReceipt: deliveryReceipt, ack: { self.sendAck(for: message) })
            } else {
                self.sendAck(for: message)
            }
            return
        }

        // "Seen" receipt.
        if let readReceipt = message.readReceipt {
            switch readReceipt.thread {
            case .feed:
                if let delegate = self.feedDelegate {
                    delegate.halloService(self, didReceiveFeedReceipt: readReceipt, ack: { self.sendAck(for: message) })
                } else {
                    self.sendAck(for: message)
                }
                break

            case .group(_), .none:
                if let delegate = self.chatDelegate {
                    delegate.halloService(self, didReceiveMessageReceipt: readReceipt, ack: { self.sendAck(for: message) })
                } else {
                    self.sendAck(for: message)
                }
                break
            }
            return
        }

        if let avatarElement = message.element(forName: "avatar") {
            if let avatarID = avatarElement.attributeStringValue(forName: "id"), let userID = avatarElement.attributeStringValue(forName: "userid") {
                avatarDelegate?.service(self, didReceiveAvatarInfo: (userID: userID, avatarID: avatarID))
            } else {
                DDLogError("XMPPController/didReceive/error avatar missing ID or userID")
            }
            self.sendAck(for: message)
            return
        }
        
        if let whisperMessageElement = message.element(forName: "whisper_keys") {
            if let whisperMessage = WhisperMessage(whisperMessageElement) {
                keyDelegate?.halloService(self, didReceiveWhisperMessage: whisperMessage)
            } else {
                DDLogError("XMPPController/didReceive/error could not read whisper message")
            }
            self.sendAck(for: message)
            return
        }
        
        if let _ = message.element(forName: "chat") {
            // NB: We pass the parent element into the initializer in order to retain the ID
            if let chatMessage = XMPPChatMessage(itemElement: message) {
                self.didGetNewChatMessage.send(chatMessage)
            } else {
                DDLogError("XMPPController/didReceive/error could not read chat message")
            }
            self.sendAck(for: message)
            return
        }
        
        if let _ = message.element(forName: "group_chat") {
            // NB: We pass the parent element into the initializer in order to retain the ID
            if let groupChatMessage = XMPPChatGroupMessage(itemElement: message) {
                chatDelegate?.halloService(self, didReceiveGroupChatMessage: groupChatMessage)
            } else {
                DDLogError("XMPPController/didReceive/error could not read group chat message")
            }
            self.sendAck(for: message)
            return
        }
        
        if let groupElement = message.element(forName: "group") {
            if let group = XMPPGroup(itemElement: groupElement, messageId: message.elementID) {
                chatDelegate?.halloService(self, didReceiveGroupMessage: group)
            } else {
                DDLogError("XMPPController/didReceive/error could not read group message")
            }
            self.sendAck(for: message)
            return
        }
        
        DDLogError("XMPPControllerMain/didReceiveMessage/error can't handle message=\(message)")

        self.sendAck(for: message)
    }

    override func didReceive(ack: XMPPAck) {
        // Receipt acks.
        let receiptKey = ack.id
        if let receipt = self.sentSeenReceipts[ack.id] {
            self.unackedReceipts.removeValue(forKey: receiptKey)
            self.sentSeenReceipts.removeValue(forKey: receiptKey)

            if case .feed = receipt.thread {
                if let delegate = self.feedDelegate {
                    delegate.halloService(self, didSendFeedReceipt: receipt)
                }
            } else {
                if let delegate = self.chatDelegate {
                    delegate.halloService(self, didSendMessageReceipt: receipt)
                }
            }
            return
        }

        // Message acks.
        self.didGetChatAck.send((id: ack.id, timestamp: ack.timestamp))
    }

    override func didReceive(presence: XMPPPresence) {
        guard let fromUserID = presence.from?.user else { return }
        self.didGetPresence.send((
            userID: fromUserID,
            presence: PresenceType(rawValue: presence.type ?? ""),
            lastSeen: Date(timeIntervalSince1970: presence.attributeDoubleValue(forName: "last_seen"))))
    }
    
    override func didReceive(chatState: XMPPChatState) {
        guard let fromUserID = chatState.from.user else { return }
        
        didGetChatState.send((from: fromUserID, threadType: chatState.threadType, threadID: chatState.threadID, type: chatState.type))
    }
    
    // MARK: XMPPReconnectDelegate

    override func xmppReconnect(_ sender: XMPPReconnect, shouldAttemptAutoReconnect connectionFlags: SCNetworkConnectionFlags) -> Bool {
        return UIApplication.shared.applicationState != .background
    }
}

extension XMPPControllerMain: XMPPPubSubDelegate {

    func xmppPubSub(_ sender: XMPPPubSub, didReceive message: XMPPMessage) {
        guard let items = message.element(forName: "event")?.element(forName: "items") else {
            DDLogError("xmpp/pubsub/message/incoming/error/invalid-message")
            self.sendAck(for: message)
            return
        }

        guard let nodeAttr = items.attributeStringValue(forName: "node") else {
            DDLogError("xmpp/pubsub/message/incoming/error/missing-node")
            self.sendAck(for: message)
            return
        }

        let nodeParts = nodeAttr.components(separatedBy: "-")
        guard nodeParts.count == 2 else {
            DDLogError("xmpp/pubsub/message/incoming/error/invalid-node [\(nodeParts)]")
            self.sendAck(for: message)
            return
        }

        DDLogInfo("xmpp/pubsub/message/incoming node=[\(nodeAttr)] id=[\(message.elementID ?? "")]")

        switch nodeParts.first! {
        case "feed":
            DDLogInfo("xmpp/pubsub/message/incoming/feed Ignore obsolete format.")
            self.sendAck(for: message)

        case "metadata":
            DDLogInfo("xmpp/pubsub/message/incoming/metadata Ack metadata message silently.")
            self.sendAck(for: message)

        default:
            DDLogError("xmpp/pubsub/message/error/unknown-type")
            self.sendAck(for: message)
        }
    }
}

