//
//  ChatEvent+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 12/20/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//
//

import Core
import CoreData

enum ChatEventType: Int16 {
    case none = 0
    case whisperKeysChange = 1
}

extension ChatEvent {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatEvent> {
        return NSFetchRequest<ChatEvent>(entityName: "ChatEvent")
    }

    @NSManaged public var typeValue: Int16
    @NSManaged public var userID: UserID
    @NSManaged public var timestamp: Date

    var type: ChatEventType {
        get {
            return ChatEventType(rawValue: self.typeValue)!
        }
        set {
            self.typeValue = newValue.rawValue
        }
    }

}

extension ChatEvent : Identifiable {

}
