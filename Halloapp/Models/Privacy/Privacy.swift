//
//  Privacy.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import Core
import Foundation
import XMPPFramework

class PrivacyListItem: Codable {

    /**
     Raw value can be used as a value for `type` attribute on `privacy_list`.
     */
    enum State: String, Codable {
        case active  = ""        // in sync with the server
        case added   = "add"     // added on the client, not synced with server
        case deleted = "delete"  // deleted on the client, not synced with server
    }

    let userId: UserID
    var state: State = .active

    init(userId: UserID, state: State = .active) {
        self.userId = userId
        self.state = state
    }
}

/**
 Raw value can be used as a value for `type` attribute on `privacy_list`.
 */
enum PrivacyListType: String {
    case all       = "all"
    case whitelist = "only"
    case blacklist = "except"
    case muted     = "mute"
    case blocked   = "block"
}

class PrivacyList {

    let type: PrivacyListType

    private(set) var items: [PrivacyListItem] = []

    private(set) var hasChanges = false

    var canBeSetAsActiveList: Bool {
        get { type == .all || type == .blacklist || type == .whitelist }
    }

    init(type: PrivacyListType, items: [PrivacyListItem]) {
        self.type = type
        self.items = items
    }

    func update<T>(with userIds: T) where T: Collection, T.Element == UserID {
        let previousUserIds = Set(items.map({ $0.userId }))
        let updatedUserIds = Set(userIds)

        // Deletes
        for item in items {
            if !updatedUserIds.contains(item.userId) {
                item.state = .deleted
                hasChanges = true
            }
        }

        // Insertions
        let newItems = updatedUserIds.subtracting(previousUserIds).map({ PrivacyListItem(userId: $0, state: .added) })
        if !newItems.isEmpty {
            items.append(contentsOf: newItems)
            hasChanges = true
        }
    }

    func commitChanges() {
        var itemIndexesToDelete = IndexSet()
        for (itemIndex, item) in items.enumerated() {
            switch item.state {
            case .deleted:
                itemIndexesToDelete.update(with: itemIndex)

            case .added:
                item.state = .active

            default:
                break
            }
        }
        items.remove(atOffsets: itemIndexesToDelete)
        hasChanges = false
    }

    func revertChanges() {
        var itemIndexesToDelete = IndexSet()
        for (itemIndex, item) in items.enumerated() {
            switch item.state {
            case .added:
                itemIndexesToDelete.update(with: itemIndex)

            case .deleted:
                item.state = .active

            default:
                break
            }
        }
        items.remove(atOffsets: itemIndexesToDelete)
        hasChanges = false
    }

    static func name(forPrivacyListType privacyListType: PrivacyListType) -> String {
        switch privacyListType {
        case .all:
            return "My Contacts"
        case .blacklist:
            return "My Contacts Except..."
        case .whitelist:
            return "Only Share With..."
        case .muted:
            return "Muted"
        case .blocked:
            return "Blocked"
        }
    }
}

class PrivacySettings: ObservableObject {

    private let xmppController: XMPPControllerMain

    init(xmppController: XMPPControllerMain) {
        self.xmppController = xmppController

        loadMutedList()

        if mutedListState == .unknown {
            xmppController.execute(whenConnectionStateIs: .connected, onQueue: .main) {
                self.downloadListsIfNecessary()
            }
        } else if mutedListState == .needsUpload {
            xmppController.execute(whenConnectionStateIs: .connected, onQueue: .main) {
                self.upload(privacyList: self.muted!)
            }
        }
    }

    private static let settingLoading = "..."

    /**
     - returns:
     `true` if privacy settings have been loaded from the server and are ready to be displayed in the UI.
     */
    @Published private(set) var isLoaded: Bool = false
    /**
     - returns:
     `true` if privacy list being uploaded or feed privacy setting is being updated on the server.
     */
    @Published private(set) var isSyncing: Bool = false

    @Published private(set) var privacyListSyncError: String? = nil

    func resetSyncError() {
        privacyListSyncError = nil
    }

    // MARK: Feed

    @Published private(set) var shortFeedSetting: String = settingLoading
    @Published private(set) var longFeedSetting: String = settingLoading

    private(set) var whitelist: PrivacyList? = nil {
        didSet {
            if activeType == .whitelist {
                reloadFeedSettingValue()
            }
        }
    }

