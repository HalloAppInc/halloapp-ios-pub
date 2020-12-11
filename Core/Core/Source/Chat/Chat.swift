//
//  Chat.swift
//  Core
//
//  Created by Igor Solomennikov on 8/18/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation
import UIKit
import XMPPFramework

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

            var protoContainer = Clients_Container()
            protoContainer.chatMessage = protoChatMessage
            return protoContainer
        }
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
            media.plaintextHash = Data(base64Encoded: sha256)!
            media.downloadURL = url.absoluteString
            return media
        }
    }
}
