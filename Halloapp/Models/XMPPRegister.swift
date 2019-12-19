
import Foundation
import XMPPFramework
import SwiftUI
import CoreData
import Combine

class XMPPRegister: NSObject, ObservableObject {
    
    var didConnect = PassthroughSubject<String, Never>()

    var xmppStream: XMPPStream

//    var hostName = "d.halloapp.dev"
    var hostName = "s.halloapp.net" // will be new host
    var userJID: XMPPJID?
    var hostPort: UInt16 = 5222
    var password: String
        
    init(phone: String, password: String) throws {
        
        let user = "\(phone)@s.halloapp.net/iphone"
        
        self.userJID = XMPPJID(string: user)
        
        self.password = password

        // Stream Configuration
        self.xmppStream = XMPPStream()
        self.xmppStream.hostName = hostName
        self.xmppStream.hostPort = hostPort
        self.xmppStream.myJID = self.userJID
        self.xmppStream.startTLSPolicy = XMPPStreamStartTLSPolicy.allowed
        
        try self.xmppStream.connect(withTimeout: XMPPStreamTimeoutNone)

        super.init()

        self.xmppStream.addDelegate(self, delegateQueue: DispatchQueue.main)

    
    }


}


extension XMPPRegister: XMPPStreamDelegate {
    
    /* stream */
    
    func xmppStream(_ sender: XMPPStream, didReceive message: XMPPMessage) {
        print("Did receive message \(message)")
    }
    
    func xmppStream(_ sender: XMPPStream, didReceive iq: XMPPIQ) -> Bool {
        return false
    }
    
    func xmppStreamWillConnect(_ sender: XMPPStream) {
        print("RegStream: WillConnect")
    }
    
    func xmppStream(_ sender: XMPPStream, socketDidConnect socket: GCDAsyncSocket) {
        print("RegStream: SocketDidConnect")
    }
    
    func xmppStreamDidStartNegotiation(_ sender: XMPPStream) {
        print("RegStream: Start Negotiation")
    }
    

    func xmppStreamDidConnect(_ stream: XMPPStream) {
        print("RegStream: Connected")
    
        
        try! stream.authenticate(withPassword: self.password)


    }

    func xmppStreamDidDisconnect(_ stream: XMPPStream) {
        print("RegStream: disconnect")
    }
    
    func xmppStreamConnectDidTimeout(_ stream: XMPPStream) {
        print("RegStream: timeout")
    }
    
    func xmppStreamDidRegister(_ sender: XMPPStream) {
        print("RegStream Did Register")
        self.didConnect.send("success")
    }
    
    func xmppStreamDidAuthenticate(_ sender: XMPPStream) {
        print("RegStream: didAuthenticate")
        self.didConnect.send("success")
    }
    
    func xmppStream(_ sender: XMPPStream, didNotAuthenticate error: DDXMLElement) {
        print("RegStream: Fail to Authenticate")
        try! sender.register(withPassword: self.password)
    }
    
    func xmppStream(_ sender: XMPPStream, didReceiveError error: DDXMLElement) {
        print("RegStream: error \(error)")
    }

    func xmppStream(_ sender: XMPPStream, didNotRegister error: DDXMLElement) {
        print("RegStream: didNotRegister: \(error)")
        
        let error2 = XMPPIQ(from: error)
        
        if (Utils().userAlreadyExists(error2)) {
            self.didConnect.send("exists")
        } else {
            
            if (Utils().accountsCreatedTooQuickly(error2)) {
                self.didConnect.send("too quick")
            } else {
            
                self.didConnect.send("error")
            }
        }
        
    }
    
    

}

