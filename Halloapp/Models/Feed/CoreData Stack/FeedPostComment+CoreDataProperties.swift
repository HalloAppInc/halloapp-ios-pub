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
        if let media = self.media {
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

            return CommentData(
                id: id,
                userId: userId,
                timestamp: timestamp,
                feedPostId: post.id,
                parentId: parent?.id,
                content: .album(mentionText, mediaItems))
        }

        return CommentData(
            id: id,
            userId: userId,
            timestamp: timestamp,
            feedPostId: post.id,
            parentId: parent?.id,
            content: .text(mentionText))
    }

    public var mentionText: MentionText? {
        guard !text.isEmpty else {
            return nil
        }
        guard let mentions = mentions, !mentions.isEmpty else {
            return MentionText(collapsedText: text, mentions: [:])
        }
        return MentionText(
            collapsedText: text,
            mentions: mentionDictionary(from: Array(mentions)))
    }

    private func mentionDictionary(from mentions: [FeedMentionProtocol]) -> [Int: MentionedUser] {
        Dictionary(uniqueKeysWithValues: mentions.map {
            (Int($0.index), MentionedUser(userID: $0.userID, pushName: $0.name))
        })
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
