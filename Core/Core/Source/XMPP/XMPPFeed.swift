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
    case text(MentionText)
    case album(MentionText, [FeedMediaData])
    case retracted
    case unsupported(Data)
}

public struct PostData: FeedPostProtocol {

    // MARK: FeedItem
    public let id: FeedPostID
    public let userId: UserID
    public var timestamp: Date = Date()

    // MARK: FeedPost
    public var content: PostContent

    public var text: String? {
        switch content {
        case .retracted, .unsupported:
            return nil
        case .text(let mentionText):
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
            case .text(let mentionText):
                return mentionText.mentions
            }
        }()
        return mentions
            .map { (i, user) in
                MentionData(index: i, userID: user.userID, name: user.pushName ?? "")
            }
            .sorted { $0.index < $1.index }
    }


    public init?(_ serverPost: Server_Post) {

        guard let protoContainer = try? Clients_Container(serializedData: serverPost.payload) else {
            DDLogError("Could not deserialize post")
            return nil
        }

        if protoContainer.hasPostContainer {
            // Future-proof post
            let post = protoContainer.postContainer

            switch post.post {
            case .text(let clientText):
                content = .text(clientText.mentionText)
            case .album(let album):
                var media = [FeedMediaData]()
                var foundUnsupportedMedia = false
                for (i, albumMedia) in album.media.enumerated() {
                    guard let mediaData = FeedMediaData(id: "\(serverPost.id)-\(i)", albumMedia: albumMedia) else {
                        foundUnsupportedMedia = true
                        continue
                    }
                    media.append(mediaData)
                }
                if foundUnsupportedMedia {
                    DDLogError("PostData/initFromServerPost/error unrecognized media")
                    content = .unsupported(serverPost.payload)
                } else {
                    content = .album(album.text.mentionText, media)
                }
            case .none:
                content = .unsupported(serverPost.payload)
            }

        } else if protoContainer.hasPost {
            // Legacy post
            let protoPost = protoContainer.post

            let media = protoPost.media.enumerated().compactMap { FeedMediaData(id: "\(serverPost.id)-\($0)", protoMedia: $1) }
            let mentionText = protoPost.mentionText

            if media.isEmpty {
                content = .text(mentionText)
            } else {
                content = .album(mentionText, media)
            }

        } else {
            DDLogError("Unrecognized post (no post or post container set)")
            return nil
        }

        self.id = serverPost.id
        self.userId = UserID(serverPost.publisherUid)
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(serverPost.timestamp))
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
            default: return nil
            }}() else { return nil }
        guard let url = URL(string: protoMedia.downloadURL) else { return nil }
        let width = CGFloat(protoMedia.width), height = CGFloat(protoMedia.height)
        guard width > 0 && height > 0 else { return nil }

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
    case text(MentionText)
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

    public init(id: FeedPostCommentID, userId: UserID, timestamp: Date = Date(), feedPostId: FeedPostID, parentId: FeedPostCommentID?, content: CommentContent) {
        self.id = id
        self.userId = userId
        self.timestamp = timestamp
        self.feedPostId = feedPostId
        self.parentId = parentId
        self.content = content
    }

    public init?(_ serverComment: Server_Comment) {

        guard let protoContainer = try? Clients_Container(serializedData: serverComment.payload) else {
            DDLogError("Could not deserialize comment")
            return nil
        }

        if protoContainer.hasCommentContainer {
            // Future-proof comment
            let comment = protoContainer.commentContainer

            // Fall back to IDs from payload if missing from top level
            let postID = serverComment.postID.isEmpty ? comment.context.feedPostID : serverComment.postID
            let parentID = serverComment.parentCommentID.isEmpty ? comment.context.parentCommentID : serverComment.parentCommentID

            self.feedPostId = postID
            self.parentId = parentID.isEmpty ? nil : parentID
            switch comment.comment {
            case .text(let clientText):
                self.content = .text(clientText.mentionText)
            case .album, .none:
                self.content = .unsupported(serverComment.payload)
            }

        } else if protoContainer.hasComment {
            // Legacy comment
            let protoComment = protoContainer.comment

            // Fall back to IDs from payload if missing from top level
            let postID = serverComment.postID.isEmpty ? protoComment.feedPostID : serverComment.postID
            let parentID = serverComment.parentCommentID.isEmpty ? protoComment.parentCommentID : serverComment.parentCommentID

            self.feedPostId = postID
            self.parentId = parentID.isEmpty ? nil : parentID
            self.content = .text(protoComment.mentionText)
        } else {
            DDLogError("Unrecognized comment (no comment or comment container set)")
            return nil
        }

        self.id = serverComment.id
        self.userId = UserID(serverComment.publisherUid)
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(serverComment.timestamp))
    }
}
