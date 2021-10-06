//
//  Feed.swift
//  Core
//
//  Created by Igor Solomennikov on 6/1/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import CoreGraphics
import Photos
import SwiftProtobuf
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
    case audio = 2
}

// MARK: Feed Mention

public protocol FeedMentionProtocol {

    var index: Int { get }

    var userID: String { get }

    var name: String { get }
}

public extension MentionText {
    init(collapsedText: String, mentionArray: [FeedMentionProtocol]) {
        self.init(
            collapsedText: collapsedText,
            mentions: Self.mentionDictionary(from: mentionArray))
    }

    private static func mentionDictionary(from mentions: [FeedMentionProtocol]) -> [Int: MentionedUser] {
        Dictionary(uniqueKeysWithValues: mentions.map {
            (Int($0.index), MentionedUser(userID: $0.userID, pushName: $0.name))
        })
    }
}

public extension FeedMentionProtocol {
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

    var protoMessage: Clients_Media? {
        get {
            guard let url = url else {
                DDLogError("FeedMediaProtocol/protoMessage/\(id)/error [missing url]")
                return nil
            }
            var media = Clients_Media()
            media.type = {
                switch type {
                case .image: return .image
                case .video: return .video
                case .audio: return .audio
                }
            }()
            media.width = Int32(size.width)
            media.height = Int32(size.height)
            media.encryptionKey = Data(base64Encoded: key)!
            media.ciphertextHash = Data(base64Encoded: sha256)!
            media.downloadURL = url.absoluteString
            return media
        }
    }

    var protoResource: Clients_EncryptedResource? {
        guard let url = url else {
            DDLogError("FeedMediaProtocol/protoResource/error missing url")
            return nil
        }
        guard let encryptionKey = Data(base64Encoded: key) else {
            DDLogError("FeedMediaProtocol/protoResource/error encryption key")
            return nil
        }
        guard let ciphertextHash = Data(base64Encoded: sha256) else {
            DDLogError("FeedMediaProtocol/protoResource/error ciphertext hash")
            return nil
        }

        var resource = Clients_EncryptedResource()
        resource.encryptionKey = encryptionKey
        resource.ciphertextHash = ciphertextHash
        resource.downloadURL = url.absoluteString

        return resource
    }

    var albumMedia: Clients_AlbumMedia? {
        guard let downloadURL = url?.absoluteString,
              let encryptionKey = Data(base64Encoded: key),
              let cipherTextHash = Data(base64Encoded: sha256) else
        {
            return nil
        }
        var albumMedia = Clients_AlbumMedia()
        var res = Clients_EncryptedResource()
        res.ciphertextHash = cipherTextHash
        res.downloadURL = downloadURL
        res.encryptionKey = encryptionKey
        switch type {
        case .image:
            var img = Clients_Image()
            img.img = res
            img.width = Int32(size.width)
            img.height = Int32(size.height)
            albumMedia.media = .image(img)
        case .video:
            var vid = Clients_Video()
            vid.video = res
            vid.width = Int32(size.width)
            vid.height = Int32(size.height)
            albumMedia.media = .video(vid)
        case .audio:
            return nil
        }
        return albumMedia
    }

}

public struct PendingVideoEdit: Equatable {
    public var start: CGFloat = 0.0
    public var end: CGFloat = 1.0
    public var muted: Bool = false

    public init(start: CGFloat, end: CGFloat, muted: Bool) {
        self.start = start
        self.end = end
        self.muted = muted
    }
}

public enum PendingMediaError: Error {
    case loadingError
    case processingError
}

public struct PendingMediaEdit: Equatable {
    public var image: UIImage?
    public var url: URL?
    public var cropRect: CGRect = CGRect.zero
    public var hFlipped: Bool = false
    public var vFlipped: Bool = false
    public var numberOfRotations: Int = 0
    public var scale: CGFloat = 1.0
    public var offset = CGPoint.zero
    
    public init(image: UIImage?, url: URL?) {
        self.image = image
        self.url = url
    }
}

public class PendingMedia {
    public static let queue = DispatchQueue(label: "com.halloapp.pending-media", qos: .userInitiated)
    private static let homeDirURL = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL

