//
//  FeedMention+CoreDataProperties.swift
//  HalloApp
//
//  Created by Garrett on 7/27/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreData

extension FeedMention {

    @NSManaged public var index: Int
    @NSManaged public var userID: UserID
    @NSManaged public var name: String
}

extension FeedMention: FeedMentionProtocol { }
