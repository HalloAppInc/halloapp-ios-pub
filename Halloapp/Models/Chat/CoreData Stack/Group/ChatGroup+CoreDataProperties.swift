//
//  ChatGroup+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 8/18/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension ChatGroup {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatGroup> {
        return NSFetchRequest<ChatGroup>(entityName: "ChatGroup")
    }

    @NSManaged var groupId: String
    @NSManaged var name: String
    @NSManaged var avatar: String?
    @NSManaged var desc: String?
    @NSManaged var maxSize: Int16
    @NSManaged var lastSync: Date?
    @NSManaged var inviteLink: String?
    
    @NSManaged var members: Set<ChatGroupMember>?
    
    public var orderedMembers: [ChatGroupMember] {
        get {
            guard let members = self.members else { return [] }
            return members.sorted { $0.userId < $1.userId }
        }
    }
}
