//
//  Feed.swift
//  Core
//
//  Created by Igor Solomennikov on 6/1/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CoreGraphics
import SwiftProtobuf
import XMPPFramework
import UIKit

// MARK: Types

public typealias FeedPostID = String

public typealias FeedPostCommentID = String

public enum FeedMediaType: Int {
    case image = 0
    case video = 1
}

public enum FeedItemType {
    case post
    case comment
}


// MARK: Feed Item Protocol

public protocol FeedItemProtocol {

    // MARK: Data Fields

    static var itemType: FeedItemType { get }

    var id: String { get }

    var userId: String { get }

    var timestamp: Date { get }

    // MARK: Serialization

    func oldFormatProtoMessage(withData: Bool) -> SwiftProtobuf.Message

    var protoMessage: SwiftProtobuf.Message { get }

    func xmppElement(withData: Bool) -> XMPPElement

    func protoFeedItem(withData: Bool) -> PBfeed_item.OneOf_Item
}

public extension FeedItemProtocol {

    func oldFormatProtoContainer(withData: Bool) -> Proto_Container {
        var container = Proto_Container()
        switch Self.itemType {
        case .post:
            container.post = self.oldFormatProtoMessage(withData: withData) as! Proto_Post
        case .comment:
            container.comment = self.oldFormatProtoMessage(withData: withData) as! Proto_Comment
        }
        return container
    }

    var protoContainer: Proto_Container {
        get {
            var container = Proto_Container()
            switch Self.itemType {
            case .post:
                container.post = protoMessage as! Proto_Post
            case .comment:
                container.comment = protoMessage as! Proto_Comment
            }
            return container
        }
    }
}

// MARK: Feed Mention

public protocol FeedMentionProtocol {

    var index: Int { get }

    var userID: String { get }

    var name: String { get }
}


extension FeedMentionProtocol {
    var protoMention: Proto_Mention {
        get {
            var mention = Proto_Mention()
            mention.index = Int32(index)
            mention.userID = userID
            mention.name = name
            return mention
        }
    }
}

// MARK: Feed Post Media

public protocol FeedMediaProtocol {

    var id: String { get }

    var url: URL? { get }

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
            media.downloadURL = url!.absoluteString
            return media
        }
    }
}

public struct PendingMediaEdit {
    public var originalURL: URL?
    public var image: UIImage?
    public var cropRect: CGRect = CGRect.zero
    public var hFlipped: Bool = false
    public var vFlipped: Bool = false
    public var numberOfRotations: Int = 0
    public var scale: CGFloat = 1.0
    public var offset = CGPoint.zero
    
    public init(originalURL: URL?, image: UIImage?) {
        self.originalURL = originalURL
        self.image = image
    }
}

public class PendingMedia {
    public var order: Int = 0
    public var type: FeedMediaType
    public var url: URL?
    public var uploadUrl: URL?
    public var size: CGSize?
    public var key: String?
    public var sha256: String?
    public var image: UIImage?
    public var videoURL: URL?
    public var fileURL: URL?
    public var encryptedFileUrl: URL?
    public var error: Error?
    
    public var edit: PendingMediaEdit?

    public init(type: FeedMediaType) {
        self.type = type
    }
    
    private func clearTemporaryMedia() {
        guard self.edit != nil else { return }
        guard let url = self.fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
    
    deinit {
        self.clearTemporaryMedia()
    }
}

public struct MediaURL {
    public var get: URL
    public var put: URL

    public init(get: URL, put: URL) {
        self.get = get
        self.put = put
    }
}

// MARK: FeedElement

public enum FeedElement {
    case post(FeedPostProtocol)
    case comment(FeedCommentProtocol, publisherName: String?)
}

public enum FeedRetract {
    case post(FeedPostID)
    case comment(FeedPostCommentID)
}

// MARK: Feed Post

public protocol FeedPostProtocol: FeedItemProtocol {

    var text: String? { get }

    var orderedMentions: [FeedMentionProtocol] { get }

    var orderedMedia: [FeedMediaProtocol] { get }
}

public extension FeedPostProtocol {

    func oldFormatProtoMessage(withData: Bool) -> Message {
        var post = Proto_Post()
        if withData {
            if text != nil {
                post.text = text!
            }
            post.mentions = orderedMentions.map { $0.protoMention }
            post.media = orderedMedia.compactMap{ $0.protoMessage }
        }
        return post
    }

    var protoMessage: SwiftProtobuf.Message {
        get {
            var post = Proto_Post()
            if let text = text {
                post.text = text
            }
            post.mentions = orderedMentions.map { $0.protoMention }
            post.media = orderedMedia.compactMap{ $0.protoMessage }
            return post
        }
    }

    func protoFeedItem(withData: Bool) -> PBfeed_item.OneOf_Item {
        var post = PBpost()

        if let uid = Int64(userId) {
            post.uid = uid
        }
        post.id = id
        post.timestamp = Int64(timestamp.timeIntervalSince1970)
        if let payload = try? oldFormatProtoContainer(withData: true).serializedData() {
            post.payload = payload
        }
        return .post(post)
    }
}

// MARK: Feed Comment

public protocol FeedCommentProtocol: FeedItemProtocol {

    var text: String { get }

    var orderedMentions: [FeedMentionProtocol] { get }

    var feedPostId: String { get }

    var feedPostUserId: UserID { get }

    var parentId: String? { get }
}

public extension FeedCommentProtocol {

    func oldFormatProtoMessage(withData: Bool) -> Message {
        var comment = Proto_Comment()
        if withData {
            comment.text = text
            comment.mentions = orderedMentions.map { $0.protoMention }
        }
        comment.feedPostID = feedPostId
        if let parentId = parentId {
            comment.parentCommentID = parentId
        }
        return comment
    }

    var protoMessage: Message {
        get {
            var comment = Proto_Comment()
            comment.text = text
            comment.feedPostID = feedPostId
            if let parentId = parentId {
                comment.parentCommentID = parentId
            }
            comment.mentions = orderedMentions.map { $0.protoMention }
            return comment
        }
    }

    func protoFeedItem(withData: Bool) -> PBfeed_item.OneOf_Item {
        var comment = PBcomment()
        comment.id = id
        if let parentID = parentId {
            comment.parentCommentID = parentID
        }
        comment.postID = feedPostId
        comment.timestamp = Int64(timestamp.timeIntervalSince1970)
        if let payload = try? oldFormatProtoContainer(withData: true).serializedData() {
            comment.payload = payload
        }

        return .comment(comment)
    }
}
