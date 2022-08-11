//
//  Feed.swift
//  Core
//
//  Created by Igor Solomennikov on 6/1/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CocoaLumberjackSwift
import Combine
import CoreGraphics
import Photos
import SwiftProtobuf
import UIKit

// MARK: Types

public typealias FeedPostID = String

public enum ShareDestination: Hashable, Equatable {
    case feed(PrivacyListType)
    case group(id: GroupID, name: String)
    case contact(id: UserID, name: String?, phone: String?)

    public static func destination(from group: Group) -> ShareDestination {
        return .group(id: group.id, name: group.name)
    }

    public static func destination(from contact: ABContact) -> ShareDestination? {
        guard let userId = contact.userId else { return nil }
        return .contact(id: userId, name: contact.fullName, phone: contact.phoneNumber)
    }
}

public typealias FeedPostCommentID = String
public typealias FeedLinkPreviewID = String

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
        Dictionary(mentions.map {
            (Int($0.index), MentionedUser(userID: $0.userID, pushName: $0.name))
        }) { (v1, v2) in v2 }
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

    var type: CommonMediaType { get }

    var size: CGSize { get }

    var key: String { get }

    var sha256: String { get }

    var blobVersion: BlobVersion { get }

    var chunkSize: Int32 { get }

    var blobSize: Int64 { get }
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
            media.blobVersion = blobVersion.protoBlobVersion
            media.chunkSize = chunkSize
            media.blobSize = blobSize
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
            var streamingInfo = Clients_StreamingInfo()
            streamingInfo.blobVersion = blobVersion.protoBlobVersion
            streamingInfo.chunkSize = chunkSize
            streamingInfo.blobSize = blobSize
            vid.streamingInfo = streamingInfo
            albumMedia.media = .video(vid)
        case .audio:
            return nil
        }
        return albumMedia
    }

}

public enum PendingUndo: Equatable {
    case flip, rotateReverse, remove, restore((Int, PendingLayer)), insert((Int, PendingLayer))

    static public func == (lhs: PendingUndo, rhs: PendingUndo) -> Bool {
        switch (lhs, rhs) {
        case (.restore((let lidx, let llayer)), .restore((let ridx, let rlayer))):
            return lidx == ridx && llayer == rlayer
        case (.insert((let lidx, let llayer)), .insert((let ridx, let rlayer))):
            return lidx == ridx && llayer == rlayer
        case (.flip, .flip), (.rotateReverse, .rotateReverse), (.remove, .remove):
            return true
        default:
            return false
        }
    }
}

public enum PendingLayer: Equatable {
    case path(Path)
    case annotation(Annotation)

    public struct Path: Equatable {
        public var points: [CGPoint]
        public var color: UIColor
        public var width: CGFloat

        public init(points: [CGPoint], color: UIColor, width: CGFloat) {
            self.points = points
            self.color = color
            self.width = width
        }
    }

    public struct Annotation: Equatable {
        public var text: String
        public var font: UIFont
        public var color: UIColor
        public var location: CGPoint
        public var rotation: CGFloat

        public init(text: String, font: UIFont, color: UIColor, location: CGPoint, rotation: CGFloat = 0) {
            self.text = text
            self.font = font
            self.color = color
            self.location = location
            self.rotation = rotation
        }
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
    public var layers = [PendingLayer]()
    public var undoStack: [PendingUndo] = []
    
    public init(image: UIImage?, url: URL?) {
        self.image = image
        self.url = url
    }
}

public class PendingMedia {
    public static let queue = DispatchQueue(label: "com.halloapp.pending-media", qos: .userInitiated)
    private static let homeDirURL = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL

    public var order: Int = 0
    public var type: CommonMediaType
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

    public init(type: CommonMediaType) {
        self.type = type
    }

    public init?(asset: PHAsset) {
        switch asset.mediaType {
        case .image:
            self.type = .image
        case .video:
            self.type = .video
        default:
            return nil
        }

        self.asset = asset
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

    var hasUploadURL: Bool {
        switch self {
        case .getPut, .patch:
            return true
        case .download:
            return false
        }
    }
}

// MARK: FeedElement

public enum FeedElementType: Int {
    case post = 0
    case comment = 1
}

extension FeedElementType {
    public var rawString: String {
        switch self {
        case .post:
            return "post"
        case .comment:
            return "comment"
        }
    }
}

public enum FeedElementID {
    case post(FeedPostID)
    case comment(FeedPostCommentID)
    case linkPreview(FeedLinkPreviewID)
}

public enum FeedElement {
    case post(PostData)
    case comment(CommentData, publisherName: String?)
}

public enum FeedContent {
    case newItems([FeedElement])
    case retracts([FeedRetract])
}

public enum FeedRetract {
    case post(FeedPostID)
    case comment(FeedPostCommentID)
}

// MARK: Feed Post

public extension PostData {

