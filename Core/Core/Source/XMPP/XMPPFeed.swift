//
//  XMPPFeed.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/15/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CoreCommon
import CocoaLumberjackSwift
import Foundation
import SwiftProtobuf

// MARK: Concrete classes

public enum PostContent {
    case text(MentionText, [LinkPreviewData])
    case album(MentionText, [FeedMediaData])
    case retracted
    case unsupported(Data)
    case voiceNote(FeedMediaData)
    case moment(FeedMediaData, unlockedUserID: UserID?)
    case waiting
}

// It is a bit confusing to use this in some places and other status in some places.
// TODO: murali@: we should somehow unify it everywhere.
public enum FeedItemStatus: Int16 {
    case none = 0
    case sent = 1               // feedItem is sent and acked.
    case received = 2           // feedItem is received fine - decrypted fine if we received encrypted payload.
    case sendError = 3          // feedItem could not be sent.
    case rerequesting = 4       // feedItem is being rerequested
}

public struct PostData {

    // MARK: FeedItem
    public let id: FeedPostID
    public let userId: UserID
    public var timestamp: Date = Date()
    public var status: FeedItemStatus
    public let isShared: Bool
    public let expiration: Date?

    // MARK: FeedPost
    public var content: PostContent
    public var commentKey: Data?

    public var audience: FeedAudience?

    public var isMoment: Bool {
        switch content {
        case .text, .album, .retracted, .unsupported, .voiceNote, .waiting:
            return false
        case .moment:
            return true
        }
    }

    public var text: String? {
        switch content {
        case .retracted, .unsupported, .voiceNote, .waiting, .moment:
            return nil
        case .text(let mentionText, _):
            return mentionText.collapsedText
        case .album(let mentionText, _):
            return mentionText.collapsedText
        }
    }

    public var orderedMedia: [FeedMediaData] {
        switch content {
        case .album(_, let media):
            return media
        case .voiceNote(let mediaItem):
            return [mediaItem]
        case .moment(let media, _):
            return [media]
        case .retracted, .text, .unsupported, .waiting:
            return []
        }
    }

    public var orderedMentions: [FeedMentionProtocol] {
        let mentions: [Int: MentionedUser] = {
            switch content {
            case .retracted, .unsupported, .voiceNote, .waiting, .moment:
                return [:]
            case .album(let mentionText, _):
                return mentionText.mentions
            case .text(let mentionText, _):
                return mentionText.mentions
            }
        }()
        return mentions
            .map { (i, user) in
                MentionData(index: i, userID: user.userID, name: user.pushName ?? "")
            }
            .sorted { $0.index < $1.index }
    }
    
    public var linkPreviewData: [LinkPreviewData] {
        switch content {
        case .retracted, .unsupported, .album, .voiceNote, .waiting, .moment:
            return []
        case .text(_, let linkPreviewData):
            return linkPreviewData
        }
    }

    public var mediaCounters: MediaCounters {
        switch content {
        case .album(_, let media):
            var counters = MediaCounters()
            media.forEach { mediaItem in
                counters.count(mediaItem.type)
            }
            return counters
        case .text(_, _):
            return MediaCounters()
        case .retracted, .unsupported, .waiting:
            return MediaCounters()
        case .voiceNote:
            return MediaCounters(numImages: 0, numVideos: 0, numAudio: 1)
        case .moment(let media, _):
            // can only be an image for now, but leaving this in for eventual video support
            return MediaCounters(numImages: media.type == .image ? 1 : 0,
                                 numVideos: media.type == .video ? 1 : 0,
                                  numAudio: 0)
        }
    }

    var serverMediaCounters: Server_MediaCounters {
        var counters = Server_MediaCounters()
        let mediaCounters = mediaCounters
        counters.numImages = mediaCounters.numImages
        counters.numVideos = mediaCounters.numVideos
        counters.numAudio = mediaCounters.numAudio
        return counters
    }

    public init(id: FeedPostID, userId: UserID, content: PostContent, timestamp: Date = Date(), expiration: Date?, status: FeedItemStatus, isShared: Bool = false, audience: FeedAudience?, commentKey: Data?) {
        self.id = id
        self.userId = userId
        self.content = content
        self.timestamp = timestamp
        self.expiration = expiration
        self.status = status
        self.isShared = isShared
        self.audience = audience
        self.commentKey = commentKey
    }

