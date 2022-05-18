//
//  GroupMember+CoreDataProperties.swift
//  Core
//
//  Created by Garrett on 4/1/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreData

public enum GroupAction: String {
    case create = "create"
    case join = "join"
    case leave = "leave"
    case delete = "delete"
    case changeName = "change_name"
    case changeDescription = "change_description"
    case changeAvatar = "change_avatar"
    case setBackground = "set_background"
    case modifyMembers = "modify_members"
    case modifyAdmins = "modify_admins"
    case get = "get"
}

public enum GroupMemberType: Int {
    case admin = 0
    case member = 1
}

public enum GroupMemberAction: String {
    case add = "add"
    case promote = "promote"
    case demote = "demote"
    case remove = "remove"
    case leave = "leave"
    case join = "join"
}

public extension GroupMember {

    @nonobjc class func fetchRequest() -> NSFetchRequest<GroupMember> {
        return NSFetchRequest<GroupMember>(entityName: "GroupMember")
    }

    @NSManaged var groupID: String
    @NSManaged var typeValue: Int16
    @NSManaged var userID: String

    @NSManaged var group: Group

    var `type`: GroupMemberType {
        get {
            return GroupMemberType(rawValue: Int(self.typeValue))!
        }
        set {
            self.typeValue = Int16(newValue.rawValue)
        }
    }

}
