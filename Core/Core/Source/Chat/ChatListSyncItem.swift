//
//  ChatList.swift
//  Core
//
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

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

    private static var fileUrl: URL {
        AppContext.sharedDirectoryURL.appendingPathComponent("chat-list.json", isDirectory: false)
    }

    public static func load() -> [ChatListSyncItem] {
        guard let data = try? Data(contentsOf: fileUrl) else {
            DDLogWarn("chat-list/load/error file does not exist.")
            return []
        }

        do {
            // file:///private/var/mobile/Containers/Shared/AppGroup/C5984765-4F4C-437C-92AC-468B65B4C264/group-list.json
            DDLogInfo("chat-list/will be loaded from \(fileUrl.description)")
            return try JSONDecoder().decode([ChatListSyncItem].self, from: data)
        } catch {
            DDLogError("chat-list/load/error \(error)")
            try? FileManager.default.removeItem(at: fileUrl)
            return []
        }
    }

    public static func save(_ items: [ChatListSyncItem]) {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileUrl)

            DDLogInfo("chat-list/saved to \(fileUrl.description)")
        } catch {
            DDLogError("chat-list/save/error \(error)")
        }
    }
}
