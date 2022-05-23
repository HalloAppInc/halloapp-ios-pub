//
//  ChatGroupMessageEvent+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 9/9/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreCommon
import CoreData
import Foundation

extension ChatGroupMessageEvent {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatGroupMessageEvent> {
        return NSFetchRequest<ChatGroupMessageEvent>(entityName: "ChatGroupMessageEvent")
    }

    @NSManaged public var actionValue: Int16
    @NSManaged public var memberActionValue: Int16
    @NSManaged public var memberUserId: String?
    @NSManaged public var sender: String?
    @NSManaged public var groupName: String?
    
    @NSManaged public var groupMessage: ChatGroupMessage
    
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

extension GroupEvent {
    enum Subject {
        case you
        case other(String)
    }

    private var subject: Subject? {
        get {
            guard let userId = senderUserID else { return nil }
            if userId == MainAppContext.shared.userData.userId {
                return .you
            }

            var name = ""
            MainAppContext.shared.contactStore.performOnBackgroundContextAndWait { managedObjectContext in
                name = MainAppContext.shared.contactStore.fullName(for: userId, in: managedObjectContext)
            }

            return .other(name)
        }
    }
    
    var memberName: String? {
        get {
            guard let userId = memberUserID else { return nil }
            if userId == MainAppContext.shared.userData.userId {
                return Localizations.userYou
            }

            var name = ""
            MainAppContext.shared.contactStore.performOnBackgroundContextAndWait { managedObjectContext in
                name = MainAppContext.shared.contactStore.fullName(for: userId, in: managedObjectContext)
            }

            return name
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
}
