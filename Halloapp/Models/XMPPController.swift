//
//  Jab.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/7/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Foundation
import SwiftUI
import XMPPFramework

enum XMPPControllerError: Error {
    case wrongUserJID
}

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

class XMPPController: NSObject {

    enum ConnectionState {
        case notConnected
        case connecting
        case connected
        case disconnecting
    }

    private class ConnectionStateCallback {
        let state: ConnectionState
        let work: (DispatchGroup) -> ()

        required init(state: ConnectionState, work: @escaping (DispatchGroup) -> ()) {
            self.state = state
            self.work = work
        }
    }

    // MARK: Connection State
    var allowedToConnect: Bool = false {
        didSet {
            if allowedToConnect {
                if connectionState == .notConnected || connectionState == .disconnecting {
                    connect()
                }
            } else {
                if connectionState == .connected || connectionState == .connecting {
                    disconnect()
                }
            }
        }
    }
    private(set) var connectionState: ConnectionState = .notConnected {
        didSet {
            DDLogDebug("xmpp/connectionState/change [\(oldValue)] -> [\(connectionState)]")
            if connectionState == .connected {
                didConnect.send()
            }
            runCallbacksForCurrentConnectionState()
        }
    }
    var isConnected: Bool { get { connectionState == .connected } }
    // This will be sent automatically when value of `connectionState` changes.
    let didConnect = PassthroughSubject<Void, Never>()

    // MARK: Chat
    weak var chatDelegate: XMPPControllerChatDelegate?
    let didGetNewChatMessage = PassthroughSubject<XMPPMessage, Never>()

    // MARK: Feed
    weak var feedDelegate: XMPPControllerFeedDelegate?

    // MARK: Misc
    let didGetAck = PassthroughSubject<XMPPAck, Never>()
    let didGetPresence = PassthroughSubject<XMPPPresence, Never>()

    // MARK: XMPP Modules
    let xmppStream = XMPPStream()
    private let xmppPubSub = XMPPPubSub(serviceJID: XMPPJID(string: "pubsub.s.halloapp.net"))

    private let userData: UserData
    private var cancellableSet: Set<AnyCancellable> = []

    init(userData: UserData) {
        self.userData = userData

        super.init()

        /* probably should be "required" once all servers including test servers are secured */
        xmppStream.startTLSPolicy = XMPPStreamStartTLSPolicy.preferred
        let clientVersion = NSString(string: UIApplication.shared.version)
        xmppStream.clientVersion = clientVersion
//        self.xmppStream.keepAliveInterval = 0.5;
        xmppStream.registerCustomElementNames(["ack"])
        xmppStream.addDelegate(self, delegateQueue: DispatchQueue.main)

        // XMPP Modules
        xmppPubSub.addDelegate(self, delegateQueue: DispatchQueue.main)
        xmppPubSub.activate(xmppStream)

        let xmppReconnect = XMPPReconnect()
        xmppReconnect.addDelegate(self, delegateQueue: DispatchQueue.main)
        xmppReconnect.activate(xmppStream)

        let xmppPing = XMPPPing()
        xmppPing.addDelegate(self, delegateQueue: DispatchQueue.main)
        xmppPing.activate(xmppStream)
        
        allowedToConnect = userData.isLoggedIn
        if allowedToConnect {
            connect()
        }

        ///TODO: consider doing the same for didLogIn.
        self.cancellableSet.insert(
            self.userData.didLogOff.sink(receiveValue: {
                DDLogInfo("xmpp/userdata-didlogoff")

                self.allowedToConnect = false
            })
        )
    }

    // MARK: Connection management

