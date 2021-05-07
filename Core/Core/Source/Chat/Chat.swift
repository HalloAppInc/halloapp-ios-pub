//
//  Chat.swift
//  Core
//
//  Created by Igor Solomennikov on 8/18/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjack
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

public enum ChatMessageMediaType: Int {
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
    
    var text: String? { get }
    var orderedMedia: [ChatMediaProtocol] { get }
    var feedPostId: FeedPostID? { get }
    var feedPostMediaIndex: Int32 { get }
    
    var chatReplyMessageID: String? { get }
    var chatReplyMessageSenderID: UserID? { get }
    var chatReplyMessageMediaIndex: Int32 { get }

    var timeIntervalSince1970: TimeInterval? { get }
}

public extension ChatMessageProtocol {
    var protoContainer: Clients_Container {
        get {
            var protoContainer = Clients_Container()
            protoContainer.chatMessage = clientChatLegacy
            return protoContainer
        }
    }

    /// Legacy format chat (will be superseded by Clients_ChatContainer)
    var clientChatLegacy: Clients_ChatMessage {
        var protoChatMessage = Clients_ChatMessage()
        if let text = text {
            protoChatMessage.text = text
        }

        if let feedPostId = feedPostId {
            protoChatMessage.feedPostID = feedPostId
            protoChatMessage.feedPostMediaIndex = feedPostMediaIndex
        }

        if let chatReplyMessageID = chatReplyMessageID, let chatReplyMessageSenderID = chatReplyMessageSenderID {
            protoChatMessage.chatReplyMessageID = chatReplyMessageID
            protoChatMessage.chatReplyMessageSenderID = chatReplyMessageSenderID
            protoChatMessage.chatReplyMessageMediaIndex = chatReplyMessageMediaIndex
        }

        protoChatMessage.media = orderedMedia.compactMap { $0.protoMessage }
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
    init?(containerData: Data) {
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
}
