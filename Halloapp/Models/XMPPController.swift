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

class XMPPController: NSObject, ObservableObject {
    var allowedToConnect: Bool = false {
        didSet {
            if self.allowedToConnect {
                if !self.isConnectedToServer {
                    self.connect()
                }
            } else {
                if self.isConnectedToServer {
                    self.xmppStream.disconnect()
                }
            }
        }
    }

    var isConnecting = PassthroughSubject<String, Never>()
    var didConnect = PassthroughSubject<String, Never>() // used by UserData to know if user is in or not
    
    var didGetNewChatMessage = PassthroughSubject<XMPPMessage, Never>()

    var didGetAck = PassthroughSubject<XMPPAck, Never>()

    var xmppStream: XMPPStream
    private var xmppPubSub: XMPPPubSub
    private var xmppReconnect: XMPPReconnect
    private var xmppPing: XMPPPing

    var userJID: XMPPJID?
    private let hostPort: UInt16 = 5222

    var userData: UserData
    var metaData: MetaData
    
    var isConnectedToServer: Bool = false
    private var cancellableSet: Set<AnyCancellable> = []

    weak var feedDelegate: XMPPControllerFeedDelegate?
    weak var chatDelegate: XMPPControllerChatDelegate?

    init(userData: UserData, metaData: MetaData) {
        
        self.userData = userData
        self.metaData = metaData

        // Stream Configuration
        self.xmppStream = XMPPStream()
        self.xmppStream.hostPort = hostPort
  
        let appVersionNStr = NSString(string: UIApplication.shared.version)
        self.xmppStream.clientVersion = appVersionNStr
        
        /* probably should be "required" once all servers including test servers are secured */
        self.xmppStream.startTLSPolicy = XMPPStreamStartTLSPolicy.preferred
        
//        self.xmppStream.keepAliveInterval = 0.5;
        
        self.xmppStream.registerCustomElementNames(["ack"])
        
        let pubsubId = XMPPJID(string: "pubsub.s.halloapp.net")
        self.xmppPubSub = XMPPPubSub(serviceJID: pubsubId)
        
        self.xmppReconnect = XMPPReconnect()
        
        self.xmppPing = XMPPPing()
        
//        self.xmppAutoPing = XMPPAutoPing()
        
        super.init()

        self.xmppStream.addDelegate(self, delegateQueue: DispatchQueue.main)
        self.xmppPubSub.addDelegate(self, delegateQueue: DispatchQueue.main)
        self.xmppPubSub.activate(self.xmppStream)
        
        self.xmppReconnect.addDelegate(self, delegateQueue: DispatchQueue.main)
        self.xmppReconnect.activate(self.xmppStream)
        self.xmppReconnect.autoReconnect = true
        
//        self.xmppPing.respondsToQueries = true
        self.xmppPing.addDelegate(self, delegateQueue: DispatchQueue.main)
        self.xmppPing.activate(self.xmppStream)
        
//        self.xmppAutoPing.addDelegate(self, delegateQueue: DispatchQueue.main)
//        self.xmppAutoPing.activate(self.xmppStream)
//        self.xmppAutoPing.pingInterval = 5
//        self.xmppAutoPing.pingTimeout = 5

        self.allowedToConnect = userData.isLoggedIn
        if self.allowedToConnect {
            self.connect()
        }

        ///TODO: consider doing the same for didLogIn.
        self.cancellableSet.insert(
            self.userData.didLogOff.sink(receiveValue: {
                DDLogInfo("XMPPController: got didLogOff, disconnecting")
                self.isConnectedToServer = false
                self.xmppStream.disconnect()
                self.allowedToConnect = false
            })
        )
    }