    private(set) var blacklist: PrivacyList? = nil {
        didSet {
            if activeType == .blacklist {
                reloadFeedSettingValue()
            }
        }
    }

    private(set) var activeType: PrivacyListType? = nil {
        didSet {
            DDLogInfo("privacy/change-active From [\(oldValue?.rawValue ?? "none")] to [\(activeType?.rawValue ?? "none")]")
            reloadFeedSettingValue()
        }
    }

    private func reloadFeedSettingValue() {
        guard let activeType = activeType else {
            shortFeedSetting = Self.settingLoading
            return
        }
        switch activeType {
        case .all:
            shortFeedSetting = "My Contacts"
            longFeedSetting = shortFeedSetting

        case .whitelist:
            if let whitelist = whitelist {
                let filteredList = whitelist.items.filter({ $0.state != .deleted })
                shortFeedSetting = "\(filteredList.count) Selected"
                longFeedSetting = "\(filteredList.count) Contacts Selected"
            } else {
                shortFeedSetting = Self.settingLoading
                longFeedSetting = shortFeedSetting
            }

        case .blacklist:
            if let blacklist = blacklist {
                let filteredList = blacklist.items.filter({ $0.state != .deleted })
                shortFeedSetting = "\(filteredList.count) Excluded"
                longFeedSetting = "\(filteredList.count) Contacts Excluded"
            } else {
                shortFeedSetting = Self.settingLoading
                longFeedSetting = shortFeedSetting
            }

        default:
            assert(false, "Active list cannot be \(activeType)")
        }
    }

    // MARK: Muted

    private enum MutedListState: Int {
        case unknown = 0     // needs to be queried from the server
        case inSync = 1      // saved locally, uploaded to the server
        case needsUpload = 2 // needs to be uploaded to the server
    }

