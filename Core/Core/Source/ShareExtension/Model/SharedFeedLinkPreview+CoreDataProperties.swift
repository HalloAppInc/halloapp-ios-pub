//
//  SharedFeedLinkPreview+CoreDataProperties.swift
//  Core
//
//  Created by Nandini Shetty on 9/29/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import CoreData
import Foundation


extension SharedFeedLinkPreview {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SharedFeedLinkPreview> {
        return NSFetchRequest<SharedFeedLinkPreview>(entityName: "SharedFeedLinkPreview")
    }

    @NSManaged public var id: FeedLinkPreviewID
    @NSManaged public var desc: String?
    @NSManaged public var title: String?
    @NSManaged public var url: URL?
    @NSManaged public var comment: SharedFeedComment?
    @NSManaged public var media: Set<SharedMedia>?
    @NSManaged public var post: SharedFeedPost?

}

// MARK: Generated accessors for media
extension SharedFeedLinkPreview {

    @objc(addMediaObject:)
    @NSManaged public func addToMedia(_ value: SharedMedia)

    @objc(removeMediaObject:)
    @NSManaged public func removeFromMedia(_ value: SharedMedia)

    @objc(addMedia:)
    @NSManaged public func addToMedia(_ values: NSSet)

    @objc(removeMedia:)
    @NSManaged public func removeFromMedia(_ values: NSSet)

}

extension SharedFeedLinkPreview : Identifiable {

}
