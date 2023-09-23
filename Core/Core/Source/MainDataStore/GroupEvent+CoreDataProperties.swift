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

        case changeExpiry = 12
        case autoPromoteAdmins = 13
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
    @NSManaged var read: Bool
    @NSManaged var timestamp: Date
    @NSManaged private var groupExpirationTypeValue: Int16
    @NSManaged var groupExpirationTime: Int64

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

    var groupExpirationType: Group.ExpirationType {
        get {
            return Group.ExpirationType(rawValue: groupExpirationTypeValue) ?? .expiresInSeconds
        }
        set {
            groupExpirationTypeValue = newValue.rawValue
        }
    }
}

public extension GroupEvent {
    enum Subject {
        case you
        case other(String)
    }

    private var subject: Subject? {
        get {
            guard let userId = senderUserID else { return nil }
            if userId == AppContext.shared.userData.userId {
                return .you
            }

            let name = managedObjectContext.flatMap { context in
                context.performAndWait {
                    UserProfile.findOrCreate(with: userId, in: context).displayName
                }
            }

            return .other(name ?? "")
        }
    }

    var memberName: String? {
        get {
            guard let userId = memberUserID else { return nil }
            if userId == AppContext.shared.userData.userId {
                return Localizations.userYou
            }

            return managedObjectContext.flatMap { context in
                context.performAndWait {
                    UserProfile.findOrCreate(with: userId, in: context).displayName
                }
            }
        }
    }

    var text: String? {
        get {
            guard let subject = subject else { return nil }
            switch action {
            case .create:
                return Localizations.groupEventCreatedGroup(subject: subject, groupName: groupName ?? "")
            case .join:
                return Localizations.groupEventJoin(subject: subject)
            case .changeName:
                return Localizations.groupEventChangedName(subject: subject, groupName: groupName ?? "")
            case .changeDescription:
                return Localizations.groupEventChangedDescription(subject: subject)
            case .changeAvatar:
                return Localizations.groupEventChangedAvatar(subject: subject, groupName: groupName ?? "")
            case .setBackground:
                return Localizations.groupEventChangedBackground(subject: subject)
            case .leave, .modifyMembers, .modifyAdmins:
                guard let memberName = memberName else { return nil }
                switch memberAction {
                case .add:
                    return Localizations.groupEventAddedMember(subject: subject, memberName: memberName)
                case .remove:
                    return Localizations.groupEventRemovedMember(subject: subject, memberName: memberName)
                case .promote:
                    return Localizations.groupEventPromotedMember(subject: subject, memberName: memberName)
                case .demote:
                    return Localizations.groupEventDemotedMember(subject: subject, memberName: memberName)
                case .leave:
                    return Localizations.groupEventMemberLeave(subject: subject)
                default:
                    return nil
                }
            case .autoPromoteAdmins:
                if memberUserID == AppContext.shared.userData.userId {
                    return Localizations.groupEventCurrentUserAutoPromoted
                } else {
                    guard let memberName = memberName else { return nil }
                    return Localizations.groupEventMemberAutopromoted(memberName: memberName)
                }
            case .changeExpiry:
                return Localizations.groupEventChangeExpiry(subject: subject, expirationType: groupExpirationType, expirationTime: groupExpirationTime)
            default:
                return nil
            }
        }
    }

}


extension Localizations {

    static func groupEventCreatedGroup(subject: GroupEvent.Subject, groupName: String) -> String {
        switch subject {
        case .you:
            let format = NSLocalizedString("group.event.created.group.you", value: "You created the group \"%1@\"", comment: "Message text shown when you create a group")
            return String(format: format, groupName)
        case .other(let senderName):
            let format = NSLocalizedString("group.event.created.group", value: "%@ created the group \"%2@\"", comment: "Message text shown with the user who created the group")
            return String(format: format, senderName, groupName)
        }
    }

    static func groupEventJoin(subject: GroupEvent.Subject) -> String {
        switch subject {
        case .you:
            return NSLocalizedString("chat.group.event.join.you", value: "You joined the group via Group Invite Link", comment: "Message text shown when you join a group via invite link")
        case .other(let senderName):
            let format = NSLocalizedString("chat.group.event.join", value: "%@ joined the group via Group Invite Link", comment: "Message text shown with the user who joined the group via invite link")
            return String(format: format, senderName)
        }
    }

