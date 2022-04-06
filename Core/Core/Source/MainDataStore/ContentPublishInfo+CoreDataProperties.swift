//
//  ContentPublishInfo+CoreDataProperties.swift
//  Core
//
//  Created by Garrett on 3/23/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CoreData

public extension ContentPublishInfo {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ContentPublishInfo> {
        return NSFetchRequest<ContentPublishInfo>(entityName: "ContentPublishInfo")
    }

    @NSManaged private var receiptInfo: Any?
    @NSManaged var post: FeedPost?
    @NSManaged private var audienceTypeValue: String?

    var receipts: [UserID : Receipt]? {
        get { receiptInfo as? [ UserID : Receipt ] }
        set { receiptInfo = newValue }
    }

    var audienceType: AudienceType? {
        get { AudienceType(rawValue: audienceTypeValue ?? "") }
        set { audienceTypeValue = newValue?.rawValue }
    }
}
