//
//  GroupEvent+CoreDataProperties.swift
//  Core
//
//  Created by Garrett on 4/1/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CoreData

public extension GroupEvent {
    enum Action: Int16 {
        case none = 0
        case get = 1
        case create = 2
        case leave = 3
        case delete = 4

        case changeName = 5
        case changeAvatar = 6

        case modifyMembers = 7
        case modifyAdmins = 8

        case join = 9
        case setBackground = 10

        case changeDescription = 11
    }

    enum MemberAction: Int16 {
        case none = 0
        case add = 1
        case remove = 2
        case promote = 3
        case demote = 4
        case leave = 5
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<GroupEvent> {
        return NSFetchRequest<GroupEvent>(entityName: "GroupEvent")
    }

    @NSManaged var actionValue: Int16
    @NSManaged var memberActionValue: Int16
    @NSManaged var memberUserID: String?
    @NSManaged var senderUserID: UserID?
    @NSManaged var groupName: String?
    @NSManaged var groupID: GroupID
    @NSManaged var timestamp: Date

    var action: GroupEvent.Action {
        get {
            return GroupEvent.Action(rawValue: self.actionValue)!
        }
        set {
            self.actionValue = newValue.rawValue
        }
    }

    var memberAction: GroupEvent.MemberAction {
        get {
            return GroupEvent.MemberAction(rawValue: self.memberActionValue)!
        }
        set {
            self.memberActionValue = newValue.rawValue
        }
    }
}