    var clientContainer: Clients_Container {
        var container = Clients_Container()
        container.postContainer = clientPostContainer
        return container
    }

    var clientPostContainer: Clients_PostContainer {
        var container = Clients_PostContainer()
        switch content {
        case .text(let mentionText, let linkPreviewData):
            let text = Clients_Text(mentionText: mentionText, linkPreviews: linkPreviewData)
            container.post = .text(text)
        case .album(let mentionText, let media):
            var album = Clients_Album()
            album.media = media.compactMap { $0.albumMedia }
            album.text = Clients_Text(mentionText: mentionText)

            if let voiceNoteMediaItem = media.first(where: { $0.type == .audio }) {
                var voiceNote = Clients_VoiceNote()
                if let audio = voiceNoteMediaItem.protoResource {
                    voiceNote.audio = audio
                }
                album.voiceNote = voiceNote
            }

            container.post = .album(album)
        case .voiceNote(let mediaItem):
            var voiceNote = Clients_VoiceNote()
            if let audio = mediaItem.protoResource {
                voiceNote.audio = audio
            }
            container.post = .voiceNote(voiceNote)
        case .moment(let mediaItem, _):
            var moment = Clients_Moment()
            var image = Clients_Image()
            if let resource = mediaItem.protoResource {
                image.img = resource
                image.width = Int32(mediaItem.size.width)
                image.height = Int32(mediaItem.size.height)
            }
            
            moment.image = image
            container.post = .moment(moment)
        case .retracted, .unsupported, .waiting:
            break
        }
        container.commentKey = commentKey ?? Data()
        return container
    }

    var clientPostContainerBlob: Clients_PostContainerBlob {
        var container = Clients_PostContainerBlob()
        container.postContainer = clientPostContainer
        container.postID = id
        container.timestamp = Int64(timestamp.timeIntervalSince1970)
        container.uid = Int64(userId) ?? 0
        return container
    }

    var serverPost: Server_Post? {
        guard let payloadData = try? clientContainer.serializedData() else {
            return nil
        }

        var serverPost = Server_Post()
        serverPost.id = id
        serverPost.payload = payloadData
        serverPost.publisherUid = Int64(userId) ?? 0
        serverPost.timestamp = Int64(timestamp.timeIntervalSince1970)

        if case let .moment(_, unlockedUserID) = content {
            serverPost.tag = .secretPost
            if let unlockedUserID = unlockedUserID, let asInteger = Int64(unlockedUserID) {
                serverPost.momentUnlockUid = asInteger
            }
        }

        // Add media counters.
        serverPost.mediaCounters = serverMediaCounters

        return serverPost
    }
}

// MARK: Feed Comment

public extension CommentData {

    var clientContainer: Clients_Container {
        var container = Clients_Container()
        container.commentContainer = clientCommentContainer
        return container
    }

    var clientCommentContainer: Clients_CommentContainer {
        var commentContainer = Clients_CommentContainer()
        switch content {
        case .text(let mentionText, let linkPreviewData):
            let text = Clients_Text(mentionText: mentionText, linkPreviews: linkPreviewData)
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
        case .commentReaction(let emoji):
            var reaction = Clients_Reaction()
            reaction.emoji = emoji
            commentContainer.reaction = reaction
        case .retracted, .unsupported, .waiting:
            break
        }
        commentContainer.context.feedPostID = feedPostId
        if let parentId = parentId {
            commentContainer.context.parentCommentID = parentId
        }
        return commentContainer
    }

    var serverComment: Server_Comment? {
        var comment = Server_Comment()
        comment.id = id
        if let parentID = parentId {
            comment.parentCommentID = parentID
        }
        comment.postID = feedPostId
        comment.publisherUid = Int64(userId) ?? 0
        comment.timestamp = Int64(timestamp.timeIntervalSince1970)
        switch content {
        case .commentReaction:
            comment.commentType = .commentReaction
        case .text, .voiceNote, .album, .unsupported, .retracted, .waiting:
            comment.commentType = .comment
        }
        if let payload = try? clientContainer.serializedData() {
            comment.payload = payload
        } else {
            DDLogError("CommentData/serverComment/\(id)/error [could not create payload]")
            return nil
        }

        // Add media counters.
        comment.mediaCounters = serverMediaCounters
        return comment
    }
}
