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

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatThread> {
        return NSFetchRequest<ChatThread>(entityName: "ChatThread")
    }

    @NSManaged public var chatWithUserId: String
    @NSManaged public var unreadCount: Int32
    @NSManaged public var lastMsgUserId: String?
    @NSManaged public var lastMsgTimestamp: Date?
    @NSManaged public var lastMsgText: String?
    

}
