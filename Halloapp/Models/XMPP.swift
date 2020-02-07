//
//  XMPPWrapper.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation
import Combine
import XMPPFramework

class XMPP: ObservableObject {

    @Published var isReady = false
    
    @Published var xmppController: XMPPController!
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    @Published var userData: UserData
    
    @Published var metaData: MetaData
    
    init(userData: UserData, metaData: MetaData) {

//        print("XMPP Init")
        
        self.userData = userData
        self.metaData = metaData
        
        do {
            
            try self.xmppController = XMPPController(userData: self.userData, metaData: self.metaData)
            
            self.xmppController.xmppStream.addDelegate(self, delegateQueue: DispatchQueue.main)
            
        } catch {
            print("error connecting to xmpp server")
        }
        
        
        self.cancellableSet.insert(
         
            self.xmppController.didConnect.sink(receiveValue: { value in

                print("got sink for didConnect")
                if (!self.isReady) {
                    self.isReady = true
                } else {
                    /* reconnected but app is already in isReady state, we should check for changes */
                    
                }

            })

        )
        
        
        self.cancellableSet.insert(
         
            self.userData.didLogOff.sink(receiveValue: {
                print("got log off signal, disconnecting")
                
                self.xmppController.xmppStream.removeDelegate(self)
                self.xmppController.xmppReconnect.deactivate()
                self.xmppController.xmppStream.disconnect()
                

            })

        )
        
        
    }
    
}