    static func groupEventChangedName(subject: GroupEvent.Subject, groupName: String) -> String {
        switch subject {
        case .you:
            let format = NSLocalizedString("group.event.changed.name.you", value: "You changed the group name to \"%1@\"", comment: "Message text shown when you change the group name")
            return String(format: format, groupName)
        case .other(let senderName):
            let format = NSLocalizedString("group.event.changed.name", value: "%1@ changed the group name to \"%2@\"", comment: "Message text shown with the user who changed the group name")
            return String(format: format, senderName, groupName)
        }
    }

    static func groupEventChangedDescription(subject: GroupEvent.Subject) -> String {
        switch subject {
        case .you:
            let format = NSLocalizedString("group.event.changed.description.you", value: "You changed the group description", comment: "Message text shown when you change the group description")
            return String(format: format)
        case .other(let senderName):
            let format = NSLocalizedString("group.event.changed.description", value: "%1@ changed the group description", comment: "Message text shown with the user who changed the group description")
            return String(format: format, senderName)
        }
    }

    static func groupEventChangedAvatar(subject: GroupEvent.Subject, groupName: String) -> String {
        switch subject {
        case .you:
            return NSLocalizedString("group.event.changed.avatar.you", value: "You changed the group icon", comment: "Message text shown with the user who changed the group avatar")
        case .other(let senderName):
            let format = NSLocalizedString("group.event.changed.avatar", value: "%@ changed the group icon", comment: "Message text shown with the user who changed the group avatar")
            return String(format: format, senderName, groupName)
        }
    }

    static func groupEventChangedBackground(subject: GroupEvent.Subject) -> String {
        switch subject {
        case .you:
            return NSLocalizedString("group.event.changed.background.you", value: "You changed the background color", comment: "Message text shown when you change the background")
        case .other(let senderName):
            let format = NSLocalizedString("group.event.changed.background", value: "%@ changed the background color", comment: "Message text shown with the user who changed the background")
            return String(format: format, senderName)
        }
    }

    static func groupEventAddedMember(subject: GroupEvent.Subject, memberName: String) -> String {
        switch subject {
        case .you:
            let format = NSLocalizedString("group.event.added.member.you", value: "You added %1@", comment: "Message text shown when you add a group member")
            return String(format: format, memberName)
        case .other(let senderName):
            let format = NSLocalizedString("group.event.added.member", value: "%1@ added %2@", comment: "Message text shown with the user who added a group member")
            return String(format: format, senderName, memberName)
        }
    }

    static func groupEventRemovedMember(subject: GroupEvent.Subject, memberName: String) -> String {
        switch subject {
        case .you:
            let format = NSLocalizedString("group.event.removed.member.you", value: "You removed %1@", comment: "Message text shown when you remove a group member")
            return String(format: format, memberName)
        case .other(let senderName):
            let format = NSLocalizedString("group.event.removed.member", value: "%1@ removed %2@", comment: "Message text shown with the user who removed a group member")
            return String(format: format, senderName, memberName)
        }
    }

    static func groupEventPromotedMember(subject: GroupEvent.Subject, memberName: String) -> String {
        switch subject {
        case .you:
            let format = NSLocalizedString("group.event.promoted.member.you", value: "You made %1@ an admin", comment: "Message text shown when you promote a group member")
            return String(format: format, memberName)
        case .other(let senderName):
            let format = NSLocalizedString("group.event.promoted.member", value: "%1@ made %2@ an admin", comment: "Message text shown with the user who promoted a group member")
            return String(format: format, senderName, memberName)
        }
    }

    static func groupEventDemotedMember(subject: GroupEvent.Subject, memberName: String) -> String {
        switch subject {
        case .you:
            let format = NSLocalizedString("group.event.demoted.member.you", value: "You removed %1@ as an admin", comment: "Message text shown when you demote a group admin")
            return String(format: format, memberName)
        case .other(let senderName):
            let format = NSLocalizedString("group.event.demoted.member", value: "%1@ removed %2@ as an admin", comment: "Message text shown with the user who demoted a group admin")
            return String(format: format, senderName, memberName)
        }
    }

    static func groupEventMemberLeave(subject: GroupEvent.Subject) -> String {
        switch subject {
        case .you:
            return NSLocalizedString("chat.group.event.member.left.you", value: "You left", comment: "Message text shown when you leave a group")
        case .other(let senderName):
            let format = NSLocalizedString("chat.group.event.member.left", value: "%@ left", comment: "Message text shown with the user who left the group")
            return String(format: format, senderName)
        }
    }