    private var mutedListState: MutedListState {
        get {
            MutedListState(rawValue: UserDefaults.standard.integer(forKey: "PrivacyMutedListState")) ?? .unknown
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "PrivacyMutedListState")
        }
    }

    @Published private(set) var mutedSetting: String = settingLoading

    let mutedContactsChanged = PassthroughSubject<Void, Never>()

    var mutedContactIds: [UserID] {
        get {
            guard let muted = muted else {
                return []
            }
            return muted.items.filter({ $0.state != .deleted }).map({ $0.userId })
        }
    }

    private(set) var muted: PrivacyList? = nil {
        didSet {
            reloadMuteSettingValue()
            mutedContactsChanged.send()
        }
    }

    private func reloadMuteSettingValue() {
        if let list = muted {
            mutedSetting = settingValueText(forListItems: list.items)
        } else {
            mutedSetting = Self.settingLoading
        }
    }

    private let mutedListFileURL = MainAppContext.documentsDirectoryURL.appendingPathComponent("MutedList.json")

    private func loadMutedList() {
        guard let jsonData = try? Data(contentsOf: mutedListFileURL) else {
            DDLogError("privacy/muted-list/read-error File does not exist.")
            mutedListState = .unknown
            return
        }
        do {
            let listItems = try JSONDecoder().decode([PrivacyListItem].self, from: jsonData)
            self.muted = PrivacyList(type: .muted, items: listItems)
            DDLogInfo("privacy/muted-list/loaded \(listItems.count) contacts")
        }
        catch {
            DDLogError("privacy/muted-list/read-error \(error)")
            try? FileManager.default.removeItem(at: mutedListFileURL)
            mutedListState = .unknown
        }
    }

    private func writeMutedList() {
        guard let mutedList = muted else { return }
        do {
            let jsonData = try JSONEncoder().encode(mutedList.items)
            try jsonData.write(to: mutedListFileURL)
            DDLogInfo("privacy/muted-list/saved to \(mutedListFileURL.path)")
        }
        catch {
            DDLogError("privacy/muted-list/write-error \(error)")
        }
    }

    // MARK: Blocked

    @Published private(set) var blockedSetting: String = settingLoading

    private(set) var blocked: PrivacyList? = nil {
        didSet {
            reloadBlockedSettingValue()
        }
    }

    private func reloadBlockedSettingValue() {
        if let list = blocked {
            blockedSetting = settingValueText(forListItems: list.items)
        } else {
            blockedSetting = Self.settingLoading
        }
    }

    // MARK: Loading & Resetting

    func downloadListsIfNecessary() {
        guard !isLoaded else { return }

        DDLogInfo("privacy/download-lists")

        privacyListSyncError = nil

        let requestMutedList = mutedListState == .unknown
        let request = XMPPGetPrivacyListsRequest(includeMuted: requestMutedList) { (lists, activeType, error) in
            if error != nil {
                DDLogError("privacy/download-lists/error \(String(describing: error))")
                self.reset()

                self.privacyListSyncError = "Failed to sync privacy settings. Please try again later."
            } else {
                DDLogInfo("privacy/download-lists/complete \(lists!.count) lists")
                self.process(lists: lists!, activeType: activeType!)
            }
        }
        xmppController.enqueue(request: request)
    }

    private func upload(privacyList: PrivacyList) {
        isSyncing = true
        privacyListSyncError = nil

        DDLogInfo("privacy/upload-list/\(privacyList.type)")

        let previousFeedSetting = activeType!
        let request = XMPPSendPrivacyListRequest(privacyList: privacyList) { (error) in
            if error == nil {
                DDLogInfo("privacy/upload-list/\(privacyList.type)/complete")

                privacyList.commitChanges()

                if privacyList.type == .muted {
                    self.mutedListState = .inSync
                    self.writeMutedList()
                }

                if privacyList.canBeSetAsActiveList {
                    self.activeType = privacyList.type
                }
            } else {
                DDLogError("privacy/upload-list/\(privacyList.type)/error \(error!)")

                if privacyList.type == .muted {
                    // 'Muted' list uses server as a backup - just try re-uploading next time.
                } else {
                    privacyList.revertChanges()
                }

                if privacyList.canBeSetAsActiveList {
                    self.activeType = previousFeedSetting
                }

                self.updateSettingValue(forPrivacyList: privacyList)

                self.privacyListSyncError = "Failed to sync privacy settings. Please try again later."
            }
            self.isSyncing = false
        }
        xmppController.enqueue(request: request)
    }

    private func process(lists: [PrivacyList], activeType: PrivacyListType) {
        // Feed
        if let whitelist = lists.first(where: { $0.type == .whitelist }) {
            self.whitelist = whitelist
        }
        if let blacklist = lists.first(where: { $0.type == .blacklist }) {
            self.blacklist = blacklist
        }
        self.activeType = activeType

        // Muted
        if let muted = lists.first(where: { $0.type == .muted }) {
            self.muted = muted
            mutedListState = .inSync
            writeMutedList()
        }

        // Blocked
        if let blocked = lists.first(where: { $0.type == .blocked }) {
            self.blocked = blocked
        }

        isLoaded = true
    }

    func update<T>(privacyList: PrivacyList, with userIds: T) where T: Collection, T.Element == UserID {
        DDLogDebug("privacy/update-list/\(privacyList.type)\nOld: \(privacyList.items.map({ $0.userId }))\nNew: \(userIds)")

        privacyList.update(with: userIds)

        // 'Muted' list needs to be saved locally and then uploaded (as a backup).
        if privacyList.type == .muted && privacyList.hasChanges {
            mutedListState = .needsUpload
            writeMutedList()
            mutedContactsChanged.send()
        }

        if privacyList.hasChanges || privacyList.canBeSetAsActiveList {
            updateSettingValue(forPrivacyList: privacyList)
            upload(privacyList: privacyList)
        }
    }

    func setFeedSettingToAllContacts() {
        upload(privacyList: PrivacyList(type: .all, items: []))
    }

    private func reset() {
        activeType = nil
        whitelist = nil
        blacklist = nil
        blocked = nil

        isLoaded = false
    }

    // MARK: Utility

    private func settingValueText(forListItems listItems: [PrivacyListItem]) -> String {
        let filteredItems = listItems.filter({ $0.state != .deleted })
        if filteredItems.count > 1 {
            return "\(filteredItems.count) Contacts"
        } else if filteredItems.count > 0 {
            return "1 Contact"
        } else {
            return "None"
        }
    }

    private func updateSettingValue(forPrivacyList privacyList: PrivacyList) {
        switch privacyList.type {
        case .all, .whitelist, .blacklist:
            reloadFeedSettingValue()

        case .muted:
            reloadMuteSettingValue()

        case .blocked:
            reloadBlockedSettingValue()
        }
    }

}
