//
//  FeedPostCommentKey+CoreDataProperties.swift
//  Core
//
//  Created by Murali Balusu on 6/19/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension FeedPostCommentKey {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<FeedPostCommentKey> {
        return NSFetchRequest<FeedPostCommentKey>(entityName: "FeedPostCommentKey")
    }

    @NSManaged public var postID: String
    @NSManaged public var commentKey: Data

}

extension FeedPostCommentKey : Identifiable {

}