    public init(id: FeedPostID, userId: UserID, content: PostContent, timestamp: Date = Date(), expiration: Date?, status: FeedItemStatus, isShared: Bool = false, audience: Server_Audience?, commentKey: Data?) {
        var feedAudience: FeedAudience?
        // Setup audience
        if let audience = audience {
            let audienceUserIDs = audience.uids.compactMap { UserID($0) }
            let audienceType: AudienceType? = {
                switch audience.type {
                case .all:
                    return AudienceType.all
                case .only:
                    return AudienceType.whitelist
                case .except:
                    return AudienceType.blacklist
                case .UNRECOGNIZED(_):
                    return nil
                }
            }()
            if let audienceType = audienceType {
                feedAudience = FeedAudience(audienceType: audienceType, userIds: Set(audienceUserIDs))
            }
        }
        self.init(id: id, userId: userId, content: content, timestamp: timestamp, expiration: expiration, status: status,
                  isShared: isShared, audience: feedAudience, commentKey: commentKey)
    }

    public init?(_ serverPost: Server_Post, expiration: Date?, status: FeedItemStatus, itemAction: ItemAction, usePlainTextPayload: Bool = true,
                 isShared: Bool = false) {

        let postId = serverPost.id
        let userId = UserID(serverPost.publisherUid)
        let timestamp = Date(timeIntervalSince1970: TimeInterval(serverPost.timestamp))

        // Fallback to plainText payload depending on the boolean here.
        if usePlainTextPayload {
            // If it is shared - then action could be retract and content must be set to retracted.
            if isShared {
                switch itemAction {
                case .none, .publish, .share:
                    self.init(id: postId, userId: userId, timestamp: timestamp, expiration: expiration, payload: serverPost.payload, status: status, isShared: isShared, audience: serverPost.audience)
                case .retract:
                    self.init(id: postId, userId: userId, content: .retracted, timestamp: timestamp, expiration: expiration, status: status, isShared: isShared, audience: serverPost.audience, commentKey: nil)
                }
            } else {
                self.init(id: postId, userId: userId, timestamp: timestamp, expiration: expiration, payload: serverPost.payload, status: status, isShared: isShared, audience: serverPost.audience)
            }
        } else {
            self.init(id: postId, userId: userId, content: .waiting, timestamp: timestamp, expiration: expiration, status: status, isShared: isShared, audience: serverPost.audience, commentKey: nil)
        }

        if case let .moment(media, _) = content, serverPost.momentUnlockUid == Int64(AppContextCommon.shared.userData.userId) {
            self.content = .moment(media, unlockedUserID: AppContextCommon.shared.userData.userId)
        }
    }

    public init?(id: String, userId: UserID, timestamp: Date, expiration: Date?, payload: Data, status: FeedItemStatus, isShared: Bool = false, audience: FeedAudience?) {
        guard let processedContent = PostData.extractContent(postId: id, payload: payload) else {
            return nil
        }
        let commentKey = PostData.extractCommentKey(postId: id, payload: payload)
        self.init(id: id, userId: userId, content: processedContent, timestamp: timestamp, expiration: expiration, status: status,
                  isShared: isShared, audience: audience, commentKey: commentKey)
    }

    public init?(id: String, userId: UserID, timestamp: Date, expiration: Date?, payload: Data, status: FeedItemStatus, isShared: Bool = false, audience: Server_Audience?) {
        guard let processedContent = PostData.extractContent(postId: id, payload: payload) else {
            return nil
        }
        let commentKey = PostData.extractCommentKey(postId: id, payload: payload)
        self.init(id: id, userId: userId, content: processedContent, timestamp: timestamp, expiration: expiration, status: status,
                  isShared: isShared, audience: audience, commentKey: commentKey)
    }

    public init?(blob: Clients_PostContainerBlob, expiration: Date?) {
        // Re-convert the postContainer to data so that we can save it for unsupported posts
        guard let payload = try? blob.postContainer.serializedData(),
              let content = Self.extractContent(postId: blob.postID, postContainer: blob.postContainer, payload: payload)  else {
            return nil
        }

        let commentKey = blob.postContainer.commentKey
        self.init(id: blob.postID,
                  userId: String(blob.uid),
                  content: content,
                  timestamp: Date(timeIntervalSince1970: TimeInterval(blob.timestamp)),
                  expiration: expiration,
                  status: .received,
                  isShared: false,
                  audience: nil as FeedAudience?,
                  commentKey: commentKey.isEmpty ? nil : commentKey)
    }