    func connect() {
        DDLogInfo("xmpp/connect")

        xmppStream.hostName = userData.hostName
        xmppStream.myJID = XMPPJID(user: userData.userId, domain: "s.halloapp.net", resource: "iphone")

        try! xmppStream.connect(withTimeout: XMPPStreamTimeoutNone) // this only throws if stream isn't configured which doesn't happen for us.

        /* we do our own manual connection timeout as the xmppStream.connect timeout is not working */
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if (self.connectionState == .notConnected || self.connectionState == .disconnecting) && self.allowedToConnect {
                self.connect()
            }
        }
    }

    func disconnect() {
        DDLogInfo("xmpp/disconnect")

        connectionState = .disconnecting
        xmppStream.disconnectAfterSending()
    }

    func disconnectImmediately() {
        DDLogInfo("xmpp/disconnectImmediately")

        connectionState = .notConnected
        xmppStream.disconnect()
    }

    // MARK: State Change Callbacks

    private var stateChangeCallbacks: [ConnectionStateCallback] = []

    func execute(whenConnectionStateIs state: ConnectionState, onQueue queue: DispatchQueue, work: @escaping @convention(block) () -> Void) {
        stateChangeCallbacks.append(ConnectionStateCallback(state: state) { (dispatchGroup) in
            queue.async(group: dispatchGroup, execute: work)
        })

        if connectionState == state {
            runCallbacksForCurrentConnectionState()
        }
    }

    private func runCallbacksForCurrentConnectionState() {
        let currentState = connectionState

        let callbacks = stateChangeCallbacks.filter { $0.state == currentState }
        guard !callbacks.isEmpty else { return }

        stateChangeCallbacks.removeAll(where: { $0.state == currentState })

        let group = DispatchGroup()
        callbacks.forEach{ $0.work(group) }
    }

    // MARK: Push token

    private static let apnsTokenUserDefaultsKey = "apnsPushToken"

    var hasValidAPNSPushToken: Bool {
        get {
            if let token = UserDefaults.standard.string(forKey: XMPPController.apnsTokenUserDefaultsKey) {
                return !token.isEmpty
            }
            return false
        }
    }

    var apnsToken: String? {
        get {
            return UserDefaults.standard.string(forKey: XMPPController.apnsTokenUserDefaultsKey)
        }
        set {
            if newValue != nil {
                UserDefaults.standard.set(newValue!, forKey: XMPPController.apnsTokenUserDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: XMPPController.apnsTokenUserDefaultsKey)
            }
        }
    }

    public func sendCurrentAPNSTokenIfPossible() {
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

    // MARK: Acks & Receipts

    func sendAck(for message: XMPPMessage) {
        if let ack = XMPPAck.ack(for: message) {
            DDLogDebug("connection/send-ack id=[\(ack.id)] to=[\(ack.to)] from=[\(ack.from)]")
            self.xmppStream.send(ack.xmlElement)
        }
    }

    fileprivate func processIncomingAck(_ ack: XMPPAck) {
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

    // Key is message's id - it would be the same as "id" in ack.
    private var sentSeenReceipts: [ String : XMPPReceipt ] = [:]
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

    // MARK: Requests
    private var requestsInFlight: [XMPPRequest] = []
    private var requestsToSend: [XMPPRequest] = []

    private func isRequestPending(_ request: XMPPRequest) -> Bool {
        if self.requestsInFlight.contains(where: { $0.requestId == request.requestId }) {
            return true
        }
        if self.requestsToSend.contains(where: { $0.requestId == request.requestId }) {
            return true
        }
        return false
    }

    func enqueue(request: XMPPRequest) {
        if self.xmppStream.isConnected {
            request.send(using: self)
            self.requestsInFlight.append(request)
        } else if request.retriesRemaining > 0 {
            self.requestsToSend.append(request)
        } else {
            request.failOnNoConnection()
        }
    }

    /**
     All requests in the queue are automatically resent when the connection is opened.
     */
    func resendAllPendingRequests() {
        guard !self.requestsToSend.isEmpty else {
            return
        }
        guard self.xmppStream.isConnected else {
            DDLogWarn("connection/requests/resend/skipped [\(self.requestsToSend.count)] [no connection]")
            return
        }

        let allRequests = self.requestsToSend
        self.requestsToSend.removeAll()

        DDLogInfo("connection/requests/resend [\(allRequests.count)]")
        for request in allRequests {
            request.send(using: self)
        }
        self.requestsInFlight.append(contentsOf: allRequests)
    }

    func cancelAllRequests() {
        DDLogInfo("connection/requests/cancel/all [\(self.requestsInFlight.count)]")

        let allRequests = self.requestsInFlight + self.requestsToSend
        self.requestsInFlight.removeAll()
        self.requestsToSend.removeAll()

        for request in allRequests {
            if request.cancelAndPrepareFor(retry: true) {
                self.requestsToSend.append(request)
            }
        }
    }

    // MARK: Feed

    func retrieveFeedData<T: Collection>(for userIds: T) where T.Element == UserID {
        guard !userIds.isEmpty else { return }
        userIds.forEach {
            self.xmppPubSub.retrieveItems(fromNode: "feed-\($0)")
        }
    }

    // MARK: Misc

    fileprivate func resendNameIfNecessary() {
        let userDefaultsKey = "xmpp.name-sent"
        guard !UserDefaults.standard.bool(forKey: userDefaultsKey) else { return }
        guard !self.userData.name.isEmpty else { return }

        let request = XMPPSendNameRequest(name: self.userData.name) { (error) in
            if error == nil {
                UserDefaults.standard.set(true, forKey: userDefaultsKey)
            }
        }
        self.enqueue(request: request)
    }
}


extension XMPPController: XMPPStreamDelegate {
    
    func xmppStream(_ sender: XMPPStream, didReceive message: XMPPMessage) {
        guard message.fromStr ?? "" != "pubsub.s.halloapp.net" else {
            // PubSub messages are handled separately.
            return
        }

        DDLogInfo("xmpp/stream/didReceiveMessage id=[\(message.elementID ?? "<empty>")]")

        // Notification about new contact on the app
        if let contactList = message.element(forName: "contact_list") {
            let contacts = contactList.elements(forName: "contact").compactMap{ XMPPContact($0) }
            AppContext.shared.syncManager.processNotification(contacts: contacts) {
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
        }
        
        self.sendAck(for: message)
    }
    
    func xmppStream(_ sender: XMPPStream, didReceive iq: XMPPIQ) -> Bool {
        DDLogInfo("xmpp/stream/didReceiveIQ")

        if let requestId = iq.elementID {
            func removeRequest(with id: String, outOf requests: inout [XMPPRequest]) -> [XMPPRequest] {
                let filteredSequence = requests.enumerated().filter { $0.element.requestId == id }
                let indexes = filteredSequence.map { $0.offset }
                let results = filteredSequence.map { $0.element }
                requests = requests.enumerated().filter { !indexes.contains($0.offset) }.map { $0.element }
                return results
            }

            // Process request responses.  We should theoretically only get back
            // responses for requests that we have sent, but in case of accidentally
            // sending a duplicated request or delayed processing related to dropping
            // a connection, we should still check both arrays.
            var matchingRequests: [XMPPRequest] = []
            matchingRequests.append(contentsOf: removeRequest(with: requestId, outOf: &self.requestsInFlight))
            matchingRequests.append(contentsOf: removeRequest(with: requestId, outOf: &self.requestsToSend))
            if matchingRequests.count > 1 {
                DDLogWarn("connection/response/\(requestId)/warning: found \(matchingRequests.count) requests")
            }
            for request in matchingRequests {
                DDLogInfo("connection/response/\(type(of: request))/\(requestId)")
                request.process(response: iq)
            }
        }

        return false
    }
    
    func xmppStreamWillConnect(_ sender: XMPPStream) {
        DDLogInfo("xmpp/stream/willConnect")

        connectionState = .connecting
    }
    
    func xmppStreamConnectDidTimeout(_ stream: XMPPStream) {
        DDLogInfo("xmpp/stream/connectDidTimeout")
    }

    func xmppStreamDidDisconnect(_ sender: XMPPStream, withError error: Error?) {
        DDLogInfo("xmpp/stream/didDisconnect [\(String(describing: error))]")

        connectionState = .notConnected
    }
    
    func xmppStream(_ sender: XMPPStream, socketDidConnect socket: GCDAsyncSocket) {
        DDLogInfo("xmpp/stream/socketDidConnect")
    }
    
    func xmppStreamDidStartNegotiation(_ sender: XMPPStream) {
        DDLogInfo("xmpp/stream/didStartNegotiation")
    }
    
    func xmppStream(_ sender: XMPPStream, willSecureWithSettings settings: NSMutableDictionary) {
        DDLogInfo("xmpp/stream/willSecureWithSettings [\(settings)]")

        settings.setObject(true, forKey:GCDAsyncSocketManuallyEvaluateTrust as NSCopying)
    }

    func xmppStream(_ sender: XMPPStream, didReceive trust: SecTrust, completionHandler: ((Bool) -> Void)) {
        DDLogInfo("xmpp/stream/didReceiveTrust")

        if SecTrustEvaluateWithError(trust, nil) {
            completionHandler(true)
        } else {
            //todo: handle gracefully and reflect in global state
            completionHandler(false)
        }
    }
    
    func xmppStreamDidSecure(_ sender: XMPPStream) {
        DDLogInfo("xmpp/stream/didSecure")
    }
    
    func xmppStreamDidConnect(_ stream: XMPPStream) {
        DDLogInfo("xmpp/stream/didConnect")
        
        try! stream.authenticate(withPassword: self.userData.password)
    }

    func xmppStreamDidDisconnect(_ stream: XMPPStream) {
        DDLogInfo("xmpp/stream/didDisconnect")

        connectionState = .notConnected
        cancelAllRequests()
    }

    func xmppStreamDidAuthenticate(_ sender: XMPPStream) {
        DDLogInfo("xmpp/stream/didAuthenticate")
        
        connectionState = .connected

        if self.hasValidAPNSPushToken {
            self.sendCurrentAPNSToken()
        }
        
        // This function sends an initial presence stanza to the server indicating that the user is online.
        // This is necessary so that the server will then respond with all the offline messages for the client.
        // stanza: <presence />
        self.xmppStream.send(XMPPPresence())

        self.resendAllPendingRequests()

        self.resendAllPendingReceipts()

        self.resendNameIfNecessary()
    }
    
    func xmppStream(_ sender: XMPPStream, didNotAuthenticate error: DDXMLElement) {
        DDLogInfo("xmpp/stream/didNotAuthenticate")

        self.userData.logout()
    }
    
    func xmppStream(_ sender: XMPPStream, didReceiveError error: DDXMLElement) {
        DDLogInfo("xmpp/stream/didReceiveError [\(error)]")
        
        if error.element(forName: "conflict") != nil {
            if let text = error.element(forName: "text")?.stringValue {
                if text == "User removed" {
                    DDLogInfo("Stream: Same user logged into another device, logging out of this one")
                    self.userData.logout()
                }
            }
        }
    }

    func xmppStream(_ sender: XMPPStream, didReceive presence: XMPPPresence) {
        DDLogInfo("xmpp/stream/didReceivePresence")

        self.didGetPresence.send(presence)
    }

    func xmppStream(_ sender: XMPPStream, didReceiveCustomElement element: DDXMLElement) {
        DDLogInfo("xmpp/stream/didReceiveCustomElement [\(element)]")

        if element.name == "ack" {
            if let ack = XMPPAck(itemElement: element) {
                self.processIncomingAck(ack)
            } else {
                DDLogError("xmpp/ack/invalid [\(element)]")
            }
            return
        }
    }
}

extension XMPPController: XMPPReconnectDelegate {

    public func xmppReconnect(_ sender: XMPPReconnect, didDetectAccidentalDisconnect connectionFlags: SCNetworkConnectionFlags) {
        DDLogInfo("xmpp/xmppReconnect/didDetectAccidentalDisconnect")
    }

    public func xmppReconnect(_ sender: XMPPReconnect, shouldAttemptAutoReconnect connectionFlags: SCNetworkConnectionFlags) -> Bool {
        return true
    }
}

extension XMPPController: XMPPPingDelegate {

    public func xmppPing(_ sender: XMPPPing!, didReceivePong pong: XMPPIQ!, withRTT rtt: TimeInterval) {
        DDLogInfo("xmpp/ping/didReceivePong")
    }

    public func xmppPing(_ sender: XMPPPing!, didNotReceivePong pingID: String!, dueToTimeout timeout: TimeInterval) {
        DDLogInfo("xmpp/ping/didNotReceivePong")
    }
}

extension XMPPController: XMPPPubSubDelegate {

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
