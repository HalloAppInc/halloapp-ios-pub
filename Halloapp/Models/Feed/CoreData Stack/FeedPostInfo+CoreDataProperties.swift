//
//  FeedPostInfo+CoreDataProperties.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/5/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreCommon
import CoreData
import Foundation
import SwiftProtobuf

extension FeedPostInfo {

    @nonobjc class func fetchRequest() -> NSFetchRequest<FeedPostInfo> {
        return NSFetchRequest<FeedPostInfo>(entityName: "FeedPostInfo")
    }

    @NSManaged private var receiptInfo: Any?
    @NSManaged private var post: FeedPost?
    @NSManaged private var privacyListTypeValue: String?

    var receipts: [UserID : Receipt]? {
        get { receiptInfo as? [ UserID : Receipt ] }
        set { receiptInfo = newValue }
    }
    
    // TODO(murali@): rename coredata attribute name - else it is confusing!
    var audienceType: AudienceType? {
        get { AudienceType(rawValue: privacyListTypeValue ?? "") }
        set { privacyListTypeValue = newValue?.rawValue }
    }

}
