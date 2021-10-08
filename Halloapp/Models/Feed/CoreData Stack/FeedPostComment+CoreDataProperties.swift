//
//  FeedPostComment+CoreDataProperties.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreData
import Foundation

extension FeedPostComment {

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

    @NSManaged public var id: FeedPostID
    @NSManaged public var mentions: Set<FeedMention>?
    @NSManaged public var text: String
    @NSManaged public var timestamp: Date
    @NSManaged public var userId: UserID
    @NSManaged var parent: FeedPostComment?
    @NSManaged var post: FeedPost
    @NSManaged var media: Set<FeedPostMedia>?
    @NSManaged var replies: Set<FeedPostComment>?
    @NSManaged public var linkPreviews: Set<FeedLinkPreview>?
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

    var isPosted: Bool {
        get {
            // TODO: murali@: allow rerequesting status as well for clients to respond for now.
            return status == .sent || status == .incoming || status == .played || status == .rerequesting
        }
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

        if let media = self.media, !media.isEmpty {
            var mediaItems = [FeedMediaData]()
            media.forEach{ (media) in
                let mediaData = FeedMediaData(
                    id: "\(self.id)-\(media.order)",
                    url: media.url,
                    type: media.type,
                    size: media.size,
                    key: media.key,
                    sha256: media.sha256)
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
                if let linkPreviewMedia = linkPreview.media, linkPreviewMedia.isEmpty {
                    mediaData = linkPreviewMedia
                        .map { FeedMediaData(from: $0) }
                }
                if let linkPreview = LinkPreviewData(id: linkPreview.id, url: linkPreview.url, title: linkPreview.title ?? "", description: linkPreview.desc ?? "", previewImages: mediaData) {
                    linkPreviewData.append(linkPreview)
                }
            }
            content = .text(mentionText, linkPreviewData)
        }

        return CommentData(
            id: id,
            userId: userId,
            timestamp: timestamp,
            feedPostId: post.id,
            parentId: parent?.id,
            content: content,
            status: feedItemStatus)
    }

    public var mentionText: MentionText? {
        guard !text.isEmpty else {
            return nil
        }
        return MentionText(
            collapsedText: text,
            mentionArray: Array(mentions ?? []))
    }
}

extension FeedPostComment {

    @objc(addMediaObject:)
    @NSManaged func addToMedia(_ value: FeedPostMedia)

    @objc(removeMediaObject:)
    @NSManaged func removeFromMedia(_ value: FeedPostMedia)

    @objc(addMedia:)
    @NSManaged func addToMedia(_ values: NSSet)

    @objc(removeMedia:)
    @NSManaged func removeFromMedia(_ values: NSSet)

}

// MARK: Generated accessors for resendAttempts
extension FeedPostComment {

    @objc(addResendAttemptsObject:)
    @NSManaged public func addToResendAttempts(_ value: FeedItemResendAttempt)

    @objc(removeResendAttemptsObject:)
    @NSManaged public func removeFromResendAttempts(_ value: FeedItemResendAttempt)

    @objc(addResendAttempts:)
    @NSManaged public func addToResendAttempts(_ values: NSSet)

    @objc(removeResendAttempts:)
    @NSManaged public func removeFromResendAttempts(_ values: NSSet)

}