    private static func extractContent(postId: FeedPostID, payload: Data) -> PostContent? {
        guard let protoContainer = try? Clients_Container(serializedData: payload) else {
            DDLogError("Could not deserialize post [\(postId)]")
            return nil
        }
        if protoContainer.hasPostContainer {
            // Future-proof post
            return extractContent(postId: postId, postContainer: protoContainer.postContainer, payload: payload)
        } else {
            DDLogError("Unrecognized post (no post or post container set)")
            return nil
        }
    }

    private static func extractCommentKey(postId: FeedPostID, payload: Data) -> Data? {
        guard let protoContainer = try? Clients_Container(serializedData: payload) else {
            DDLogError("Could not deserialize post [\(postId)]")
            return nil
        }
        if protoContainer.hasPostContainer {
            let commentKey = protoContainer.postContainer.commentKey
            return commentKey.isEmpty ? nil : commentKey
        } else {
            DDLogError("Unrecognized post (no post or post container set)")
            return nil
        }
    }

    private static func extractContent(postId: FeedPostID, postContainer post: Clients_PostContainer, payload: Data) -> PostContent? {
        switch post.post {
        case .text(let clientText):
            return .text(clientText.mentionText, clientText.linkPreviewData)
        case .album(let album):
            var media = [FeedMediaData]()
            var foundUnsupportedMedia = false
            for (i, albumMedia) in album.media.enumerated() {
                guard let mediaData = FeedMediaData(id: "\(postId)-\(i)", albumMedia: albumMedia) else {
                    foundUnsupportedMedia = true
                    continue
                }
                media.append(mediaData)
            }
            if album.hasVoiceNote {
                if let mediaData = FeedMediaData(id: "\(postId)-voicenote", clientVoiceNote: album.voiceNote) {
                    media.append(mediaData)
                } else {
                    foundUnsupportedMedia = true
                }
            }
            if foundUnsupportedMedia {
                DDLogError("PostData/initFromServerPost/error unrecognized media")
                return .unsupported(payload)
            } else {
                return .album(album.text.mentionText, media)
            }
        case .voiceNote(let voiceNote):
            guard let media = FeedMediaData(id: "\(postId)-voicenote", clientVoiceNote: voiceNote) else {
                DDLogError("PostData/initFromServerPost/error unrecognized media")
                return .unsupported(payload)
            }
            return .voiceNote(media)
        case .moment(let moment):
            guard let media = FeedMediaData(id: "\(postId)-moment", clientImage: moment.image) else {
                return .unsupported(payload)
            }
            return .moment(media, unlockedUserID: nil)
        case .none:
            return .unsupported(payload)
        }
    }

    public mutating func update(with serverPost: Server_Post) {
        if case let .moment(media, _) = content, serverPost.momentUnlockUid == Int64(AppContextCommon.shared.userData.userId) {
            content = .moment(media, unlockedUserID: AppContextCommon.shared.userData.userId)
        }
    }
}

public struct MentionData: Codable, FeedMentionProtocol {
    public let index: Int
    public let userID: String
    public let name: String

    public init(index: Int, userID: String, name: String) {
        self.index = index
        self.userID = userID
        self.name = name
    }
}

public struct FeedMediaData: FeedMediaProtocol {

    public init(id: String, url: URL?, type: CommonMediaType, size: CGSize, key: String, sha256: String, blobVersion: BlobVersion, chunkSize: Int32, blobSize: Int64) {
        self.id = id
        self.url = url
        self.type = type
        self.size = size
        self.key = key
        self.sha256 = sha256
        self.blobVersion = blobVersion
        self.chunkSize = chunkSize
        self.blobSize = blobSize
    }

    public init(from media: FeedMediaProtocol) {
        self.init(
            id: media.id,
            url: media.url,
            type: media.type,
            size: media.size,
            key: media.key,
            sha256: media.sha256,
            blobVersion: media.blobVersion,
            chunkSize: media.chunkSize,
            blobSize: media.blobSize)
    }

    public let id: String
    public let url: URL?
    public let type: CommonMediaType
    public let size: CGSize
    public let key: String
    public let sha256: String
    public let blobVersion: BlobVersion
    public let chunkSize: Int32
    public let blobSize: Int64

