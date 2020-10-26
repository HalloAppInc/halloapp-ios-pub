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

    init?(xml: XMLElement) {
        guard let fromStr = xml.attributeStringValue(forName: "from") else { return nil }
        guard let from = XMPPJID(string: fromStr) else { return nil }

        guard let toStr = xml.attributeStringValue(forName: "to") else { return nil }
        guard let to = XMPPJID(string: toStr) else { return nil }

        guard let threadTypeStr = xml.attributeStringValue(forName: "thread_type") else { return nil }
        guard let threadID = xml.attributeStringValue(forName: "thread_id") else { return nil }

        guard let typeStr = xml.attributeStringValue(forName: "type") else { return nil }
         
        let threadType: ChatType = {
            switch threadTypeStr {
            case "chat": return .oneToOne
            case "group_chat": return .group
            default:
                return .oneToOne
            }
        }()
        
        let type: ChatState = {
            switch typeStr {
            case ChatState.available.rawValue: return .available
            case ChatState.typing.rawValue: return .typing
            default:
                return .available
            }
        }()
        
        self.from = from
        self.to = to
        self.threadType = threadType
        self.threadID = threadID
        self.type = type
    }
}

