//
//  ChatThread+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreData
import Foundation

extension ChatThread {

    enum LastMsgStatus: Int16 {
        case none = 0
        case pending = 1
        case sentOut = 2
        case delivered = 3
        case seen = 4
        case error = 5
    }
    
    enum LastMsgMediaType: Int16 {
        case none = 0
        case image = 1
        case video = 2
    }
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ChatThread> {
        return NSFetchRequest<ChatThread>(entityName: "ChatThread")
    }

    @NSManaged private var typeValue: Int16
    
    @NSManaged var groupId: GroupID?
    @NSManaged var chatWithUserId: UserID?
    
    @NSManaged var title: String?
    @NSManaged var unreadCount: Int32
    
    @NSManaged var lastMsgId: String?
    @NSManaged var lastMsgUserId: String?
    @NSManaged private var lastMsgStatusValue: Int16
    @NSManaged var lastMsgText: String?
    @NSManaged private var lastMsgMediaTypeValue: Int16
    @NSManaged var lastMsgTimestamp: Date?

    @NSManaged var draft: String?
    
    var type: ChatType {
        get {
            return ChatType(rawValue: self.typeValue)!
        }
        set {
            self.typeValue = newValue.rawValue
        }
    }
    
    var lastMsgStatus: LastMsgStatus {
        get {
            return LastMsgStatus(rawValue: self.lastMsgStatusValue)!
        }
        set {
            self.lastMsgStatusValue = newValue.rawValue
        }
    }
    
    var lastMsgMediaType: LastMsgMediaType {
        get {
            return LastMsgMediaType(rawValue: self.lastMsgMediaTypeValue)!
        }
        set {
            self.lastMsgMediaTypeValue = newValue.rawValue
        }
    }
    
}
