//
//  ChatMessage+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension ChatMessage {

    enum ReceiverStatus: Int16 {
        case none = 0
        case haveSeen = 1
        case sentSeenReceipt = 2
        case error = 3
    }
    
    enum SenderStatus: Int16 {
        case none = 0
        case pending = 1        // initial state, only recorded in the database
        case sentOut = 2        // got ACK from server, timestamp is from server
        case delivered = 3      // other user have gotten the message
        case seen = 4           // other user have seen the message
        case error = 5
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
    
    @NSManaged var quoted: ChatQuoted?
    
    @NSManaged var receiverStatusValue: Int16
    @NSManaged var senderStatusValue: Int16

    @NSManaged var timestamp: Date?
    
    var receiverStatus: ReceiverStatus {
        get {
            return ReceiverStatus(rawValue: self.receiverStatusValue)!
        }
        set {
            self.receiverStatusValue = newValue.rawValue
        }
    }
    
    var senderStatus: SenderStatus {
        get {
            return SenderStatus(rawValue: self.senderStatusValue)!
        }
        set {
            self.senderStatusValue = newValue.rawValue
        }
    }

}
