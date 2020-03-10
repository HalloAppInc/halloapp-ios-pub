//
//  Jab.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/7/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

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
    var didGetNewContactsItem = PassthroughSubject<XMPPMessage, Never>()

    var didGetFeedItems = PassthroughSubject<XMPPIQ, Never>()
    var didGetContactsItems = PassthroughSubject<XMPPIQ, Never>()
    
    var didGetOwnAffiliations = PassthroughSubject<XMPPIQ, Never>() // all of the user's own affiliations
    var didGetAllAffiliations = PassthroughSubject<XMPPIQ, Never>() // all the affiliations that others have the user on
    
    var didGetNormBatch = PassthroughSubject<XMPPIQ, Never>()
    var didGetAffContactsBatch = PassthroughSubject<XMPPIQ, Never>()
    var didGetAffFeedBatch = PassthroughSubject<XMPPIQ, Never>()
    
    var didGetUploadUrl = PassthroughSubject<XMPPIQ, Never>()
    
    var didSubscribeToContact = PassthroughSubject<String, Never>()
    var didNotSubscribeToContact = PassthroughSubject<String, Never>()
    
    var didGetSubscriptions = PassthroughSubject<XMPPIQ, Never>()
    
    var xmppStream: XMPPStream
    var xmppPubSub: XMPPPubSub
    var xmppReconnect: XMPPReconnect
    var xmppPing: XMPPPing
    
