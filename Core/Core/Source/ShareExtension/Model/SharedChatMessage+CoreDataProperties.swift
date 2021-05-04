//
//  SharedChatMessage+CoreDataProperties.swift
//  
//
//  Created by Alan Luo on 8/1/20.
//
//

import Foundation
import CoreData


extension SharedChatMessage {
    public enum Status: Int16 {
        case none = 0
        case sent = 1
        case received = 2
        case sendError = 3
        case acked = 4
        case decryptionError = 5
        case rerequesting = 6
    }

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SharedChatMessage> {
        return NSFetchRequest<SharedChatMessage>(entityName: "SharedChatMessage")
    }

    @NSManaged public var id: String
    @NSManaged public var toUserId: String
    @NSManaged public var fromUserId: String
    @NSManaged public var text: String?
    @NSManaged public var statusValue: Int16
    @NSManaged public var timestamp: Date
    @NSManaged public var clientChatMsgPb: Data?
    @NSManaged public var senderClientVersion: String?
    @NSManaged public var decryptionError: String?
    @NSManaged public var ephemeralKey: Data?
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
extension SharedChatMessage {

    @objc(addMediaObject:)
    @NSManaged public func addToMedia(_ value: SharedMedia)

    @objc(removeMediaObject:)
    @NSManaged public func removeFromMedia(_ value: SharedMedia)

    @objc(addMedia:)
    @NSManaged public func addToMedia(_ values: NSSet)

    @objc(removeMedia:)
    @NSManaged public func removeFromMedia(_ values: NSSet)

}

extension SharedChatMessage: ChatMessageProtocol {

    public var rerequestCount: Int32 {
        0
    }

    public var retryCount: Int32? {
        nil
    }
    
    public var orderedMedia: [ChatMediaProtocol] {
        guard let media = media else { return [] }
        return media.sorted { $0.order < $1.order }
    }

    public var feedPostId: FeedPostID? {
        nil
    }
    
    public var feedPostMediaIndex: Int32 {
        0
    }

    public var chatReplyMessageID: String? {
        nil
    }
    
    public var chatReplyMessageSenderID: UserID? {
        nil
    }
    
    public var chatReplyMessageMediaIndex: Int32 {
        0
    }
    
    public var timeIntervalSince1970: TimeInterval? {
        timestamp.timeIntervalSince1970
    }
}
