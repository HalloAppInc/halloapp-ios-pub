//
//  Chat.swift
//  Core
//
//  Created by Igor Solomennikov on 8/18/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import UIKit

public typealias GroupID = String

public enum ChatType: Int16 {
    case oneToOne = 0
    case group = 1
}

public enum ChatState: String {
    case available = "available"
    case typing = "typing"
}

public enum ChatMessageMediaType: Int, Codable {
    case image = 0
    case video = 1
}

public enum IncomingChatMessage {
    case notDecrypted(ChatMessageTombstone)
    case decrypted(ChatMessageProtocol)
}

public protocol ChatMessageProtocol {
    var id: String { get }
    var fromUserId: UserID { get }
    var toUserId: UserID { get }

    /// 1 and higher means it's an offline message and that server has sent out a push notification already
    var retryCount: Int32? { get }

    /// 0 when the message is first sent, incrementing each time the message is rerequested
    var rerequestCount: Int32 { get }

    var content: ChatContent { get }
    var context: ChatContext { get }

    var timeIntervalSince1970: TimeInterval? { get }
}

public enum ChatContent {
    case text(String)
    case album(String?, [ChatMediaProtocol])
    case unsupported(Data)
}

public struct ChatContext {
    public init(feedPostID: String? = nil, feedPostMediaIndex: Int32 = 0, chatReplyMessageID: String? = nil, chatReplyMessageMediaIndex: Int32 = 0, chatReplyMessageSenderID: String? = nil) {
        self.feedPostID = feedPostID
        self.feedPostMediaIndex = feedPostMediaIndex
        self.chatReplyMessageID = chatReplyMessageID
        self.chatReplyMessageMediaIndex = chatReplyMessageMediaIndex
        self.chatReplyMessageSenderID = chatReplyMessageSenderID
    }

    public var feedPostID: String? = nil
    public var feedPostMediaIndex: Int32 = 0
    public var chatReplyMessageID: String? = nil
    public var chatReplyMessageMediaIndex: Int32 = 0
    public var chatReplyMessageSenderID: String? = nil
}

public extension ChatContext {
    var clientContext: Clients_ChatContext {
        var context = Clients_ChatContext()
        if let feedPostID = feedPostID {
            context.feedPostID = feedPostID
            context.feedPostMediaIndex = feedPostMediaIndex
        }
        if let chatReplyMessageID = chatReplyMessageID, let chatReplyMessageSenderID = chatReplyMessageSenderID {
            context.chatReplyMessageID = chatReplyMessageID
            context.chatReplyMessageMediaIndex = chatReplyMessageMediaIndex
            context.chatReplyMessageSenderID = chatReplyMessageSenderID
        }
        return context
    }
}

public extension ChatMessageProtocol {
    var protoContainer: Clients_Container? {
        get {
            guard let clientChatLegacy = clientChatLegacy else { return nil }
            var protoContainer = Clients_Container()
            protoContainer.chatMessage = clientChatLegacy
            if let clientChatContainer = clientChatContainer {
                protoContainer.chatContainer = clientChatContainer
            }
            return protoContainer
        }
    }

    var clientChatContainer: Clients_ChatContainer? {
        var container = Clients_ChatContainer()
        container.context = context.clientContext
        switch content {
        case .album(let text, let media):
            var album = Clients_Album()
            album.media = media.compactMap { $0.albumMedia }
            album.text = Clients_Text(text: text ?? "")
            container.message = .album(album)
        case .text(let text):
            let clientsText = Clients_Text(text: text)
            container.message = .text(clientsText)
        case .unsupported(_):
            return nil
        }
        return container
    }

    /// Legacy format chat (will be superseded by Clients_ChatContainer)
    var clientChatLegacy: Clients_ChatMessage? {
        var protoChatMessage = Clients_ChatMessage()
        switch content {
        case .album(let text, let media):
            protoChatMessage.text = text ?? ""
            protoChatMessage.media = media.compactMap { $0.protoMessage }
        case .text(let text):
            protoChatMessage.text = text
        case .unsupported(_):
            return nil
        }

        if let feedPostID = context.feedPostID, !feedPostID.isEmpty {
            protoChatMessage.feedPostID = feedPostID
            protoChatMessage.feedPostMediaIndex = context.feedPostMediaIndex
        }

        if let replyMessageID = context.chatReplyMessageID, !replyMessageID.isEmpty, let replySenderID = context.chatReplyMessageSenderID, !replySenderID.isEmpty {
            protoChatMessage.chatReplyMessageID = replyMessageID
            protoChatMessage.chatReplyMessageSenderID = replySenderID
            protoChatMessage.chatReplyMessageMediaIndex = context.chatReplyMessageMediaIndex
        }

        return protoChatMessage
    }
}

public protocol ChatMediaProtocol {
    var url: URL? { get }
    var mediaType: ChatMessageMediaType { get }
    var size: CGSize { get }
    var key: String { get }
    var sha256: String { get }
}

