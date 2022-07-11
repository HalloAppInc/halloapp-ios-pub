//
//  FeedPost+CoreDataProperties.swift
//  Core
//
//  Created by Garrett on 3/21/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CoreData

public extension FeedPost {

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
        case expired = 11
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<FeedPost> {
        return NSFetchRequest<FeedPost>(entityName: "FeedPost")
    }

    @NSManaged var id: FeedPostID
    @NSManaged var isMoment: Bool
    @NSManaged var rawText: String?
    @NSManaged var timestamp: Date
    @NSManaged var userID: UserID
    @NSManaged var groupID: GroupID?
    @NSManaged var comments: Set<FeedPostComment>?
    @NSManaged var media: Set<CommonMedia>?
    @NSManaged private var mentionsValue: Any?
    var mentions: [MentionData] {
        get { return mentionsValue as? [MentionData] ?? [] }
        set { mentionsValue = newValue }
    }

    @NSManaged var linkPreviews: Set<CommonLinkPreview>?
    @NSManaged var unreadCount: Int32
    @NSManaged var info: ContentPublishInfo?
    @NSManaged var rawData: Data?
    @NSManaged var contentResendInfo: Set<ContentResendInfo>?
    @NSManaged var statusValue: Int16
    @NSManaged var fromExternalShare: Bool
    @NSManaged var lastUpdated: Date?
    @NSManaged var hasBeenProcessed: Bool

    /// The user ID of the moment that was unlocked by this post.
    ///
    /// The actual ID is only useful for the user's own (outgoing) moments.
    /// For other user's (incoming) moments, this value will either be the user's own ID, or `nil`.
    @NSManaged var unlockedMomentUserID: UserID?

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

    var isExpired: Bool {
        status == .expired
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

    var hasSaveablePostMedia: Bool {
        return media?.contains { [.image, .video].contains($0.type) } ?? false
    }
}

 extension FeedPost {

    private var postContent: PostContent {
        guard !isPostRetracted else {
            return .retracted
        }
        
        if isMoment, let media = media?.first {
            let mediaData = FeedMediaData(from: media)
            return .moment(mediaData, unlockedUserID: unlockedMomentUserID)
        }

        let mentionText = MentionText(
            collapsedText: rawText ?? "",
            mentionArray: mentions)

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
        case .incoming, .seen, .retracted, .retracting, .expired: return .received
        case .rerequesting: return .rerequesting
        }
    }

    public var postData: PostData {
        return PostData(
            id: id,
            userId: userID,
            content: postContent,
            timestamp: timestamp,
            status: feedItemStatus,
            audience: audience,
            commentKey: nil)
    }

    public var orderedMentions: [MentionData] {
        return mentions.sorted(by: { $0.index < $1.index })
     }

    public var orderedMedia: [FeedMediaProtocol] {
        get {
            guard let media = self.media else { return [] }
            return media.sorted { $0.order < $1.order }
        }
    }
}

public extension FeedPost {

    // TODO: Remove and use `userID` everywhere
    var userId: UserID {
        get { return userID }
        set { userID = newValue }
    }

    // TODO: Remove and use `groupID` everywhere
    var groupId: GroupID? {
        get { return groupID }
        set { groupID = newValue }
    }
}
