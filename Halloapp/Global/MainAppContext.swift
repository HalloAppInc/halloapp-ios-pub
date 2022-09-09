//
//  MainAppContext.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Contacts
import Core
import CoreCommon
import Foundation
import Intents

let userDefaultsKeyForMergeDataAttempts = "userDefaultsKeyForMergeDataAttempts"

class MainAppContext: AppContext {
    // MARK: Constants
    private static let feedDatabaseFilename = "feed.sqlite"
    private static let chatDatabaseFilename = "chat.sqlite"
    private static let cryptoStatsDatabaseFilenameLegacy = "cryptoStats.sqlite"
    private static let uploadDatabaseFilenameLegacy = "upload.sqlite"
    private static let userDefaultsAppVersion = "com.halloapp.app.version"

    // MARK: Global objects
    private(set) var feedData: FeedData!
    private(set) var chatData: ChatData!
    private(set) var syncManager: SyncManager!
    private(set) var callManager: CallManager!
    private(set) var privacySettingsImpl: PrivacySettings!
    private(set) var shareExtensionDataStore: ShareExtensionDataStore!
    private(set) var notificationServiceExtensionDataStore: NotificationServiceExtensionDataStore!
    lazy var webClientManager: WebClientManager? = {
        // TODO: Support logout
        guard let keys = userData.credentials?.noiseKeys else { return nil }
        let webStaticKey = Keychain.loadWebClientStaticKey(for: userData.userId)
        let manager = WebClientManager(service: service, dataStore: mainDataStore, noiseKeys: keys, webStaticKey: webStaticKey)
        manager.delegate = self
        return manager
    }()
    lazy var nux: NUX = { NUX(userDefaults: userDefaults) }()
    private lazy var mergeSharedDataQueue = { DispatchQueue(label: "com.halloapp.mergeSharedData", qos: .default) }()

    static let MediaUploadDataLastCleanUpTime = "MediaUploadDataLastCleanUpTime"

    let didTapNotification = PassthroughSubject<NotificationMetadata, Never>()
    let didTapIntent = CurrentValueSubject<INIntent?, Never>(nil)
    let activityViewControllerPresentRequest = PassthroughSubject<[Any], Never>()
    let groupFeedFromGroupTabPresentRequest = CurrentValueSubject<GroupID?, Never>(nil)
    let openChatThreadRequest = PassthroughSubject<UserID, Never>()
    let mediaDidStartPlaying = PassthroughSubject<URL?, Never>()
    let openPostInFeed = PassthroughSubject<FeedPostID, Never>()
    let migrationInProgress = CurrentValueSubject<Bool, Never>(false)

    let didPrivacySettingChange = PassthroughSubject<UserID, Never>()
    let mentionPasteboard = UIPasteboard.withUniqueName()
    
    var service: HalloService {
        coreService as! HalloService
    }

    override var contactStore: ContactStoreMain {
        get {
            super.contactStore as! ContactStoreMain
        }
    }

    override var privacySettings: PrivacySettings {
        get {
            privacySettingsImpl
        }
    }

    // MARK: Global App Properties

    override var isAppExtension: Bool {
        get { false }
    }

    override var applicationIconBadgeNumber: Int {
        didSet {
            UIApplication.shared.applicationIconBadgeNumber = applicationIconBadgeNumber
        }
    }

    // MARK: Paths

    static let feedStoreURLLegacy = {
        AppContext.documentsDirectoryURL.appendingPathComponent(feedDatabaseFilename)
    }()

    static let chatStoreURLLegacy = {
        AppContext.documentsDirectoryURL.appendingPathComponent(chatDatabaseFilename)
    }()

    static let cryptoStatsStoreURLLegacy = {
        AppContext.documentsDirectoryURL.appendingPathComponent(cryptoStatsDatabaseFilenameLegacy)
    }()

    static let uploadStoreURLLegacy = {
        AppContext.documentsDirectoryURL.appendingPathComponent(uploadDatabaseFilenameLegacy)
    }()
    
    func deleteDocumentsDirectory() {
        do {
            try FileManager.default.removeItem(at: AppContext.documentsDirectoryURL)
            DDLogInfo("MainAppContext/deleteDocumentsDirectory: Deleted documents data")
        } catch {
            DDLogError("MainAppContext/deleteDocumentsDirectory: Error deleting documents data: \(error)")
        }
    }
    
    func deleteLibraryDirectory() {
        do {
            try FileManager.default.removeItem(at: Self.libraryDirectoryURL)
            DDLogInfo("MainAppContext/deleteLibraryDirectory: Deleted library data")
        } catch {
            DDLogError("MainAppContext/deleteLibraryDirectory: Error deleting documents data: \(error)")
        }
    }
    
