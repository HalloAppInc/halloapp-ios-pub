//
//  CommonReaction+CoreDataProperties.swift
//  Core
//
//  Created by Vaishvi Patel on 7/19/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreData

public typealias CommonReactionID = String

public extension CommonReaction {

    enum IncomingStatus: Int16 {
        case none = 0
        case error = 1
        case retracted = 2
        case rerequesting = 3
        case unsupported = 4
        case incoming = 5
    }

    enum OutgoingStatus: Int16 {
        case none = 0
        case pending = 1        // initial state, only recorded in the database
        case sentOut = 2        // got ACK from server, timestamp is from server
        case delivered = 3      // other user have gotten the reaction
        case seen = 4           // other user have seen the reaction
        case error = 5
        case retracting = 6     // marked for deletion but no server ack yet
        case retracted = 7      // deleted reactions
    }
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<CommonReaction> {
        return NSFetchRequest<CommonReaction>(entityName: "CommonReaction")
    }

    @NSManaged var id: CommonReactionID
    @NSManaged var emoji: String
    @NSManaged var toUserID: String
    @NSManaged var fromUserID: String
    @NSManaged var timestamp: Date
    @NSManaged var serverTimestamp: Date
    @NSManaged var incomingStatusValue: Int16
    @NSManaged var outgoingStatusValue: Int16
    @NSManaged var resendAttempts: Int16
    @NSManaged var retractID: String

    @NSManaged var message: ChatMessage?
    @NSManaged var comment: FeedPostComment?

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
}
