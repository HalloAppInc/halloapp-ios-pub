//
//  XMPPChatMessage.swift
//  HalloApp
//
//  Created by Alan Luo on 8/3/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit

struct XMPPChatMessage {
    let id: String
    let fromUserId: UserID
    let toUserId: UserID
    var retryCount: Int32? = nil
    var rerequestCount: Int32
    let content: ChatContent
    let context: ChatContext
    var timestamp: TimeInterval?
}

extension XMPPChatMessage: ChatMessageProtocol {
    var orderedMedia: [ChatMediaProtocol] {
        switch content {
        case .album(_, let media):
            return media
        case .text, .unsupported:
            return []
        }
    }

    var timeIntervalSince1970: TimeInterval? {
        timestamp
    }
}

extension XMPPChatMedia {
    init(chatMedia: ChatMedia) {
        self.init(
            url: chatMedia.url,
            type: chatMedia.type == .image ? .image : .video,
            size: chatMedia.size,
            key: chatMedia.key,
            sha256: chatMedia.sha256)
    }
}
