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

protocol XMPPControllerFeedDelegate: AnyObject {
    func xmppController(_ xmppController: XMPPController, didReceiveFeedItems items: [XMLElement], in xmppMessage: XMPPMessage?)
    func xmppController(_ xmppController: XMPPController, didReceiveFeedRetracts items: [XMLElement], in xmppMessage: XMPPMessage?)
    func xmppController(_ xmppController: XMPPController, didReceiveFeedReceipt receipt: XMPPReceipt, in xmppMessage: XMPPMessage?)
    func xmppController(_ xmppController: XMPPController, didSendFeedReceipt receipt: XMPPReceipt)
}

protocol XMPPControllerChatDelegate: AnyObject {
    func xmppController(_ xmppController: XMPPController, didReceiveMessageReceipt receipt: XMPPReceipt, in xmppMessage: XMPPMessage?)
    func xmppController(_ xmppController: XMPPController, didSendMessageReceipt receipt: XMPPReceipt)
}


fileprivate let userDefaultsKeyForAPNSToken = "apnsPushToken"
fileprivate let userDefaultsKeyForAvatarSync = "xmpp.avatar-sent"
fileprivate let userDefaultsKeyForNameSync = "xmpp.name-sent"

class XMPPControllerMain: XMPPController {

    // MARK: XMPP Modules
    private let xmppPubSub = XMPPPubSub(serviceJID: XMPPJID(string: "pubsub.s.halloapp.net"))

    // MARK: Feed
    weak var feedDelegate: XMPPControllerFeedDelegate?

    // MARK: Chat
    weak var chatDelegate: XMPPControllerChatDelegate?
    let didGetNewChatMessage = PassthroughSubject<XMPPMessage, Never>()

    // MARK: Misc
    let didGetAck = PassthroughSubject<XMPPAck, Never>()
    let didGetPresence = PassthroughSubject<XMPPPresence, Never>()

    // MARK: Privacy
    private(set) var privacySettings: PrivacySettings!

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

        privacySettings = PrivacySettings(xmppController: self)
    }

    override func configure(xmppStream: XMPPStream) {
        super.configure(xmppStream: xmppStream)
        let clientVersion = NSString(string: UIApplication.shared.version)
        xmppStream.clientVersion = clientVersion
    }

    // MARK: Feed

    func retrieveFeedData<T: Collection>(for userIds: T) where T.Element == UserID {
        guard !userIds.isEmpty else { return }
        userIds.forEach {
            self.xmppPubSub.retrieveItems(fromNode: "feed-\($0)")
        }
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

        let request = XMPPSendNameRequest(name: self.userData.name) { (error) in
            if error == nil {
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
        guard !UserDefaults.standard.bool(forKey: userDefaultsKeyForAvatarSync) else { return }
        
        guard let avatarData = MainAppContext.shared.avatarStore.userAvatar(forUserId: self.userData.userId).data else {
            DDLogError("XMPPController/resendAvatarIfNecessary/error avatar does not exist")
            UserDefaults.standard.set(true, forKey: userDefaultsKeyForAvatarSync)
            return
        }
        
        let request = XMPPUploadAvatarRequest(data: avatarData) { (error, avatarId) in
            if error == nil {
                UserDefaults.standard.set(true, forKey: userDefaultsKeyForAvatarSync)
                
                if let avatarId = avatarId {
                    MainAppContext.shared.avatarStore.update(avatarId: avatarId, forUserId: self.userData.userId)
                }
            } else {
                DDLogError("XMPPController/resendAvatarIfNecessary/error while uploading avatar got \(error!)")
            }
        }

        self.enqueue(request: request)
    }

    func sendCurrentAvatarIfPossible() {
        UserDefaults.standard.set(false, forKey: userDefaultsKeyForAvatarSync)

        if isConnected {
            resendAvatarIfNecessary()
        }
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

    // MARK: XMPPController Overrides

    override func performOnConnect() {
        super.performOnConnect()

        if hasValidAPNSPushToken {
            sendCurrentAPNSToken()
        }

        resendNameIfNecessary()
        resendAvatarIfNecessary()
        resendAllPendingReceipts()
    }

    override func didReceive(message: XMPPMessage) {
        // Notification about new contact on the app
        if let contactList = message.element(forName: "contact_list") {
            let contacts = contactList.elements(forName: "contact").compactMap{ XMPPContact($0) }
            MainAppContext.shared.syncManager.processNotification(contacts: contacts) {
                self.sendAck(for: message)
            }
            return
        }

        // Delivery receipt.
        if let deliveryReceipt = message.deliveryReceipt {

            // Feed doesn't have delivery receipts.
            if let delegate = self.chatDelegate {
                delegate.xmppController(self, didReceiveMessageReceipt: deliveryReceipt, in: message)
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
                    delegate.xmppController(self, didReceiveFeedReceipt: readReceipt, in: message)
                } else {
                    self.sendAck(for: message)
                }
                break

            case .group(_), .none:
                if let delegate = self.chatDelegate {
                    delegate.xmppController(self, didReceiveMessageReceipt: readReceipt, in: message)
                } else {
                    self.sendAck(for: message)
                }
                break
            }
            return
        }

        if message.element(forName: "chat") != nil {
            self.didGetNewChatMessage.send(message)
            self.sendAck(for: message)
            return
        }
        
        if let avatarElement = message.element(forName: "avatar") {
            if let delegate = self.avatarDelegate {
                delegate.xmppController(self, didReceiveAvatar: avatarElement)
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
                    delegate.xmppController(self, didSendFeedReceipt: receipt)
                }
            } else {
                if let delegate = self.chatDelegate {
                    delegate.xmppController(self, didSendMessageReceipt: receipt)
                }
            }
            return
        }

        // Message acks.
        self.didGetAck.send(ack)
    }

    override func didReceive(presence: XMPPPresence) {
        self.didGetPresence.send(presence)
    }

}

extension XMPPControllerMain: XMPPPubSubDelegate {

    func xmppPubSub(_ sender: XMPPPubSub, didRetrieveItems iq: XMPPIQ, fromNode node: String) {
        DDLogInfo("xmpp/pubsub/didRetrieveItems")

        guard let delegate = self.feedDelegate else { return }

        // TODO: redo this using XMPPRequest
        guard let items = iq.element(forName: "pubsub")?.element(forName: "items") else { return }
        guard let nodeAttr = items.attributeStringValue(forName: "node") else { return }
        let nodeParts = nodeAttr.components(separatedBy: "-")
        guard nodeParts.count == 2 else { return }
        if nodeParts.first! == "feed" {
            delegate.xmppController(self, didReceiveFeedItems: items.elements(forName: "item"), in: nil)
        }
    }

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
            guard let delegate = self.feedDelegate else {
                self.sendAck(for: message)
                break
            }
            let feedItems = items.elements(forName: "item")
            let feedRetracts = items.elements(forName: "retract")
            // One message could not contain both feed items and retracts.
            // Delegate is responsible for sending an ack once it's finished processing data.
            if !feedItems.isEmpty {
                delegate.xmppController(self, didReceiveFeedItems: feedItems, in: message)
            } else if !feedRetracts.isEmpty {
                delegate.xmppController(self, didReceiveFeedRetracts: feedRetracts, in: message)
            } else {
                self.sendAck(for: message)
            }

        case "metadata":
            DDLogInfo("xmpp/pubsub/message/incoming/metadata Ack metadata message silently.")
            self.sendAck(for: message)

        default:
            DDLogError("xmpp/pubsub/message/error/unknown-type")
            self.sendAck(for: message)
        }
    }
}

