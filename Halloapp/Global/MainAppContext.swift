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
    private(set) var avatarStore: AvatarStore!
    private(set) var feedData: FeedData!
    private(set) var chatData: ChatData!
    private(set) var syncManager: SyncManager!
    private(set) var callManager: CallManager!
    private(set) var privacySettingsImpl: PrivacySettings!
    private(set) var shareExtensionDataStore: ShareExtensionDataStore!
    private(set) var notificationServiceExtensionDataStore: NotificationServiceExtensionDataStore!
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

    let didPrivacySettingChange = PassthroughSubject<UserID, Never>()

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

    static let mediaDirectoryURL = {
        AppContext.libraryDirectoryURL.appendingPathComponent("Media", isDirectory: false)
    }()

    static let chatMediaDirectoryURL = {
        AppContext.libraryDirectoryURL.appendingPathComponent("ChatMedia", isDirectory: false)
    }()

    static let feedStoreURL = {
        AppContext.documentsDirectoryURL.appendingPathComponent(feedDatabaseFilename)
    }()

    static let chatStoreURL = {
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
        // This is needed to encode/decode protobuf in FeedPostInfo.
        ValueTransformer.setValueTransformer(FeedPostReceiptInfoTransformer(), forName: .feedPostReceiptInfoTransformer)

        feedData = FeedData(service: service, contactStore: contactStore, mainDataStore: mainDataStore, userData: userData)
        chatData = ChatData(service: service, contactStore: contactStore, userData: userData)
        syncManager = SyncManager(contactStore: contactStore, service: service, userData: userData)
        avatarStore = AvatarStore()
        coreService.avatarDelegate = avatarStore
        privacySettingsImpl = PrivacySettings(contactStore: contactStore, service: service)
        shareExtensionDataStore = ShareExtensionDataStore()
        notificationServiceExtensionDataStore = NotificationServiceExtensionDataStore()
        callManager = CallManager(service: service)
        AudioSessionManager.initialize()

        performAppUpdateMigrationIfNecessary()
        migrateUploadDataIfNecessary()

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

        let oneHour = TimeInterval(60*60)
        migrateLegacyCryptoDataIfNecessary()
        cryptoData.startReporting(interval: oneHour) { [weak self] events in
            self?.eventMonitor.observe(events)
        }
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

    private var backgroundTaskIds: [String: UIBackgroundTaskIdentifier] = [:]

    func beginBackgroundTask(_ itemId: String, expirationHandler: (() -> Void)? = nil) {
        DispatchQueue.global().async { [self] in
            if backgroundTaskIds[itemId] != nil {
                DDLogInfo("end existing background task: [\(itemId)]")
                endBackgroundTask(itemId)
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
        DispatchQueue.global().async { [self] in
            guard let taskId = backgroundTaskIds[itemId] else { return }
            DDLogInfo("background task ended [\(itemId)]")

            UIApplication.shared.endBackgroundTask(taskId)
            backgroundTaskIds.removeValue(forKey: itemId)
        }
    }
}