    /* we do our own manual connection timeout as the xmppStream.connect timeout is not working */
    func connect() {
        // Reconfigure credentials
        
        self.userJID = XMPPJID(user: self.userData.userId, domain: "s.halloapp.net", resource: "iphone")

        self.xmppStream.hostName = self.userData.hostName
        self.xmppStream.myJID = self.userJID

        do {
            DDLogInfo("Connecting")
//            self.metaData.setIsOffline(value: true)
            
            self.isConnecting.send("isConnecting")
            self.isConnectedToServer = false
            try xmppStream.connect(withTimeout: XMPPStreamTimeoutNone)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if !self.isConnectedToServer && self.allowedToConnect {
                    self.connect()
                }
            }
    
        } catch {
            /* this never fires, probably bug with xmppframework */
            DDLogError("connection failed after WillConnect (spotty internet)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if !self.isConnectedToServer && self.allowedToConnect {
                    self.connect()
                }
            }
        }
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
        set(newToken) {
            if newToken != nil {
                UserDefaults.standard.set(newToken, forKey: XMPPController.apnsTokenUserDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: XMPPController.apnsTokenUserDefaultsKey)
            }
        }
    }

    public func sendCurrentAPNSTokenIfPossible() {
        if self.xmppStream.isAuthenticated {
            self.sendCurrentAPNSToken()
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
}


extension XMPPController: XMPPStreamDelegate {
    
    func xmppStream(_ sender: XMPPStream, didReceive message: XMPPMessage) {
        guard message.fromStr ?? "" != "pubsub.s.halloapp.net" else {
            // PubSub messages are handled separately.
            return
        }

        DDLogInfo("xmpp/message/incoming id=[\(message.elementID ?? "")]")

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
        
        // TODO: do not set ack for pubsub messages - that must be done in pubsub message handler, after processing of a message is complete.
        self.sendAck(for: message)
    }
    
    func xmppStream(_ sender: XMPPStream, didReceive iq: XMPPIQ) -> Bool {
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
        DDLogInfo("Stream: WillConnect")
    }
    
    func xmppStreamConnectDidTimeout(_ stream: XMPPStream) {
        DDLogInfo("Stream: DidTimeout")
    }
    
    func xmppStream(_ sender: XMPPStream, socketDidConnect socket: GCDAsyncSocket) {
        DDLogInfo("Stream: SocketDidConnect")
    }
    
    func xmppStreamDidStartNegotiation(_ sender: XMPPStream) {
        DDLogInfo("Stream: Start Negotiation")
    }
    
    func xmppStream(_ sender: XMPPStream, willSecureWithSettings settings: NSMutableDictionary) {
        DDLogInfo("Stream: willSecureWithSettings")
        settings.setObject(true, forKey:GCDAsyncSocketManuallyEvaluateTrust as NSCopying)
    }

    func xmppStream(_ sender: XMPPStream, didReceive trust: SecTrust, completionHandler: ((Bool) -> Void)) {
        DDLogInfo("Stream: didReceive trust")

//        let certificate = SecTrustGetCertificateAtIndex(trust, 0)
//        var cn: CFString?
//        SecCertificateCopyCommonName(certificate!, &cn)
//        print(cn)
        
        let result = SecTrustEvaluateWithError(trust, nil)
        
        if result {
            completionHandler(true)
        } else {
            //todo: handle gracefully and reflect in global state
            completionHandler(false)
        }
    }
    
    func xmppStreamDidSecure(_ sender: XMPPStream) {
        DDLogInfo("Stream: xmppStreamDidSecure")
    }
    
    func xmppStreamDidConnect(_ stream: XMPPStream) {
        DDLogInfo("Stream: Connected")
        
        try! stream.authenticate(withPassword: self.userData.password)
    }

    func xmppStreamDidDisconnect(_ stream: XMPPStream) {
        DDLogInfo("Stream: disconnect")

        self.cancelAllRequests()
    }
    
    func xmppStreamDidRegister(_ sender: XMPPStream) {
        DDLogInfo("Stream Did Register")
    }
    
    func xmppStreamDidAuthenticate(_ sender: XMPPStream) {
        DDLogInfo("Stream: Authenticated")
        
        self.isConnectedToServer = true
        self.didConnect.send("didConnect")
        
        if self.hasValidAPNSPushToken {
            self.sendCurrentAPNSToken()
        }
        
        // This function sends an initial presence stanza to the server indicating that the user is online.
        // This is necessary so that the server will then respond with all the offline messages for the client.
        // stanza: <presence />
        self.xmppStream.send(XMPPPresence())

        self.resendAllPendingRequests()

        self.resendAllPendingReceipts()
    }
    
    func xmppStream(_ sender: XMPPStream, didNotAuthenticate error: DDXMLElement) {
        DDLogInfo("Stream: Fail to Authenticate")
        self.userData.logout()
    }
    
    func xmppStream(_ sender: XMPPStream, didReceiveError error: DDXMLElement) {
        DDLogInfo("Stream: error \(error)")
        
        if error.element(forName: "conflict") != nil {
            
            if let text = error.element(forName: "text") {
            
                if let value = text.stringValue {
                    if value == "User removed" {
                        DDLogInfo("Stream: Same user logged into another device, logging out of this one")
                        self.userData.logout()
                    }
                }
                
            }
            
        }
        
    }

    func xmppStream(_ sender: XMPPStream, didNotRegister error: DDXMLElement) {
        DDLogInfo("Stream: didNotRegister: \(error)")
    }
    
    func xmppStream(_ sender: XMPPStream, didSendCustomElement element: DDXMLElement) {
//        DDLogInfo("Stream: didSendCustomElement: \(element)")
    }

    func xmppStream(_ sender: XMPPStream, didReceiveCustomElement element: DDXMLElement) {
//        DDLogInfo("Stream: didReceiveCustomElement: \(element)")
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
        DDLogInfo("xmppReconnect: didDetectAccidentalDisconnect")
    }

    public func xmppReconnect(_ sender: XMPPReconnect, shouldAttemptAutoReconnect connectionFlags: SCNetworkConnectionFlags) -> Bool {
        DDLogInfo("xmppReconnect: shouldAttemptAutoReconnect")
        self.isConnecting.send("isConnecting")
        return true
    }
}

extension XMPPController: XMPPPingDelegate {

    public func xmppPing(_ sender: XMPPPing!, didReceivePong pong: XMPPIQ!, withRTT rtt: TimeInterval) {
        DDLogInfo("Ping: didReceivePong")
    }

    public func xmppPing(_ sender: XMPPPing!, didNotReceivePong pingID: String!, dueToTimeout timeout: TimeInterval) {
        DDLogInfo("Ping: didNotReceivePong")
    }
}

extension XMPPController: XMPPPubSubDelegate {

    func xmppPubSub(_ sender: XMPPPubSub, didRetrieveItems iq: XMPPIQ, fromNode node: String) {
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