//    var xmppAutoPing: XMPPAutoPing

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
                self.userData.log("XMPPController: got didLogOff, disconnecting")
                self.isConnectedToServer = false
                self.xmppStream.disconnect()
                self.allowedToConnect = false
            })
        )
    }

    /* we do our own manual connection timeout as the xmppStream.connect timeout is not working */
    func connect() {
        // Reconfigure credentials
        let user = "\(self.userData.phone)@s.halloapp.net/iphone"
        self.userJID = XMPPJID(string: user)

        self.xmppStream.hostName = self.userData.hostName
        self.xmppStream.myJID = self.userJID

        do {
            self.userData.log("Connecting")
//            self.metaData.setIsOffline(value: true)
            
            self.isConnecting.send("isConnecting")
            self.isConnectedToServer = false
            try xmppStream.connect(withTimeout: XMPPStreamTimeoutNone)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if !self.isConnectedToServer {
                    self.connect()
                }
            }
    
        } catch {
            /* this never fires, probably bug with xmppframework */
            self.userData.log("connection failed after WillConnect (spotty internet)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if !self.isConnectedToServer {
                    self.connect()
                }
            }
        }
    }
    
    func sendApnsPushTokenFromUserDefault() {
        let userDefault = UserDefaults.standard
        let tokenStr = userDefault.string(forKey: "apnsPushToken")

        let pushToken = XMLElement(name: "push_token")
        pushToken.addAttribute(withName: "os", stringValue: "ios")
        pushToken.stringValue = tokenStr

        let pushRegister = XMLElement(name: "push_register")
        pushRegister.addAttribute(withName: "xmlns", stringValue: "halloapp:push:notifications")
        pushRegister.addChild(pushToken)

        let iq = XMLElement(name: "iq")
        iq.addAttribute(withName: "type", stringValue: "set")
        iq.addAttribute(withName: "from", stringValue: "\(self.userData.phone)@s.halloapp.net/iphone")
        iq.addAttribute(withName: "to", stringValue: "s.halloapp.net")
        iq.addAttribute(withName: "id", stringValue: "apnsPushToken")

        iq.addChild(pushRegister)

//        self.userData.log("sending the iq with push token here. \(iq)")
        self.userData.log("Notifications: Sending Push Token")
        self.xmppStream.send(iq)
    }
    
    func createNodes() {
        var node = ""
        if let userJID = self.userJID {
            node = userJID.user!
        }

        let nodeOptions: [String:String] = [
            "pubsub#access_model": "whitelist",
            "pubsub#send_last_published_item": "never",
            "pubsub#max_items": "1000", // must not go over max or else error
            "pubsub#notify_retract": "0",
            "pubsub#notify_delete": "0",
            "pubsub#notification_type": "normal" // Updating the notification type to be normal, so that feed updates could be stored by the server when offline.
        ]

        var contactsNodeOptions = nodeOptions
        contactsNodeOptions.merge(["pubsub#max_items": "3"]) { (current, new) -> String in
            return new
        }
        
        if (!self.userData.haveContactsSub) {
            print("creating contacts node")
            self.xmppPubSub.createNode("contacts-\(node)", withOptions: nodeOptions)
            Utils().sendAff(xmppStream: self.xmppStream, node: "contacts-\(self.userData.phone)", from: "\(self.userData.phone)", user: self.userData.phone, role: "owner")
            self.xmppPubSub.subscribe(toNode: "contacts-\(self.userData.phone)")
        }
        
        var feedNodeOptions = nodeOptions
        feedNodeOptions.merge(["pubsub#publish_model": "subscribers"]) { (current, new) -> String in
            return new
        }
        
        if (!self.userData.haveFeedSub) {
            print("creating feed node: feed-\(node)")
            self.xmppPubSub.createNode("feed-\(node)", withOptions: feedNodeOptions)
            Utils().sendAff(xmppStream: self.xmppStream, node: "feed-\(self.userData.phone)", from: "\(self.userData.phone)", user: self.userData.phone, role: "owner")
            self.xmppPubSub.subscribe(toNode: "feed-\(self.userData.phone)")
            self.xmppPubSub.retrieveItems(fromNode: "feed-\(self.userData.phone)") // if the user logs off, then logs back in
        }
        
//        self.xmppPubSub.configureNode("feed-\(node)", withOptions: feedNodeOptions)
//        self.xmppPubSub.configureNode("contacts-\(node)", withOptions: nodeOptions)
        
        
        /* see node metadata */
//        let query = XMLElement(name: "query")
//        query.addAttribute(withName: "xmlns", stringValue: "http://jabber.org/protocol/disco#info")
//        query.addAttribute(withName: "node", stringValue: "feed-\(userData.phone)")
//
//        let iq = XMLElement(name: "iq")
//        iq.addAttribute(withName: "type", stringValue: "get")
//        iq.addAttribute(withName: "from", stringValue: "\(userData.phone)@s.halloapp.net/iphone")
//        iq.addAttribute(withName: "to", stringValue: "pubsub.s.halloapp.net")
//        iq.addAttribute(withName: "id", stringValue: "3")
//        iq.addChild(query)

//        self.xmppStream.send(iq)
        
        /* see configuration */
//        let configure = XMLElement(name: "configure")
//        configure.addAttribute(withName: "node", stringValue: "feed-\(userData.phone)")
//
//        let pubsub = XMLElement(name: "pubsub")
//        pubsub.addAttribute(withName: "xmlns", stringValue: "http://jabber.org/protocol/pubsub#owner")
//        pubsub.addChild(configure)
//
//        let iq = XMLElement(name: "iq")
//        iq.addAttribute(withName: "type", stringValue: "get")
//        iq.addAttribute(withName: "from", stringValue: "\(userData.phone)@s.halloapp.net/iphone")
//        iq.addAttribute(withName: "to", stringValue: "pubsub.s.halloapp.net")
//        iq.addAttribute(withName: "id", stringValue: "3")
//        iq.addChild(pubsub)
//
//        self.xmppStream.send(iq)

    }
}


extension XMPPController: XMPPStreamDelegate {
    
    func xmppStream(_ sender: XMPPStream, didReceive message: XMPPMessage) {
        self.userData.log("Stream: didReceive message \(message)")
        if (message.fromStr! != "pubsub.s.halloapp.net") {
            self.userData.log("Stream: didReceive \(message)")
        }
    }
    
