//
//  XMPPFeed.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/15/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Foundation
import SwiftProtobuf

// MARK: Concrete classes

public struct XMPPFeedPost: FeedPostProtocol {

    // MARK: FeedItem
    public static var itemType: FeedItemType { .post }
    public let id: FeedPostID
    public let userId: UserID
    public var timestamp: Date = Date()

    // MARK: FeedPost
    public let text: String?
    public var orderedMentions: [FeedMentionProtocol] {
        get { mentions.sorted { $0.index < $1.index } }
    }
    public var orderedMedia: [FeedMediaProtocol] {
        get { media }
    }

    public let media: [FeedMediaData]
    public let mentions: [XMPPFeedMention]

    public init?(_ serverPost: Server_Post) {
        let protoPost: Clients_Post
        if let protoContainer = try? Clients_Container(serializedData: serverPost.payload), protoContainer.hasPost {
            protoPost = protoContainer.post
        } else if let decodedData = Data(base64Encoded: serverPost.payload), let protoContainer = try? Clients_Container(serializedData: decodedData), protoContainer.hasPost {
            protoPost = protoContainer.post
        } else {
            DDLogError("Could not deserialize post")
            return nil
        }

        self.id = serverPost.id
        self.userId = UserID(serverPost.publisherUid)
        self.text = protoPost.text.isEmpty ? nil : protoPost.text
        self.media = protoPost.media.enumerated().compactMap { FeedMediaData(id: "\(serverPost.id)-\($0)", protoMedia: $1) }
        self.mentions = protoPost.mentions.map { XMPPFeedMention(index: Int($0.index), userID: $0.userID, name: $0.name) }
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(serverPost.timestamp))
    }
}

public struct XMPPFeedMention: FeedMentionProtocol {

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
        self.sha256 = protoMedia.plaintextHash.base64EncodedString()
    }
}

public struct XMPPComment: FeedCommentProtocol {

    // MARK: FeedItem
    public static var itemType: FeedItemType { .comment }
    public let id: FeedPostCommentID
    public let userId: UserID
    public var timestamp: Date = Date()

    // MARK: FeedComment
    public let feedPostId: FeedPostID
    public let feedPostUserId: UserID = "" // added for protocol conformance,  not actually used anywhere
    public let parentId: FeedPostCommentID?
    public let text: String
    public var orderedMentions: [FeedMentionProtocol] {
        get { mentions.sorted { $0.index < $1.index } }
    }

    public let mentions: [XMPPFeedMention]

    public init?(_ serverComment: Server_Comment) {
        let protoComment: Clients_Comment
        if let protoContainer = try? Clients_Container(serializedData: serverComment.payload), protoContainer.hasComment {
            protoComment = protoContainer.comment
        } else if let decodedData = Data(base64Encoded: serverComment.payload), let protoContainer = try? Clients_Container(serializedData: decodedData), protoContainer.hasComment {
            protoComment = protoContainer.comment
        } else {
            DDLogError("Could not deserialize comment")
            return nil
        }

        // Fall back to IDs from payload if missing from top level
        let postID = serverComment.postID.isEmpty ? protoComment.feedPostID : serverComment.postID
        let parentID = serverComment.parentCommentID.isEmpty ? protoComment.parentCommentID : serverComment.parentCommentID

        self.id = serverComment.id
        self.userId = UserID(serverComment.publisherUid)
        self.feedPostId = postID
        self.parentId = parentID.isEmpty ? nil : parentID
        self.text = protoComment.text
        self.mentions = protoComment.mentions.map { XMPPFeedMention(index: Int($0.index), userID: $0.userID, name: $0.name) }
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(serverComment.timestamp))
    }
}
