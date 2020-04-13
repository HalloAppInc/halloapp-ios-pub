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

class XMPPController: NSObject, ObservableObject {
    var allowedToConnect: Bool = false {
        didSet {
            if (self.allowedToConnect) {
                if (!self.isConnectedToServer) {
                    self.connect()
                }
            } else {
                if (self.isConnectedToServer) {
                    self.xmppStream.disconnect()
                }
            }
        }
    }

    var isConnecting = PassthroughSubject<String, Never>()
    var didConnect = PassthroughSubject<String, Never>() // used by UserData to know if user is in or not
    
    var didChangeMessage = PassthroughSubject<XMPPMessage, Never>()
    var didGetNewFeedItem = PassthroughSubject<XMPPMessage, Never>()
    var didGetRetractItem = PassthroughSubject<XMPPMessage, Never>()
    var didGetFeedItems = PassthroughSubject<XMPPIQ, Never>()

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

    init(userData: UserData, metaData: MetaData) {
        
        self.userData = userData
        self.metaData = metaData

        // Stream Configuration
        self.xmppStream = XMPPStream()
        self.xmppStream.hostPort = hostPort
  
        let appVersionNStr:NSString = NSString(string: Utils().appVersion())
        self.xmppStream.clientVersion = appVersionNStr
        
        /* probably should be "required" once all servers including test servers are secured */
        self.xmppStream.startTLSPolicy = XMPPStreamStartTLSPolicy.preferred
        
//        self.xmppStream.keepAliveInterval = 0.5;
        
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
        if (self.allowedToConnect) {
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
        
        var user = "\(self.userData.phone)@s.halloapp.net/iphone"
        
        if self.userData.useNewRegistration {
            user = "\(self.userData.userId)@s.halloapp.net/iphone"
        }
    
        self.userJID = XMPPJID(string: user)

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

    func retrieveFeedData<T: Collection>(for userIds: T) where T.Element == ABContact.UserID {
        guard !userIds.isEmpty else { return }
        userIds.forEach {
            self.xmppPubSub.retrieveItems(fromNode: "feed-\($0)")
        }
    }
}


extension XMPPController: XMPPStreamDelegate {
    
    func xmppStream(_ sender: XMPPStream, didReceive message: XMPPMessage) {
        if message.fromStr! != "pubsub.s.halloapp.net" {
            DDLogInfo("Stream: didReceive \(message)")
        }

        // Notification about new contact on the app
        if let contactList = message.element(forName: "contact_list") {
            AppContext.shared.syncManager.processNotification(contacts: contactList.elements(forName: "contact").compactMap{ XMPPContact($0) })
        }

        // TODO: do not set ack for pubsub messages - that must be done in pubsub message handler, after processing of a message is complete.
        if let id = message.elementID {
            DDLogInfo("Message: Send Ack: id: \(id)")
            Utils().sendAck(xmppStream: self.xmppStream, id: id, from: self.userData.phone)
        }
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
//        DDLogInfo("PubSub: didRetrieveItems - \(iq)")
        let pubsub = iq.element(forName: "pubsub")
        let items = pubsub?.element(forName: "items")
        if let node = items?.attributeStringValue(forName: "node") {
            let nodeParts = node.components(separatedBy: "-")
            if nodeParts.count > 0 {
                if (nodeParts[0] == "feed") {
                    self.didGetFeedItems.send(iq)
                }
            }
        }
    }

    func xmppPubSub(_ sender: XMPPPubSub, didReceive message: XMPPMessage) {

//        DDLogInfo("PubSub: didReceive Message \(message)")

        let event = message.element(forName: "event")
        let items = event?.element(forName: "items")
        
        if (event?.element(forName: "delete")) != nil {
            //todo: eating the deletes for now
            DDLogInfo("eating the deletes for now")
        }
        
        if let node = items?.attributeStringValue(forName: "node") {

            let nodeParts = node.components(separatedBy: "-")
            
            if nodeParts.count > 0 {
                if (nodeParts[0] == "feed") {
                    if items?.element(forName: "retract") != nil {
                        self.didGetRetractItem.send(message)
                    } else {
                        self.didGetNewFeedItem.send(message)
                    }
                } else if (nodeParts[0] == "metadata") {
                    //todo: handle metadata messages before acking them
                    DDLogInfo("eating metadata messages for now")
                }
            }
            
        }
        
        if let id = message.elementID {
            DDLogInfo("Message: Send Ack: id: \(id)")
            Utils().sendAck(xmppStream: self.xmppStream, id: id, from: self.userData.phone)
        }
    }
}
