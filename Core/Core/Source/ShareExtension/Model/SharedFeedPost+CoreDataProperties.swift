//
//  FeedPost+CoreDataProperties.swift
//
//
//  Created by Alan Luo on 7/16/20.
//
//

import CoreData

extension SharedFeedPost {
    public enum Status: Int16 {
        case none = 0
        case sent = 1
        case received = 2
        case sendError = 3
    }

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SharedFeedPost> {
        return NSFetchRequest<SharedFeedPost>(entityName: "SharedFeedPost")
    }
    
    @NSManaged private var statusValue: Int16

    @NSManaged public var id: FeedPostID
    @NSManaged public var text: String?
    @NSManaged public var mentions: Set<SharedFeedMention>?
    @NSManaged public var timestamp: Date
    @NSManaged public var userId: UserID
    @NSManaged public var groupId: GroupID?
    @NSManaged public var media: Set<SharedMedia>?
    @NSManaged private var privacyListTypeValue: String?
    @NSManaged public var audienceUserIds: [UserID]?

    // TODO(murali@): update attribute name in the entity.
    public var audienceType: AudienceType? {
        get { AudienceType(rawValue: privacyListTypeValue ?? "") }
        set { privacyListTypeValue = newValue?.rawValue }
    }

    public var status: Status {
        get {
            return Status(rawValue: statusValue)!
        }
        set {
            statusValue = newValue.rawValue
        }
    }

    public var audience: FeedAudience? {
        guard let audienceType = audienceType else { return nil }
        guard let userIds = audienceUserIds else { return nil }
        return FeedAudience(audienceType: audienceType, userIds: Set(userIds))
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
    public var orderedMentions: [FeedMentionProtocol] {
        guard let mentions = mentions else { return [] }
        return mentions.sorted { $0.index < $1.index }
    }

    public var orderedMedia: [FeedMediaProtocol] {
        guard let media = media else { return [] }
        return media.sorted { $0.order < $1.order }
    }
}
