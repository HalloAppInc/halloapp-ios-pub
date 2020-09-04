//
//  XMPPChatMessage.swift
//  HalloApp
//
//  Created by Alan Luo on 8/3/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit
import XMPPFramework


struct XMPPChatMessage {
    let id: String
    let fromUserId: UserID
    let toUserId: UserID
    let text: String?
    let media: [XMPPChatMedia]
    let feedPostId: String?
    let feedPostMediaIndex: Int32
    var timestamp: TimeInterval?
}

extension XMPPChatMessage: ChatMessageProtocol {
    var orderedMedia: [ChatMediaProtocol] {
        media
    }

    var timeIntervalSince1970: TimeInterval? {
        timestamp
    }
}

struct XMPPChatMedia {
    let url: URL?
    let type: ChatMessageMediaType
    let size: CGSize
    let key: String
    let sha256: String

    init(chatMedia: ChatMedia) {
        self.url = chatMedia.url
        self.type = chatMedia.type == .image ? ChatMessageMediaType.image : ChatMessageMediaType.video
        self.size = chatMedia.size
        self.key = chatMedia.key
        self.sha256 = chatMedia.sha256
    }
    
    init?(urlElement: XMLElement) {
        guard let typeStr = urlElement.attributeStringValue(forName: "type") else { return nil }
        guard let type: ChatMessageMediaType = {
            switch typeStr {
            case "image": return .image
            case "video": return .video
            default: return nil
            }}() else { return nil }
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
        guard let type: ChatMessageMediaType = {
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
}

extension XMPPChatMedia: ChatMediaProtocol {
    var mediaType: ChatMessageMediaType {
        type
    }
}

extension Proto_Container {
    static func chatMessageContainer(from entry: XMLElement) -> Proto_Container? {
        guard let s1 = entry.element(forName: "s1")?.stringValue else { return nil }
        guard let data = Data(base64Encoded: s1, options: .ignoreUnknownCharacters) else { return nil }
        do {
            let protoContainer = try Proto_Container(serializedData: data)
            if protoContainer.hasChatMessage {
                return protoContainer
            }
        }
        catch {
            DDLogError("xmpp/chatmessage/invalid-protobuf")
        }
        return nil
    }
}
