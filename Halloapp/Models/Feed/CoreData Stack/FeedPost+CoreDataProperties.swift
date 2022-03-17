//
//  FeedPost+CoreDataProperties.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreCommon
import CoreData
import Foundation

extension FeedPost {

    enum Status: Int16 {
        case none = 0
        case sending = 1
        case sent = 2
        case sendError = 3
        case incoming = 4
        case retracted = 5
        case retracting = 6
        case seenSending = 7
        case seen = 8
        case unsupported = 9
        case rerequesting = 10
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<FeedPost> {
        return NSFetchRequest<FeedPost>(entityName: "FeedPost")
    }

    @NSManaged public var id: FeedPostID
    @NSManaged public var text: String?
    @NSManaged public var timestamp: Date
    @NSManaged public var userId: UserID
    @NSManaged public var groupId: GroupID?
    @NSManaged var comments: Set<FeedPostComment>?
    @NSManaged var media: Set<FeedPostMedia>?
    @NSManaged public var mentions: Set<FeedMention>?
    @NSManaged public var linkPreviews: Set<FeedLinkPreview>?
    @NSManaged var unreadCount: Int32
    @NSManaged var info: FeedPostInfo?
    @NSManaged var rawData: Data?
    @NSManaged public var resendAttempts: Set<FeedItemResendAttempt>?
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
            return self.status == .retracted
        }
    }

    var isRerequested: Bool {
        get {
            return self.status == .rerequesting
        }
    }

    var isPostUnsupported: Bool {
        return self.status == .unsupported
    }

    var isWaiting: Bool {
        switch self.postData.content {
        case .waiting: return true
        default: return false
        }
    }

    var audience: FeedAudience? {
        guard let audienceType = info?.audienceType else { return nil }
        guard let receipts = info?.receipts else { return nil }
        return FeedAudience(audienceType: audienceType, userIds: Set(receipts.keys))
    }
    
    var hasPostMedia: Bool {
        return media?.count ?? 0 > 0
    }

    var hasSaveablePostMedia: Bool {
        return media?.contains { [.image, .video].contains($0.type) } ?? false
    }

    var canSaveMedia: Bool {
        return groupId != nil || userId == MainAppContext.shared.userData.userId
    }
}

extension FeedPost {

    private var postContent: PostContent {
        guard !isPostRetracted else {
            return .retracted
        }

        let mentionText = MentionText(
            collapsedText: text ?? "",
            mentionArray: Array(mentions ?? []))

        if let media = media, !media.isEmpty {
            let mediaData: [FeedMediaData] = media
                .sorted { $0.order < $1.order }
                .map { FeedMediaData(from: $0) }

            if media.count == 1, let mediaDataItem = mediaData.first, mediaDataItem.type == .audio {
                return .voiceNote(mediaDataItem)
            }

            return .album(mentionText, mediaData)
        } else {
            var linkPreviewData = [LinkPreviewData]()
            linkPreviews?.forEach { linkPreview in
                // Check for link preview media
                var mediaData = [FeedMediaData]()
                if let linkPreviewMedia = linkPreview.media, !linkPreviewMedia.isEmpty {
                    mediaData = linkPreviewMedia
                        .map { FeedMediaData(from: $0) }
                }
                if let linkPreview = LinkPreviewData(id: linkPreview.id, url: linkPreview.url, title: linkPreview.title ?? "", description: linkPreview.desc ?? "", previewImages: mediaData) {
                    linkPreviewData.append(linkPreview)
                }
            }
            // If status is rerequesting and the content is empty, then this means postContent is nil.
            if feedItemStatus == .rerequesting && mentionText.isEmpty() && linkPreviewData.isEmpty {
                return .waiting
            } else {
                return .text(mentionText, linkPreviewData)
            }
        }
    }

    public var feedItemStatus: FeedItemStatus {
        switch status {
        case .none, .unsupported: return .none
        case .sending, .sent, .seenSending: return .sent
        case .sendError: return .sendError
        case .incoming, .seen, .retracted, .retracting: return .received
        case .rerequesting: return .rerequesting
        }
    }

    public var postData: PostData {
        return PostData(
            id: id,
            userId: userId,
            content: postContent,
            timestamp: timestamp,
            status: feedItemStatus,
            audience: audience)
    }

    public var orderedMentions: [FeedMentionProtocol] {
        get {
            guard let mentions = self.mentions else { return [] }
            return mentions.sorted { $0.index < $1.index }
        }
    }

    public var orderedMedia: [FeedMediaProtocol] {
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

// MARK: Generated accessors for resendAttempts
extension FeedPost {

    @objc(addResendAttemptsObject:)
    @NSManaged public func addToResendAttempts(_ value: FeedItemResendAttempt)

    @objc(removeResendAttemptsObject:)
    @NSManaged public func removeFromResendAttempts(_ value: FeedItemResendAttempt)

    @objc(addResendAttempts:)
    @NSManaged public func addToResendAttempts(_ values: NSSet)

    @objc(removeResendAttempts:)
    @NSManaged public func removeFromResendAttempts(_ values: NSSet)

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

extension FeedPost: ChatQuotedProtocol {
    public var type: ChatQuoteType {
        return .feedpost
    }

    public var mediaList: [QuotedMedia] {
        if let media = media {
            return Array(media)
        } else {
            return []
        }
    }

}
