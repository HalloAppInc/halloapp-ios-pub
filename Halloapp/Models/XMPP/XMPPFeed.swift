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

// MARK: Feed Item Protocol

enum FeedItemType {
    case post
    case comment
}

protocol FeedItemProtocol {

    // MARK: Data Fields

    static var itemType: FeedItemType { get }

    var id: String { get }

    var userId: String { get }

    var timestamp: Date { get }

    // MARK: Serialization

    func protoMessage(withData: Bool) -> SwiftProtobuf.Message
}

extension FeedItemProtocol {

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

    func protoContainer(withData: Bool) -> Proto_Container {
        var container = Proto_Container()
        switch Self.itemType {
        case .post:
            container.post = self.protoMessage(withData: withData) as! Proto_Post
        case .comment:
            container.comment = self.protoMessage(withData: withData) as! Proto_Comment
        }
        return container
    }
}

// MARK: Feed Post Media

protocol FeedMediaProtocol {

    var url: URL { get }

    var type: FeedMediaType { get }

    var size: CGSize { get }

    var key: String { get }

    var sha256: String { get }
}

extension FeedMediaProtocol {

    var protoMessage: Proto_Media {
        get {
            var media = Proto_Media()
            media.type = {
                switch type {
                case .image: return .image
                case .video: return .video
                }
            }()
            media.width = Int32(size.width)
            media.height = Int32(size.height)
            media.encryptionKey = Data(base64Encoded: key)!
            media.plaintextHash = Data(base64Encoded: sha256)!
            media.downloadURL = url.absoluteString
            return media
        }
    }
}

// MARK: Feed Post

protocol FeedPostProtocol: FeedItemProtocol {

    var text: String? { get }

    var orderedMedia: [FeedMediaProtocol] { get }
}

extension FeedPostProtocol {

    func protoMessage(withData: Bool) -> Message {
        var post = Proto_Post()
        if withData {
            if text != nil {
                post.text = text!
            }
            post.media = orderedMedia.compactMap{ $0.protoMessage }
        }
        return post
    }
}

// MARK: Feed Comment

protocol FeedCommentProtocol: FeedItemProtocol {

    var text: String { get }

    var feedPostId: String { get }

    var parentId: String? { get }
}

extension FeedCommentProtocol {

    func protoMessage(withData: Bool) -> Message {
        var comment = Proto_Comment()
        if withData {
            comment.text = text
        }
        comment.feedPostID = feedPostId
        if let parentId = parentId {
            comment.parentCommentID = parentId
        }
        return comment
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

struct XMPPFeedPost: FeedPostProtocol {

    // MARK: FeedItem
    static var itemType: FeedItemType { .post }
    let id: FeedPostID
    let userId: UserID
    var timestamp: Date = Date()

    // MARK: FeedPost
    let text: String?
    var orderedMedia: [FeedMediaProtocol] {
        get { media }
    }

    let media: [XMPPFeedMedia]

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
    init?(itemElement item: XMLElement) {
        guard let id = item.attributeStringValue(forName: "id") else { return nil }
        guard let userId = item.attributeStringValue(forName: "publisher")?.components(separatedBy: "@").first else { return nil }
        guard let entry = item.element(forName: "entry") else { return nil }
        guard let protoContainer = Proto_Container.feedItemContainer(from: entry) else { return nil }
        guard protoContainer.hasPost else { return nil }

        self.id = id
        self.userId = userId
        self.text = protoContainer.post.text.isEmpty ? nil : protoContainer.post.text
        self.media = protoContainer.post.media.compactMap { XMPPFeedMedia(protoMedia: $0) }
        let ts = item.attributeDoubleValue(forName: "timestamp")
        if ts > 0 {
            self.timestamp = Date(timeIntervalSince1970: ts)
        }
    }
}

struct XMPPFeedMedia: FeedMediaProtocol {

    let url: URL
    let type: FeedMediaType
    let size: CGSize
    let key: String
    let sha256: String

    init(feedMedia: PendingMedia) {
        self.url = feedMedia.url!
        self.type = feedMedia.type
        self.size = feedMedia.size!
        self.key = feedMedia.key!
        self.sha256 = feedMedia.sha256!
    }

    /**
    <url type="image" width="1200" height="1600" key="wn58/JZ4nsZgxOBHw6usvdHfSIBRltZWzqb7u4kSyxc=" sha256hash="FA0cGbpNOfG9oFXezNIdsGVy3GSL2OXGxZ5sX8uXZls=">https://cdn.halloapp.net/CumlsHUTEeqobwpeZJbt6A</url>
     */
    init?(urlElement: XMLElement) {
        guard let typeStr = urlElement.attributeStringValue(forName: "type") else { return nil }
        guard let type: FeedMediaType = {
            switch typeStr {
            case "image": return .image
            case "video": return .video
            default: return nil
            }}() else { return nil }
        guard let urlString = urlElement.stringValue else { return nil }
        guard let url = URL(string: urlString) else { return nil }
        let width = urlElement.attributeIntegerValue(forName: "width"), height = urlElement.attributeIntegerValue(forName: "height")
        guard width > 0 && height > 0 else { return nil }
        guard let key = urlElement.attributeStringValue(forName: "key") else { return nil }
        guard let sha256 = urlElement.attributeStringValue(forName: "sha256hash") else { return nil }

        self.url = url
        self.type = type
        self.size = CGSize(width: width, height: height)
        self.key = key
        self.sha256 = sha256
    }

    init?(protoMedia: Proto_Media) {
        guard let type: FeedMediaType = {
            switch protoMedia.type {
            case .image: return .image
            case .video: return .video
            default: return nil
            }}() else { return nil }
        guard let url = URL(string: protoMedia.downloadURL) else { return nil }
        let width = CGFloat(protoMedia.width), height = CGFloat(protoMedia.height)
        guard width > 0 && height > 0 else { return nil }

        self.url = url
        self.type = type
        self.size = CGSize(width: width, height: height)
        self.key = protoMedia.encryptionKey.base64EncodedString()
        self.sha256 = protoMedia.plaintextHash.base64EncodedString()
    }
}

struct XMPPComment: FeedCommentProtocol {

    // MARK: FeedItem
    static var itemType: FeedItemType { .comment }
    let id: FeedPostCommentID
    let userId: UserID
    var timestamp: Date = Date()

    // MARK: FeedComment
    let feedPostId: FeedPostID
    let parentId: FeedPostCommentID?
    let text: String

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
    init?(itemElement item: XMLElement) {
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
        let ts = item.attributeDoubleValue(forName: "timestamp")
        if ts > 0 {
            self.timestamp = Date(timeIntervalSince1970: ts)
        }
    }
}
