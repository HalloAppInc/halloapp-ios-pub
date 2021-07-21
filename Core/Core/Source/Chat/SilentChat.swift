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
    public var content = ChatContent.text(Self.text)
    public var context = ChatContext()
    public var timeIntervalSince1970: TimeInterval?

    public var rerequestCount: Int32

    init(from fromUserID: UserID, to toUserID: UserID, ts: TimeInterval = Date().timeIntervalSince1970, resendAttempts: Int32 = 0) {
        self.fromUserId = fromUserID
        self.toUserId = toUserID
        self.timeIntervalSince1970 = ts
        self.rerequestCount = resendAttempts

        self.id = [Self.text, fromUserID, toUserID, String(ts)].joined(separator: ":")
    }

    public static func isSilentChatID(_ id: String) -> Bool {
        return fromID(id) != nil
    }

    /// Use the ID to regenerate messages for incoming rerequests so we don't have to store them
    public static func fromID(_ incomingID: String) -> SilentChatMessage? {
        let components = incomingID.split(separator: ":")
        guard components.count == 4,
              components[0] == Self.text,
              let ts = TimeInterval(components[3]) else
        {
            return nil
        }

        return SilentChatMessage(
            from: UserID(components[1]),
            to: UserID(components[2]),
            ts: ts)
    }
}
