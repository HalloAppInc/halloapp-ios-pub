//
//  GroupList.swift
//
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Foundation

// Simple way to share existing groups between app and extensions
public struct GroupListItem: Codable {
    public var id: GroupID
    public var name: String
    public var users: [UserID]

    public init(id: GroupID, name: String, users: [UserID]) {
        self.id = id
        self.name = name
        self.users = users
    }

    private static var fileUrl: URL {
        AppContext.sharedDirectoryURL.appendingPathComponent("group-list.json", isDirectory: false)
    }

    public static func load() -> [GroupListItem] {
        guard let data = try? Data(contentsOf: fileUrl) else {
            DDLogWarn("group-list/load/error file does not exist.")
            return []
        }

        do {
            return try JSONDecoder().decode([GroupListItem].self, from: data)
        } catch {
            DDLogError("group-list/load/error \(error)")
            try? FileManager.default.removeItem(at: fileUrl)
            return []
        }
    }

    public static func save(_ items: [GroupListItem]) {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileUrl)

            DDLogInfo("group-list/saved to \(fileUrl.description)")
        } catch {
            DDLogError("group-list/save/error \(error)")
        }
    }
}
