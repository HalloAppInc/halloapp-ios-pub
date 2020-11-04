//
//  SilentChat.swift
//  Core
//
//  Created by Garrett on 10/28/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation

public struct SilentChatMessage: ChatMessageProtocol {

    static let text = "shhh"

    public var id: String
    public var fromUserId: UserID
    public var toUserId: UserID
    public var retryCount: Int32? = nil
    public var text: String?
    public var orderedMedia: [ChatMediaProtocol] = []
    public var feedPostId: FeedPostID? = nil
    public var feedPostMediaIndex: Int32 = 0
    public var chatReplyMessageID: String? = nil
    public var chatReplyMessageSenderID: UserID? = nil
    public var chatReplyMessageMediaIndex: Int32 = 0
    public var timeIntervalSince1970: TimeInterval?

    public var resendAttempts: Int

    init(from fromUserID: UserID, to toUserID: UserID, ts: TimeInterval = Date().timeIntervalSince1970, resendAttempts: Int = 0) {
        self.fromUserId = fromUserID
        self.toUserId = toUserID
        self.text = Self.text
        self.timeIntervalSince1970 = ts
        self.resendAttempts = resendAttempts

        self.id = [Self.text, fromUserID, toUserID, String(ts), String(resendAttempts)].joined(separator: ":")
    }

    /// Use the ID to regenerate messages for incoming rerequests so we don't have to store them
    public static func forRerequest(incomingID: String) -> SilentChatMessage? {
        let components = incomingID.split(separator: ":")
        guard components.count == 5,
              components[0] == Self.text,
              let ts = TimeInterval(components[3]),
              let resends = Int(components[4]) else
        {
            return nil
        }
        let message = SilentChatMessage(
            from: UserID(components[1]),
            to: UserID(components[2]),
            ts: ts,
            resendAttempts: resends + 1)
        return message
    }
}
