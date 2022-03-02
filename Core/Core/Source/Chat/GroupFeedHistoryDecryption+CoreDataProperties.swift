//
//  GroupFeedHistoryDecryption+CoreDataProperties.swift
//  Core
//
//  Created by Murali Balusu on 2/28/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension GroupFeedHistoryDecryption {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<GroupFeedHistoryDecryption> {
        return NSFetchRequest<GroupFeedHistoryDecryption>(entityName: "GroupFeedHistoryDecryption")
    }

    @NSManaged public var groupID: String
    @NSManaged public var numDecrypted: Int32
    @NSManaged public var numExpected: Int32
    @NSManaged public var rerequestCount: Int32
    @NSManaged public var timeLastUpdated: Date
    @NSManaged public var timeReceived: Date
    @NSManaged public var userAgentReceiver: String
    @NSManaged public var hasBeenReported: Bool

}

extension GroupFeedHistoryDecryption : Identifiable {

}
