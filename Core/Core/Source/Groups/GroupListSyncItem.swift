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
    public var type: GroupType
    public var lastActivityTimestamp: Date?

    public init(id: GroupID, type: GroupType, name: String, users: [UserID], lastActivityTimestamp: Date?) {
        self.id = id
        self.name = name
        self.users = users
        self.lastActivityTimestamp = lastActivityTimestamp
        self.type = type
    }

    public static func load() -> [GroupListSyncItem] {
        DDLogInfo("GroupListSyncItem/load/begin")
        // Do some cleanup
        cleanup()
        let groups = AppContext.shared.mainDataStore.groups(predicate: NSPredicate(format: "typeValue = %d || typeValue = %d", GroupType.groupFeed.rawValue, GroupType.groupChat.rawValue),
                                                            in: AppContext.shared.mainDataStore.viewContext)
        let groupListItems = groups.map { group -> GroupListSyncItem in
            let users = group.orderedMembers.map{ $0.userID }
            let thread = AppContext.shared.mainDataStore.groupThread(for: group.id, in: AppContext.shared.mainDataStore.viewContext)
            return GroupListSyncItem(id: group.id, type: group.type,name: group.name, users: users, lastActivityTimestamp: thread?.lastFeedTimestamp)
        }
        DDLogInfo("GroupListSyncItem/load/groupListItems: \(groupListItems.count)/done")
        return groupListItems
    }

    public static func cleanup() {
        let fileURL = AppContext.sharedDirectoryURL.appendingPathComponent("group-list.json", isDirectory: false)
        try? FileManager.default.removeItem(at: fileURL)
        DDLogInfo("GroupListSyncItem/cleanup/fileURL: \(fileURL)")
    }
}
