//
//  ConversationID.swift
//  HalloApp
//
//  Created by Matt Geimer on 5/26/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation

enum ConversationType {
    case chat, group
    
    var stringRepresentation: String {
        switch self {
        case .chat:
            return "CHAT"
        case .group:
            return "GRUP"
        }
    }
}

struct ConversationID: CustomStringConvertible {
    var id: String
    var conversationType: ConversationType
    
    init(_ conversationID: String) {
        let splitValues = conversationID.split(separator: ":", maxSplits: 1)
        self.id = String(splitValues[1])
        
        if splitValues[0] == ConversationType.group.stringRepresentation {
            conversationType = .group
        } else {
            conversationType = .chat
        }
    }
    
    init(id: String, type: ConversationType) {
        self.id = id
        self.conversationType = type
    }
    
    var description: String {
        return conversationType.stringRepresentation + ":" + id
    }
}
