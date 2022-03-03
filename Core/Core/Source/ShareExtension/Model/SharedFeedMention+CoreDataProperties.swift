//
//  SharedFeedMention+CoreDataProperties.swift
//  Core
//
//  Created by Garrett on 7/29/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation
import CoreCommon

extension SharedFeedMention {

    @NSManaged public var index: Int
    @NSManaged public var userID: UserID
    @NSManaged public var name: String
}

extension SharedFeedMention: FeedMentionProtocol { }