    public var order: Int = 0
    public var type: FeedMediaType
    public var url: URL?
    public var uploadUrl: URL?
    public var size: CGSize?
    public var key: String?
    public var sha256: String?
    public var isResized = false
    public var progress = CurrentValueSubject<Float, Never>(0)
    public var ready = CurrentValueSubject<Bool, Never>(false)
    public var error = CurrentValueSubject<Error?, Never>(nil)

    public var image: UIImage? {
        get {
            guard let url = fileURL else { return nil }
            return UIImage(contentsOfFile: url.path)
        }
        set {
            guard let image = newValue else {
                fileURL = nil
                return
            }

            PendingMedia.queue.async { [weak self] in
                guard let self = self else { return }

                // Local copy of the file is required for further processing
                let url = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(UUID().uuidString, isDirectory: false)
                    .appendingPathExtension("jpg")

                guard image.save(to: url) else {
                    DDLogError("PendingMedia: unable to save image")
                    return
                }

                self.size = image.size
                self.fileURL = url

                DispatchQueue.main.async {
                    self.progress.send(1)
                    self.progress.send(completion: .finished)
                    self.ready.send(true)
                    self.ready.send(completion: .finished)
                }
            }
        }
    }

    // TODO(VL): Possibly create custom type for videoURL and fileURL, that manages their lifecycle?
    public var originalVideoURL: URL? {
        didSet {
            if originalVideoURL != nil { DDLogDebug("PendingMedia: set originalVideoURL \(originalVideoURL!)") }
            if let previousVideoURL = oldValue, !isInUseURL(previousVideoURL) {
                PendingMedia.queue.async { [weak self] in
                    guard let self = self else { return }
                    self.clearTemporaryMedia(tempURL: previousVideoURL)
                }
            }
        }
    }
    public var fileURL: URL? {
        didSet {
            if fileURL != nil { DDLogDebug("PendingMedia: set fileUrl \(fileURL!)") }
            if let previousFileURL = oldValue, !isInUseURL(previousFileURL) {
                PendingMedia.queue.async {  [weak self] in
                    guard let self = self else { return }
                    self.clearTemporaryMedia(tempURL: previousFileURL)
                }
            }

            if type == .video {
                PendingMedia.queue.async { [weak self] in
                    guard let self = self else { return }
                    defer {
                        DispatchQueue.main.async {
                            self.progress.send(1)
                            self.progress.send(completion: .finished)
                            self.ready.send(true)
                            self.ready.send(completion: .finished)
                        }
                    }

                    guard let url = self.fileURL else { return }
                    guard let track = AVURLAsset(url: url).tracks(withMediaType: AVMediaType.video).first else { return }

                    let size = track.naturalSize.applying(track.preferredTransform)
                    self.size = CGSize(width: abs(size.width), height: abs(size.height))

                    DDLogInfo("PendingMedia Video size: [\(NSCoder.string(for: size))]")
                }
            }
        }
    }
    public var encryptedFileUrl: URL?
    public var asset: PHAsset?
    
    public var edit: PendingMediaEdit?
    public var videoEdit: PendingVideoEdit?

    public init(type: FeedMediaType) {
        self.type = type
    }

    public func resetProgress() {
        progress = CurrentValueSubject<Float, Never>(0)
        ready = CurrentValueSubject<Bool, Never>(false)
        error = CurrentValueSubject<Error?, Never>(nil)
    }

    private func clearTemporaryMedia(tempURL: URL?) {
        guard let toBeClearedURL = tempURL, toBeClearedURL.isFileURL, toBeClearedURL.standardizedFileURL.path.hasPrefix(PendingMedia.homeDirURL.path) else { return }
        DDLogDebug("PendingMedia: free tempURL \(toBeClearedURL)")
        try? FileManager.default.removeItem(at: toBeClearedURL)
    }

    private func isInUseURL(_ previousURL: URL) -> Bool {
        return [fileURL, originalVideoURL, edit?.url].contains(previousURL)
    }
    
    deinit {
        [fileURL, originalVideoURL, edit?.url].forEach { tempURL in clearTemporaryMedia(tempURL: tempURL) }
    }
}

public enum MediaURLInfo {
    case getPut(URL, URL)
    case patch(URL)
    case download(URL)
}

// MARK: FeedElement

public enum FeedElementType: Int {
    case post = 0
    case comment = 1
}

