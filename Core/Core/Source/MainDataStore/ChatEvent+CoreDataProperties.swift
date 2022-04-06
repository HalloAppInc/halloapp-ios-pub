//
//  ChatEvent+CoreDataProperties.swift
//  Core
//
//  Created by Garrett on 4/1/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CoreData

public enum ChatEventType: Int16 {
    case none = 0
    case whisperKeysChange = 1
}

public extension ChatEvent {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ChatEvent> {
        return NSFetchRequest<ChatEvent>(entityName: "ChatEvent")
    }

    @NSManaged var typeValue: Int16
    @NSManaged var userID: UserID
    @NSManaged var timestamp: Date

    var type: ChatEventType {
        get {
            return ChatEventType(rawValue: self.typeValue)!
        }
        set {
            self.typeValue = newValue.rawValue
        }
    }
}
