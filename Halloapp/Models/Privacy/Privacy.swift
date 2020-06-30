//
//  Privacy.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import Foundation
import XMPPFramework

class PrivacyListItem {

    /**
     Raw value can be used as a value for `type` attribute on `privacy_list`.
     */
    enum State: String {
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

    @Published private(set) var mutedSetting: String = settingLoading

    private(set) var muted: PrivacyList? = nil {
        didSet {
            reloadMuteSettingValue()
        }
    }

    private func reloadMuteSettingValue() {
        if let list = muted {
            mutedSetting = settingValueText(forListItems: list.items)
        } else {
            mutedSetting = Self.settingLoading
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

    func syncListsIfNecessary() {
        // Fetch lists from the server.
        if !isLoaded {
            let request = XMPPGetPrivacyListsRequest{ (lists, activeType, error) in
                if lists != nil {
                    self.process(lists: lists!, activeType: activeType!)
                } else {
                    self.reset()
                }
            }
            MainAppContext.shared.xmppController.enqueue(request: request)

            return
        }
    }

    private func upload(privacyList: PrivacyList) {
        isSyncing = true

        let previousFeedSetting = activeType!

        let request = XMPPSendPrivacyListRequest(privacyList: privacyList) { (error) in
            if error == nil {
                privacyList.commitChanges()

                if privacyList.canBeSetAsActiveList {
                    self.activeType = privacyList.type
                }
            } else {
                privacyList.revertChanges()

                if privacyList.canBeSetAsActiveList {
                    self.activeType = previousFeedSetting
                }

                self.updateSettingValue(forPrivacyList: privacyList)
            }
            self.isSyncing = false
        }
        MainAppContext.shared.xmppController.enqueue(request: request)
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
        }

        // Blocked
        if let blocked = lists.first(where: { $0.type == .blocked }) {
            self.blocked = blocked
        }

        isLoaded = true
    }

    func update<T>(privacyList: PrivacyList, with userIds: T) where T: Collection, T.Element == UserID {
        privacyList.update(with: userIds)

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
        muted = nil
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
