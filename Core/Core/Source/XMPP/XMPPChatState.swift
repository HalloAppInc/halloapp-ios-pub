//
//  XMPPChatState.swift
//  Core
//
//  Created by Tony Jiang on 10/23/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import XMPPFramework

public struct XMPPChatState {
    public let from: XMPPJID
    public let to: XMPPJID
    public let threadType: ChatType
    public let threadID: String
    public let type: ChatState
}