    public init?(id: String, protoMedia: Clients_Media) {
        guard let type: CommonMediaType = {
            switch protoMedia.type {
            case .image: return .image
            case .video: return .video
            case .audio: return .audio
            default: return nil
            }}() else { return nil }
        guard let url = URL(string: protoMedia.downloadURL) else { return nil }
        let width = CGFloat(protoMedia.width), height = CGFloat(protoMedia.height)
        guard (width > 0 && height > 0) || type == .audio else { return nil }

        self.id = id
        self.url = url
        self.type = type
        self.size = CGSize(width: width, height: height)
        self.key = protoMedia.encryptionKey.base64EncodedString()
        self.sha256 = protoMedia.ciphertextHash.base64EncodedString()
        self.blobVersion = BlobVersion.init(fromProto: protoMedia.blobVersion)
        self.chunkSize = protoMedia.chunkSize
        self.blobSize = protoMedia.blobSize
    }

    public init?(id: String, clientImage: Clients_Image) {
        guard let downloadURL = URL(string: clientImage.img.downloadURL) else {
            DDLogError("FeedMediaData/initFromClientImage/\(id)/error invalid downloadURL [\(clientImage.img.downloadURL)]")
            return nil
        }

        let size = CGSize(width: CGFloat(clientImage.width), height: CGFloat(clientImage.height))
        guard size.width > 0 && size.height > 0 else {
            DDLogError("FeedMediaData/initFromClientImage/\(id)/error invalid size [\(size)]")
            return nil
        }
        self.id = id
        self.url = downloadURL
        self.type = .image
        self.size = size
        self.key = clientImage.img.encryptionKey.base64EncodedString()
        self.sha256 = clientImage.img.ciphertextHash.base64EncodedString()
        self.blobVersion = .default
        self.chunkSize = 0
        self.blobSize = 0
    }

    public init?(id: String, clientVideo: Clients_Video) {
        guard let url = URL(string: clientVideo.video.downloadURL) else {
            DDLogError("FeedMediaData/initFromClientVideo/\(id)/error invalid downloadURL [\(clientVideo.video.downloadURL)]")
            return nil
        }

        let size = CGSize(width: CGFloat(clientVideo.width), height: CGFloat(clientVideo.height))
        guard size.width > 0 && size.height > 0 else {
            DDLogError("FeedMediaData/initFromClientVideo/\(id)/error invalid size [\(size)]")
            return nil
        }

        self.id = id
        self.url = url
        self.type = .video
        self.size = size
        self.key = clientVideo.video.encryptionKey.base64EncodedString()
        self.sha256 = clientVideo.video.ciphertextHash.base64EncodedString()
        self.blobVersion = BlobVersion.init(fromProto: clientVideo.streamingInfo.blobVersion)
        self.chunkSize = clientVideo.streamingInfo.chunkSize
        self.blobSize = clientVideo.streamingInfo.blobSize
    }

    public init?(id: String, clientVoiceNote: Clients_VoiceNote) {
        guard let url = URL(string: clientVoiceNote.audio.downloadURL) else {
            DDLogError("FeedMediaData/initFromClientVoiceNote/\(id)/error invalid downloadURL [\(clientVoiceNote.audio.downloadURL)]")
            return nil
        }

        self.id = id
        self.url = url
        self.type = .audio
        self.size = .zero
        self.key = clientVoiceNote.audio.encryptionKey.base64EncodedString()
        self.sha256 = clientVoiceNote.audio.ciphertextHash.base64EncodedString()
        self.blobVersion = .default
        self.chunkSize = 0
        self.blobSize = 0
    }

    public init?(id: String, albumMedia: Clients_AlbumMedia) {
        switch albumMedia.media {
        case .image(let image):
            self.init(id: id, clientImage: image)
        case .video(let video):
            self.init(id: id, clientVideo: video)
        case .none:
            return nil
        }
    }
}

public enum CommentContent {
    case text(MentionText, [LinkPreviewData])
    case album(MentionText, [FeedMediaData])
    case voiceNote(FeedMediaData)
    case commentReaction(String)
    case unsupported(Data)
    case retracted
    case waiting
 }

public struct CommentData {

    // MARK: FeedItem
    public let id: FeedPostCommentID
    public let userId: UserID
    public var timestamp: Date = Date()
    public var  status: FeedItemStatus

