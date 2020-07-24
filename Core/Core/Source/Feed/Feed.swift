//
//  Feed.swift
//  Core
//
//  Created by Igor Solomennikov on 6/1/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CoreGraphics
import SwiftProtobuf
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

    func protoMessage(withData: Bool) -> SwiftProtobuf.Message
}

extension FeedItemProtocol {

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

public protocol FeedMediaProtocol {

    var id: String { get }

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

public class PendingMedia {
    public var order: Int = 0
    public var type: FeedMediaType
    public var url: URL?
    public var size: CGSize?
    public var key: String?
    public var sha256: String?
    public var image: UIImage?
    public var videoURL: URL?
    public var fileURL: URL?
    public var error: Error?

    public init(type: FeedMediaType) {
        self.type = type
    }
}


// MARK: Feed Post

public protocol FeedPostProtocol: FeedItemProtocol {

    var text: String? { get }

    var orderedMedia: [FeedMediaProtocol] { get }
}

public extension FeedPostProtocol {

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

public protocol FeedCommentProtocol: FeedItemProtocol {

    var text: String { get }

    var feedPostId: String { get }

    var parentId: String? { get }
}

public extension FeedCommentProtocol {

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
