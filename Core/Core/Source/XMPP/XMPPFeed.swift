//
//  XMPPFeed.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/15/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Foundation
import SwiftProtobuf

// MARK: Concrete classes

public enum PostContent {
    case text(MentionText, [LinkPreviewData])
    case album(MentionText, [FeedMediaData])
    case retracted
    case unsupported(Data)
}

public struct PostData {

    // MARK: FeedItem
    public let id: FeedPostID
    public let userId: UserID
    public var timestamp: Date = Date()

    public let isShared: Bool

    // MARK: FeedPost
    public var content: PostContent

    public var text: String? {
        switch content {
        case .retracted, .unsupported:
            return nil
        case .text(let mentionText, _):
            return mentionText.collapsedText
        case .album(let mentionText, _):
            return mentionText.collapsedText
        }
    }

    public var orderedMedia: [FeedMediaProtocol] {
        switch content {
        case .album(_, let media):
            return media
        case .retracted, .text, .unsupported:
            return []
        }
    }

    public var orderedMentions: [FeedMentionProtocol] {
        let mentions: [Int: MentionedUser] = {
            switch content {
            case .retracted, .unsupported:
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
    
    public var linkPreviewData: [LinkPreviewProtocol] {
        switch content {
        case .retracted, .unsupported, .album:
            return []
        case .text(_, let linkPreviewData):
            return linkPreviewData
        }
    }

    public init(id: FeedPostID, userId: UserID, content: PostContent, timestamp: Date = Date(), isShared: Bool = false) {
        self.id = id
        self.userId = userId
        self.content = content
        self.timestamp = timestamp
        self.isShared = isShared
    }

    public init?(_ serverPost: Server_Post, isShared: Bool = false) {
        self.init(id: serverPost.id,
                  userId: UserID(serverPost.publisherUid),
                  timestamp: Date(timeIntervalSince1970: TimeInterval(serverPost.timestamp)),
                  payload: serverPost.payload,
                  isShared: isShared)
    }

    public init?(id: String, userId: UserID, timestamp: Date, payload: Data, isShared: Bool = false) {
        guard let processedContent = PostData.extractContent(postId: id, payload: payload) else {
            return nil
        }
        self.init(id: id, userId: userId, content: processedContent, timestamp: timestamp, isShared: isShared)
    }

    public static func extractContent(postId: String, payload: Data) -> PostContent? {
        guard let protoContainer = try? Clients_Container(serializedData: payload) else {
            DDLogError("Could not deserialize post [\(postId)]")
            return nil
        }
        if protoContainer.hasPostContainer {
            // Future-proof post
            let post = protoContainer.postContainer

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
                if foundUnsupportedMedia {
                    DDLogError("PostData/initFromServerPost/error unrecognized media")
                    return .unsupported(payload)
                } else {
                    return .album(album.text.mentionText, media)
                }
            case .none:
                return .unsupported(payload)
            }

        } else if protoContainer.hasPost {
            // Legacy post
            let protoPost = protoContainer.post

            let media = protoPost.media.enumerated().compactMap { FeedMediaData(id: "\(postId)-\($0)", protoMedia: $1) }
            let mentionText = protoPost.mentionText

            if media.isEmpty {
                return .text(mentionText, [])
            } else {
                return .album(mentionText, media)
            }

        } else {
            DDLogError("Unrecognized post (no post or post container set)")
            return nil
        }
    }
}

public struct MentionData: FeedMentionProtocol {
    public let index: Int
    public let userID: String
    public let name: String
}

public struct FeedMediaData: FeedMediaProtocol {

    public init(id: String, url: URL?, type: FeedMediaType, size: CGSize, key: String, sha256: String) {
        self.id = id
        self.url = url
        self.type = type
        self.size = size
        self.key = key
        self.sha256 = sha256
    }

    public init(from media: FeedMediaProtocol) {
        self.init(
            id: media.id,
            url: media.url,
            type: media.type,
            size: media.size,
            key: media.key,
            sha256: media.sha256)
    }

    public let id: String
    public let url: URL?
    public let type: FeedMediaType
    public let size: CGSize
    public let key: String
    public let sha256: String

    public init?(id: String, protoMedia: Clients_Media) {
        guard let type: FeedMediaType = {
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
    case unsupported(Data)
    case retracted
 }

public struct CommentData {

    // MARK: FeedItem
    public let id: FeedPostCommentID
    public let userId: UserID
    public var timestamp: Date = Date()

    // MARK: FeedComment
    public let feedPostId: FeedPostID
    public let parentId: FeedPostCommentID?
    public var content: CommentContent

    
    public var orderedMedia: [FeedMediaProtocol] {
        switch content {
        case .album(_, let media):
            return media
        case .voiceNote(let mediaItem):
            return [mediaItem]
        case .retracted, .text, .unsupported:
            return []
        }
    }

    public var orderedMentions: [FeedMentionProtocol] {
        let mentions: [Int: MentionedUser] = {
            switch content {
            case .retracted, .unsupported, .voiceNote:
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
        case .retracted, .unsupported, .album, .voiceNote:
            return []
        case .text(_, let linkPreviewData):
            return linkPreviewData
        }
    }

    public init(id: FeedPostCommentID, userId: UserID, timestamp: Date = Date(), feedPostId: FeedPostID, parentId: FeedPostCommentID?, content: CommentContent) {
        self.id = id
        self.userId = userId
        self.timestamp = timestamp
        self.feedPostId = feedPostId
        self.parentId = parentId
        self.content = content
    }

    public init?(_ serverComment: Server_Comment) {
        // do we need fallback for some of these ids to the clients_container?
        self.init(id: serverComment.id,
                  userId: UserID(serverComment.publisherUid),
                  feedPostId: serverComment.postID,
                  parentId: serverComment.parentCommentID.isEmpty ? nil : serverComment.parentCommentID,
                  timestamp: Date(timeIntervalSince1970: TimeInterval(serverComment.timestamp)),
                  payload: serverComment.payload)
    }

    public init?(id: String, userId: UserID, feedPostId: String, parentId: String?, timestamp: Date, payload: Data) {
        self.id = id
        self.userId = userId
        self.timestamp = timestamp
        self.feedPostId = feedPostId
        self.parentId = parentId
        guard let processedContent = CommentData.extractContent(commentId: id, payload: payload) else {
            return nil
        }
        self.content = processedContent
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
            case .none:
                return .unsupported(payload)
            }

        } else if protoContainer.hasComment {
            // Legacy comment
            let protoComment = protoContainer.comment
            return .text(protoComment.mentionText, [])
        } else {
            DDLogError("Unrecognized comment (no comment or comment container set)")
            return nil
        }
    }
}
