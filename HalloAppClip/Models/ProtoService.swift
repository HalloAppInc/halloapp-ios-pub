//
//  ProtoService.swift
//  HalloAppClip
//
//  Created by Nandini Shetty on 6/11/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Combine
import Core
import XMPPFramework

fileprivate let userDefaultsKeyForNameSync = "xmpp.name-sent"

open class ProtoService: ProtoServiceCore {
    private var cancellableSet = Set<AnyCancellable>()

    public required init(userData: UserData, passiveMode: Bool = false, automaticallyReconnect: Bool = true) {
        super.init(userData: userData, passiveMode: passiveMode, automaticallyReconnect: automaticallyReconnect)

        func requestCountOfOneTimeKeys(completion: @escaping ServiceRequestCompletion<Int32>) {
            enqueue(request: ProtoWhisperGetCountOfOneTimeKeysRequest(completion: completion))
        }

        self.cancellableSet.insert(
            userData.didLogIn.sink {
                DDLogInfo("proto/userdata/didLogIn")
                self.configureStream(with: self.userData)
                self.connect()
            })

        self.cancellableSet.insert(
            userData.didLogOff.sink {
                DDLogInfo("proto/userdata/didLogOff")
                self.disconnectImmediately() // this is only necessary when manually logging out from a developer menu.
                self.configureStream(with: nil)
            })
    }
}
