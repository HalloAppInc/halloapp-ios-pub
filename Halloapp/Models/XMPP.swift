//
//  XMPPWrapper.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation


class XMPP: ObservableObject {

    @Published var isReady = false
    
    @Published var xmppController: XMPPController!
    
    init(user: String, password: String) {
        self.isReady = true
        do {
            try self.xmppController = XMPPController(user: user, password: password)
            
            self.xmppController.xmppStream.addDelegate(self, delegateQueue: DispatchQueue.main)
            
//            self.xmppController.connect()
            
//            self.isReady = true
            
        } catch {
            print("error connecting to xmpp server")
        }
    }
    
}
