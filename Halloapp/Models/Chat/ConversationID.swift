//
//  ConversationID.swift
//  HalloApp
//
//  Created by Matt Geimer on 5/26/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation

enum ConversationType: String {
    case chat = "CHAT"
    case group = "GRUP"
}

struct ConversationID: CustomStringConvertible {
    var id: String
    var conversationType: ConversationType
    
    init?(_ conversationID: String) {
        let splitValues = conversationID.split(separator: ":", maxSplits: 1)
        guard splitValues.count == 2 else { return nil }
        
        self.id = String(splitValues[1])
        
        guard let conversationType = ConversationType(rawValue: String(splitValues[0])) else { return nil }
        self.conversationType = conversationType
    }
    
    init(id: String, type: ConversationType) {
        self.id = id
        self.conversationType = type
    }
    
    var description: String {
        return conversationType.rawValue + ":" + id
    }
}
