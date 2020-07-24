//
//  XMPPController.swift
//  Shared Extension
//
//  Created by Alan Luo on 7/8/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import Core
import UIKit
import XMPPFramework

class XMPPControllerShareExtension: XMPPController {
    override func configure(xmppStream: XMPPStream) {
        super.configure(xmppStream: xmppStream)
        xmppStream.passiveMode = true
    }
    
    /*
     By default, XMPP will try to reconnect after 10 seconds
     if 1. the connection is failed,
     or 2. the current link ends in 10 seconds.
     Since a share action can be done in less than 10 seconds,
     we need to prevent the XMPP from reconnecting after 10 seconds.
     */
    override func startConnectingIfNecessary() {
        if ShareExtensionContext.shared.shareExtensionIsActive {
            super.startConnectingIfNecessary()
        }
    }
}