    // MARK: FeedComment
    public let feedPostId: FeedPostID
    public let parentId: FeedPostCommentID?
    public var content: CommentContent

    // TODO: murali@: fix this to return nil - update coredata field accordingly.
    public var text: String {
        switch content {
        case .retracted, .unsupported, .voiceNote, .waiting:
            return ""
        case .text(let mentionText, _):
            return mentionText.collapsedText
        case .album(let mentionText, _):
            return mentionText.collapsedText
        case .commentReaction(let emoji):
            return emoji
        }
    }
    
    public var orderedMedia: [FeedMediaProtocol] {
        switch content {
        case .album(_, let media):
            return media
        case .voiceNote(let mediaItem):
            return [mediaItem]
        case .retracted, .text, .commentReaction, .unsupported, .waiting:
            return []
        }
    }

    public var orderedMentions: [FeedMentionProtocol] {
        let mentions: [Int: MentionedUser] = {
            switch content {
            case .retracted, .unsupported, .voiceNote, .commentReaction, .waiting:
                return [:]
            case .text(let mentionText, _):
                return mentionText.mentions
            case .album(let mentionText, _):
                return mentionText.mentions
            }
        }()
        return mentions
            .map { (i, user) in
                MentionData(index: i, userID: user.userID, name: user.pushName ?? "")
            }
            .sorted { $0.index < $1.index }
    }
    
    public var linkPreviewData: [LinkPreviewProtocol] {
        switch content {
        case .retracted, .unsupported, .album, .voiceNote, .commentReaction, .waiting:
            return []
        case .text(_, let linkPreviewData):
            return linkPreviewData
        }
    }

    public var mediaCounters: MediaCounters {
        switch content {
        case .album(_, let media):
            var counters = MediaCounters()
            media.forEach { mediaItem in
                counters.count(mediaItem.type)
            }
            return counters
        case .text(_, _):
            return MediaCounters()
        case .voiceNote:
            return MediaCounters(numImages: 0, numVideos: 0, numAudio: 1)
        case .retracted, .unsupported, .commentReaction, .waiting:
            return MediaCounters()
        }
    }

    public var serverMediaCounters: Server_MediaCounters {
        var counters = Server_MediaCounters()
        let mediaCounters = mediaCounters
        counters.numImages = mediaCounters.numImages
        counters.numVideos = mediaCounters.numVideos
        counters.numAudio = mediaCounters.numAudio
        return counters
    }

    public init(id: FeedPostCommentID, userId: UserID, timestamp: Date, feedPostId: FeedPostID, parentId: FeedPostCommentID?, content: CommentContent, status: FeedItemStatus) {
        self.id = id
        self.userId = userId
        self.timestamp = timestamp
        self.feedPostId = feedPostId
        self.parentId = parentId
        self.content = content
        self.status = status
    }

    public init?(_ serverComment: Server_Comment, status: FeedItemStatus, itemAction: ItemAction, usePlainTextPayload: Bool = true, isShared: Bool = false) {
        let commentId = serverComment.id
        let userId = UserID(serverComment.publisherUid)
        let timestamp = Date(timeIntervalSince1970: TimeInterval(serverComment.timestamp))
        let feedPostId = serverComment.postID
        let parentId = serverComment.parentCommentID.isEmpty ? nil : serverComment.parentCommentID

        // Fallback to plainText payload depending on the boolean here.
        if usePlainTextPayload {
            // If it is shared - then action could be retract and content must be set to retracted.
            if isShared {
                switch itemAction {
                case .none, .publish, .share:
                    self.init(id: commentId, userId: userId, feedPostId: feedPostId, parentId: parentId, timestamp: timestamp, payload: serverComment.payload, status: status)
                case .retract:
                    self.init(id: commentId, userId: userId, timestamp: timestamp, feedPostId: feedPostId, parentId: parentId, content: .retracted, status: status)
                }
            } else {
                self.init(id: commentId, userId: userId, feedPostId: feedPostId, parentId: parentId, timestamp: timestamp, payload: serverComment.payload, status: status)
            }
        } else {
            self.init(id: commentId, userId: userId, timestamp: timestamp, feedPostId: feedPostId, parentId: parentId, content: .waiting, status: status)
        }
    }

