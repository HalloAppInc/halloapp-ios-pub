//
//  MainAppContext.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Contacts
import Core
import FirebaseCore
import FirebaseCrashlytics
import Foundation

class MainAppContext: AppContext {
    // MARK: Constants
    private static let feedDatabaseFilename = "feed.sqlite"
    private static let chatDatabaseFilename = "chat.sqlite"
    private static let cryptoStatsDatabaseFilename = "cryptoStats.sqlite"
    private static let uploadDatabaseFilename = "upload.sqlite"

    // MARK: Global objects
    private(set) var avatarStore: AvatarStore!
    private(set) var feedData: FeedData!
    private(set) var chatData: ChatData!
    private(set) var keyData: KeyData!
    private(set) var uploadData: UploadData!
    private(set) var syncManager: SyncManager!
    private(set) var privacySettings: PrivacySettings!
    private(set) var shareExtensionDataStore: ShareExtensionDataStore!
    private(set) var notificationServiceExtensionDataStore: NotificationServiceExtensionDataStore!
    lazy var nux: NUX = { NUX(userDefaults: userDefaults) }()
    lazy var cryptoData: CryptoData = { CryptoData() }()
    
    let didTapNotification = PassthroughSubject<NotificationMetadata, Never>()
    let activityViewControllerPresentRequest = PassthroughSubject<[Any], Never>()
    let groupFeedFromGroupTabPresentRequest = CurrentValueSubject<GroupID?, Never>(nil)
    let didGetGroupInviteToken = PassthroughSubject<Void, Never>()

    var service: HalloService {
        coreService as! HalloService
    }

    override var contactStore: ContactStoreMain {
        get {
            super.contactStore as! ContactStoreMain
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
    static let documentsDirectoryURL = {
        URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!)
    }()

    static let libraryDirectoryURL = {
        URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first!)
    }()

    static let mediaDirectoryURL = {
        libraryDirectoryURL.appendingPathComponent("Media", isDirectory: false)
    }()

    static let chatMediaDirectoryURL = {
        libraryDirectoryURL.appendingPathComponent("ChatMedia", isDirectory: false)
    }()

    static let feedStoreURL = {
        documentsDirectoryURL.appendingPathComponent(feedDatabaseFilename)
    }()

    static let chatStoreURL = {
        documentsDirectoryURL.appendingPathComponent(chatDatabaseFilename)
    }()

    static let cryptoStatsStoreURL = {
        documentsDirectoryURL.appendingPathComponent(cryptoStatsDatabaseFilename)
    }()

    static let uploadStoreURL = {
        documentsDirectoryURL.appendingPathComponent(uploadDatabaseFilename)
    }()
    
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

        feedData = FeedData(service: service, contactStore: contactStore, userData: userData)
        chatData = ChatData(service: service, contactStore: contactStore, userData: userData)
        keyData = KeyData(service: service, userData: userData, keyStore: keyStore)
        uploadData = UploadData()
        syncManager = SyncManager(contactStore: contactStore, service: service, userData: userData)
        avatarStore = AvatarStore()
        coreService.avatarDelegate = avatarStore
        privacySettings = PrivacySettings(contactStore: contactStore, service: service)
        shareExtensionDataStore = ShareExtensionDataStore()
        notificationServiceExtensionDataStore = NotificationServiceExtensionDataStore()

        // Add observer to notify us when persistentStore records changes.
        // These notifications are triggered for all cross process writes to the store.
        NotificationCenter.default.addObserver(self, selector: #selector(processStoreRemoteChanges),
                                               name: .NSPersistentStoreRemoteChange,
                                               object: shareExtensionDataStore.persistentContainer.persistentStoreCoordinator)
        NotificationCenter.default.addObserver(self, selector: #selector(processStoreRemoteChanges),
                                               name: .NSPersistentStoreRemoteChange,
                                               object: notificationServiceExtensionDataStore.persistentContainer.persistentStoreCoordinator)

        let oneHour = TimeInterval(60*60)
        cryptoData.startReporting(interval: oneHour) { [weak self] events in
            self?.eventMonitor.observe(events)
        }
    }

    // Process persistent history to merge changes from other coordinators.
    @objc private func processStoreRemoteChanges(_ notification: Notification) {
        mergeSharedData()
    }
    
    private var mergingSharedData = false
    
    func mergeSharedData() {
        guard !mergingSharedData else { return }

        mergingSharedData = true

        let mergeGroup = DispatchGroup()

        // Always merge feedData first and then chatData: because chatContent might refer to feedItems.
        DDLogInfo("MainAppContext/merge-data/share-extension")

        mergeGroup.enter()
        feedData.mergeData(from: shareExtensionDataStore) {
            mergeGroup.leave()
        }
        mergeGroup.enter()
        chatData.mergeData(from: shareExtensionDataStore) {
            mergeGroup.leave()
        }

        DDLogInfo("MainAppContext/merge-data/notification-service-extension")

        mergeGroup.enter()
        service.mergeData(from: notificationServiceExtensionDataStore) {
            mergeGroup.leave()
        }

        mergeGroup.enter()
        feedData.mergeData(from: notificationServiceExtensionDataStore) {
            mergeGroup.leave()
        }
        mergeGroup.enter()
        chatData.mergeData(from: notificationServiceExtensionDataStore) {
            mergeGroup.leave()
        }

        mergeGroup.notify(queue: .main) {
            DDLogInfo("MainAppContext/merge-data/finished")
            self.mergingSharedData = false
        }
    }
}
