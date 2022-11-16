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
