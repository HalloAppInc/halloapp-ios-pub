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

public enum ChatMessageMediaType: Int {
    case image = 0
    case video = 1
}

public protocol ChatMessageProtocol {
    var id: String { get }
    var fromUserId: UserID { get }
    var toUserId: UserID { get }

    var text: String? { get }
    var orderedMedia: [ChatMediaProtocol] { get }
    var feedPostId: FeedPostID? { get }
    var feedPostMediaIndex: Int32 { get }

    var timeIntervalSince1970: TimeInterval? { get }
}

public extension ChatMessageProtocol {
    var protoContainer: Proto_Container {
        get {
            var protoChatMessage = Proto_ChatMessage()
            if let text = text {
                protoChatMessage.text = text
            }

            if let feedPostId = feedPostId {
                protoChatMessage.feedPostID = feedPostId
                protoChatMessage.feedPostMediaIndex = feedPostMediaIndex
            }

            protoChatMessage.media = orderedMedia.map { $0.protoMessage }

            var protoContainer = Proto_Container()
            protoContainer.chatMessage = protoChatMessage
            return protoContainer
        }
    }
}

public extension ChatMessageProtocol {
    var xmppElement: XMPPElement {
        let message = XMPPElement(name: "message")
        message.addAttribute(withName: "id", stringValue: id)
        message.addAttribute(withName: "to", stringValue: "\(toUserId)@s.halloapp.net")
        message.addChild({
            let chat = XMPPElement(name: "chat")
            chat.addAttribute(withName: "xmlns", stringValue: "halloapp:chat:messages")
            if let protobufData = try? self.protoContainer.serializedData() {
                chat.addChild(XMPPElement(name: "s1", stringValue: protobufData.base64EncodedString()))
            }
            return chat
        }())
        return message
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
    var protoMessage: Proto_Media {
        get {
            var media = Proto_Media()
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
            media.downloadURL = url!.absoluteString
            return media
        }
    }
}
