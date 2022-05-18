//
//  FeedPostComment+CoreDataProperties.swift
//  Core
//
//  Created by Garrett on 3/22/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CoreData

public extension FeedPostComment {

    enum Status: Int16 {
        case none = 0
        case sending = 1
        case sent = 2
        case sendError = 3
        case incoming = 4
        case retracted = 5
        case retracting = 6
        case unsupported = 7
        case played = 8
        case rerequesting = 9
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<FeedPostComment> {
        return NSFetchRequest<FeedPostComment>(entityName: "FeedPostComment")
    }

    @NSManaged var id: FeedPostCommentID
    @NSManaged private var mentionsValue: Any?
    var mentions: [MentionData] {
        get { return mentionsValue as? [MentionData] ?? [] }
        set { mentionsValue = newValue }
    }

    @NSManaged var rawText: String
    @NSManaged var timestamp: Date
    @NSManaged var userID: UserID
    @NSManaged var parent: FeedPostComment?
    @NSManaged var post: FeedPost
    @NSManaged var media: Set<CommonMedia>?
    @NSManaged var replies: Set<FeedPostComment>?
    @NSManaged var linkPreviews: Set<CommonLinkPreview>?
    @NSManaged var rawData: Data?
    @NSManaged var contentResendInfo: Set<ContentResendInfo>?
    @NSManaged var hasBeenProcessed: Bool
    @NSManaged private var statusValue: Int16
    var status: Status {
        get {
            return Status(rawValue: self.statusValue)!
        }
        set {
            self.statusValue = newValue.rawValue
        }
    }

    var canBeRetracted: Bool {
        get {
            status == .sent
        }
    }

    var isRetracted: Bool {
        get {
            return status == .retracted || status == .retracting
        }
    }

    var isRerequested: Bool {
        get {
            return self.status == .rerequesting
        }
    }

    var isUnsupported: Bool {
        return status == .unsupported
    }

    var isWaiting: Bool {
        switch self.commentData.content {
        case .waiting: return true
        default: return false
        }
    }

    var isPosted: Bool {
        get {
            // TODO: murali@: allow rerequesting status as well for clients to respond for now.
            return status == .sent || status == .incoming || status == .played || status == .rerequesting
        }
    }

    var orderedMentions: [MentionData] {
        return mentions.sorted(by: { $0.index < $1.index })
     }
}

extension FeedPostComment {

    public var feedItemStatus: FeedItemStatus {
        switch status {
        case .none, .unsupported: return .none
        case .sending, .sent: return .sent
        case .sendError: return .sendError
        case .incoming, .played, .retracted, .retracting: return .received
        case .rerequesting: return .rerequesting
        }
    }

    public var commentData: CommentData {
        let mentionText = self.mentionText ?? MentionText(collapsedText: "", mentions: [:])
        let content: CommentContent

        if status == .retracted {
            content = .retracted
        } else if let media = self.media, !media.isEmpty {
            var mediaItems = [FeedMediaData]()
            media.forEach{ (media) in
                let mediaData = FeedMediaData(
                    id: "\(self.id)-\(media.order)",
                    url: media.url,
                    type: media.type,
                    size: media.size,
                    key: media.key,
                    sha256: media.sha256,
                    blobVersion: media.blobVersion,
                    chunkSize: media.chunkSize,
                    blobSize: media.blobSize)
                mediaItems.append(mediaData)
            }

            if media.count == 1 && media.first?.type == .audio {
                content = .voiceNote(mediaItems[0])
            } else {
                content = .album(mentionText, mediaItems)
            }
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
            // If status is rerequesting and the content is empty, then this means commentContent is nil.
            if feedItemStatus == .rerequesting && mentionText.isEmpty() && linkPreviewData.isEmpty {
                content = .waiting
            } else {
                content = .text(mentionText, linkPreviewData)
            }
        }

        return CommentData(
            id: id,
            userId: userID,
            timestamp: timestamp,
            feedPostId: post.id,
            parentId: parent?.id,
            content: content,
            status: feedItemStatus)
    }

    public var mentionText: MentionText? {
        guard !rawText.isEmpty else {
            return nil
        }
        return MentionText(
            collapsedText: rawText,
            mentionArray: mentions)
    }
}

public extension FeedPostComment {

    // TODO: Remove and use `userID` everywhere
    var userId: UserID {
        get { return userID }
        set { userID = newValue }
    }
}
