//
//  Privacy.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core

public enum PrivacyListItemUpdateAction: String, RawRepresentable {
    case add
    case delete
}

public protocol PrivacyListUpdateProtocol {
    var type: PrivacyListType { get }
    var updates: [UserID: PrivacyListItemUpdateAction] { get }

    /// Hash of the final list with updates applied
    var resultHash: Data? { get }
}

extension PrivacyList: PrivacyListUpdateProtocol {
    public var updates: [UserID : PrivacyListItemUpdateAction] {
        Dictionary(uniqueKeysWithValues: items.compactMap { item in
            switch item.state {
            case .added: return (item.userId, .add)
            case .deleted: return (item.userId, .delete)
            case .active: return nil
            }
        })
    }
    public var resultHash: Data? {
        hash
    }
}

final class PrivacyListAllContacts: PrivacyListUpdateProtocol {

    init() {}

    var type: PrivacyListType {
        .all
    }

    var updates: [UserID : PrivacyListItemUpdateAction] {
        [:]
    }

    var resultHash: Data? {
        nil
    }
}

extension PrivacyList {

    var canBeSetAsFeedAudience: Bool {
        get { type == .all || type == .blacklist || type == .whitelist }
    }

    func update<T>(with userIds: T) where T: Collection, T.Element == UserID {
        let previousUserIds = Set(items.map({ $0.userId }))
        let updatedUserIds = Set(userIds)

        // Deletes
        for item in items {
            if !updatedUserIds.contains(item.userId) {
                item.state = .deleted
                state = .needsUpstreamSync
            }
        }

        // Insertions
        let newItems = updatedUserIds.subtracting(previousUserIds).map({ PrivacyListItem(userId: $0, state: .added) })
        if !newItems.isEmpty {
            items.append(contentsOf: newItems)
            state = .needsUpstreamSync
        }

        save()
    }

    func set(userIds: [UserID]) {
        items = userIds.map({ PrivacyListItem(userId: $0) })
        state = .inSync

        save()
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

        state = .inSync

        save()
    }

    private func save() {
        assert(state != .unknown)

        // Prepare directory.
        let directoryUrl = fileUrl.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryUrl, withIntermediateDirectories: true)

        do {
            let jsonData = try JSONEncoder().encode(self)
            try jsonData.write(to: fileUrl)
            DDLogInfo("privacy/list/\(type)/saved to \(fileUrl.path)")
        }
        catch {
            DDLogError("privacy/list/\(type)/write-error \(error)")
        }
    }

    // MARK: UI Support
    static func name(forPrivacyListType privacyListType: PrivacyListType) -> String {
        switch privacyListType {
        case .all:
            return NSLocalizedString("feed.privacy.list.all", value: "My Phone Contacts", comment: "Settings > Privacy > Posts: one of the possible setting values.")
        case .blacklist:
            return NSLocalizedString("feed.privacy.list.except", value: "My Contacts Except...", comment: "Settings > Privacy > Posts: one of the possible setting values.")
        case .whitelist:
            return NSLocalizedString("feed.privacy.list.only", value: "Only Share With...", comment: "Settings > Privacy > Posts: one of the possible setting values.")
        case .muted:
            return "Muted" // not in use currently
        case .blocked:
            return NSLocalizedString("privacy.list.blocked", value: "Blocked", comment: "Settings > Privacy: Title for the list of blocked contact and also setting menu item.")
        }
    }

}


class PrivacySettings: Core.PrivacySettings, ObservableObject {

    private struct Constants {
        static let SettingLoading = "..."
    }

    private let service: HalloService
    private var didConnectCancellable: AnyCancellable!

    init(contactStore: ContactStore, service: HalloService) {
        self.service = service
        super.init(contactStore: contactStore)
        didConnectCancellable = service.didConnect.sink { [weak self] in
            guard let self = self else { return }
            self.syncListsIfNecessary()
        }
    }

