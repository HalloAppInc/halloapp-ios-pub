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
    public var fullName: String?
    public var pushName: String?
    public var phoneNumber: String?

    public var displayName: String {
        get {
            let name: String
            if fullName?.isEmpty ?? true {
                if pushName?.isEmpty ?? true {
                    // This should never happen
                    // since we filter out chatListSyncItems when pushName or fullName is empty.
                    name = phoneNumber ?? ""
                } else {
                    name = "~\(pushName ?? "")"
                }
            } else {
                name = fullName ?? ""
            }
            return name
        }
    }

    public init(userId: UserID, timestamp: Date?, fullName: String?, pushName: String?, phoneNumber: String?) {
        self.userId = userId
        self.timestamp = timestamp
        self.fullName = fullName
        self.pushName = pushName
        self.phoneNumber = phoneNumber
    }

    public static func load() -> [ChatListSyncItem] {
        DDLogInfo("ChatListSyncItem/load/begin")
        // Do some cleanup
        cleanup()

        let chatThreads = AppContext.shared.mainDataStore.chatThreads(in: AppContext.shared.mainDataStore.viewContext)
        let threadUserIDs = chatThreads.compactMap { $0.userID }
        let profiles = UserProfile.find(with: threadUserIDs, in: AppContext.shared.mainDataStore.viewContext)
            .reduce(into: [UserID: UserProfile]()) {
                $0[$1.id] = $1
            }

        var chatTimestamps: [UserID : Date] = [:]
        let chatListItems1 = chatThreads.compactMap { chatThread -> ChatListSyncItem? in
            guard let userID = chatThread.userID else {
                return nil
            }

            if let profile = profiles[userID], profile.friendshipStatus == .friends {
                // These are included below as part of contacts.
                chatTimestamps[userID] = chatThread.lastTimestamp
                return nil
            }

            guard let name = profiles[userID]?.name else {
                return nil
            }
            return ChatListSyncItem(userId: userID, timestamp: chatThread.lastTimestamp, fullName: "", pushName: name, phoneNumber: "")
        }

        let friends = profiles.values.filter { $0.friendshipStatus == .friends }
        let chatListItems2 = friends.compactMap { profile -> ChatListSyncItem? in
            if profile.name.isEmpty, profiles[profile.id]?.name.isEmpty ?? true {
                return nil
            }
            return ChatListSyncItem(userId: profile.id, timestamp: chatTimestamps[profile.id], fullName: profile.name, pushName: nil, phoneNumber: nil)
        }

        let allChatListItems = chatListItems1 + chatListItems2
        DDLogInfo("ChatListSyncItem/load/chatListItems: \(allChatListItems.count)/done")
        return allChatListItems
    }

    public static func cleanup() {
        let fileURL = AppContext.sharedDirectoryURL.appendingPathComponent("chat-list.json", isDirectory: false)
        try? FileManager.default.removeItem(at: fileURL)
        DDLogInfo("ChatListSyncItem/cleanup/fileURL: \(fileURL)")
    }
}
