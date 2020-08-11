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

enum ChatMessageMediaType: Int {
    case image = 0
    case video = 1
}

struct XMPPChatMessage {
    let id: String
    let fromUserId: UserID
    let toUserId: UserID
    let text: String?
    let media: [XMPPChatMedia]
    let feedPostId: String?
    let feedPostMediaIndex: Int32
    var timestamp: TimeInterval?

    // init outgoing message
    init(toUserId: String, text: String?, media: [PendingMedia]?, feedPostId: String?, feedPostMediaIndex: Int32) {
        self.id = UUID().uuidString
        self.fromUserId = AppContext.shared.userData.userId
        self.toUserId = toUserId
        self.text = text
        if let media = media?.map({ XMPPChatMedia(chatMedia: $0) }) {
            self.media = media
        } else {
            self.media = []
        }
        self.feedPostId = feedPostId
        self.feedPostMediaIndex = feedPostMediaIndex
    }

    var xmppElement: XMPPElement {
        get {
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
    
    var protoContainer: Proto_Container {
        get {
            var protoChatMessage = Proto_ChatMessage()
            if self.text != nil {
                protoChatMessage.text = self.text!
            }
            
            if self.feedPostId != nil {
                protoChatMessage.feedPostID = self.feedPostId!
                protoChatMessage.feedPostMediaIndex = self.feedPostMediaIndex
            }
            
            if self.media.count > 0 {
                protoChatMessage.media = self.media.compactMap { med in
                    
                    var protoMedia = Proto_Media()
                    protoMedia.type = {
                        switch med.type {
                        case .image: return .image
                        case .video: return .video
                        }
                    }()
                    protoMedia.width = Int32(med.size.width)
                    protoMedia.height = Int32(med.size.height)
                    protoMedia.encryptionKey = Data(base64Encoded: med.key)!
                    protoMedia.plaintextHash = Data(base64Encoded: med.sha256)!
                    protoMedia.downloadURL = med.url.absoluteString
                    return protoMedia
                }
            }
            
            var protoContainer = Proto_Container()
            protoContainer.chatMessage = protoChatMessage
            
            return protoContainer
        }
    }
    
}

struct XMPPChatMedia: ChatMediaProtocol {

    let url: URL
    let type: ChatMessageMediaType
    let size: CGSize
    let key: String
    let sha256: String

    init(chatMedia: PendingMedia) {
        self.url = chatMedia.url!
        self.type = chatMedia.type == .image ? ChatMessageMediaType.image : ChatMessageMediaType.video
        self.size = chatMedia.size!
        self.key = chatMedia.key!
        self.sha256 = chatMedia.sha256!
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

protocol ChatMediaProtocol {
    var url: URL { get }
    var type: ChatMessageMediaType { get }
    var size: CGSize { get }
    var key: String { get }
    var sha256: String { get }
}

extension ChatMediaProtocol {
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
