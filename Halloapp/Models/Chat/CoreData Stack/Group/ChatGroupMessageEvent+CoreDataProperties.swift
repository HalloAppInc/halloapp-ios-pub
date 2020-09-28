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
                return "You"
            }
            return MainAppContext.shared.contactStore.fullName(for: userId)
        }
    }
    
    var memberName: String? {
        get {
            guard let userId = memberUserId else { return nil }
            if userId == MainAppContext.shared.userData.userId {
                return "you"
            }
            return MainAppContext.shared.contactStore.fullName(for: userId)
        }
    }
    
    var text: String? {
        get {
            guard let senderName = senderName else { return nil }
            switch action {
            case .create: return "\(senderName) created this group"
            case .changeName: return "\(senderName) changed the group name to \"\(groupName ?? "")\""
            case .changeAvatar: return "\(senderName) changed the group avatar"
            case .leave, .modifyMembers, .modifyAdmins:
                guard let memberName = memberName else { return nil }
                switch memberAction {
                case .add: return "\(senderName) added \(memberName)"
                case .remove: return "\(senderName) removed \(memberName)"
                case .promote: return "\(senderName) promoted \(memberName) to admin"
                case .demote: return "\(senderName) demoted \(memberName)"
                case .leave: return "\(senderName) left the group"
                default: return nil
                }
            default: return nil
            }
        }
    }

}
