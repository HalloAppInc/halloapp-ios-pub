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
        case sent = 1               // message is sent and acked.
        case received = 2           // message is received but we did not send an ack yet.
        case sendError = 3          // message could not be sent.
        case acked = 4              // message has been acked.
        case decryptionError = 5    // message could not be decrypted.
        case rerequesting = 6       // we sent a rerequest and an ack for a message that could not be decrypted.
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
    @NSManaged public var serverTimestamp: Date?
    @NSManaged public var serialID: Int32
    @NSManaged public var clientChatMsgPb: Data?
    // TODO(murali@): it is not good to have both clientChatMsgPb and serverMsgPb
    // We should just use serverMsgPb.
    @NSManaged public var serverMsgPb: Data?
    @NSManaged public var senderClientVersion: String?
    @NSManaged public var decryptionError: String?
    @NSManaged public var ephemeralKey: Data?
    @NSManaged public var media: Set<SharedMedia>?
    @NSManaged public var linkPreviews: Set<SharedFeedLinkPreview>?
    
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

    public var context: ChatContext {
        return ChatContext()
    }
    
    public var timeIntervalSince1970: TimeInterval? {
        timestamp.timeIntervalSince1970
    }
    
    public var linkPreviewData: [LinkPreviewProtocol] {
        switch content {
        case .album, .reaction, .voiceNote, .unsupported:
            return []
        case .text(_, let linkPreviewData):
            return linkPreviewData
        }
    }

    public var content: ChatContent {
        if orderedMedia.isEmpty {
            var linkPreviewData = [LinkPreviewData]()
            if let linkPreviews = linkPreviews , !linkPreviews.isEmpty {
                linkPreviews.forEach { linkPreview in
                    // Check for link preview media
                    var mediaData = [FeedMediaData]()
                    if let linkPreviewMedia = linkPreview.media, !linkPreviewMedia.isEmpty {
                        mediaData = linkPreviewMedia
                            .map {
                                FeedMediaData(from: $0)
                            }
                    }
                    if let linkPreview = LinkPreviewData(id: linkPreview.id, url: linkPreview.url, title: linkPreview.title ?? "", description: linkPreview.desc ?? "", previewImages: mediaData) {
                        linkPreviewData.append(linkPreview)
                    }
                }
            }
            return .text(text ?? "", linkPreviewData)
        } else {
            return .album(text, orderedMedia)
        }
    }
}