    override func loadSettings() {
        super.loadSettings()

        reloadFeedSettingValue()
        reloadMuteSettingValue()
        reloadBlockedSettingValue()

        validateState()
    }

    /**
     - returns:
     `true` if privacy settings have been loaded from the server and are ready to be displayed in the UI.
     */
    @Published private(set) var isDownloaded: Bool = false
    /**
     - returns:
     `true` if privacy list being uploaded or feed privacy setting is being updated on the server.
     */
    @Published private(set) var isSyncing: Bool = false
    private var numberOfPendingRequests = 0 {
        didSet {
            isSyncing = numberOfPendingRequests > 0
        }
    }

    @Published private(set) var privacyListSyncError: String? = nil

    func resetSyncError() {
        privacyListSyncError = nil
    }

    // MARK: Post Composer

    @Published private(set) var composerIndicator: String = Constants.SettingLoading

    private func reloadPostComposerSubtitle() {
        guard let activeType = activeType else {
            composerIndicator = Constants.SettingLoading
            return
        }
        switch activeType {
        case .all:
            composerIndicator = NSLocalizedString("composer.privacy.value.my.contacts", value: "Sharing with my contacts", comment: "Feed Privacy indicator in post composer.")

        case .whitelist:
            if whitelist.isLoaded {
                let userCount = whitelist.userIds.count
                let shortFormatString = NSLocalizedString("composer.privacy.value.n.selected", comment: "Feed Privacy indicator in post composer.")
                composerIndicator = String.localizedStringWithFormat(shortFormatString, userCount)
            } else {
                composerIndicator = Constants.SettingLoading
            }

        case .blacklist:
            composerIndicator = NSLocalizedString("composer.privacy.value.excluded", value: "Sharing with some of my contacts", comment: "Feed Privacy indicator in post composer.")

        default:
            assert(false, "Active list cannot be \(activeType)")
        }
    }

    // MARK: Feed

    @Published private(set) var shortFeedSetting: String = Constants.SettingLoading
    @Published private(set) var longFeedSetting: String = Constants.SettingLoading

    override var activeType: PrivacyListType? {
        didSet {
            reloadFeedSettingValue()
            reloadPostComposerSubtitle()
        }
    }

    private func reloadFeedSettingValue() {
        guard let activeType = activeType else {
            shortFeedSetting = Constants.SettingLoading
            return
        }
        switch activeType {
        case .all:
            shortFeedSetting = NSLocalizedString("feed.privacy.value.my.contacts", value: "My Phone Contacts", comment: "Possible Feed Privacy setting value.")
            longFeedSetting = shortFeedSetting

        case .whitelist:
            if whitelist.isLoaded {
                let userCount = whitelist.userIds.count
                // "\(userCount) Selected"
                let shortFormatString = NSLocalizedString("feed.privacy.value.n.selected", comment: "Possible Feed Privacy setting value. Keep short.")
                shortFeedSetting = String.localizedStringWithFormat(shortFormatString, userCount)
                // "\(userCount) Contacts Selected"
                let fullFormatString = NSLocalizedString("feed.privacy.value.n.contacts.selected", comment: "Possible Feed Privacy setting value. Can be longer.")
                longFeedSetting = String.localizedStringWithFormat(fullFormatString, userCount)
            } else {
                shortFeedSetting = Constants.SettingLoading
                longFeedSetting = shortFeedSetting
            }

        case .blacklist:
            if blacklist.isLoaded {
                let userCount = blacklist.userIds.count
                // "\(userCount) Excluded"
                let shortFormatString = NSLocalizedString("feed.privacy.value.n.excluded", comment: "Possible Feed Privacy setting value. Keep short.")
                shortFeedSetting = String.localizedStringWithFormat(shortFormatString, userCount)
                // "\(userCount) Contacts Excluded"
                let fullFormatString = NSLocalizedString("feed.privacy.value.n.contacts.excluded", comment: "Possible Feed Privacy setting value. Can be longer.")
                longFeedSetting = String.localizedStringWithFormat(fullFormatString, userCount)
            } else {
                shortFeedSetting = Constants.SettingLoading
                longFeedSetting = shortFeedSetting
            }

        default:
            assert(false, "Active list cannot be \(activeType)")
        }
    }

