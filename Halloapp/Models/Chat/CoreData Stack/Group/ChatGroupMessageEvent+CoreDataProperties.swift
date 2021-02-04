//
//  ChatGroupMessageEvent+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 9/9/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreData
import Foundation

extension ChatGroupMessageEvent {

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
    }
    
    enum MemberAction: Int16 {
        case none = 0
        case add = 1
        case remove = 2
        case promote = 3
        case demote = 4
        case leave = 5
    }
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatGroupMessageEvent> {
        return NSFetchRequest<ChatGroupMessageEvent>(entityName: "ChatGroupMessageEvent")
    }
    
    @NSManaged public var actionValue: Int16
    @NSManaged public var memberActionValue: Int16
    @NSManaged public var memberUserId: String?
    @NSManaged public var sender: String?
    @NSManaged public var groupName: String?
    
    @NSManaged public var groupMessage: ChatGroupMessage
    
    var action: Action {
        get {
            return Action(rawValue: self.actionValue)!
        }
        set {
            self.actionValue = newValue.rawValue
        }
    }
    
    var memberAction: MemberAction {
        get {
            return MemberAction(rawValue: self.memberActionValue)!
        }
        set {
            self.memberActionValue = newValue.rawValue
        }
    }
    
    var senderName: String? {
        get {
            guard let userId = sender else { return nil }
            if userId == MainAppContext.shared.userData.userId {
                return Localizations.userYouCapitalized
            }
            return MainAppContext.shared.contactStore.fullName(for: userId)
        }
    }
    
    var memberName: String? {
        get {
            guard let userId = memberUserId else { return nil }
            if userId == MainAppContext.shared.userData.userId {
                return Localizations.userYou
            }
            return MainAppContext.shared.contactStore.fullName(for: userId)
        }
    }

    var text: String? {
        get {
            guard let senderName = senderName else { return nil }
            switch action {
            case .create:
                let formatString = NSLocalizedString("chat.group.event.created.group", value: "%@ created this group", comment: "Message text shown with the user who created the group")
                return String(format: formatString, senderName)
            case .changeName:
                let formatString = NSLocalizedString("chat.group.event.changed.name", value: "%1@ changed the group's name to %2@", comment: "Message text shown with the user who changed the group name")
                return String(format: formatString, senderName, groupName ?? "")
            case .changeAvatar:
                let formatString = NSLocalizedString("chat.group.event.changed.avatar", value: "%@ changed this group's icon", comment: "Message text shown with the user who changed the group avatar")
                return String(format: formatString, senderName)
            case .leave, .modifyMembers, .modifyAdmins:
                guard let memberName = memberName else { return nil }
                switch memberAction {
                case .add:
                    let formatString = NSLocalizedString("chat.group.event.added.member", value: "%1@ added %2@", comment: "Message text shown with the user who added a group member")
                    return String(format: formatString, senderName, memberName)
                case .remove:
                    let formatString = NSLocalizedString("chat.group.event.removed.member", value: "%1@ removed %2@", comment: "Message text shown with the user who removed a group member")
                    return String(format: formatString, senderName, memberName)
                case .promote:
                    let formatString = NSLocalizedString("chat.group.event.promoted.member", value: "%1@ made %2@ an admin", comment: "Message text shown with the user who promoted a group member")
                    return String(format: formatString, senderName, memberName)
                case .demote:
                    let formatString = NSLocalizedString("chat.group.event.demoted.member", value: "%1@ removed %2@ as admin", comment: "Message text shown with the user who demoted a group admin")
                    return String(format: formatString, senderName, memberName)
                case .leave:
                    let formatString = NSLocalizedString("chat.group.event.demoted.member", value: "%@ left the group", comment: "Message text shown with the user who left the group")
                    return String(format: formatString, senderName)
                default:
                    return nil
                }
            default:
                return nil
            }
        }
    }

}
