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
    case moment(MomentContent)
    case waiting
}

public struct MomentContent {

    public let image: FeedMediaData
    public let selfieImage: FeedMediaData?
    public let selfieLeading: Bool
    public let locationString: String?
    public private(set) var unlockUserID: UserID?

    public private(set) var notificationTimestamp: Date?
    public private(set) var secondsTaken: Int
    public private(set) var numberOfTakes: Int

    init(image: FeedMediaData,
         selfieImage: FeedMediaData?,
         selfieLeading: Bool,
         locationString: String?,
         unlockUserID: UserID?,
         notificationTimestamp: Date?,
         secondsTaken: Int,
         numberOfTakes: Int) {

        self.image = image
        self.selfieImage = selfieImage
        self.selfieLeading = selfieLeading
        self.locationString = locationString
        self.unlockUserID = unlockUserID

        self.notificationTimestamp = notificationTimestamp
        self.secondsTaken = secondsTaken
        self.numberOfTakes = numberOfTakes
    }

    init?(_ clientsMoment: Clients_Moment, postID: FeedPostID) {
        guard let parsed = FeedMediaData(id: "\(postID)-moment", clientImage: clientsMoment.image) else {
            return nil
        }

        image = parsed
        selfieImage = FeedMediaData(id: "\(postID)-selfie-moment", clientImage: clientsMoment.selfieImage)
        selfieLeading = clientsMoment.selfieLeading
        locationString = clientsMoment.location.isEmpty ? nil : clientsMoment.location
        unlockUserID = nil

        notificationTimestamp = nil
        secondsTaken = 0
        numberOfTakes = 1
    }

    mutating func update(with serverPost: Server_Post) {
        let asString = UserID(serverPost.momentUnlockUid)
        let momentInfo = serverPost.momentInfo
        let timestamp = momentInfo.notificationTimestamp

        if asString == AppContextCommon.shared.userData.userId {
            unlockUserID = asString
        }

        notificationTimestamp = timestamp == .zero ? nil : Date(timeIntervalSince1970: TimeInterval(timestamp))
        secondsTaken = Int(momentInfo.timeTaken)
        numberOfTakes = Int(momentInfo.numTakes)
    }

    var proto: Clients_Moment {
        var moment = Clients_Moment()
        var main = Clients_Image()
        var selfie = Clients_Image()

        if let resource = image.protoResource {
            main.img = resource
            main.width = Int32(image.size.width)
            main.height = Int32(image.size.height)
        }

        if let resource = selfieImage?.protoResource {
            selfie.img = resource
            selfie.width = Int32(image.size.width)
            selfie.height = Int32(image.size.height)
            moment.selfieImage = selfie
        }

        moment.image = main
        moment.selfieLeading = selfieLeading
        if let locationString {
            moment.location = locationString
        } else {
            moment.location = ""
        }

        return moment
    }

    var info: Server_MomentInfo {
        var info = Server_MomentInfo()

        info.notificationTimestamp = Int64(notificationTimestamp?.timeIntervalSince1970 ?? .zero)
        info.timeTaken = Int64(secondsTaken)
        info.numTakes = Int64(numberOfTakes)

        return info
    }
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
        case .moment(let content):
            return [content.image, content.selfieImage].compactMap { $0 }
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
        case .moment(let content):
            // can only be an image for now, but leaving this in for eventual video support
            return MediaCounters(numImages: content.selfieImage != nil ? 2 : 1,
                                 numVideos: 0,
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

        if case var .moment(momentContent) = content {
            momentContent.update(with: serverPost)
            content = .moment(momentContent)
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
            guard let content = MomentContent(moment, postID: postId) else {
                return .unsupported(payload)
            }
            return .moment(content)
        case .none:
            return .unsupported(payload)
        }
    }

    public mutating func update(with serverPost: Server_Post) {
        if case var .moment(momentContent) = content {
            momentContent.update(with: serverPost)
            content = .moment(momentContent)
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

    public init(name: String?, id: String, url: URL?, type: CommonMediaType, size: CGSize, key: String, sha256: String, blobVersion: BlobVersion, chunkSize: Int32, blobSize: Int64) {
        self.name = name
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
            name: media.name,
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
    public let name: String?

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
        self.name = nil
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
        self.name = nil
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
        self.name = nil
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
        self.name = nil
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
    case reaction(String)
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
        case .reaction(let emoji):
            return emoji
        }
    }
    
    public var orderedMedia: [FeedMediaProtocol] {
        switch content {
        case .album(_, let media):
            return media
        case .voiceNote(let mediaItem):
            return [mediaItem]
        case .retracted, .text, .reaction, .unsupported, .waiting:
            return []
        }
    }

    public var orderedMentions: [FeedMentionProtocol] {
        let mentions: [Int: MentionedUser] = {
            switch content {
            case .retracted, .unsupported, .voiceNote, .reaction, .waiting:
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
        case .retracted, .unsupported, .album, .voiceNote, .reaction, .waiting:
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
        case .retracted, .unsupported, .reaction, .waiting:
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
                return .reaction(reaction.emoji)
            case .sticker, .videoReaction:
                return .unsupported(payload)
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
        case .comment(let comment):
            switch comment.commentType {
            case .comment: return .comment
            case .commentReaction: return .commentReaction
            case .postReaction: return .postReaction
            case .UNRECOGNIZED: return .comment
            }
        default: return nil
        }
    }

    public var reportContentType: GroupDecryptionReportContentType? {
        switch self.item {
        case .post: return .post
        case .comment(let comment):
            switch comment.commentType {
            case .comment: return .comment
            case .commentReaction: return .commentReaction
            case .postReaction: return .postReaction
            case .UNRECOGNIZED: return .comment
            }
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
        case .comment(let comment):
            switch comment.commentType {
            case .comment: return .comment
            case .commentReaction: return .commentReaction
            case .postReaction: return .postReaction
            case .UNRECOGNIZED: return .comment
            }
        default: return nil
        }
    }

    public var reportContentType: HomeDecryptionReportContentType? {
        switch self.item {
        case .post: return .post
        case .comment(let comment):
            switch comment.commentType {
            case .comment: return .comment
            case .commentReaction: return .commentReaction
            case .postReaction: return .postReaction
            case .UNRECOGNIZED: return .comment
            }
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
        case .publicUpdatePublish, .publicUpdateRetract, .expire:
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
