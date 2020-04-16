//
//  XMPPFeed.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/15/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

enum XMPPFeedMediaType: String {
    case image = "image"
    case video = "video"
}

extension Proto_Container {
    static func feedPostContainer(from entry: XMLElement) -> Proto_Container? {
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


struct XMPPFeedPost {
    let id: FeedPostID
    let userId: UserID
    let text: String?
    let media: [XMPPFeedMedia]
    var timestamp: TimeInterval?

    init(text: String?, media: [PendingMedia]?) {
        self.id = UUID().uuidString
        self.userId = AppContext.shared.userData.userId
        self.text = text
        if let media = media?.map({ XMPPFeedMedia(feedMedia: $0) }) {
            self.media = media
        } else {
            self.media = []
        }
    }

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

        var hasProto = false, text: String?, media: [XMPPFeedMedia] = []
        if let protoContainer = Proto_Container.feedPostContainer(from: entry) {
            if protoContainer.hasPost {
                text = protoContainer.post.text.isEmpty ? nil : protoContainer.post.text
                media = protoContainer.post.media.compactMap { XMPPFeedMedia(protoMedia: $0) }

                hasProto = true
            }
        }

        if !hasProto {
            guard let feedPost = entry.element(forName: "feedpost") else { return nil }

            text = feedPost.element(forName: "text")?.stringValue
            if let mediaElement = feedPost.element(forName: "media") {
                media = mediaElement.elements(forName: "url").compactMap{ XMPPFeedMedia(urlElement: $0) }
            }
        }

        self.id = id
        self.userId = userId
        self.text = text
        self.media = media
        self.timestamp = item.attributeDoubleValue(forName: "timestamp")
    }

    var xmppElement: XMPPElement {
        get {
            let item = XMPPElement(name: "item")
            item.addAttribute(withName: "type", stringValue: "feedpost")
            item.addAttribute(withName: "id", stringValue: id)
            item.addChild({
                let entry = XMPPElement(name: "entry")
                entry.addChild({
                    let feedPost = XMPPElement(name: "feedpost")
                    if let text = text {
                        feedPost.addChild(XMPPElement(name: "text", stringValue: text))
                    }
                    if !self.media.isEmpty {
                        feedPost.addChild({
                            let media = XMLElement(name: "media")
                            media.setChildren(self.media.map{ $0.xmppElement })
                            return media
                        }())
                    }
                    return feedPost
                    }())
                if let protobufData = try? self.proto.serializedData() {
                    entry.addChild(XMPPElement(name: "s1", stringValue: protobufData.base64EncodedString()))
                }
                return entry
            }())
            return item
        }
    }

    fileprivate var proto: Proto_Container {
        get {
            var post = Proto_Post()
            if self.text != nil {
                post.text = self.text!
            }
            post.media = self.media.compactMap{ $0.proto }
            var container = Proto_Container()
            container.post = post
            return container
        }
    }
}

struct XMPPFeedMedia {
    let url: URL
    let type: XMPPFeedMediaType
    let size: CGSize
    let key: String
    let sha256: String

    init(feedMedia: PendingMedia) {
        self.url = feedMedia.url!
        self.type = {
            switch feedMedia.type {
            case .image: return .image
            case .video: return .video }
        }()
        self.size = feedMedia.size!
        self.key = feedMedia.key!
        self.sha256 = feedMedia.sha256!
    }

