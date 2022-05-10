//
//  ChatList.swift
//  Core
//
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CocoaLumberjackSwift
import Foundation

// Simple way to share chats order according to last activity
public struct ChatListSyncItem: Codable {
    public var userId: UserID
    public var timestamp: Date?

    public init(userId: UserID, timestamp: Date?) {
        self.userId = userId
        self.timestamp = timestamp
    }

    public static func load() -> [ChatListSyncItem] {
        DDLogInfo("ChatListSyncItem/load/begin")
        // Do some cleanup
        cleanup()
        let chatThreads = AppContext.shared.mainDataStore.chatThreads(in: AppContext.shared.mainDataStore.viewContext)
        let chatListItems = chatThreads.compactMap { chatThread -> ChatListSyncItem? in
            guard let userID = chatThread.userID else {
                return nil
            }
            return ChatListSyncItem(userId: userID, timestamp: chatThread.lastMsgTimestamp)
        }
        DDLogInfo("ChatListSyncItem/load/chatListItems: \(chatListItems.count)/done")
        return chatListItems
    }

    public static func cleanup() {
        let fileURL = AppContext.sharedDirectoryURL.appendingPathComponent("chat-list.json", isDirectory: false)
        try? FileManager.default.removeItem(at: fileURL)
        DDLogInfo("ChatListSyncItem/cleanup/fileURL: \(fileURL)")
    }
}