    static var groupEventCurrentUserAutoPromoted: String {
        return NSLocalizedString("chat.group.event.member.autopromoted.you", value: "You were auto-promoted to admin", comment: "Message text shown when you are auto promoted to admin. When the one-and-only admin of a group leaves the group, a random member is promoted to admin")
    }

    static func groupEventMemberAutopromoted(memberName: String) -> String {
        let format =  NSLocalizedString("chat.group.event.member.autopromoted", value: "%@ was auto-promoted to admin", comment: "Message text shown when a group member is auto promoted to admin. When the one-and-only admin of a group leaves the group, a random member is promoted to admin")
        return String(format: format, memberName)
    }

    private static let expiryTimeFormatter: DateComponentsFormatter = {
        let expiryTimeFormatter = DateComponentsFormatter()
        expiryTimeFormatter.allowedUnits = [.day, .hour]
        expiryTimeFormatter.collapsesLargestUnit = true
        expiryTimeFormatter.maximumUnitCount = 1
        expiryTimeFormatter.unitsStyle = .full
        return expiryTimeFormatter
    }()

    private static let expiryDateFormatter: DateFormatter = {
        let expiryDateFormatter = DateFormatter()
        expiryDateFormatter.dateStyle = .short
        expiryDateFormatter.timeStyle = .none
        return expiryDateFormatter
    }()

    static func groupEventChangeExpiry(subject: GroupEvent.Subject, expirationType: Group.ExpirationType, expirationTime: Int64) -> String {
        let expirationTimeString = Group.formattedExpirationTime(type: expirationType, time: expirationTime)

        switch subject {
        case .you:
            let format = NSLocalizedString("chat.group.event.expiry.changed.you",
                                     value: "You changed the group’s content expiration to %1@",
                                     comment: "Message text shown when you change a groups content expiry settings")
            return String(format: format, expirationTimeString)
        case .other(let senderName):
            let format = NSLocalizedString("chat.group.event.expiry.changed",
                                           value: "%1@ changed the group’s content expiration to %2@",
                                           comment: "Message text shown with the user who changed a groups content expiry settings")
            return String(format: format, senderName, expirationTimeString)
        }
    }
    // MARK: - Group Expiry

    static var chatGroupExpiryOption24Hours: String {
        NSLocalizedString("chat.group.expiry.option.24hours", value: "24 Hours", comment: "Group content expiry time limit option")
    }

    static var chatGroupExpiryOption30Days: String {
        NSLocalizedString("chat.group.expiry.option.30days", value: "30 Days", comment: "Group content expiry time limit option")
    }

    static var chatGroupExpiryOptionNever: String {
        NSLocalizedString("chat.group.expiry.option.never", value: "Never", comment: "Group content expiry time limit option")
    }
}

// MARK: Event Collapsing

extension GroupEvent {

    public func canCollapse(with groupEvent: GroupEvent) -> Bool {
        if action == groupEvent.action, memberAction == groupEvent.memberAction {
            // mirror cases in collapsedText
            switch action {
            case .modifyMembers:
                switch memberAction {
                case .add, .remove:
                    return true
                default:
                    return false
                }
            case .join, .leave:
                return true
            default:
                return false
            }
        }
        return false
    }

    public static func collapsedText(for action: Action, memberAction: MemberAction, count: Int) -> String? {
        let formatString: String?

        // mirror cases in canCollapse
        switch action {
        case .modifyMembers:
            switch memberAction {
            case .add:
                formatString = NSLocalizedString("feed.collapsed.n.users.added", comment: "Number of contacts added to a group.")
            case .remove:
                formatString = NSLocalizedString("feed.collapsed.n.users.removed", comment: "Number of contacts removed from a group.")
            default:
                formatString = nil
            }
        case .join:
            formatString = NSLocalizedString("feed.collapsed.n.users.joined", comment: "Number of contacts that joined a group.")
        case .leave:
            formatString = NSLocalizedString("feed.collapsed.n.users.left", comment: "Number of contacts that left a group.")
        default:
            formatString = nil
        }

        return formatString.flatMap { String.localizedStringWithFormat($0, count) }
    }
}
