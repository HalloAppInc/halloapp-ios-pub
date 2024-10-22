//
//  XMPPReaction.swift
//  Core
//
//  Created by Vaishvi Patel on 7/25/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import UIKit

public struct XMPPReaction {
    public let id: String
    public let fromUserId: UserID
    public var chatMessageRecipient: ChatMessageRecipient
    public var retryCount: Int32? = nil
    public var rerequestCount: Int32
    public let content: ChatContent
    public let context: ChatContext
    public var timestamp: TimeInterval?
}

extension XMPPReaction: ChatMessageProtocol {
    
    public var orderedMedia: [ChatMediaProtocol] {
        return []
    }
    
    public var linkPreviewData: [LinkPreviewProtocol] {
        return []
    }


    public var timeIntervalSince1970: TimeInterval? {
        timestamp
    }
}

extension XMPPReaction {

    // for outbound message
    public init?(chatReaction reaction: CommonReaction) {
        guard let chatMessageRecipient = reaction.chatMessageRecipient else {
            return nil
        }
        self.id = reaction.id
        self.fromUserId = reaction.fromUserID
        self.chatMessageRecipient = chatMessageRecipient
        self.context = ChatContext(
            feedPostID: nil,
            feedPostMediaIndex: 0,
            chatReplyMessageID: reaction.message?.id,
            chatReplyMessageMediaIndex: 0,
            chatReplyMessageSenderID: reaction.message?.fromUserID)
        self.rerequestCount = Int32(reaction.resendAttempts)

        self.content = .reaction(reaction.emoji)
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
