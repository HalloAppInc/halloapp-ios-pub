//
//  ChatGroupMember+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 8/18/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension ChatGroupMember {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatGroupMember> {
        return NSFetchRequest<ChatGroupMember>(entityName: "ChatGroupMember")
    }

    @NSManaged var groupId: String
    @NSManaged var typeValue: Int16
    @NSManaged var userId: String

    @NSManaged var group: ChatGroup
    
    var `type`: ChatGroupMemberType {
        get {
            return ChatGroupMemberType(rawValue: Int(self.typeValue))!
        }
        set {
            self.typeValue = Int16(newValue.rawValue)
        }
    }
}