    // MARK: Initializer

    override class var shared: MainAppContext {
        get {
            return super.shared as! MainAppContext
        }
    }

    required init(serviceBuilder: ServiceBuilder, contactStoreClass: ContactStore.Type, appTarget: AppTarget) {
        super.init(serviceBuilder: serviceBuilder, contactStoreClass: contactStoreClass, appTarget: appTarget)
        
        feedData = FeedData(service: service, contactStore: contactStore, mainDataStore: mainDataStore, userData: userData, coreFeedData: coreFeedData, mediaUploader: mediaUploader)
        chatData = ChatData(service: service, contactStore: contactStore, mainDataStore: mainDataStore, userData: userData, coreChatData: coreChatData)
        syncManager = SyncManager(contactStore: contactStore, service: service, userData: userData)
        
        privacySettingsImpl = PrivacySettings(contactStore: contactStore, service: service)
        shareExtensionDataStore = ShareExtensionDataStore()
        notificationServiceExtensionDataStore = NotificationServiceExtensionDataStore()
        callManager = CallManager(service: service)
        AudioSessionManager.initialize()

        // Add observer to notify us when persistentStore records changes.
        // These notifications are triggered for all cross process writes to the store.

        // Don't merge and delete in ShareExtensionDataStore while the share process
        // is still running and operating on that same data. Merge conficlts on core
        // data level may arise due to race conditions.
        //
        // NotificationCenter.default.addObserver(self, selector: #selector(processStoreRemoteChanges),
        //                                        name: .NSPersistentStoreRemoteChange,
        //                                        object: shareExtensionDataStore.persistentContainer.persistentStoreCoordinator)

        // this notification is removing messages from nse immediately - somehow.
        // i initially thought - this will work only if the mainApp is active - but it is not fully clear now on how it works.
        // as a result of this: some messages are being merged from nse-shared container to main app immediately.
        // so we are not able to ack them properly.
        // disable this for now - shared models in all these cases would work really well!
        // lets get there soon!
        // NotificationCenter.default.addObserver(self, selector: #selector(processStoreRemoteChanges),
        //                                       name: .NSPersistentStoreRemoteChange,
        //                                       object: notificationServiceExtensionDataStore.persistentContainer.persistentStoreCoordinator)

         // NotificationCenter.default.addObserver(self, selector: #selector(processStoreRemoteChanges),
         //                                       name: .NSPersistentStoreRemoteChange,
         //                                       object: mainDataStore.persistentContainer.persistentStoreCoordinator)

        let oneHour = TimeInterval(60*60)
        migrateLegacyCryptoDataIfNecessary()
        cryptoData.startReporting(interval: oneHour) { [weak self] events in
            self?.eventMonitor.observe(events)
        }

        // CoreData migrations (moving feed/chat to MainDataStore)
        let shouldMigrateFeedData = self.shouldMigrateFeedData
        let shouldMigrateChatData = self.shouldMigrateChatData

        if shouldMigrateFeedData || shouldMigrateChatData {
            self.migrationInProgress.send(true)
            DispatchQueue.main.async {
                if shouldMigrateFeedData {
                    self.migrateFeedData()
                }
                if shouldMigrateChatData {
                    self.migrateChatData()
                }
                self.migrationInProgress.send(false)

                self.performAppUpdateMigrationIfNecessary()
                self.migrateUploadDataIfNecessary()
                self.migrateFeedPostLastUpdatedIfNecessary()
                self.migrateFeedPostExpiryIfNecessary()
                self.migrateCommonMediaIDsIfNecessary()
            }
        } else {
            performAppUpdateMigrationIfNecessary()
            migrateUploadDataIfNecessary()
            migrateFeedPostLastUpdatedIfNecessary()
            migrateFeedPostExpiryIfNecessary()
            migrateCommonMediaIDsIfNecessary()
        }

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak mediaUploader] _ in
                mediaUploader?.resumeBackgroundURLSessions()
            }
            .store(in: &cancellableSet)
    }

    private func performAppUpdateMigrationIfNecessary() {
        let userDefaults = Self.userDefaultsForAppGroup
        let oldAppVersion = userDefaults?.string(forKey: Self.userDefaultsAppVersion)
        if Self.appVersionForService != oldAppVersion {
            feedData.migrate(from: oldAppVersion)
            chatData.migrate(from: oldAppVersion)
            userDefaults?.setValue(Self.appVersionForService, forKey: Self.userDefaultsAppVersion)
        }
    }

    private func migrateUploadDataIfNecessary() {
        guard FileManager.default.fileExists(atPath: Self.uploadStoreURLLegacy.path) else {
            DDLogInfo("MainAppContext/migrateUploadData/skipping [not found]")
            return
        }
        DDLogInfo("MainAppContext/migrateUploadData/starting")
        let legacyUploadData = UploadData(persistentStoreURL: Self.uploadStoreURLLegacy)
        legacyUploadData.integrateEarlierResults(into: mediaHashStore) {
            DDLogInfo("MainAppContext/migrateLegacyUploadData/complete [destroying old store]")
            legacyUploadData.destroyStore()
        }
    }

    private func migrateLegacyCryptoDataIfNecessary() {
        guard FileManager.default.fileExists(atPath: Self.cryptoStatsStoreURLLegacy.path) else {
            DDLogInfo("MainAppContext/migrateLegacyCryptoData/skipping [not found]")
            return
        }
        DDLogInfo("MainAppContext/migrateLegacyCryptoData/starting")
        let legacyCryptoData = CryptoData(persistentStoreURL: Self.cryptoStatsStoreURLLegacy)
        cryptoData.integrateEarlierResults(from: legacyCryptoData) {
            DDLogInfo("MainAppContext/migrateLegacyCryptoData/complete [destroying old store]")
            legacyCryptoData.destroyStore()
        }
    }

    private func migrateFeedPostLastUpdatedIfNecessary() {
        let key = "migration.feedpostlastupdated.complete.2"
        if !userDefaults.bool(forKey: key) {
            feedData.migrateFeedPostLastUpdated()
            userDefaults.set(true, forKey: key)
        }
    }

    private func migrateFeedPostExpiryIfNecessary() {
        let key = "migration.feeedpostexpiry.complete.2"
        if !userDefaults.bool(forKey: key) {
            feedData.migrateFeedPostExpiration()
            chatData.migrateGroupExpiry()
            userDefaults.set(true, forKey: key)
        }
    }

    private func migrateCommonMediaIDsIfNecessary() {
        let key = "migration.commonmedia.id.complete"
        if !userDefaults.bool(forKey: key) {
            mainDataStore.migrateCommonMediaIDs()
            userDefaults.set(true, forKey: key)
        }
    }

    private var shouldMigrateFeedData: Bool {
        return FileManager.default.fileExists(atPath: Self.feedStoreURLLegacy.path)
    }

    private func migrateFeedData() {
        let feedLegacy = FeedDataLegacy(persistentStoreURL: Self.feedStoreURLLegacy)

        DDLogInfo("MainAppContext/migrateFeedData/starting")
        do {
            try autoreleasepool {
                try feedData.migrateLegacyPosts(feedLegacy.fetchPosts())
            }
            try autoreleasepool {
                try feedData.migrateLegacyNotifications(feedLegacy.fetchNotifications())
            }
            DDLogInfo("MainAppContext/migrateFeedData/destroying-store")
            feedLegacy.destroyStore()
            DDLogInfo("MainAppContext/migrateFeedData/finished successfully")
        } catch {
            errorLogger?.logError(error)
            DDLogError("MainAppContext/migrateFeedData/failed [\(error)]")
        }
    }

    var shouldMigrateChatData: Bool {
        return FileManager.default.fileExists(atPath: Self.chatStoreURLLegacy.path)
    }

    private func migrateChatData() {
        let chatLegacy = ChatDataLegacy(persistentStoreURL: Self.chatStoreURLLegacy)

        DDLogInfo("MainAppContext/migrateChatData/starting")
        do {
            try autoreleasepool {
                try chatData.migrateLegacyGroups(chatLegacy.fetchGroups())
            }
            try autoreleasepool {
                try chatData.migrateLegacyThreads(chatLegacy.fetchThreads())
            }
            try autoreleasepool {
                try chatData.migrateLegacyMessages(chatLegacy.fetchMessages())
            }
            try autoreleasepool {
                try chatData.migrateLegacyChatEvents(chatLegacy.fetchEvents())
            }
            DDLogInfo("MainAppContext/migrateChatData/destroying-store")
            chatLegacy.destroyStore()
            DDLogInfo("MainAppContext/migrateChatData/finished successfully")
        } catch {
            errorLogger?.logError(error)
            DDLogError("MainAppContext/migrateChatData/failed [\(error)]")
        }
    }

    // Process persistent history to merge changes from other coordinators.
    @objc private func processStoreRemoteChanges(_ notification: Notification) {
        mergeSharedData()
    }
    
    private var mergingSharedData = false
    
    // needs to run only on mergeDataQueue
    func mergeSharedData() {
        mergeSharedDataQueue.async { [weak self] in
            guard let self = self else { return }

            let mergeAttempts = self.userDefaults.integer(forKey: userDefaultsKeyForMergeDataAttempts)
            guard mergeAttempts < 2 else {
                self.shareExtensionDataStore.deleteAllContent()
                self.notificationServiceExtensionDataStore.deleteAllContent()
                let reportUserInfo = [
                    "userId": AppContext.shared.userData.userId
                ]
                AppContext.shared.errorLogger?.logError(NSError.init(domain: "MergeSharedDataError", code: 1006, userInfo: reportUserInfo))
                DDLogError("MainAppContext/merge-data/failed so clearing all shared data from extensions")
                self.userDefaults.removeObject(forKey: userDefaultsKeyForMergeDataAttempts)
                return
            }
            self.userDefaults.set(mergeAttempts + 1, forKey: userDefaultsKeyForMergeDataAttempts)

            let mergeGroup = DispatchGroup()

            // Always merge feedData first and then chatData: because chatContent might refer to feedItems.
            DDLogInfo("MainAppContext/merge-data/share-extension")

            mergeGroup.enter()
            self.feedData.mergeData(from: self.shareExtensionDataStore) {
                mergeGroup.leave()
            }
            mergeGroup.enter()
            self.chatData.mergeData(from: self.shareExtensionDataStore) {
                mergeGroup.leave()
            }

            DDLogInfo("MainAppContext/merge-data/notification-service-extension")

            mergeGroup.enter()
            self.feedData.mergeData(from: self.notificationServiceExtensionDataStore) {
                mergeGroup.leave()
            }
            mergeGroup.enter()
            self.chatData.mergeData(from: self.notificationServiceExtensionDataStore) {
                mergeGroup.leave()
            }

            // We need to merge other messages after merging chatMsgs and FeedMsgs
            // since retracts are stored here.
            // TODO: We dont like this api on CoreService: we should remove it.
            mergeGroup.enter()
            self.service.mergeData(from: self.notificationServiceExtensionDataStore) {
                mergeGroup.leave()
            }

            mergeGroup.notify(queue: .main) {
                DDLogInfo("MainAppContext/merge-data/finished")
                self.userDefaults.removeObject(forKey: userDefaultsKeyForMergeDataAttempts)
            }
        }
    }

    // All accesses to backgroundTaskIds should run on backgroundTaskQueue to prevent concurrent modifications
    private let backgroundTaskQueue = DispatchQueue(label: "backgroundTask", qos: .default)
    private var backgroundTaskIds: [String: UIBackgroundTaskIdentifier] = [:]

    func beginBackgroundTask(_ itemId: String, expirationHandler: (() -> Void)? = nil) {
        backgroundTaskQueue.async { [self] in
            if let taskID = backgroundTaskIds[itemId] {
                DDLogInfo("end existing background task: [\(itemId)]")
                UIApplication.shared.endBackgroundTask(taskID)
            }
            DDLogInfo("background task create [\(itemId)]")
            backgroundTaskIds[itemId] = UIApplication.shared.beginBackgroundTask(withName: "background-task-\(itemId)") { [weak self] in
                guard let self = self else { return }

                DDLogInfo("background task expired [\(itemId)]")
                self.endBackgroundTask(itemId)

                expirationHandler?()
            }
        }
    }

    func endBackgroundTask(_ itemId: String) {
        backgroundTaskQueue.async { [self] in
            guard let taskId = backgroundTaskIds[itemId] else { return }
            DDLogInfo("background task ended [\(itemId)]")

            UIApplication.shared.endBackgroundTask(taskId)
            backgroundTaskIds.removeValue(forKey: itemId)
        }
    }

    // Overrides extension safe version defined in AppContext
    override func startBackgroundTask(withName name: String, expirationHandler handler: (() -> Void)? = nil) -> () -> Void {
        DDLogInfo("MainAppContext/startBackgroundTask/starting: \(name)")
        let identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            DDLogInfo("MainAppContext/startBackgroundTask/expiration called for \(name)")
            handler?()
        }
        return {
            DDLogInfo("AppContext/startBackgroundTask/ending: \(name)")
            UIApplication.shared.endBackgroundTask(identifier)
        }
    }
}

extension MainAppContext: WebClientManagerDelegate {
    func webClientManager(_ manager: WebClientManager, didUpdateWebStaticKey staticKey: Data?) {
        if let staticKey = staticKey {
            Keychain.saveWebClientStaticKey(staticKey, for: userData.userId)
        } else {
            Keychain.removeWebClientStaticKey(for: userData.userId)
        }
    }
}
