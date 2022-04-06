//
//  Group+CoreDataProperties.swift
//  Core
//
//  Created by Garrett on 4/1/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreData

public extension Group {

    @nonobjc class func fetchRequest() -> NSFetchRequest<Group> {
        return NSFetchRequest<Group>(entityName: "Group")
    }

    @NSManaged var id: String
    @NSManaged var name: String
    @NSManaged var avatarID: String?
    @NSManaged var background: Int32
    @NSManaged var desc: String?
    @NSManaged var maxSize: Int16
    @NSManaged var lastSync: Date?
    @NSManaged var inviteLink: String?

    @NSManaged var members: Set<GroupMember>?

    var orderedMembers: [GroupMember] {
        get {
            guard let members = self.members else { return [] }
            return members.sorted { $0.userID < $1.userID }
        }
    }
}
