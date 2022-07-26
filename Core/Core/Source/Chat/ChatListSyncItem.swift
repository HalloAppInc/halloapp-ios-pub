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

        let viewContext = AppContext.shared.contactStore.viewContext
        let abContacts = AppContext.shared.contactStore.allRegisteredContacts(sorted: false, in: viewContext)
        var contactsMap = [UserID: ABContact]()
        for contact in abContacts {
            guard let userID = contact.userId else {
                continue
            }
            contactsMap[userID] = contact
        }

        let pushNames = AppContext.shared.contactStore.pushNames

        let chatThreads = AppContext.shared.mainDataStore.chatThreads(in: AppContext.shared.mainDataStore.viewContext)
        var chatTimestamps: [UserID : Date] = [:]
        let chatListItems1 = chatThreads.compactMap { chatThread -> ChatListSyncItem? in
            guard let userID = chatThread.userID else {
                return nil
            }
            guard contactsMap[userID] == nil else {
                // These are included below as part of contacts.
                chatTimestamps[userID] = chatThread.lastTimestamp
                return nil
            }
            guard let pushName = pushNames[userID] else {
                return nil
            }
            return ChatListSyncItem(userId: userID, timestamp: chatThread.lastTimestamp, fullName: "", pushName: pushName, phoneNumber: "")
        }

        let chatListItems2 = AppContext.shared.contactStore.allRegisteredContacts(sorted: false, in: viewContext).compactMap { contact -> ChatListSyncItem? in
            guard let userID = contact.userId else {
                return nil
            }
            if (contact.fullName?.isEmpty ?? true) && (pushNames[userID]?.isEmpty ?? true) {
                return nil
            }
            return ChatListSyncItem(userId: userID, timestamp: chatTimestamps[userID], fullName: contact.fullName, pushName: pushNames[userID], phoneNumber: contact.phoneNumber)
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
