//
//  Feed.swift
//  Core
//
//  Created by Igor Solomennikov on 6/1/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CoreGraphics
import Photos
import SwiftProtobuf
import XMPPFramework
import UIKit

// MARK: Types

public typealias FeedPostID = String

public enum FeedPostDestination {
    case userFeed
    case groupFeed(GroupID)
}

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

    var protoMessage: SwiftProtobuf.Message { get }

    func protoFeedItem(withData: Bool) -> Server_FeedItem.OneOf_Item
}

public extension FeedItemProtocol {

    var protoContainer: Clients_Container {
        get {
            var container = Clients_Container()
            switch Self.itemType {
            case .post:
                container.post = protoMessage as! Clients_Post
            case .comment:
                container.comment = protoMessage as! Clients_Comment
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
    var protoMention: Clients_Mention {
        get {
            var mention = Clients_Mention()
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

    var protoMessage: Clients_Media {
        get {
            var media = Clients_Media()
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
    public var asset: PHAsset?
    
    public var edit: PendingMediaEdit?

    public init(type: FeedMediaType) {
        self.type = type
    }
    
    private func clearTemporaryMedia() {
        guard self.edit != nil else { return }
        guard let url = self.fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func clearVideo() {
        guard let url = self.videoURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
    
    deinit {
        clearTemporaryMedia()
        clearVideo()
    }
}

public enum MediaURLInfo {
    case getPut(URL, URL)
    case patch(URL)
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

    var protoMessage: SwiftProtobuf.Message {
        get {
            var post = Clients_Post()
            if let text = text {
                post.text = text
            }
            post.mentions = orderedMentions.map { $0.protoMention }
            post.media = orderedMedia.compactMap{ $0.protoMessage }
            return post
        }
    }

    var serverPost: Server_Post {
        var post = Server_Post()

        if let uid = Int64(userId) {
            post.publisherUid = uid
        }
        post.id = id
        post.timestamp = Int64(timestamp.timeIntervalSince1970)
        if let payload = try? protoContainer.serializedData() {
            post.payload = payload
        }
        return post
    }

    func protoFeedItem(withData: Bool) -> Server_FeedItem.OneOf_Item {
        if withData {
            return .post(serverPost)
        } else {
            var post = Server_Post()
            post.id = id
            return .post(post)
        }
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

    var protoMessage: Message {
        get {
            var comment = Clients_Comment()
            comment.text = text
            comment.feedPostID = feedPostId
            if let parentId = parentId {
                comment.parentCommentID = parentId
            }
            comment.mentions = orderedMentions.map { $0.protoMention }
            return comment
        }
    }

    var serverComment: Server_Comment {
        var comment = Server_Comment()
        comment.id = id
        if let parentID = parentId {
            comment.parentCommentID = parentID
        }
        comment.postID = feedPostId
        comment.timestamp = Int64(timestamp.timeIntervalSince1970)
        if let payload = try? protoContainer.serializedData() {
            comment.payload = payload
        }

        return comment
    }

    func protoFeedItem(withData: Bool) -> Server_FeedItem.OneOf_Item {
        if withData {
            return .comment(serverComment)
        } else {
            var comment = Server_Comment()
            comment.id = id
            comment.postID = feedPostId
            return .comment(comment)
        }
    }
}
