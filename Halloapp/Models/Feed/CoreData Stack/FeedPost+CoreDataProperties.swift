//
//  FeedPost+CoreDataProperties.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
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
    @NSManaged var unreadCount: Int32
    @NSManaged var info: FeedPostInfo?
    @NSManaged var rawData: Data?
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

    var isPostUnsupported: Bool {
        return self.status == .unsupported
    }

    var audience: FeedAudience? {
        guard let audienceType = info?.audienceType else { return nil }
        guard let receipts = info?.receipts else { return nil }
        return FeedAudience(audienceType: audienceType, userIds: Set(receipts.keys))
    }
    
    var hasPostMedia: Bool {
        return media?.count ?? 0 > 0
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

            return .album(mentionText, mediaData)
        } else {
            // TODO process linkPreviewData
            var linkPreviewData = [LinkPreviewData]()
            return .text(mentionText, linkPreviewData)
        }
    }

    public var postData: PostData {
        return PostData(
            id: id,
            userId: userId,
            content: postContent,
            timestamp: timestamp)
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
