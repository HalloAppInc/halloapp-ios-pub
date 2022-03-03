//
//  FeedLinkPreview+CoreDataProperties.swift
//  HalloApp
//
//  Created by Nandini Shetty on 9/29/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import Foundation
import CoreData


extension FeedLinkPreview {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<FeedLinkPreview> {
        return NSFetchRequest<FeedLinkPreview>(entityName: "FeedLinkPreview")
    }

    @NSManaged public var id: FeedLinkPreviewID
    @NSManaged public var desc: String?
    @NSManaged public var title: String?
    @NSManaged public var url: URL?
    @NSManaged public var comment: FeedPostComment?
    @NSManaged var media: Set<FeedPostMedia>?
    @NSManaged public var post: FeedPost?

}

// MARK: Generated accessors for media
extension FeedLinkPreview {

    @objc(addMediaObject:)
    @NSManaged public func addToMedia(_ value: FeedPostMedia)

    @objc(removeMediaObject:)
    @NSManaged public func removeFromMedia(_ value: FeedPostMedia)

    @objc(addMedia:)
    @NSManaged public func addToMedia(_ values: NSSet)

    @objc(removeMedia:)
    @NSManaged public func removeFromMedia(_ values: NSSet)

}

extension FeedLinkPreview : Identifiable {

}
