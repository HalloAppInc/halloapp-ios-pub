//
//  XMPPFeed.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/15/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import SwiftProtobuf
import XMPPFramework

public extension FeedPostProtocol {

    func xmppElement(withData: Bool) -> XMPPElement {
        let postElement = XMPPElement(name: "post")
        postElement.addAttribute(withName: "id", stringValue: id)
        // "uid" and "timestamp" are ignored when posting.
        if withData, let protobufData = try? protoContainer.serializedData() {
            postElement.stringValue = protobufData.base64EncodedString()
        }
        return postElement
    }
}

public extension FeedCommentProtocol {

    func xmppElement(withData: Bool) -> XMPPElement {
        let commentElement = XMPPElement(name: "comment")
        commentElement.addAttribute(withName: "id", stringValue: id)
        commentElement.addAttribute(withName: "post_id", stringValue: feedPostId)
        if let parentCommentId = parentId {
            commentElement.addAttribute(withName: "parent_comment_id", stringValue: parentCommentId)
        }
        // "publisher_uid", "publisher_name" and "timestamp" are ignored when posting.
        if withData, let protobufData = try? protoContainer.serializedData() {
            commentElement.stringValue = protobufData.base64EncodedString()
        }
        return commentElement
    }
}

enum XMPPFeedMediaType: String {
    case image = "image"
    case video = "video"
}

extension Clients_Container {

    static func feedItemContainer(from itemElement: XMLElement) -> Clients_Container? {

        guard let base64String = itemElement.stringValue,
            let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) else { return nil }
        do {
            let protoContainer = try Clients_Container(serializedData: data)
            if protoContainer.hasComment || protoContainer.hasPost {
                return protoContainer
            }
        }
        catch {
            DDLogError("xmpp/post/invalid-protobuf")
        }
        return nil
    }
}

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

    public let media: [XMPPFeedMedia]
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
        self.media = protoPost.media.enumerated().compactMap { XMPPFeedMedia(id: "\(serverPost.id)-\($0)", protoMedia: $1) }
        self.mentions = protoPost.mentions.map { XMPPFeedMention(index: Int($0.index), userID: $0.userID, name: $0.name) }
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(serverPost.timestamp))
    }

    /**
     <post id='bnd81g37d61f49fgn581' uid='1000000000000000001' timestamp='1583883173'>
       .....pb_payload.....
     </post >
     */
    public init?(itemElement item: XMLElement) {
        // Feed uses "uid" (legacy name) while group feed uses "publisher_uid".
        guard let id = item.attributeStringValue(forName: "id"),
              let userId = item.attributeStringValue(forName: "uid") ?? item.attributeStringValue(forName: "publisher_uid"),
              let protoContainer = Clients_Container.feedItemContainer(from: item), protoContainer.hasPost else
        {
            return nil
        }

        let timestamp = item.attributeDoubleValue(forName: "timestamp")
        guard timestamp > 0 else { return nil }

        let protoPost = protoContainer.post

        self.id = id
        self.userId = userId
        self.text = protoPost.text.isEmpty ? nil : protoPost.text
        self.media = protoPost.media.enumerated().compactMap { XMPPFeedMedia(id: "\(id)-\($0)", protoMedia: $1) }
        self.mentions = protoPost.mentions.map { XMPPFeedMention(index: Int($0.index), userID: $0.userID, name: $0.name) }
        self.timestamp = Date(timeIntervalSince1970: timestamp)
    }
}

public struct XMPPFeedMention: FeedMentionProtocol {

    public let index: Int
    public let userID: String
    public let name: String
}

public struct XMPPFeedMedia: FeedMediaProtocol {

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

    /**
     <comment id='6ede90def1fb40b08ff71' post_id='bnd81g37d61f49fgn581' timestamp='1583894714' publisher_uid='1000000000000000003' publisher_name='user3'/>
       .....pb_payload.....
     </comment >
     */
    public init?(itemElement item: XMLElement) {
        guard let id = item.attributeStringValue(forName: "id"),
            let userId = item.attributeStringValue(forName: "publisher_uid"),
            let protoContainer = Clients_Container.feedItemContainer(from: item), protoContainer.hasComment else { return nil }

        let timestamp = item.attributeDoubleValue(forName: "timestamp")
        guard timestamp > 0 else { return nil }

        let protoComment = protoContainer.comment

        // Parsing "post_id" and "parent_comment_id" is temporary and needed for posts sent using old API.
        let postId = item.attributeStringValue(forName: "post_id") ?? protoComment.feedPostID
        guard !postId.isEmpty else {
            return nil
        }
        let parentCommentId = item.attributeStringValue(forName: "parent_comment_id") ?? protoComment.parentCommentID

        self.id = id
        self.userId = userId
        self.feedPostId = postId
        self.parentId = parentCommentId.isEmpty ? nil : parentCommentId
        self.text = protoComment.text
        self.mentions = protoComment.mentions.map { XMPPFeedMention(index: Int($0.index), userID: $0.userID, name: $0.name) }
        self.timestamp = Date(timeIntervalSince1970: timestamp)
    }
}
