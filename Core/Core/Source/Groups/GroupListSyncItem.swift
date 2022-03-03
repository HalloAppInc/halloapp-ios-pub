//
//  GroupListSyncItem.swift
//
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CocoaLumberjackSwift
import Foundation

// Simple way to share existing groups between app and extensions
public struct GroupListSyncItem: Codable {
    public var id: GroupID
    public var name: String
    public var users: [UserID]
    public var lastActivityTimestamp: Date?

    public init(id: GroupID, name: String, users: [UserID], lastActivityTimestamp: Date?) {
        self.id = id
        self.name = name
        self.users = users
        self.lastActivityTimestamp = lastActivityTimestamp
    }

    private static var fileUrl: URL {
        AppContext.sharedDirectoryURL.appendingPathComponent("group-list.json", isDirectory: false)
    }

    public static func load() -> [GroupListSyncItem] {
        guard let data = try? Data(contentsOf: fileUrl) else {
            DDLogWarn("group-list/load/error file does not exist.")
            return []
        }

        do {
            // file:///private/var/mobile/Containers/Shared/AppGroup/C5984765-4F4C-437C-92AC-468B65B4C264/group-list.json
            DDLogInfo("group-list/will be loaded from \(fileUrl.description)")
            return try JSONDecoder().decode([GroupListSyncItem].self, from: data)
        } catch {
            DDLogError("group-list/load/error \(error)")
            try? FileManager.default.removeItem(at: fileUrl)
            return []
        }
    }

    public static func save(_ items: [GroupListSyncItem]) {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileUrl)

            DDLogInfo("group-list/saved to \(fileUrl.description)")
        } catch {
            DDLogError("group-list/save/error \(error)")
        }
    }
}
