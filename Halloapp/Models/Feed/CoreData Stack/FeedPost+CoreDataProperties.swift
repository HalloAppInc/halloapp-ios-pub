//
//  FeedPost+CoreDataProperties.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Foundation
import CoreData

extension FeedPost {

    enum Status: Int16 {
        case none = 0
        case sending = 1
        case sent = 2
        case sendError = 3
        case incoming = 4
        case retracted = 5
        case retracting = 6
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<FeedPost> {
        return NSFetchRequest<FeedPost>(entityName: "FeedPost")
    }

    @NSManaged var id: FeedPostID
    @NSManaged var text: String?
    @NSManaged var timestamp: Date
    @NSManaged var userId: UserID
    @NSManaged var comments: Set<FeedPostComment>?
    @NSManaged var media: Set<FeedPostMedia>?
    @NSManaged var unreadCount: Int32
    @NSManaged var info: FeedPostInfo?
    @NSManaged private var statusValue: Int16
    var status: Status {
        get {
            return Status(rawValue: self.statusValue)!
        }
        set {
            self.statusValue = newValue.rawValue
        }
    }

    var isPostRetracted: Bool {
        get {
            return self.status == .retracted || self.status == .retracting
        }
    }

}

extension FeedPost: FeedPostProtocol {

    static var itemType: FeedItemType {
        .post
    }

    var orderedMedia: [FeedMediaProtocol] {
        get {
            guard let media = self.media else { return [] }
            return media.sorted { $0.order < $1.order }
        }
    }
}

// MARK: Generated accessors for comments
extension FeedPost {

    @objc(addCommentsObject:)
    @NSManaged func addToComments(_ value: FeedPostComment)

    @objc(removeCommentsObject:)
    @NSManaged func removeFromComments(_ value: FeedPostComment)

    @objc(addComments:)
    @NSManaged func addToComments(_ values: NSSet)

    @objc(removeComments:)
    @NSManaged func removeFromComments(_ values: NSSet)

}

// MARK: Generated accessors for media
extension FeedPost {

    @objc(addMediaObject:)
    @NSManaged func addToMedia(_ value: FeedPostMedia)

    @objc(removeMediaObject:)
    @NSManaged func removeFromMedia(_ value: FeedPostMedia)

    @objc(addMedia:)
    @NSManaged func addToMedia(_ values: NSSet)

    @objc(removeMedia:)
    @NSManaged func removeFromMedia(_ values: NSSet)

}