    public init?(id: String, userId: UserID, feedPostId: String, parentId: String?, timestamp: Date, payload: Data, status: FeedItemStatus) {
        self.id = id
        self.userId = userId
        self.timestamp = timestamp
        self.feedPostId = feedPostId
        self.parentId = parentId
        guard let processedContent = CommentData.extractContent(commentId: id, payload: payload) else {
            return nil
        }
        self.content = processedContent
        self.status = status
    }
    
    public static func extractContent(commentId: String, payload: Data) -> CommentContent? {
        guard let protoContainer = try? Clients_Container(serializedData: payload) else {
            DDLogError("Could not deserialize comment [\(commentId)]")
            return nil
        }
        if protoContainer.hasCommentContainer {
            // Future-proof comment
            let comment = protoContainer.commentContainer
            switch comment.comment {
            case .text(let clientText):
                return .text(clientText.mentionText, clientText.linkPreviewData)
            case .album(let clientAlbum):
                var media = [FeedMediaData]()
                var foundUnsupportedMedia = false
                for (i, albumMedia) in clientAlbum.media.enumerated() {
                    // TODO Nandini is this ID set right?
                    guard let mediaData = FeedMediaData(id: "\(commentId)-\(i)", albumMedia: albumMedia) else {
                       foundUnsupportedMedia = true
                       continue
                   }
                   media.append(mediaData)
               }
               if foundUnsupportedMedia {
                   DDLogError("CommentData/album/error unrecognized media")
                   return  .unsupported(payload)
               } else {
                   return .album(clientAlbum.text.mentionText, media)
               }
            case .voiceNote(let voiceNote):
                guard let media = FeedMediaData(id: "\(commentId)-0", clientVoiceNote: voiceNote) else {
                    DDLogError("CommentData/voiceNote/error unrecognized media")
                    return .unsupported(payload)
                }
                return .voiceNote(media)
            case .reaction(let reaction):
                return .commentReaction(reaction.emoji)
            case .none:
                return .unsupported(payload)
            }

        } else {
            DDLogError("Unrecognized comment (no comment or comment container set)")
            return nil
        }
    }
}

public enum ItemAction {
    case none
    case publish
    case retract
    case share
}


extension Server_GroupFeedItem {
    var contentId: String? {
        switch self.item {
        case .post(let post): return post.id
        case .comment(let comment): return comment.id
        default: return nil
        }
    }

    var publisherUid: UserID? {
        switch self.item {
        case .post(let post): return UserID(post.publisherUid)
        case .comment(let comment): return UserID(comment.publisherUid)
        default: return nil
        }
    }

    var encryptedPayload: Data? {
        switch self.item {
        case .post(let post): return post.encPayload.isEmpty ? nil : post.encPayload
        case .comment(let comment): return comment.encPayload.isEmpty ? nil : comment.encPayload
        default: return nil
        }
    }

    public var contentType: GroupFeedRerequestContentType? {
        switch self.item {
        case .post: return .post
        case .comment: return .comment
        default: return nil
        }
    }

    public var itemAction: ItemAction {
        switch self.action {
        case .retract:
            return .retract
        case .publish:
            return .publish
        case .share:
            return .share
        case .UNRECOGNIZED(_):
            return .none
        }
    }
}

extension Server_FeedItem {
    public var contentId: String? {
        switch self.item {
        case .post(let post): return post.id
        case .comment(let comment): return comment.id
        default: return nil
        }
    }

    public var publisherUid: UserID? {
        switch self.item {
        case .post(let post): return UserID(post.publisherUid)
        case .comment(let comment): return UserID(comment.publisherUid)
        default: return nil
        }
    }

    public var encryptedPayload: Data? {
        switch self.item {
        case .post(let post): return post.encPayload.isEmpty ? nil : post.encPayload
        case .comment(let comment): return comment.encPayload.isEmpty ? nil : comment.encPayload
        default: return nil
        }
    }

    public var contentType: HomeFeedRerequestContentType? {
        switch self.item {
        case .post: return .post
        case .comment: return .comment
        default: return nil
        }
    }

    public var itemAction: ItemAction {
        switch self.action {
        case .retract:
            return .retract
        case .publish:
            return .publish
        case .share:
            return .share
        case .UNRECOGNIZED(_):
            return .none
        }
    }

    public var sessionType: HomeSessionType {
        switch item {
        case .post(let post):
            switch post.audience.type {
            case .all:
                return .all
            case .only:
                return .favorites
            default:
                return .all
            }
        case .comment(_):
            return .all
        default:
            return .all
        }
    }
}
