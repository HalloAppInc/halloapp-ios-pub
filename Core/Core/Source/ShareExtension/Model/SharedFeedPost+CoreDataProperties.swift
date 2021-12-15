//
//  FeedPost+CoreDataProperties.swift
//
//
//  Created by Alan Luo on 7/16/20.
//
//

import CoreData

extension SharedFeedPost {
    public enum Status: Int16 {
        case none = 0
        case sent = 1               // post is sent and acked.
        case received = 2           // post is received but we did not send an ack yet.
        case sendError = 3          // post could not be sent.
        case acked = 4              // post has been acked.
        case decryptionError = 5    // post could not be decrypted.
        case rerequesting = 6       // we sent a rerequest and an ack for a post that could not be decrypted.
    }

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SharedFeedPost> {
        return NSFetchRequest<SharedFeedPost>(entityName: "SharedFeedPost")
    }
    
    @NSManaged private var statusValue: Int16

    @NSManaged public var id: FeedPostID
    @NSManaged public var text: String?
    @NSManaged public var mentions: Set<SharedFeedMention>?
    @NSManaged public var timestamp: Date
    @NSManaged public var userId: UserID
    @NSManaged public var groupId: GroupID?
    @NSManaged public var media: Set<SharedMedia>?
    @NSManaged public var linkPreviews: Set<SharedFeedLinkPreview>?
    @NSManaged private var privacyListTypeValue: String?
    @NSManaged public var audienceUserIds: [UserID]?
    @NSManaged public var rawData: Data?

    // TODO(murali@): update attribute name in the entity.
    public var audienceType: AudienceType? {
        get { AudienceType(rawValue: privacyListTypeValue ?? "") }
        set { privacyListTypeValue = newValue?.rawValue }
    }

    public var status: Status {
        get {
            return Status(rawValue: statusValue)!
        }
        set {
            statusValue = newValue.rawValue
        }
    }

    public var audience: FeedAudience? {
        guard let audienceType = audienceType else { return nil }
        guard let userIds = audienceUserIds else { return nil }
        return FeedAudience(audienceType: audienceType, userIds: Set(userIds))
    }

}

// MARK: Generated accessors for media
extension SharedFeedPost {

    @objc(addMediaObject:)
    @NSManaged public func addToMedia(_ value: SharedMedia)

    @objc(removeMediaObject:)
    @NSManaged public func removeFromMedia(_ value: SharedMedia)

    @objc(addMedia:)
    @NSManaged public func addToMedia(_ values: NSSet)

    @objc(removeMedia:)
    @NSManaged public func removeFromMedia(_ values: NSSet)

}

extension SharedFeedPost {

    private var postContent: PostContent {
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
                if let linkPreview = LinkPreviewData(id: linkPreview.id , url: linkPreview.url, title: linkPreview.title ?? "", description: linkPreview.desc ?? "", previewImages: mediaData) {
                    linkPreviewData.append(linkPreview)
                }
            }
            return .text(mentionText, linkPreviewData)
        }
    }

    private var feedItemStatus: FeedItemStatus {
        switch status {
        case .none: return .none
        case .sent: return .sent
        case .sendError: return .sendError
        case .received, .acked: return .received
        case .decryptionError, .rerequesting: return .rerequesting
        }
    }

    public var postData: PostData {
        return PostData(
            id: id,
            userId: userId,
            content: postContent,
            timestamp: timestamp,
            status: feedItemStatus)
    }

    public var orderedMentions: [FeedMentionProtocol] {
        guard let mentions = mentions else { return [] }
        return mentions.sorted { $0.index < $1.index }
    }

    public var orderedMedia: [FeedMediaProtocol] {
        guard let media = media else { return [] }
        return media.sorted { $0.order < $1.order }
    }
}
