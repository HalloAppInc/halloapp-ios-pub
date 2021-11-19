//
//  NotificationStatus+CoreDataProperties.swift
//  Core
//
//  Created by Murali Balusu on 11/17/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension NotificationStatus {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<NotificationStatus> {
        return NSFetchRequest<NotificationStatus>(entityName: "NotificationStatus")
    }

    @NSManaged public var contentId: String?
    @NSManaged public var contentTypeRaw: String?
    @NSManaged public var timestamp: Date?

}

extension NotificationStatus : Identifiable {

}
