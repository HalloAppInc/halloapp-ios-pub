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

                self.isReady = true

            })

        )
        
        
    }
    
}
