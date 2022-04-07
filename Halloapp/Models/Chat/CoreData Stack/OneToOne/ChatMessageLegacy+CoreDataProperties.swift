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
import CoreCommon
import CoreData

extension ChatMessageLegacy {
    
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
    
    @NSManaged var quoted: ChatQuotedLegacy?
    
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
    
    var incomingStatus: ChatMessage.IncomingStatus {
        get {
            return ChatMessage.IncomingStatus(rawValue: self.incomingStatusValue)!
        }
        set {
            self.incomingStatusValue = newValue.rawValue
        }
    }
    
    var outgoingStatus: ChatMessage.OutgoingStatus {
        get {
            return ChatMessage.OutgoingStatus(rawValue: self.outgoingStatusValue)!
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
