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
    
    var didChangeMessage = PassthroughSubject<XMPPMessage, Never>()
    
//    @EnvironmentObject var feedModel: FeedModel
    
    var xmppStream: XMPPStream

//    let xmppRosterStorage = XMPPRosterCoreDataStorage()
//    var xmppRoster: XMPPRoster

    var xmppPubSub: XMPPPubSub
    
    var hostName = "d.halloapp.dev"
    var userJID: XMPPJID?
    var hostPort: UInt16 = 5222
    var password: String?

    init(user: String, password: String) throws {
        
        
        guard let userJID = XMPPJID(string: user) else {
            print("guard error")
            throw XMPPControllerError.wrongUserJID
        }

//        self.hostName = hostName
        self.userJID = userJID
//        self.hostPort = hostPort
        self.password = password

        // Stream Configuration
        self.xmppStream = XMPPStream()
        self.xmppStream.hostName = hostName
        self.xmppStream.hostPort = hostPort
        self.xmppStream.startTLSPolicy = XMPPStreamStartTLSPolicy.allowed
        self.xmppStream.myJID = userJID
        
        try self.xmppStream.connect(withTimeout: XMPPStreamTimeoutNone)
        
//        self.xmppRoster = XMPPRoster(rosterStorage: xmppRosterStorage)

        let pubsubId = XMPPJID(string: "pubsub.s.halloapp.net")
        self.xmppPubSub = XMPPPubSub(serviceJID: pubsubId)
        
        
        super.init()

        self.xmppStream.addDelegate(self, delegateQueue: DispatchQueue.main)
        
        self.xmppPubSub.activate(self.xmppStream)
        self.xmppPubSub.addDelegate(self, delegateQueue: DispatchQueue.main)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
//            self.xmppPubSub.createNode("1111")
            self.xmppPubSub.subscribe(toNode: "2222")
            
//            let summary = XMLElement(name: "summary", stringValue: "How is the weather?")
//            let root = XMLElement(name: "entry")
//            root.addChild(summary)
//            self.xmppPubSub.publish(toNode: "2222", entry: root)
            
        }
        
//        print(self.xmppPubSub.serviceJID)
        
        self.xmppPubSub.retrieveSubscriptions()
        
        
//        self.xmppRoster.activate(self.xmppStream)
//        self.xmppRoster.addDelegate(self, delegateQueue: DispatchQueue.main)
        
//        self.xmppRoster.addUser(<#T##jid: XMPPJID##XMPPJID#>, withNickname: <#T##String?#>)
        
        
        /* Configure Node */
//        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
//
//            let options: [String:String] = [
//                "pubsub#access_model": "whitelist"
//            ]
//
//
//
//            self.xmppPubSub.configureNode("1111", withOptions: options)
//
//
//        }
    }
    
    
//    func connect() {
//       
//        do {
//            // Stream Configuration
//            self.xmppStream = XMPPStream()
//            self.xmppStream.hostName = hostName
//            self.xmppStream.hostPort = hostPort
//            
//            
//            print("try to connect to xmppStream")
//            print("user: \(self.xmppStream.myJID)")
//            print("host: \(self.xmppStream.hostName)")
//            print("port: \(self.xmppStream.hostPort)")
//            
//            try self.xmppStream.connect(withTimeout: XMPPStreamTimeoutNone)
//        } catch {
//            print("error connecting to xmppStream")
//        }
//        
//    }

//    func createNodes() {
//
//        var node = ""
//        if let userJID = self.userJID {
//            let token = userJID.user!.components(separatedBy: "@")
//            node = token[0]
//        }
//
//        print("creating Nodes: \(node)")
//
//        self.xmppPubSub.createNode("feed-\(node)")
//        self.xmppPubSub.createNode("contacts-\(node)")
//    }

}


extension XMPPController: XMPPStreamDelegate {

    // pubsub
    
    func xmppPubSub(_ sender: XMPPPubSub, didCreateNode node: String, withResult iq: XMPPIQ) {
        print("PubSub: didCreateNode - \(iq)")
    }
    
    func xmppPubSub(_ sender: XMPPPubSub, didNotCreateNode node: String, withResult iq: XMPPIQ) {
        print("PubSub: didNotCreateNode - \(iq)")
    }
    
    func xmppPubSub(_ sender: XMPPPubSub, didRetrieveSubscriptions iq: XMPPIQ) {
        print("PubSub: didCreateNode - \(iq)")
    }
    
    func xmppPubSub(_ sender: XMPPPubSub, didNotRetrieveSubscriptions iq: XMPPIQ) {
        print("PubSub: didNotRetrieveSubscriptions - \(iq)")
    }
    
    func xmppPubSub(_ sender: XMPPPubSub, didReceiveMessage message: XMPPMessage) {
        print("PubSub: didReceiveMessage - \(message)")
        
//         self.feedModel.pushItem(username: "xxx", imageUrl: "", userImageUrl: "", text: "text")
    }
    
    // stream
    
    func xmppStream(_ sender: XMPPStream, didReceive message: XMPPMessage) {
        print("Did received message \(message)")
        self.didChangeMessage.send(message)
//        self.feedModel.pushItem(username: "xxx", imageUrl: "", userImageUrl: "", text: "text")
    }
    
    func xmppStream(_ sender: XMPPStream, didReceive iq: XMPPIQ) -> Bool {
        print("got iq: \(iq)")
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
    
//    func xmppStream(_ sender: XMPPStream, willSecureWithSettings settings: NSMutableDictionary) {
//        print("Stream: willSecureWithSettings")
//        settings.setObject(true, forKey:GCDAsyncSocketManuallyEvaluateTrust as NSCopying)
//    }
//
//    func xmppStream(_ sender: XMPPStream, didReceive trust: SecTrust, completionHandler: ((Bool) -> Void)) {
//        print("Stream: didReceive trust")
//        completionHandler(true)
//    }
    
    func xmppStreamDidConnect(_ stream: XMPPStream) {
        print("Stream: Connected")
        try! stream.authenticate(withPassword: self.password ?? "")
    }

    func xmppStreamDidDisconnect(_ stream: XMPPStream) {
        print("Stream: disconnect")
    }
    
    func xmppStreamConnectDidTimeout(_ stream: XMPPStream) {
        print("Stream: timeout")
    }
    
    func xmppStreamDidAuthenticate(_ sender: XMPPStream) {
        print("Stream: didAuthenticate")
        self.xmppStream.send(XMPPPresence())
        
//        self.createNodes()
        
        print("Stream: Authenticated")
    }
    
    func xmppStream(_ sender: XMPPStream, didReceiveError error: DDXMLElement) {
        print("Stream error")
    }
    
    func xmppStream(_ sender: XMPPStream, didNotAuthenticate error: DDXMLElement) {
        print("Stream: Fail to Authenticate")
    }
    

}

