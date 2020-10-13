//
//  ChatGroupMessage+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 8/18/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreData
import Foundation


extension ChatGroupMessage {
    
    enum InboundStatus: Int16 {
        case none = 0
        case haveSeen = 1
        case sentSeenReceipt = 2
        case error = 3
    }
    
    enum OutboundStatus: Int16 {
        case none = 0
        case pending = 1        // initial state, only recorded in the database
        case sentOut = 2        // got ACK from server, timestamp is from server
        case delivered = 3      // all group members have gotten the message
        case seen = 4           // all group members have seen the message
        case error = 5
    }
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatGroupMessage> {
        return NSFetchRequest<ChatGroupMessage>(entityName: "ChatGroupMessage")
    }

    @NSManaged public var groupId: String
    @NSManaged public var id: String

    @NSManaged public var userId: UserID?
    
    @NSManaged var typeValue: Int16
    
    @NSManaged public var text: String?
    @NSManaged public var timestamp: Date?
    
    @NSManaged var media: Set<ChatMedia>?
    @NSManaged var info: Set<ChatGroupMessageInfo>?
    
    @NSManaged var chatReplyMessageID: String?
    @NSManaged var chatReplyMessageSenderID: UserID?
    @NSManaged var chatReplyMessageMediaIndex: Int32
    
    @NSManaged var quoted: ChatQuoted?
    
    @NSManaged var event: ChatGroupMessageEvent?
    
    @NSManaged var cellHeight: Int16
    
    @NSManaged var inboundStatusValue: Int16
    @NSManaged var outboundStatusValue: Int16
    
    var isEvent: Bool {
        return event != nil
    }
    
    var inboundStatus: InboundStatus {
        get {
            return InboundStatus(rawValue: self.inboundStatusValue)!
        }
        set {
            self.inboundStatusValue = newValue.rawValue
        }
    }
    
    var outboundStatus: OutboundStatus {
        get {
            return OutboundStatus(rawValue: self.outboundStatusValue)!
        }
        set {
            self.outboundStatusValue = newValue.rawValue
        }
    }
    
    public var orderedMedia: [ChatMedia] {
        get {
            guard let media = self.media else { return [] }
            return media.sorted { $0.order < $1.order }
        }
    }
    
    public var orderedInfo: [ChatGroupMessageInfo] {
        get {
            guard let info = self.info else { return [] }
            return info.sorted {
                return $0.timestamp < $1.timestamp
            }
        }
    }

}

