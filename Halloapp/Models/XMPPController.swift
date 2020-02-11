//
//  Jab.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/7/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation
import XMPPFramework
import SwiftUI
import CoreData
import Combine

enum XMPPControllerError: Error {
    case wrongUserJID
}

class XMPPController: NSObject, ObservableObject {
    
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

    var userJID: XMPPJID?
    var hostPort: UInt16 = 5222

    var userData: UserData
    var metaData: MetaData
        
    init(userData: UserData, metaData: MetaData) throws {
        
        self.userData = userData
        self.metaData = metaData
        
        let user = "\(self.userData.phone)@s.halloapp.net/iphone"
        
        self.userJID = XMPPJID(string: user)

        // Stream Configuration
        self.xmppStream = XMPPStream()
        self.xmppStream.hostName = self.userData.hostName
        self.xmppStream.hostPort = hostPort
        self.xmppStream.myJID = self.userJID
        
        /* probably should be "required" once all servers including test servers are secured */
        self.xmppStream.startTLSPolicy = XMPPStreamStartTLSPolicy.preferred
        
//        self.xmppStream.keepAliveInterval = 0.5;
        
        try self.xmppStream.connect(withTimeout: XMPPStreamTimeoutNone)

        let pubsubId = XMPPJID(string: "pubsub.s.halloapp.net")
        self.xmppPubSub = XMPPPubSub(serviceJID: pubsubId)
        
        self.xmppReconnect = XMPPReconnect()
        
        super.init()

        self.xmppStream.addDelegate(self, delegateQueue: DispatchQueue.main)
        
        self.xmppPubSub.addDelegate(self, delegateQueue: DispatchQueue.main)
        self.xmppPubSub.activate(self.xmppStream)
        
        self.xmppReconnect.addDelegate(self, delegateQueue: DispatchQueue.main)
        self.xmppReconnect.activate(self.xmppStream)
        self.xmppReconnect.autoReconnect = true

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

//        print ("sending the iq with push token here. \(iq)")
        print ("sending the iq with push token here.")
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
        if (message.fromStr! != "pubsub.s.halloapp.net") {
//            print("Stream: didReceive \(message)")
        }
        
    }
    
    func xmppStream(_ sender: XMPPStream, didReceive iq: XMPPIQ) -> Bool {

        if (iq.fromStr! == "pubsub.s.halloapp.net") {

            let pubsub = iq.element(forName: "pubsub")
            
            let affiliations = pubsub?.element(forName: "affiliations")
            if affiliations != nil {
//                print("Stream: didReceive \(iq)")
                
                let node = affiliations?.attributeStringValue(forName: "node")
                
                if node != nil && node == "contacts-\(self.userData.phone)" {
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
            
//            print("Stream: didReceive \(iq)")
            
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
            
//                print("Stream: didReceive \(iq)")
            }
        }
        
//        let idx = self.metaData.whiteListIds.firstIndex(where: {$0 == iq.elementID})
//
//        if (idx != nil) {
//
//
//            let miniElapsed = Date().timeIntervalSince1970 - self.metaData.timeStartWhitelist
//            print("\(self.metaData.whiteListIds[idx!]) perf: \(Int(miniElapsed))")
//
//            self.metaData.whiteListIds.remove(at: idx!)
//
//            if self.metaData.whiteListIds.count == 0 {
//                let timeElapsed = Date().timeIntervalSince1970 - self.metaData.timeStartWhitelist
//                print("total perf: \(Int(timeElapsed)/60)")
//            }
//        }
        
        return false
    }
    
    func xmppStreamWillConnect(_ sender: XMPPStream) {
        print("Stream: WillConnect")
    }
    
    func xmppStream(_ sender: XMPPStream, socketDidConnect socket: GCDAsyncSocket) {
        print("Stream: SocketDidConnect")
    }
    
    func xmppStreamDidStartNegotiation(_ sender: XMPPStream) {
        print("Stream: Start Negotiation")
    }
    
    /* ssl */
    func xmppStream(_ sender: XMPPStream, willSecureWithSettings settings: NSMutableDictionary) {
        print("Stream: willSecureWithSettings")
        settings.setObject(true, forKey:GCDAsyncSocketManuallyEvaluateTrust as NSCopying)
    }

    func xmppStream(_ sender: XMPPStream, didReceive trust: SecTrust, completionHandler: ((Bool) -> Void)) {
//        print("Stream: didReceive trust")

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
        print("Stream: xmppStreamDidSecure")
    }
    
    func xmppStreamDidConnect(_ stream: XMPPStream) {
        print("Stream: Connected")
//        self.userData.setIsOffline(value: false)
        
        try! stream.authenticate(withPassword: self.userData.password)
    }

    func xmppStreamDidDisconnect(_ stream: XMPPStream) {
        print("Stream: disconnect")
    }
    
    func xmppStreamConnectDidTimeout(_ stream: XMPPStream) {
        print("Stream: timeout")
    }
    
    func xmppStreamDidRegister(_ sender: XMPPStream) {
        print("Stream Did Register")
    }
    
    func xmppStreamDidAuthenticate(_ sender: XMPPStream) {
        print("Stream: Authenticated")
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
        print("Stream: Fail to Authenticate")
        self.userData.logout()
        
    }
    
    func xmppStream(_ sender: XMPPStream, didReceiveError error: DDXMLElement) {
        print("Stream: error \(error)")
    }

    func xmppStream(_ sender: XMPPStream, didNotRegister error: DDXMLElement) {
        print("Stream: didNotRegister: \(error)")
    }
    
}

extension XMPPReconnect: XMPPReconnectDelegate {
    public func xmppReconnect(_ sender: XMPPReconnect, didDetectAccidentalDisconnect connectionFlags: SCNetworkConnectionFlags) {
        print("xmppReconnect: didDetectAccidentalDisconnect")
    }
    public func xmppReconnect(_ sender: XMPPReconnect, shouldAttemptAutoReconnect connectionFlags: SCNetworkConnectionFlags) -> Bool {
        print("xmppReconnect: shouldAttemptAutoReconnect")
        return true
    }
}

extension XMPPController: XMPPPubSubDelegate {

