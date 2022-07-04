//
//  Privacy.swift
//  Core
//
//  Created by Igor Solomennikov on 8/24/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CocoaLumberjackSwift
import Foundation
import CoreData

/**
 Raw values are used in xmpp requests and for persisting lists to disk.
 */
public enum PrivacyListType: String, Codable {
    case all = "all"
    case whitelist = "only"
    case blacklist = "except"
    case muted = "mute"
    case blocked = "block"
}

public enum AudienceType: String, Codable {
    case all = "all"
    case whitelist = "only"
    case blacklist = "except"
    case group = "group"
}


public protocol PrivacyListProtocol {

    var type: PrivacyListType { get }

    var userIds: [UserID] { get }

    var hash: Data? { get }
}

public extension PrivacyListProtocol {

    var hash: Data? {
        let string = userIds.sorted().map({ "," + $0 }).joined()
        return string.sha256()
    }
}


public struct FeedAudience {
    public let audienceType: AudienceType
    public let userIds: Set<UserID>

    public init(audienceType: AudienceType, userIds: Set<UserID>) {
        self.audienceType = audienceType
        self.userIds = userIds
    }
}

extension FeedAudience {
    public var homeSessionType: HomeSessionType {
        switch self.audienceType {
        case .all: return .all
        default: return .favorites
        }
    }
}


public final class PrivacyListItem: Codable {

    /**
     Raw value can be used as a value for `type` attribute on `privacy_list`.
     */
    public enum State: String, Codable {
        case active  = ""        // in sync with the server
        case added   = "add"     // added on the client, not synced with server
        case deleted = "delete"  // deleted on the client, not synced with server
    }

    public let userId: UserID
    public var state: State = .active

    public init(userId: UserID, state: State = .active) {
        self.userId = userId
        self.state = state
    }
}


public final class PrivacyList {

    public let type: PrivacyListType
    public private(set) var fileUrl: URL!

    public enum State: Int, Codable {
        case unknown = 0
        case inSync
        case needsDownstreamSync
        case needsUpstreamSync
    }
    public var state: State = .unknown
    public var isLoaded: Bool {
        state == .inSync || state == .needsUpstreamSync
    }

    public var items = [PrivacyListItem]()

    init(type: PrivacyListType, fileUrl: URL) {
        self.type = type
        self.fileUrl = fileUrl

        load()
    }

    private func load() {
        guard let jsonData = try? Data(contentsOf: fileUrl) else {
            DDLogError("privacy/list/\(type)/read-error File does not exist.")
            state = .needsDownstreamSync
            return
        }
        do {
            let list = try JSONDecoder().decode(PrivacyList.self, from: jsonData)
            state = list.state
            items = list.items
            DDLogInfo("privacy/list/\(type)/loaded \(items.count) contacts")
        }
        catch {
            DDLogError("privacy/list/\(type)/read-error \(error)")
            try? FileManager.default.removeItem(at: fileUrl)
            state = .needsDownstreamSync
        }
    }

}

extension PrivacyList: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case state
        case items
    }
}

extension PrivacyList: PrivacyListProtocol {
    public var userIds: [UserID] {
        items.filter({ $0.state != .deleted }).map({ $0.userId })
    }
}

enum PrivacySettingsError: Error {
    case currentSettingUnknown
    case currentListUnavailable
    case contactsNotReady
}


open class PrivacySettings {

    private let contactStore: ContactStore

    public private(set) var whitelist: PrivacyList!
    public private(set) var blacklist: PrivacyList!
    public private(set) var muted: PrivacyList!
    public private(set) var blocked: PrivacyList!

    public init(contactStore: ContactStore) {
        self.contactStore = contactStore
        loadSettings()
    }

    open func loadSettings() {
        let privacyListsDirectory = AppContext.sharedDirectoryURL.appendingPathComponent("Privacy", isDirectory: true)
        whitelist = PrivacyList(type: .whitelist, fileUrl: privacyListsDirectory.appendingPathComponent("list1.json", isDirectory: false))
        blacklist = PrivacyList(type: .blacklist, fileUrl: privacyListsDirectory.appendingPathComponent("list2.json", isDirectory: false))
        muted = PrivacyList(type: .muted, fileUrl: privacyListsDirectory.appendingPathComponent("list3.json", isDirectory: false))
        blocked = PrivacyList(type: .blocked, fileUrl: privacyListsDirectory.appendingPathComponent("list4.json", isDirectory: false))

        activeType = .all
    }

    open var activeType: PrivacyListType? = nil {
        didSet {
            DDLogInfo("privacy/change-active From [\(oldValue?.rawValue ?? "none")] to [\(activeType?.rawValue ?? "none")]")
        }
    }

    public func currentFeedAudience() throws -> FeedAudience {
        guard let selectedListType = activeType else { throw PrivacySettingsError.currentSettingUnknown }
        return try feedAudience(for: selectedListType)
    }

    public func feedAudience(for privacyListType: PrivacyListType) throws -> FeedAudience {
        guard let audienceType = AudienceType(rawValue: privacyListType.rawValue) else {
            throw PrivacySettingsError.currentSettingUnknown
        }
        if privacyListType == .whitelist {
            guard whitelist.isLoaded else { throw PrivacySettingsError.currentListUnavailable }
        }
        if privacyListType == .blacklist {
            guard blacklist.isLoaded else { throw PrivacySettingsError.currentListUnavailable }
        }

        var allContacts: Set<UserID> = []
        contactStore.performOnBackgroundContextAndWait { managedObjectContext in
            allContacts = Set(contactStore.allRegisteredContactIDs(in: managedObjectContext))
        }

        var results: Set<UserID>
        if privacyListType == .whitelist {
            results = allContacts.intersection(whitelist.userIds)
        } else if privacyListType == .blacklist {
            results = allContacts.subtracting(blacklist.userIds)
        } else {
            results = allContacts
        }
        if blocked.isLoaded {
            results.subtract(blocked.userIds)
        }

        return FeedAudience(audienceType: audienceType, userIds: results)
    }
}