public enum FeedElementID {
    case post(FeedPostID)
    case comment(FeedPostCommentID)
}

public enum FeedElement {
    case post(PostData)
    case comment(CommentData, publisherName: String?)
}

public enum FeedRetract {
    case post(FeedPostID)
    case comment(FeedPostCommentID)
}

// MARK: Feed Post

public extension PostData {

    var clientContainer: Clients_Container? {
        var container = Clients_Container()
        container.postContainer = clientPostContainer
        if let postLegacy = clientPostLegacy {
            container.post = postLegacy
        }
        return container
    }

    var clientPostContainer: Clients_PostContainer {
        var container = Clients_PostContainer()
        switch content {
        case .text(let mentionText, let linkPreviewData):
            var text = Clients_Text(mentionText: mentionText)
            text.linkPreviewData = linkPreviewData
            container.post = .text(text)
        case .album(let mentionText, let media):
            var album = Clients_Album()
            album.media = media.compactMap { $0.albumMedia }
            album.text = Clients_Text(mentionText: mentionText)
            container.post = .album(album)
        case .retracted, .unsupported:
            break
        }
        return container
    }

    /// Legacy format post (will be superseded by Clients_PostContainer)
    var clientPostLegacy: Clients_Post? {
        var post = Clients_Post()
        if let text = text {
            post.text = text
        }
        post.mentions = orderedMentions.map { $0.protoMention }
        post.media = orderedMedia.compactMap { $0.protoMessage }
        if post.media.count < orderedMedia.count {
            DDLogError("PostData/clientPostLegacy/\(id)/error [media not ready]")
            return nil
        }
        return post
    }
}

// MARK: Feed Comment

public extension CommentData {

    var clientContainer: Clients_Container {
        var container = Clients_Container()
        // Populate container.comment only if its not a media comment
        if let clientCommentLegacy = clientCommentLegacy {
            container.comment = clientCommentLegacy
        }
        container.commentContainer = clientCommentContainer
        return container
    }

    var clientCommentContainer: Clients_CommentContainer {
        var commentContainer = Clients_CommentContainer()
        switch content {
        case .text(let mentionText, let linkPreviewData):
            var text = Clients_Text(mentionText: mentionText)
            text.linkPreviewData = linkPreviewData
            commentContainer.text = text
        case .album(let mentionText, let media):
            var album = Clients_Album()
            album.media = media.compactMap { $0.albumMedia }
            album.text = Clients_Text(mentionText: mentionText)
            commentContainer.album = album
        case .voiceNote(let media):
            guard let protoResource = media.protoResource else { break }
            var voiceNote = Clients_VoiceNote()
            voiceNote.audio = protoResource
            commentContainer.voiceNote = voiceNote
        case .retracted, .unsupported:
            break
        }
        commentContainer.context.feedPostID = feedPostId
        if let parentId = parentId {
            commentContainer.context.parentCommentID = parentId
        }
        return commentContainer
    }

    /// Legacy format comment (will be superseded by Clients_CommentContainer)
    var clientCommentLegacy: Clients_Comment? {
        var comment = Clients_Comment()
        switch content {
        case .text(let mentionText, _):
            comment.text = mentionText.collapsedText
            comment.mentions = mentionText.mentions
                .map { (i, user) in
                    var clientMention = Clients_Mention()
                    clientMention.userID = user.userID
                    clientMention.name = user.pushName ?? ""
                    clientMention.index = Int32(i)
                    return clientMention
                }
                .sorted { $0.index < $1.index }
        case .album(_, _), .voiceNote:
            return nil
        case .retracted, .unsupported:
            break
        }
        comment.feedPostID = feedPostId
        if let parentId = parentId {
            comment.parentCommentID = parentId
        }
        return comment
    }

    var serverComment: Server_Comment? {
        var comment = Server_Comment()
        comment.id = id
        if let parentID = parentId {
            comment.parentCommentID = parentID
        }
        comment.postID = feedPostId
        comment.timestamp = Int64(timestamp.timeIntervalSince1970)
        if let payload = try? clientContainer.serializedData() {
            comment.payload = payload
        } else {
            DDLogError("CommentData/serverComment/\(id)/error [could not create payload]")
            return nil
        }

        return comment
    }
}
