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
    private var userData: UserData
    private var metaData: MetaData
    @Published private(set) var xmppController: XMPPController!
    private var cancellableSet: Set<AnyCancellable> = []

    init(userData: UserData, metaData: MetaData) {
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
//                print("got sink for didConnect")
//                if (self.metaData.isOffline) {
//                    self.metaData.isOffline = false
//                }
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
