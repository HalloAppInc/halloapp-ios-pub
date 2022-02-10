//
//  ChatMessage+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Foundation
import Core
import CoreData

extension ChatMessage {

    enum IncomingStatus: Int16 {
        case none = 0
        case haveSeen = 1
        case sentSeenReceipt = 2
        case error = 3
        case retracted = 4
        case rerequesting = 5
        case unsupported = 6
        case played = 7
        case sentPlayedReceipt = 8
    }
    
    enum OutgoingStatus: Int16 {
        case none = 0
        case pending = 1        // initial state, only recorded in the database
        case sentOut = 2        // got ACK from server, timestamp is from server
        case delivered = 3      // other user have gotten the message
        case seen = 4           // other user have seen the message
        case error = 5
        case retracting = 6     // marked for deletion but no server ack yet
        case retracted = 7      // deleted messages
        case played = 8         // other user have played the message, only for voice notes
    }
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatMessage> {
        return NSFetchRequest<ChatMessage>(entityName: "ChatMessage")
    }

    @NSManaged var id: ChatMessageID
    @NSManaged var fromUserId: String
    @NSManaged var toUserId: String
    @NSManaged public var text: String?
    @NSManaged var media: Set<ChatMedia>?
    
    @NSManaged var feedPostId: String?
    @NSManaged var feedPostMediaIndex: Int32
    
    @NSManaged var chatReplyMessageID: String?
    @NSManaged var chatReplyMessageSenderID: UserID?
    @NSManaged var chatReplyMessageMediaIndex: Int32
    
    @NSManaged var quoted: ChatQuoted?
    
    @NSManaged var incomingStatusValue: Int16
    @NSManaged var outgoingStatusValue: Int16
    @NSManaged var resendAttempts: Int16
    
    @NSManaged var retractID: String?

    @NSManaged var serialID: Int32
    // TODO: we should switch this timestamp to be in milliseconds.
    @NSManaged var timestamp: Date?
    @NSManaged var serverTimestamp: Date?
    
    @NSManaged var cellHeight: Int16

    @NSManaged var rawData: Data?

    @NSManaged public var linkPreviews: Set<ChatLinkPreview>?
    
    var incomingStatus: IncomingStatus {
        get {
            return IncomingStatus(rawValue: self.incomingStatusValue)!
        }
        set {
            self.incomingStatusValue = newValue.rawValue
        }
    }
    
    var outgoingStatus: OutgoingStatus {
        get {
            return OutgoingStatus(rawValue: self.outgoingStatusValue)!
        }
        set {
            self.outgoingStatusValue = newValue.rawValue
        }
    }

    public var orderedMedia: [ChatMedia] {
        get {
            guard let media = self.media else { return [] }
            return media.sorted { $0.order < $1.order }
        }
    }

    public var linkPreviewData: [LinkPreviewProtocol] {
        get {
            var linkPreviewData = [LinkPreviewData]()
            linkPreviews?.forEach { linkPreview in
                // Check for link preview media
                var mediaData = [FeedMediaData]()
                if let linkPreviewMedia = linkPreview.media, !linkPreviewMedia.isEmpty {
                    mediaData = linkPreviewMedia
                        .map {
                            // @TODO Unify Media Objects. Github issue: 1502
                            FeedMediaData(id: "", url: $0.url , type: $0.feedMediaType , size: $0.size, key: $0.key, sha256: $0.sha256, blobVersion: .default, chunkSize: 0, blobSize: 0)
                        }
                }
                if let linkPreview = LinkPreviewData(id: linkPreview.id, url: linkPreview.url, title: linkPreview.title ?? "", description: linkPreview.desc ?? "", previewImages: mediaData) {
                    linkPreviewData.append(linkPreview)
                }
            }
            return linkPreviewData
        }
    }
}


extension ChatMessage: ChatQuotedProtocol {
    public var userId: String {
        return fromUserId
    }

    public var type: ChatQuoteType {
        return .message
    }

    public var mentions: Set<FeedMention>? {
        return nil
    }

    public var mediaList: [QuotedMedia] {
        if let media = media {
            return Array(media)
        } else {
            return []
        }
    }

}