public extension ChatMediaProtocol {
    var protoMessage: Clients_Media? {
        get {
            guard let url = url else {
                DDLogError("ChatMediaProtocol/protoMessage/error missing url!")
                return nil
            }
            var media = Clients_Media()
            media.type = {
                switch mediaType {
                case .image: return .image
                case .video: return .video
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
        switch mediaType {
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
        }
        return albumMedia
    }
}

public struct ChatMessageTombstone {
    public init(id: String, from: UserID, to: UserID, timestamp: Date) {
        self.id = id
        self.from = from
        self.to = to
        self.timestamp = timestamp
    }

    public var id: String
    public var from: UserID
    public var to: UserID
    public var timestamp: Date
}

extension Clients_ChatMessage {
    public init?(containerData: Data) {
        if let protoContainer = try? Clients_Container(serializedData: containerData),
            protoContainer.hasChatMessage
        {
            // Binary protocol
            self = protoContainer.chatMessage
        } else if let decodedData = Data(base64Encoded: containerData, options: .ignoreUnknownCharacters),
            let protoContainer = try? Clients_Container(serializedData: decodedData),
            protoContainer.hasChatMessage
        {
            // Legacy Base64 protocol
            self = protoContainer.chatMessage
        } else {
            return nil
        }
    }

    public var chatContext: ChatContext {
        return ChatContext(
            feedPostID: feedPostID.isEmpty ? nil : feedPostID,
            feedPostMediaIndex: feedPostMediaIndex,
            chatReplyMessageID: chatReplyMessageID.isEmpty ? nil : chatReplyMessageID,
            chatReplyMessageMediaIndex: chatReplyMessageMediaIndex,
            chatReplyMessageSenderID: chatReplyMessageSenderID.isEmpty ? nil : chatReplyMessageSenderID)
    }

    public var chatContent: ChatContent {
        if media.isEmpty {
            return .text(text)
        } else {
            return .album(
                text.isEmpty ? nil : text,
                media.compactMap { XMPPChatMedia(protoMedia: $0) })
        }
    }
}

extension Clients_Text {
    init(text: String) {
        self.init()
        self.text = text
    }
}

extension Clients_ChatContainer {
    public init?(containerData: Data) {
        guard let protoContainer = try? Clients_Container(serializedData: containerData),
              protoContainer.hasChatContainer else
        {
            return nil
        }
        self = protoContainer.chatContainer
    }

    public var chatContext: ChatContext {
        return ChatContext(
            feedPostID: context.feedPostID.isEmpty ? nil : context.feedPostID,
            feedPostMediaIndex: context.feedPostMediaIndex,
            chatReplyMessageID: context.chatReplyMessageID.isEmpty ? nil : context.chatReplyMessageID,
            chatReplyMessageMediaIndex: context.chatReplyMessageMediaIndex,
            chatReplyMessageSenderID: context.chatReplyMessageSenderID.isEmpty ? nil : context.chatReplyMessageSenderID)
    }

    public var chatContent: ChatContent {
        switch message {
        case .text(let clientText):
            return .text(clientText.text)
        case .album(let album):
            return .album(
                album.text.text.isEmpty ? nil : album.text.text,
                album.media.compactMap {  XMPPChatMedia(albumMedia: $0) })
        case .contactCard, .voiceNote, .none:
            let data = try? serializedData()
            return .unsupported(data ?? Data())
        }
    }
}

public struct XMPPChatMedia {
    public var url: URL?
    public var type: ChatMessageMediaType
    public var size: CGSize
    public var key: String
    public var sha256: String

    public init(url: URL? = nil, type: ChatMessageMediaType, size: CGSize, key: String, sha256: String) {
        self.url = url
        self.type = type
        self.size = size
        self.key = key
        self.sha256 = sha256
    }

    public init?(protoMedia: Clients_Media) {
        guard let type = ChatMessageMediaType(clientsMediaType: protoMedia.type) else { return nil }
        guard let url = URL(string: protoMedia.downloadURL) else { return nil }
        let width = CGFloat(protoMedia.width), height = CGFloat(protoMedia.height)
        guard width > 0 && height > 0 else { return nil }

        self.url = url
        self.type = type
        self.size = CGSize(width: width, height: height)
        self.key = protoMedia.encryptionKey.base64EncodedString()
        self.sha256 = protoMedia.ciphertextHash.base64EncodedString()
    }

    public init?(albumMedia: Clients_AlbumMedia) {
        guard let media = albumMedia.media else { return nil }

        switch media {
        case .image(let image):
            guard let downloadURL = URL(string: image.img.downloadURL) else { return nil }
            let width = CGFloat(image.width), height = CGFloat(image.height)
            guard width > 0 && height > 0 else { return nil }

            type = .image
            url = downloadURL
            size = CGSize(width: width, height: height)
            key = image.img.encryptionKey.base64EncodedString()
            sha256 = image.img.ciphertextHash.base64EncodedString()
        case .video(let video):
            guard let downloadURL = URL(string: video.video.downloadURL) else { return nil }
            let width = CGFloat(video.width), height = CGFloat(video.height)
            guard width > 0 && height > 0 else { return nil }

            type = .video
            url = downloadURL
            size = CGSize(width: width, height: height)
            key = video.video.encryptionKey.base64EncodedString()
            sha256 = video.video.ciphertextHash.base64EncodedString()
        }
    }
}

extension XMPPChatMedia: ChatMediaProtocol {
    public var mediaType: ChatMessageMediaType {
        type
    }
}

public extension ChatMessageMediaType {
    init?(clientsMediaType: Clients_MediaType) {
        switch clientsMediaType {
        case .image:
            self = .image
        case .video:
            self = .video
        case .audio, .unspecified, .UNRECOGNIZED:
            return nil
        }
    }
}
