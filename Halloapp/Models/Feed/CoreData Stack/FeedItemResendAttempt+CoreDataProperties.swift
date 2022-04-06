//
//  FeedItemResendAttempt+CoreDataProperties.swift
//  HalloApp
//
//  Created by Murali Balusu on 10/6/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//
//

import Core
import CoreData
import Foundation

extension FeedItemResendAttempt {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<FeedItemResendAttempt> {
        return NSFetchRequest<FeedItemResendAttempt>(entityName: "FeedItemResendAttempt")
    }

    @NSManaged public var userID: String
    @NSManaged public var contentID: String
    @NSManaged public var retryCount: Int32
    @NSManaged public var post: FeedPost?
    @NSManaged public var comment: FeedPostComment?

}

extension FeedItemResendAttempt : Identifiable {

}