    func xmppStream(_ sender: XMPPStream, didReceive iq: XMPPIQ) -> Bool {
//        self.userData.log("Stream: didReceive iq \(iq)")
        
        if (iq.fromStr! == "pubsub.s.halloapp.net") {

            let pubsub = iq.element(forName: "pubsub")
            
            let affiliations = pubsub?.element(forName: "affiliations")
            if affiliations != nil {
//                print("Stream: didReceive \(iq)")
                
                let node = affiliations?.attributeStringValue(forName: "node")
                
                if node != nil && (node == "contacts-\(self.userData.phone)" || node == "feed-\(self.userData.phone)") {
                    self.didGetOwnAffiliations.send(iq)
                } else {
                    self.didGetAllAffiliations.send(iq)
                }
                return false
            }
            
            let subscriptions = pubsub?.element(forName: "subscriptions")
            if subscriptions != nil {
                return false
            }
            
            let items = pubsub?.element(forName: "items")
            if items != nil {
                return false
            }
            
//            self.userData.log("Stream: didReceive \(iq)")
            
            if let idParts = iq.elementID?.components(separatedBy: "-") {
                if (idParts[0] == "batchAff") {
                    self.didGetAffContactsBatch.send(iq) // for batch affiliations
                } else if (idParts[0] == "batchAffFeed") {
                    self.didGetAffFeedBatch.send(iq) // for batch affiliations
                }
            }
            

        } else {
        
            let contactList = iq.element(forName: "contact_list")
            
            let uploadMedia = iq.element(forName: "upload_media")
            
            if contactList != nil {
                
                self.didGetNormBatch.send(iq)
                
            } else if uploadMedia != nil {
                
                self.didGetUploadUrl.send(iq)
                
            } else {
//                self.userData.log("Stream: didReceive \(iq)")
            }
        }

        
        return false
    }
    
    func xmppStreamWillConnect(_ sender: XMPPStream) {
        self.userData.log("Stream: WillConnect")
    }
    
    func xmppStreamConnectDidTimeout(_ stream: XMPPStream) {
        self.userData.log("Stream: DidTimeout")
    }
    
    func xmppStream(_ sender: XMPPStream, socketDidConnect socket: GCDAsyncSocket) {
        self.userData.log("Stream: SocketDidConnect")
    }
    
    func xmppStreamDidStartNegotiation(_ sender: XMPPStream) {
        self.userData.log("Stream: Start Negotiation")
    }
    
    /* ssl */
    func xmppStream(_ sender: XMPPStream, willSecureWithSettings settings: NSMutableDictionary) {
        self.userData.log("Stream: willSecureWithSettings")
        settings.setObject(true, forKey:GCDAsyncSocketManuallyEvaluateTrust as NSCopying)
    }

    func xmppStream(_ sender: XMPPStream, didReceive trust: SecTrust, completionHandler: ((Bool) -> Void)) {
        self.userData.log("Stream: didReceive trust")

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
        self.userData.log("Stream: xmppStreamDidSecure")
    }
    
    func xmppStreamDidConnect(_ stream: XMPPStream) {
        self.userData.log("Stream: Connected")
        
        try! stream.authenticate(withPassword: self.userData.password)
    }

    func xmppStreamDidDisconnect(_ stream: XMPPStream) {
        self.userData.log("Stream: disconnect")
    }
    
    func xmppStreamDidRegister(_ sender: XMPPStream) {
        self.userData.log("Stream Did Register")
    }
    
    func xmppStreamDidAuthenticate(_ sender: XMPPStream) {
        self.userData.log("Stream: Authenticated")
        
        self.isConnectedToServer = true
        self.didConnect.send("didConnect")
        
        #if targetEnvironment(simulator)
            // Simulator
        #else
            self.sendApnsPushTokenFromUserDefault()
        #endif
        
        self.createNodes()

        // This function sends an initial presence stanza to the server indicating that the user is online.
        // This is necessary so that the server will then respond with all the offline messages for the client.
        // stanza: <presence />
        self.xmppStream.send(XMPPPresence())
    }
    