    // MARK: Muted

    @Published private(set) var mutedSetting: String = Constants.SettingLoading

    private func reloadMuteSettingValue() {
        if muted.isLoaded {
            mutedSetting = Self.settingValueText(forPrivacyList: muted)
        } else {
            mutedSetting = Constants.SettingLoading
        }
    }

    // MARK: Blocked

    @Published private(set) var blockedSetting: String = Constants.SettingLoading

    private func reloadBlockedSettingValue() {
        if blocked.isLoaded {
            blockedSetting = Self.settingValueText(forPrivacyList: blocked)
        } else {
            blockedSetting = Constants.SettingLoading
        }
    }

    // MARK: Loading & Resetting

    private func validateState() {
        guard activeType != nil else {
            isDownloaded = false
            return
        }

        guard whitelist.isLoaded && blacklist.isLoaded && muted.isLoaded && blocked.isLoaded else {
            isDownloaded = false
            return
        }
        isDownloaded = true
    }

    private func syncListsIfNecessary() {
        self.downloadListsIfNecessary()
        self.uploadListsIfNecessary()
    }

    private func downloadListsIfNecessary() {
        guard !isDownloaded else { return }

        privacyListSyncError = nil

        var listTypes = [PrivacyListType]()
        if whitelist.state == .needsDownstreamSync {
            listTypes.append(.whitelist)
        }
        if blacklist.state == .needsDownstreamSync {
            listTypes.append(.blacklist)
        }
        if muted.state == .needsDownstreamSync {
            listTypes.append(.muted)
        }
        if blocked.state == .needsDownstreamSync {
            listTypes.append(.blocked)
        }

        guard !listTypes.isEmpty || activeType == nil else {
            return
        }

        DDLogInfo("privacy/download-lists")
        service.getPrivacyLists(listTypes) { result in
            switch result {
            case .success(let (lists, activeType)):
                DDLogInfo("privacy/download-lists/complete \(lists.count) lists")
                self.process(lists: lists, activeType: activeType)

            case .failure(let error):
                DDLogError("privacy/download-lists/error \(error)")
                self.privacyListSyncError = "Failed to sync privacy settings. Please try again later."
            }
        }
    }

    private func uploadListsIfNecessary() {
        // Sending all | blacklist | whitelist sets them active on the server,
        // so only send if those lists are currently selected.
        if activeType == .whitelist && whitelist.state == .needsUpstreamSync {
            upload(privacyList: whitelist)
        } else if activeType == .blacklist && blacklist.state == .needsUpstreamSync {
            upload(privacyList: blacklist)
        }

        // Muted is sent to the server as a backup.
        if muted.state == .needsUpstreamSync {
            upload(privacyList: muted)
        }

        if blocked.state == .needsUpstreamSync {
            upload(privacyList: blocked)
        }
    }

    private func upload(privacyList: PrivacyList) {
        numberOfPendingRequests += 1
        privacyListSyncError = nil

        DDLogInfo("privacy/upload-list/\(privacyList.type)")

        let previousSetting = activeType!
        service.updatePrivacyList(privacyList) { result in
            switch result {
            case .success:
                DDLogInfo("privacy/upload-list/\(privacyList.type)/complete")

                privacyList.commitChanges()
                if privacyList.canBeSetAsFeedAudience {
                    self.activeType = privacyList.type
                }

            case .failure(let error):
                DDLogError("privacy/upload-list/\(privacyList.type)/error \(error)")

                self.activeType = previousSetting
                self.privacyListSyncError = "Failed to sync privacy settings. Please try again later."
            }
            self.numberOfPendingRequests -= 1
        }
    }

