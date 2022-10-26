//
//  ChatReceiptInfo+CoreDataProperties.swift
//  Core
//
//  Created by Nandini Shetty on 10/18/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CoreData
import Foundation

public extension ChatReceiptInfo {

    enum OutgoingStatus: Int16 {
        case none = 0
        case delivered = 1      // other user have gotten the message
        case seen = 2           // other user have seen the message
        case played = 3         // other user have played the message, only for voice notes
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<ChatReceiptInfo> {
        return NSFetchRequest<ChatReceiptInfo>(entityName: "ChatReceiptInfo")
    }

    @NSManaged var chatMessageId: String
    @NSManaged var userId: UserID
    @NSManaged var status: Int16
    @NSManaged var chatMessage: ChatMessage
    @NSManaged var timestamp: Date

    var outgoingStatus: OutgoingStatus {
        get {
            return OutgoingStatus(rawValue: self.status)!
        }
        set {
            self.status = newValue.rawValue
        }
    }

}
