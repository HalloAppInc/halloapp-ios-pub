//
//  SharedFeedComment+CoreDataProperties.swift
//
//
//  Created by Murali Balusu on 3/20/21.
//
//
import Foundation
import CoreCommon
import CoreData


extension SharedFeedComment {
    public enum Status: Int16 {
        case none = 0
        case sent = 1               // comment is sent and acked.
        case received = 2           // comment is received but we did not send an ack yet.
        case sendError = 3          // comment could not be sent.
        case acked = 4              // comment has been acked.
        case decryptionError = 5    // comment could not be decrypted.
        case rerequesting = 6       // we sent a rerequest and an ack for a comment that could not be decrypted.
    }
    @nonobjc public class func fetchRequest() -> NSFetchRequest<SharedFeedComment> {
        return NSFetchRequest<SharedFeedComment>(entityName: "SharedFeedComment")
    }

    @NSManaged public var userId: UserID
    @NSManaged public var timestamp: Date
    @NSManaged public var text: String
    @NSManaged public var statusValue: Int16
    @NSManaged public var id: FeedPostID
    @NSManaged public var postId: FeedPostID
    @NSManaged public var parentCommentId: String?
    @NSManaged public var mentions: Set<SharedFeedMention>?
    @NSManaged public var media: Set<SharedMedia>?
    @NSManaged public var linkPreviews: Set<SharedFeedLinkPreview>?
    @NSManaged public var rawData: Data?
    public var status: Status {
        get {
            return Status(rawValue: self.statusValue)!
        }
        set {
            self.statusValue = newValue.rawValue
        }
    }
}

// MARK: Generated accessors for mentions
extension SharedFeedComment {

    @objc(addMentionsObject:)
    @NSManaged public func addToMentions(_ value: SharedFeedMention)

    @objc(removeMentionsObject:)
    @NSManaged public func removeFromMentions(_ value: SharedFeedMention)

    @objc(addMentions:)
    @NSManaged public func addToMentions(_ values: NSSet)

    @objc(removeMentions:)
    @NSManaged public func removeFromMentions(_ values: NSSet)

}