    private func process(lists: [PrivacyListProtocol], activeType: PrivacyListType) {
        // Feed
        if let serverList = lists.first(where: { $0.type == .whitelist }) {
            whitelist.set(userIds: serverList.userIds)
        }
        if let serverList = lists.first(where: { $0.type == .blacklist }) {
            blacklist.set(userIds: serverList.userIds)
        }
        self.activeType = activeType

        // Muted
        if let serverList = lists.first(where: { $0.type == .muted }) {
            muted.set(userIds: serverList.userIds)
            reloadMuteSettingValue()
        }

        // Blocked
        if let serverList = lists.first(where: { $0.type == .blocked }) {
            blocked.set(userIds: serverList.userIds)
            reloadBlockedSettingValue()
        }

        validateState()
    }

    func update<T>(privacyList: PrivacyList, with userIds: T) where T: Collection, T.Element == UserID {
        DDLogInfo("privacy/update-list/\(privacyList.type)\nOld: \(privacyList.items.map({ $0.userId }))\nNew: \(userIds)")

        privacyList.update(with: userIds)

        if privacyList.state == .needsUpstreamSync || privacyList.canBeSetAsFeedAudience {
            updateSettingValue(forPrivacyList: privacyList)
            upload(privacyList: privacyList)
        }
    }

    func hidePostsFrom(userId: UserID) {
        DDLogInfo("privacy/hide-from/\(userId)")

        // If "whitelist" is currently active and user is on the list:
        //    remove user from the "whitelist", add to "blacklist", but keep "whitelist" active.
        // Otherwise:
        //    add contact to the "blacklist" and set it active.

        var blacklistUserIds = Set(blacklist.userIds)

        if activeType == .whitelist {
            var whitelistUserIds = Set(whitelist.userIds)
            if whitelistUserIds.remove(userId) != nil {
                DDLogInfo("privacy/hide-from/\(userId) Removed contact from whitelist.")

                update(privacyList: whitelist, with: whitelistUserIds)

                // Also add userId to "blacklist" if user decides to choose that privacy setting later.
                if blacklistUserIds.insert(userId).inserted {
                    DDLogInfo("privacy/hide-from/\(userId) Added contact to blacklist without making blacklist active.")
                    blacklist.update(with: blacklistUserIds)
                }

                return
            }
        }

        if blacklistUserIds.insert(userId).inserted {
            DDLogInfo("privacy/hide-from/\(userId) Added contact to blacklist.")
        } else {
            DDLogInfo("privacy/hide-from/\(userId) Contact is already in blacklist.")
        }
        DDLogWarn("privacy/hide-from/\(userId) Setting blacklist active.")
        update(privacyList: blacklist, with: blacklistUserIds)
    }

    func setFeedSettingToAllContacts() {
        numberOfPendingRequests += 1
        privacyListSyncError = nil

        DDLogInfo("privacy/set-list/all")

        let previousSetting = activeType!
        service.updatePrivacyList(PrivacyListAllContacts()) { result in
            switch result {
            case .success:
                DDLogInfo("privacy/set-list/all/complete")
                self.activeType = .all

            case .failure(let error):
                DDLogError("privacy/set-list/all/error \(error)")

                self.activeType = previousSetting
                self.privacyListSyncError = "Failed to sync privacy settings. Please try again later."
            }
            self.numberOfPendingRequests -= 1
        }
    }

    // MARK: Utility

    private static func settingValueText(forPrivacyList privacyList: PrivacyListProtocol) -> String {
        let userCount = privacyList.userIds.count
        // "None" / "1 Contact" / "N Contacts"
        let formatString = NSLocalizedString("privacy.n.contacts", comment: "Generic setting value telling how many contacts are blocked or muted.")
        return String.localizedStringWithFormat(formatString, userCount)
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
