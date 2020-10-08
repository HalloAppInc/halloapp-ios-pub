//
//  ChatMention+CoreDataProperties.swift
//  HalloApp
//
//  Created by Garrett on 10/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreData

extension ChatMention {
    @NSManaged public var index: Int
    @NSManaged public var userID: UserID
    @NSManaged public var name: String
}

extension ChatMention: FeedMentionProtocol { }
