//
//  ChatMessage+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Foundation
import Core
import CoreData

extension ChatMessage {

    enum IncomingStatus: Int16 {
        case none = 0
        case haveSeen = 1
        case sentSeenReceipt = 2
        case error = 3
        case retracted = 4
    }
    
    enum OutgoingStatus: Int16 {
        case none = 0
        case pending = 1        // initial state, only recorded in the database
        case sentOut = 2        // got ACK from server, timestamp is from server
        case delivered = 3      // other user have gotten the message
        case seen = 4           // other user have seen the message
        case error = 5
        case retracting = 6     // marked for deletion but no server ack yet
        case retracted = 7      // deleted messages
    }
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatMessage> {
        return NSFetchRequest<ChatMessage>(entityName: "ChatMessage")
    }

    @NSManaged var id: ChatMessageID
    @NSManaged var fromUserId: String
    @NSManaged var toUserId: String
    @NSManaged var text: String?
    @NSManaged var media: Set<ChatMedia>?
    
    @NSManaged var feedPostId: String?
    @NSManaged var feedPostMediaIndex: Int32
    
    @NSManaged var chatReplyMessageID: String?
    @NSManaged var chatReplyMessageSenderID: UserID?
    @NSManaged var chatReplyMessageMediaIndex: Int32
    
    @NSManaged var quoted: ChatQuoted?
    
    @NSManaged var incomingStatusValue: Int16
    @NSManaged var outgoingStatusValue: Int16
    @NSManaged var resendAttempts: Int16
    
    @NSManaged var retractID: String?

    @NSManaged var timestamp: Date?
    
    @NSManaged var cellHeight: Int16
    
    var incomingStatus: IncomingStatus {
        get {
            return IncomingStatus(rawValue: self.incomingStatusValue)!
        }
        set {
            self.incomingStatusValue = newValue.rawValue
        }
    }
    
    var outgoingStatus: OutgoingStatus {
        get {
            return OutgoingStatus(rawValue: self.outgoingStatusValue)!
        }
        set {
            self.outgoingStatusValue = newValue.rawValue
        }
    }

    public var orderedMedia: [ChatMedia] {
        get {
            guard let media = self.media else { return [] }
            return media.sorted { $0.order < $1.order }
        }
    }
}
