//
//  GroupFeedItemDecryption+CoreDataProperties.swift
//  
//
//  Created by Murali Balusu on 9/29/21.
//
//

import Foundation
import CoreData


extension GroupFeedItemDecryption {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<GroupFeedItemDecryption> {
        return NSFetchRequest<GroupFeedItemDecryption>(entityName: "GroupFeedItemDecryption")
    }

    @NSManaged public var contentID: String
    @NSManaged public var contentType: String
    @NSManaged public var decryptionError: String
    @NSManaged public var groupID: String
    @NSManaged public var userAgentReceiver: String
    @NSManaged public var hasBeenReported: Bool
    @NSManaged public var rerequestCount: Int32
    @NSManaged public var timeDecrypted: Date?
    @NSManaged public var timeReceived: Date?

}