    func xmppPubSub(_ sender: XMPPPubSub, didRetrieveSubscriptions iq: XMPPIQ) {
//        print("PubSub: didRetrieveSubscriptions - \(iq)")
        self.didGetSubscriptions.send(iq)
        
    }

//    func xmppPubSub(_ sender: XMPPPubSub, didNotRetrieveSubscriptions iq: XMPPIQ) {
//        print("PubSub: didNotRetrieveSubscriptions - \(iq)")
//    }
    
    func xmppPubSub(_ sender: XMPPPubSub, didSubscribeToNode node: String, withResult iq: XMPPIQ) {
        print("PubSub: didSubscribeToNode - \(node)")
        
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
        print("PubSub: didNotSubscribeToNode - \(node)")
        
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
//        print("PubSub: didCreateNode - \(iq)")
//    }
    
//    func xmppPubSub(_ sender: XMPPPubSub, didNotCreateNode node: String, withError iq: XMPPIQ) {
//        print("PubSub: didNotCreateNode - \(iq)")
//    }
        
    func xmppPubSub(_ sender: XMPPPubSub, didRetrieveItems iq: XMPPIQ, fromNode node: String) {
//        print("PubSub: didRetrieveItems - \(iq)")
        
        let pubsub = iq.element(forName: "pubsub")
        let items = pubsub?.element(forName: "items")
        let node = items?.attributeStringValue(forName: "node")
        
        let nodeParts = node!.components(separatedBy: "-")
        
        if (nodeParts[0] == "feed") {
            self.didGetFeedItems.send(iq)
        } else if (nodeParts[0] == "contacts") {
            self.didGetContactsItems.send(iq)
        }
        
    }
    
//    func xmppPubSub(_ sender: XMPPPubSub, didNotRetrieveItems iq: XMPPIQ, fromNode node: String) {
//        print("PubSub: didNotRetrieveItems - \(iq)")
//    }

    func xmppPubSub(_ sender: XMPPPubSub, didReceive message: XMPPMessage) {
        print("PubSub: didReceiveMessage - \(message)")
        

        let event = message.element(forName: "event")
        let items = event?.element(forName: "items")
        let node = items?.attributeStringValue(forName: "node")
        
        let nodeParts = node!.components(separatedBy: "-")
        
        if (nodeParts[0] == "feed") {
            self.didGetNewFeedItem.send(message)
        } else if (nodeParts[0] == "contacts") {
            self.didGetNewContactsItem.send(message)
        }
        
    }
            
}
