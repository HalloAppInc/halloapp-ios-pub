//
//  ConversationID.swift
//  HalloApp
//
//  Created by Matt Geimer on 5/26/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation

public enum ConversationType: String {
    case chat = "CHAT"
    case group = "GRUP"
}

public struct ConversationID: CustomStringConvertible {
    public var id: String
    public var conversationType: ConversationType
    
    public init?(_ conversationID: String) {
        let splitValues = conversationID.split(separator: ":", maxSplits: 1)
        guard splitValues.count == 2 else { return nil }
        
        self.id = String(splitValues[1])
        
        guard let conversationType = ConversationType(rawValue: String(splitValues[0])) else { return nil }
        self.conversationType = conversationType
    }
    
    public init(id: String, type: ConversationType) {
        self.id = id
        self.conversationType = type
    }
    
    public var description: String {
        return conversationType.rawValue + ":" + id
    }
}
