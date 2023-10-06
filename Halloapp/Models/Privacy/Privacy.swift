//
//  Privacy.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon

private extension Localizations {
    static var privacySyncFailure: String {
        NSLocalizedString("privacy.sync.failure", value: "Failed to sync privacy settings. Please try again later.", comment: "Error banner displayed when there is a failure syncing preivacy settings, displayed on the privacy view")
    }
}

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
                if type == .blocked {
                    MainAppContext.shared.chatData.recordNewChatEvent(userID: item.userId, type: .unblocked)
                }
                itemIndexesToDelete.update(with: itemIndex)

            case .added:
                if type == .blocked {
                    MainAppContext.shared.chatData.recordNewChatEvent(userID: item.userId, type: .blocked)
                }
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
            return NSLocalizedString("feed.privacy.list.all", value: "My Contacts", comment: "Settings > Privacy > Posts: one of the possible setting values.")
        case .blacklist:
            return NSLocalizedString("feed.privacy.list.except", value: "My Contacts Except...", comment: "Settings > Privacy > Posts: one of the possible setting values.")
        case .whitelist:
            return NSLocalizedString("feed.privacy.list.only", value: "Favorites", comment: "Settings > Privacy > Posts > Favorites privacy setting.")
        case .muted:
            return "Muted" // not in use currently
        case .blocked:
            return NSLocalizedString("privacy.list.blocked", value: "Blocked", comment: "Settings > Privacy: Title for the list of blocked contact and also setting menu item.")
        }
    }

    static func title(forPrivacyListType privacyListType: PrivacyListType) -> String? {
        switch privacyListType {
        case .all:
            return name(forPrivacyListType: privacyListType)
        case .blacklist:
            return NSLocalizedString("feed.privacy.list.except.title", value: "Hide Posts From...", comment: "Title for the list when selecting contacts to not share with.")
        case .whitelist:
            return name(forPrivacyListType: privacyListType)
        case .muted:
            return name(forPrivacyListType: privacyListType)
        case .blocked:
            return name(forPrivacyListType: privacyListType)
        }
    }

    static func details(forPrivacyListType privacyListType: PrivacyListType) -> String? {
        switch privacyListType {
        case .all:
            return NSLocalizedString("feed.privacy.list.all.details", value: "My HalloApp Contacts", comment: "Header for the list of all contacts on HallAapp.")
        case .blacklist:
            return NSLocalizedString("feed.privacy.list.except.details", value: "Select who won't see this post", comment: "Header for the list when selecting contacts to not share with.")
        case .whitelist:
            return Localizations.favoritesTitleAlt
        case .muted:
            return nil
        case .blocked:
            return nil
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

    let privacyListDidChange = PassthroughSubject<PrivacyListType, Never>()

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
    let feedPrivacySettingDidChange = PassthroughSubject<Void, Never>()
    
    override var activeType: PrivacyListType? {
        didSet {
            reloadFeedSettingValue()
            reloadPostComposerSubtitle()
            feedPrivacySettingDidChange.send()
        }
    }

    private func reloadFeedSettingValue() {
        guard let activeType = activeType else {
            shortFeedSetting = Constants.SettingLoading
            return
        }
        switch activeType {
        case .all:
            shortFeedSetting = NSLocalizedString("feed.privacy.value.my.contacts", value: "My Contacts", comment: "Possible Feed Privacy setting value.")
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

        downloadLists(listTypes: listTypes)
    }

    private func downloadLists(listTypes: [PrivacyListType]) {
        DDLogInfo("privacy/download-lists")
        service.getPrivacyLists(listTypes) { result in
            switch result {
            case .success(let (lists, activeType)):
                DDLogInfo("privacy/download-lists/complete \(lists.count) lists")
                self.process(lists: lists, activeType: activeType)

            case .failure(let error):
                DDLogError("privacy/download-lists/error \(error)")
                self.privacyListSyncError = Localizations.privacySyncFailure
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

    private func upload(privacyList: PrivacyList, retryOnFailure: Bool = true, setActiveType: Bool = true) {
        numberOfPendingRequests += 1
        privacyListSyncError = nil

        DDLogInfo("privacy/upload-list/\(privacyList.type)")

        let previousSetting = activeType!
        service.updatePrivacyList(privacyList) { result in
            switch result {
            case .success:
                DDLogInfo("privacy/upload-list/\(privacyList.type)/complete")

                privacyList.commitChanges()
                if privacyList.canBeSetAsFeedAudience, setActiveType {
                    self.activeType = privacyList.type
                }

            case .failure(let error):
                DDLogError("privacy/upload-list/\(privacyList.type)/error \(error)")

                var resync: Bool = false
                // upon server error to upload lists - resync that specific list and update the list on the server.
                if retryOnFailure == true {
                    switch error {
                    case .serverError(let reason):
                        DDLogInfo("privacy/retry sync for privacy list type: \(privacyList.type)")
                        if reason == "hash_mismatch" {
                            self.handleFailure(privacyList: privacyList)
                            resync = true
                        }
                    default:
                        resync = false
                    }
                }
                if !resync {
                    self.activeType = previousSetting
                    self.privacyListSyncError = Localizations.privacySyncFailure
                }
            }
            self.numberOfPendingRequests -= 1
        }
    }

    // currently, server allows clients to sync only one privacy list at a time.
    // this function handles failures received when we try to sync a specific privacy list with the server.
    private func handleFailure(privacyList: PrivacyList) {
        let privacyListType = privacyList.type
        service.getPrivacyLists([privacyListType]) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let (lists, _)):
                DDLogInfo("privacy/download-lists/complete \(lists.count) lists, type: \(privacyListType)")
                let currentUserIds = privacyList.userIds
                if let serverList = lists.first(where: { $0.type == privacyListType }) {
                    privacyList.set(userIds: serverList.userIds)
                    self.replaceUserIDs(in: privacyList, with: currentUserIds, retryOnFailure: false)
                }
            case .failure(let error):
                DDLogError("privacy/download-lists/error \(error)")
            }
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

    // TODO: Improve this API to clarify that the new list will be synced
    func replaceUserIDs<T>(in privacyList: PrivacyList, with userIds: T, retryOnFailure: Bool = true, setActiveType: Bool = true) where T: Collection, T.Element == UserID {
        DDLogInfo("privacy/update-list/\(privacyList.type)\nOld: \(privacyList.items.map({ $0.userId }))\nNew: \(userIds)")

        privacyList.update(with: userIds)

        if privacyList.state == .needsUpstreamSync || privacyList.canBeSetAsFeedAudience {
            updateSettingValue(forPrivacyList: privacyList)
            upload(privacyList: privacyList, retryOnFailure: retryOnFailure, setActiveType: setActiveType)
        }

        privacyListDidChange.send(privacyList.type)
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

                replaceUserIDs(in: whitelist, with: whitelistUserIds)

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
        replaceUserIDs(in: blacklist, with: blacklistUserIds)
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
                self.privacyListSyncError = Localizations.privacySyncFailure
            }
            self.numberOfPendingRequests -= 1
        }
    }

    // MARK: Utility

    private static func settingValueText(forPrivacyList privacyList: PrivacyListProtocol) -> String {
        let userCount = privacyList.userIds.count
        // "None" / "1 Contact" / "N Contacts"
        let formatString = Localizations.userCountFormat
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
    
    /// Adds `userID` to blocked.
    ///
    /// This method will remove `userID` from `whitelist` if it is contained there.
    public func block(userID: UserID) {
        guard
            let blockedList = blocked,
            userID != MainAppContext.shared.userData.userId
        else {
            return
        }
        
        replaceUserIDs(in: blockedList, with: blockedList.userIds + [userID])
        removeFavorite(userID)

        MainAppContext.shared.didPrivacySettingChange.send(userID)
    }
    
    /// Removes `userID` from `blocked`.
    public func unblock(userID: UserID) {
        guard let blockedList = blocked else {
            return
        }

        var newBlockedList = blockedList.userIds
        newBlockedList.removeAll { $0 == userID }
        if newBlockedList.count == blockedList.userIds.count {
            return
        }

        replaceUserIDs(in: blockedList, with: newBlockedList)
        MainAppContext.shared.didPrivacySettingChange.send(userID)
    }

    /// - Returns: `true` if `userID` is contained in `blocked`.
    public func isBlocked(_ userID: UserID) -> Bool {
        blocked?.userIds.contains(userID) ?? false
    }

    /// Adds `userID` to `whitelist`.
    public func addFavorite(_ userID: UserID) {
        guard let whitelist = whitelist else {
            return
        }

        replaceUserIDs(in: whitelist, with: whitelist.userIds + [userID])
    }

    /// Removes `userID` from `whitelist`.
    public func removeFavorite(_ userID: UserID) {
        guard let whitelist = whitelist else {
            return
        }

        var newWhitelist = whitelist.userIds
        newWhitelist.removeAll { $0 == userID }
        if newWhitelist.count == whitelist.userIds.count {
            return
        }

        replaceUserIDs(in: whitelist, with: newWhitelist)
    }

    /// - Returns: `true` if the `userID` is contained in `whitelist`.
    public func isFavorite(_ userID: UserID) -> Bool {
        whitelist?.userIds.contains(userID) ?? false
    }
}

// MARK: - subscribing to privacy list changes

extension PrivacySettings {
    /// Use this to keep track of a user's favorite status as privacy lists change.
    /// Publishes `true` if the user is a favorite.
    func favoriteStatus(for userID: UserID) -> AnyPublisher<Bool, Never> {
        let didChangePublisher = privacyListDidChange
            .filter { $0 == .whitelist }
            .map { [whitelist] _ in
                whitelist?.userIds.contains(userID) ?? false
            }

        return Just(isFavorite(userID)).merge(with: didChangePublisher)
            .eraseToAnyPublisher()
    }
}
