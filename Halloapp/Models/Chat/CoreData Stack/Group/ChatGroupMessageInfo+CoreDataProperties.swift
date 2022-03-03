//
//  ChatGroupMessageInfo+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 8/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreCommon
import CoreData
import Foundation


extension ChatGroupMessageInfo {

    enum OutboundStatus: Int16 {
        case none = 0
        case delivered = 1      // user have gotten the message
        case seen = 2           // user have seen the message
        case error = 5
    }
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatGroupMessageInfo> {
        return NSFetchRequest<ChatGroupMessageInfo>(entityName: "ChatGroupMessageInfo")
    }

    @NSManaged public var chatGroupMessageId: String
    @NSManaged public var userId: UserID
    @NSManaged public var outboundStatusValue: Int16
    @NSManaged public var groupMessage: ChatGroupMessage
    @NSManaged public var timestamp: Date
    
    var outboundStatus: OutboundStatus {
        get {
            return OutboundStatus(rawValue: self.outboundStatusValue)!
        }
        set {
            self.outboundStatusValue = newValue.rawValue
        }
    }

}