    /**
    <url type="image" width="1200" height="1600" key="wn58/JZ4nsZgxOBHw6usvdHfSIBRltZWzqb7u4kSyxc=" sha256hash="FA0cGbpNOfG9oFXezNIdsGVy3GSL2OXGxZ5sX8uXZls=">https://cdn.halloapp.net/CumlsHUTEeqobwpeZJbt6A</url>
     */
    init?(urlElement: XMLElement) {
        guard let type = XMPPFeedMediaType(rawValue: urlElement.attributeStringValue(forName: "type") ?? "") else { return nil }
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
        guard let type: XMPPFeedMediaType = {
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

    var xmppElement: XMPPElement {
        get {
            let media = XMPPElement(name: "url", stringValue: self.url.absoluteString)
            media.addAttribute(withName: "type", stringValue: self.type.rawValue)
            media.addAttribute(withName: "width", integerValue: Int(self.size.width))
            media.addAttribute(withName: "height", integerValue: Int(self.size.height))
            media.addAttribute(withName: "key", stringValue: key)
            media.addAttribute(withName: "sha256hash", stringValue: sha256)
            return media
        }
    }

    fileprivate var proto: Proto_Media? {
        get {
            guard let encryptionKey = Data(base64Encoded: self.key) else { return nil }
            guard let plaintextHash = Data(base64Encoded: self.sha256) else { return nil }

            var media = Proto_Media()
            media.type = {
                switch self.type {
                case .image: return .image
                case .video: return .video
                }
            }()
            media.width = Int32(self.size.width)
            media.height = Int32(self.size.height)
            media.encryptionKey = encryptionKey
            media.plaintextHash = plaintextHash
            media.downloadURL = self.url.absoluteString
            return media
        }
    }
}

struct XMPPComment {
    let id: FeedPostCommentID
    let userId: UserID
    let parentId: FeedPostCommentID?
    let feedPostId: FeedPostID
    let text: String
    var timestamp: TimeInterval?

    init(text: String, feedPostId: FeedPostID, parentCommentId: FeedPostCommentID?) {
        self.id = UUID().uuidString
        self.userId = AppContext.shared.userData.userId
        self.parentId = parentCommentId
        self.feedPostId = feedPostId
        self.text = text
    }

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

        var text: String?, feedPostId: String?, parentCommentId: String?
        if let protoContainer = Proto_Container.feedPostContainer(from: entry) {
            if protoContainer.hasComment {
                let protoComment = protoContainer.comment
                text = protoComment.text.isEmpty ? nil : protoComment.text
                feedPostId = protoComment.feedPostID.isEmpty ? nil : protoComment.feedPostID
                parentCommentId = protoComment.parentCommentID.isEmpty ? nil : protoComment.parentCommentID
            }
        }

        if text == nil || feedPostId == nil {
            guard let comment = item.element(forName: "entry")?.element(forName: "comment") else { return nil }
            feedPostId = comment.element(forName: "feedItemId")?.stringValue
            text = comment.element(forName: "text")?.stringValue
            parentCommentId = comment.element(forName: "parentCommentId")?.stringValue
        }

        guard feedPostId != nil && text != nil else { return nil }

        self.id = id
        self.userId = userId
        self.feedPostId = feedPostId!
        self.parentId = parentCommentId
        self.text = text!
        self.timestamp = item.attributeDoubleValue(forName: "timestamp")
    }

    var xmppElement: XMPPElement {
        get {
            let item = XMPPElement(name: "item")
            item.addAttribute(withName: "type", stringValue: "comment")
            item.addAttribute(withName: "id", stringValue: id)
            item.addChild({
                let entry = XMPPElement(name: "entry")
                entry.addChild({
                    let comment = XMPPElement(name: "comment")
                    comment.addChild(XMPPElement(name: "feedItemId", stringValue: feedPostId))
                    comment.addChild(XMPPElement(name: "text", stringValue: text))
                    if let parentId = parentId {
                        comment.addChild(XMPPElement(name: "parentCommentId", stringValue: parentId))
                    }
                    return comment
                }())
                if let protobufData = try? self.proto.serializedData() {
                    entry.addChild(XMPPElement(name: "s1", stringValue: protobufData.base64EncodedString()))
                }
                return entry
            }())
            return item
        }
    }

    fileprivate var proto: Proto_Container {
        get {
            var comment = Proto_Comment()
            comment.text = self.text
            comment.feedPostID = self.feedPostId
            if self.parentId != nil {
                comment.parentCommentID = self.parentId!
            }
            var container = Proto_Container()
            container.comment = comment
            return container
        }
    }
}
