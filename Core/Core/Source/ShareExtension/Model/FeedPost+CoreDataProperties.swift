//
//  FeedPost+CoreDataProperties.swift
//  
//
//  Created by Alan Luo on 7/16/20.
//
//

import Foundation
import CoreData
import SwiftProtobuf


extension SharedFeedPost {
    public enum Status: Int16 {
        case none = 0
        case sent = 1
        case received = 2
    }

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SharedFeedPost> {
        return NSFetchRequest<SharedFeedPost>(entityName: "SharedFeedPost")
    }
    
    @NSManaged private var statusValue: Int16

    @NSManaged public var id: FeedPostID
    @NSManaged public var text: String?
    @NSManaged public var timestamp: Date
    @NSManaged public var userId: UserID
    @NSManaged public var media: Set<SharedMedia>?

    public var status: Status {
        get {
            return Status(rawValue: self.statusValue)!
        }
        set {
            self.statusValue = newValue.rawValue
        }
    }
}

// MARK: Generated accessors for media
extension SharedFeedPost {

    @objc(addMediaObject:)
    @NSManaged public func addToMedia(_ value: SharedMedia)

    @objc(removeMediaObject:)
    @NSManaged public func removeFromMedia(_ value: SharedMedia)

    @objc(addMedia:)
    @NSManaged public func addToMedia(_ values: NSSet)

    @objc(removeMedia:)
    @NSManaged public func removeFromMedia(_ values: NSSet)

}

extension SharedFeedPost: FeedItemProtocol {
    public static var itemType: FeedItemType {
        .post
    }
}

extension SharedFeedPost: FeedPostProtocol {
    public var orderedMedia: [FeedMediaProtocol] {
        guard let media = media else { return [] }
        return media.sorted { $0.order < $1.order }
    }
}
