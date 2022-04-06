//
//  FeedPost+CoreDataClass.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Foundation
import CoreData

@objc(FeedPostLegacy)
final class FeedPostLegacy: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var groupId: String?
    @NSManaged var rawData: Data?
    @NSManaged var statusValue: Int16
    @NSManaged var text: String?
    @NSManaged var timestamp: Date
    @NSManaged var unreadCount: Int32
    @NSManaged var userId: String
    @NSManaged var comments: Set<FeedPostCommentLegacy>?
    @NSManaged var media: Set<FeedPostMedia>?
    @NSManaged var mentions: Set<FeedMention>?
    @NSManaged var linkPreviews: Set<FeedLinkPreview>?
    @NSManaged var resendAttempts: Set<FeedItemResendAttempt>?
    @NSManaged var info: FeedPostInfo?
}
