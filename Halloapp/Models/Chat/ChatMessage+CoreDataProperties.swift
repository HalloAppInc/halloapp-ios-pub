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
        case sentSeenReceipt = 1
        case error = 2
    }
    
    enum SenderStatus: Int16 {
        case none = 0
        case delivered = 1
        case seen = 2
        case error = 3
    }
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatMessage> {
        return NSFetchRequest<ChatMessage>(entityName: "ChatMessage")
    }

    @NSManaged var fromUserId: String
    @NSManaged var id: ChatMessageID
    @NSManaged var receiverStatusValue: Int16
    @NSManaged var senderStatusValue: Int16
    @NSManaged var text: String?
    @NSManaged var timestamp: Date?
    @NSManaged var toUserId: String
    @NSManaged var media: Set<ChatMedia>?
    
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
