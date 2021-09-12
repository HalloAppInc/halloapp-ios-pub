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

    var isUnsupported: Bool {
        return status == .unsupported
    }

    var isPosted: Bool {
        get {
            return status == .sent || status == .incoming
        }
    }
}

extension FeedPostComment {
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
            content = .text(mentionText)
        }

        return CommentData(
            id: id,
            userId: userId,
            timestamp: timestamp,
            feedPostId: post.id,
            parentId: parent?.id,
            content: content)
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
