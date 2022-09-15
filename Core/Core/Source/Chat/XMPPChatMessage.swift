//
//  XMPPChatMessage.swift
//  HalloApp
//
//  Created by Alan Luo on 8/3/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CoreCommon
import UIKit

public struct XMPPChatMessage {
    public let id: String
    public let fromUserId: UserID
    public let chatMessageRecipient: ChatMessageRecipient
    public var retryCount: Int32? = nil
    public var rerequestCount: Int32
    public let content: ChatContent
    public let context: ChatContext
    public var timestamp: TimeInterval?
}

extension XMPPChatMessage: ChatMessageProtocol {

    public var orderedMedia: [ChatMediaProtocol] {
        switch content {
        case .album(_, let media):
            return media
        case .voiceNote(let media):
            return [media]
        case .text, .reaction, .location, .unsupported:
            return []
        }
    }

    public var timeIntervalSince1970: TimeInterval? {
        timestamp
    }

    public var linkPreviewData: [LinkPreviewProtocol] {
        switch content {
        case .album, .reaction, .voiceNote, .location, .unsupported:
            return []
        case .text(_, let linkPreviewData):
            return linkPreviewData
        }
    }
}

extension XMPPChatMedia {
    public init(chatMedia: CommonMedia) {
        self.init(
            url: chatMedia.url,
            type: chatMedia.type,
            size: chatMedia.size,
            key: chatMedia.key,
            sha256: chatMedia.sha256,
            blobVersion: chatMedia.blobVersion,
            chunkSize: chatMedia.chunkSize,
            blobSize: chatMedia.blobSize)
    }
}

extension XMPPChatMessage {

    // for outbound message
    public init(chatMessage: ChatMessage) {
        self.id = chatMessage.id
        self.fromUserId = chatMessage.fromUserId
        self.chatMessageRecipient = chatMessage.chatMessageRecipient
        self.context = ChatContext(
            feedPostID: chatMessage.feedPostId,
            feedPostMediaIndex: chatMessage.feedPostMediaIndex,
            chatReplyMessageID: chatMessage.chatReplyMessageID,
            chatReplyMessageMediaIndex: chatMessage.chatReplyMessageMediaIndex,
            chatReplyMessageSenderID: chatMessage.chatReplyMessageSenderID,
            forwardCount: chatMessage.forwardCount)
        self.rerequestCount = Int32(chatMessage.resendAttempts)

        if let media = chatMessage.media, !media.isEmpty {
            if media.count == 1, let item = media.first, item.type == .audio {
                self.content = .voiceNote(XMPPChatMedia(chatMedia: item))
            } else {
                self.content = .album(
                    chatMessage.rawText,
                    media.sorted(by: { $0.order < $1.order }).map{ XMPPChatMedia(chatMedia: $0) })
            }
        } else if let commonLocation = chatMessage.location {
            self.content = .location(ChatLocation(commonLocation))
        } else {
            self.content = .text(chatMessage.rawText ?? "", chatMessage.linkPreviewData)
        }
    }

    public init(content: ChatContent, context: ChatContext, timestamp: Int64, from fromUserID: UserID, chatMessageRecipient: ChatMessageRecipient, id: String, retryCount: Int32, rerequestCount: Int32) {
        self.id = id
        self.fromUserId = fromUserID
        self.chatMessageRecipient = chatMessageRecipient
        self.timestamp = TimeInterval(timestamp)
        self.retryCount = retryCount
        self.rerequestCount = rerequestCount
        self.content = content
        self.context = context
    }
}