    func xmppStream(_ sender: XMPPStream, didNotAuthenticate error: DDXMLElement) {
        self.userData.log("Stream: Fail to Authenticate")
        self.userData.logout()
    }
    
    func xmppStream(_ sender: XMPPStream, didReceiveError error: DDXMLElement) {
        self.userData.log("Stream: error \(error)")
        
        if error.element(forName: "conflict") != nil {
            
            if let text = error.element(forName: "text") {
            
                if let value = text.stringValue {
                    if value == "User removed" {
                        self.userData.log("Stream: Same user logged into another device, logging out of this one")
                        self.userData.logout()
                    }
                }
                
            }
            
        }
        
    }

    func xmppStream(_ sender: XMPPStream, didNotRegister error: DDXMLElement) {
        self.userData.log("Stream: didNotRegister: \(error)")
    }
    
    func xmppStream(_ sender: XMPPStream, didSend message: XMPPMessage) {
//        self.userData.log("Stream: didSendMessage: \(message)")
    }
    
    func xmppStream(_ sender: XMPPStream, didSend iq: XMPPIQ) {
//        self.userData.log("Stream: didSendIQ: \(iq)")
    }
    
}

extension XMPPController: XMPPReconnectDelegate {
    public func xmppReconnect(_ sender: XMPPReconnect, didDetectAccidentalDisconnect connectionFlags: SCNetworkConnectionFlags) {
        self.userData.log("xmppReconnect: didDetectAccidentalDisconnect")
    }
    public func xmppReconnect(_ sender: XMPPReconnect, shouldAttemptAutoReconnect connectionFlags: SCNetworkConnectionFlags) -> Bool {
        self.userData.log("xmppReconnect: shouldAttemptAutoReconnect")
        self.isConnecting.send("isConnecting")
        return true
    }
}

extension XMPPController: XMPPPingDelegate {

    public func xmppPing(_ sender: XMPPPing!, didReceivePong pong: XMPPIQ!, withRTT rtt: TimeInterval) {
        self.userData.log("Ping: didReceivePong")
    }

    public func xmppPing(_ sender: XMPPPing!, didNotReceivePong pingID: String!, dueToTimeout timeout: TimeInterval) {
        self.userData.log("Ping: didNotReceivePong")
    }

}

//extension XMPPController: XMPPAutoPingDelegate {
//
//    public func xmppAutoPingDidSend(_ sender: XMPPAutoPing) {
//        self.userData.log("xmppAutoPingDidSendPing")
//    }
//
//    public func xmppAutoPingDidReceivePong(_ sender: XMPPAutoPing) {
//        self.userData.log("xmppAutoPingDidReceivePong")
//    }
//
//    public func xmppAutoPingDidTimeout(_ sender: XMPPAutoPing) {
//        self.userData.log("xmppAutoPingDidTimeout")
//    }
//
//}

extension XMPPController: XMPPPubSubDelegate {

    func xmppPubSub(_ sender: XMPPPubSub, didRetrieveSubscriptions iq: XMPPIQ) {
//        self.userData.log("PubSub: didRetrieveSubscriptions - \(iq)")
        self.didGetSubscriptions.send(iq)
        
    }

//    func xmppPubSub(_ sender: XMPPPubSub, didNotRetrieveSubscriptions iq: XMPPIQ) {
//        self.userData.log("PubSub: didNotRetrieveSubscriptions - \(iq)")
//    }
    
