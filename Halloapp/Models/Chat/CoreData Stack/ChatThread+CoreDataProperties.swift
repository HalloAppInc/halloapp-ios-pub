//
//  ChatThread+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension ChatThread {

    enum Status: Int16 {
        case none = 0
        case available = 1
        case away = 2
    }
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ChatThread> {
        return NSFetchRequest<ChatThread>(entityName: "ChatThread")
    }

    @NSManaged var title: String?
    
    @NSManaged var chatWithUserId: String
    @NSManaged var unreadCount: Int32
    
    @NSManaged var statusValue: Int16
    @NSManaged var lastSeenTimestamp: Date?
    
    @NSManaged var lastMsgUserId: String?
    @NSManaged var lastMsgTimestamp: Date?
    @NSManaged var lastMsgText: String?
    
    var status: Status {
        get {
            return Status(rawValue: self.statusValue)!
        }
        set {
            self.statusValue = newValue.rawValue
        }
    }

}
