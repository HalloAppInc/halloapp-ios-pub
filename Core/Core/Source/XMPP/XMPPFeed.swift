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

public extension FeedItemProtocol {

    func xmppElement(withData: Bool) -> XMPPElement {
        let type: String = {
            switch Self.itemType {
            case .post: return "feedpost"
            case .comment: return "comment"
            }}()
        let item = XMPPElement(name: "item")
        item.addAttribute(withName: "id", stringValue: id)
        item.addAttribute(withName: "type", stringValue: type)
        item.addChild({
            let entry = XMPPElement(name: "entry")
            if let protobufData = try? self.protoContainer(withData: withData).serializedData() {
                entry.addChild(XMPPElement(name: "s1", stringValue: protobufData.base64EncodedString()))
            }
            return entry
            }())
        return item
    }
}

enum XMPPFeedMediaType: String {
    case image = "image"
    case video = "video"
}

extension Proto_Container {

    static func feedItemContainer(from entry: XMLElement) -> Proto_Container? {
        guard let s1 = entry.element(forName: "s1")?.stringValue else { return nil }
        guard let data = Data(base64Encoded: s1, options: .ignoreUnknownCharacters) else { return nil }
        do {
            let protoContainer = try Proto_Container(serializedData: data)
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

    /**
     <item timestamp="1585853535" publisher="16504228573@s.halloapp.net/iphone" type="feedpost" id="4A0D1C4E-566A-4BED-93A3-0D6D995B3B9B">
        <entry>
            <feedpost>
                <text>Test post</text>
                <media>
                    <url type="image" width="1200" height="1600" key="wn58/JZ4nsZgxOBHw6usvdHfSIBRltZWzqb7u4kSyxc=" sha256hash="FA0cGbpNOfG9oFXezNIdsGVy3GSL2OXGxZ5sX8uXZls=">https://cdn.halloapp.net/CumlsHUTEeqobwpeZJbt6A</url>
                </media>
            </feedpost>
            <s1>EmYKIDM0MzBjYmFjNmM5YTRjMGVhZWEwMDhkMTE3MjU1M2JjEgsxNjUwMjgxMzY3NxokRDUyOEIzNUYtNzUxQy00ODdGLUFBODgtQkE2NkVDNEE0RDZBIg9UaGV5IGFyZSB5ZWxsb3c=</s1>
        </entry>
     </item>
     */
    public init?(itemElement item: XMLElement) {
        guard let id = item.attributeStringValue(forName: "id") else { return nil }
        guard let userId = item.attributeStringValue(forName: "publisher")?.components(separatedBy: "@").first else { return nil }
        guard let entry = item.element(forName: "entry") else { return nil }
        guard let protoContainer = Proto_Container.feedItemContainer(from: entry) else { return nil }
        guard protoContainer.hasPost else { return nil }

        self.id = id
        self.userId = userId
        self.text = protoContainer.post.text.isEmpty ? nil : protoContainer.post.text
        self.media = protoContainer.post.media.enumerated().compactMap { XMPPFeedMedia(id: "\(id)-\($0)", protoMedia: $1) }
        self.mentions = protoContainer.post.mentions.map { XMPPFeedMention(index: Int($0.index), userID: $0.userID, name: $0.name) }
        let ts = item.attributeDoubleValue(forName: "timestamp")
        if ts > 0 {
            self.timestamp = Date(timeIntervalSince1970: ts)
        }
    }
}

public struct XMPPFeedMention: FeedMentionProtocol {

    public let index: Int
    public let userID: String
    public let name: String
}

public struct XMPPFeedMedia: FeedMediaProtocol {

    public let id: String
    public let url: URL
    public let type: FeedMediaType
    public let size: CGSize
    public let key: String
    public let sha256: String

    public init?(id: String, protoMedia: Proto_Media) {
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
    public let parentId: FeedPostCommentID?
    public let text: String
    public var orderedMentions: [FeedMentionProtocol] {
        get { mentions.sorted { $0.index < $1.index } }
    }

    public let mentions: [XMPPFeedMention]

    /**
     <item timestamp="1585847898" publisher="16504228573@s.halloapp.net/iphone" type="comment" id="F198FE77-EEF7-487A-9D40-A36A74B24221">
         <entry>
             <comment>
                <feedItemId>5099E935-65AD-4325-93B7-FA30B3FD8461</feedItemId>
                <text>Qwertyu</text>
             </comment>
             <s1>EmYKIDM0MzBjYmFjNmM5YTRjMGVhZWEwMDhkMTE3MjU1M2JjEgsxNjUwMjgxMzY3NxokRDUyOEIzNUYtNzUxQy00ODdGLUFBODgtQkE2NkVDNEE0RDZBIg9UaGV5IGFyZSB5ZWxsb3c=</s1>
         </entry>
     </item>
     */
    public init?(itemElement item: XMLElement) {
        guard let id = item.attributeStringValue(forName: "id") else { return nil }
        guard let userId = item.attributeStringValue(forName: "publisher")?.components(separatedBy: "@").first else { return nil }
        guard let entry = item.element(forName: "entry") else { return nil }

        guard let protoContainer = Proto_Container.feedItemContainer(from: entry) else { return nil }
        guard protoContainer.hasComment else { return nil }

        let protoComment = protoContainer.comment

        let text = protoComment.text.isEmpty ? nil : protoComment.text
        let feedPostId = protoComment.feedPostID.isEmpty ? nil : protoComment.feedPostID
        let parentCommentId = protoComment.parentCommentID.isEmpty ? nil : protoComment.parentCommentID
        guard feedPostId != nil && text != nil else { return nil }

        self.id = id
        self.userId = userId
        self.feedPostId = feedPostId!
        self.parentId = parentCommentId
        self.text = text!
        self.mentions = protoComment.mentions.map { XMPPFeedMention(index: Int($0.index), userID: $0.userID, name: $0.name) }
        let ts = item.attributeDoubleValue(forName: "timestamp")
        if ts > 0 {
            self.timestamp = Date(timeIntervalSince1970: ts)
        }
    }
}