    func xmppPubSub(_ sender: XMPPPubSub, didSubscribeToNode node: String, withResult iq: XMPPIQ) {
        self.userData.log("PubSub: didSubscribeToNode - \(node)")
        
        if (node == "contacts-\(self.userData.phone)") {
            self.userData.setHaveContactsSub(value: true)
        } else if (node == "feed-\(self.userData.phone)") {
            self.userData.setHaveFeedSub(value: true)
        } else {
            let nodeParts = node.components(separatedBy: "-")

            if (nodeParts[0] == "contacts") {
                self.didSubscribeToContact.send(nodeParts[1])
            }
            
            let idx = self.metaData.checkIds.firstIndex(where: {$0 == node})
            
            if (idx != nil) {
                
                let miniElapsed = Date().timeIntervalSince1970 - self.metaData.timeStartCheck
                print("\(self.metaData.checkIds[idx!]) perf: \(Int(miniElapsed))")
                
                self.metaData.checkIds.remove(at: idx!)
                
                if self.metaData.checkIds.count == 0 {
                    let timeElapsed = Date().timeIntervalSince1970 - self.metaData.timeStartCheck
                    print("total perf: \(Int(timeElapsed)/60)")
                }
            }
            
            
        }
        
    }
    
    func xmppPubSub(_ sender: XMPPPubSub, didNotSubscribeToNode node: String, withError iq: XMPPIQ) {
        self.userData.log("PubSub: didNotSubscribeToNode - \(node)")
        
        let nodeParts = node.components(separatedBy: "-")

        if (nodeParts[0] == "contacts") {
            self.didNotSubscribeToContact.send(nodeParts[1])
        }
        
        let idx = self.metaData.checkIds.firstIndex(where: {$0 == node})
        
        if (idx != nil) {
            
            let miniElapsed = Date().timeIntervalSince1970 - self.metaData.timeStartCheck
            print("\(self.metaData.checkIds[idx!]) perf: \(Int(miniElapsed))")
            
            self.metaData.checkIds.remove(at: idx!)
            
            if self.metaData.checkIds.count == 0 {
                let timeElapsed = Date().timeIntervalSince1970 - self.metaData.timeStartCheck
                print("total perf: \(Int(timeElapsed)/60)")
            }
        }
        
    }
    
//    func xmppPubSub(_ sender: XMPPPubSub, didCreateNode node: String, withResult iq: XMPPIQ) {
//        self.userData.log("PubSub: didCreateNode - \(iq)")
//    }
    
//    func xmppPubSub(_ sender: XMPPPubSub, didNotCreateNode node: String, withError iq: XMPPIQ) {
//        self.userData.log("PubSub: didNotCreateNode - \(iq)")
//    }
        
    func xmppPubSub(_ sender: XMPPPubSub, didRetrieveItems iq: XMPPIQ, fromNode node: String) {
//        self.userData.log("PubSub: didRetrieveItems - \(iq)")
        
        let pubsub = iq.element(forName: "pubsub")
        let items = pubsub?.element(forName: "items")
        
        if let node = items?.attributeStringValue(forName: "node") {
        
            let nodeParts = node.components(separatedBy: "-")
            
            if nodeParts.count > 0 {
                if (nodeParts[0] == "feed") {
                    self.didGetFeedItems.send(iq)
                } else if (nodeParts[0] == "contacts") {
                    self.didGetContactsItems.send(iq)
                }
            }
        }
        
    }
    
//    func xmppPubSub(_ sender: XMPPPubSub, didNotRetrieveItems iq: XMPPIQ, fromNode node: String) {
//        self.userData.log("PubSub: didNotRetrieveItems - \(iq)")
//    }

    func xmppPubSub(_ sender: XMPPPubSub, didReceive message: XMPPMessage) {

        self.userData.log("PubSub: didReceiveMessage \(message)")

        let event = message.element(forName: "event")
        let items = event?.element(forName: "items")
        
        if (event?.element(forName: "delete")) != nil {
            if let id = message.elementID {
                //todo: eating the deletes for now
                Utils().sendAck(xmppStream: self.xmppStream, id: id, from: self.userData.phone)
            }
        }
        
        if let node = items?.attributeStringValue(forName: "node") {

            let nodeParts = node.components(separatedBy: "-")
            
            if nodeParts.count > 0 {
                if (nodeParts[0] == "feed") {
                    self.didGetNewFeedItem.send(message)
                } else if (nodeParts[0] == "contacts") {
                    self.didGetNewContactsItem.send(message)
                }
            }
            
        }
        
    }
            
}
