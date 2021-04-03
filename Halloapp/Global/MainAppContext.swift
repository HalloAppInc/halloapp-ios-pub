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
import Foundation

class MainAppContext: AppContext {
    // MARK: Constants
    private static let feedDatabaseFilename = "feed.sqlite"
    private static let chatDatabaseFilename = "chat.sqlite"
    private static let cryptoStatsDatabaseFilename = "cryptoStats.sqlite"

    // MARK: Global objects
    private(set) var avatarStore: AvatarStore!
    private(set) var feedData: FeedData!
    private(set) var chatData: ChatData!
    private(set) var keyData: KeyData!
    private(set) var syncManager: SyncManager!
    private(set) var privacySettings: PrivacySettings!
    lazy var nux: NUX = { NUX(userDefaults: userDefaults) }()
    lazy var cryptoData: CryptoData = { CryptoData() }()
    
    let didTapNotification = PassthroughSubject<NotificationMetadata, Never>()
    let activityViewControllerPresentRequest = PassthroughSubject<[Any], Never>()

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
    
    // MARK: Initializer

    override class var shared: MainAppContext {
        get {
            return super.shared as! MainAppContext
        }
    }

    required init(serviceBuilder: ServiceBuilder, contactStoreClass: ContactStore.Type) {
        FirebaseApp.configure()

        let logger = CrashlyticsLogger()
        logger.logFormatter = LogFormatter()
        DDLog.add(logger)

        super.init(serviceBuilder: serviceBuilder, contactStoreClass: contactStoreClass)
        // This is needed to encode/decode protobuf in FeedPostInfo.
        ValueTransformer.setValueTransformer(FeedPostReceiptInfoTransformer(), forName: .feedPostReceiptInfoTransformer)

        feedData = FeedData(service: service, contactStore: contactStore, userData: userData)
        chatData = ChatData(service: service, contactStore: contactStore, userData: userData)
        keyData = KeyData(service: service, userData: userData, keyStore: keyStore)
        syncManager = SyncManager(contactStore: contactStore, service: service, userData: userData)
        avatarStore = AvatarStore()
        coreService.avatarDelegate = avatarStore
        privacySettings = PrivacySettings(contactStore: contactStore, service: service)

        let oneHour = TimeInterval(60*60)
        cryptoData.startReporting(interval: oneHour) { [weak self] events in
            self?.eventMonitor.observe(events)
        }

        #if !DEBUG
        // Log errors to firebase
        errorLogger = logger
        #endif
    }
    
    private var mergingSharedData = false
    
    func mergeSharedData() {
        guard !mergingSharedData else { return }

        mergingSharedData = true
        let mergeGroup = DispatchGroup()

        DDLogInfo("MainAppContext/merge-data/share-extension")
        
        let shareExtensionDataStore = ShareExtensionDataStore()
        mergeGroup.enter()
        feedData.mergeData(from: shareExtensionDataStore) {
            mergeGroup.leave()
        }
        mergeGroup.enter()
        chatData.mergeData(from: shareExtensionDataStore) {
            mergeGroup.leave()
        }

        DDLogInfo("MainAppContext/merge-data/notification-service-extension")
        let notificationServiceExtensionDataStore = NotificationServiceExtensionDataStore()
        mergeGroup.enter()
        feedData.mergeData(from: notificationServiceExtensionDataStore) {
            mergeGroup.leave()
        }

        mergeGroup.notify(queue: .main) {
            DDLogInfo("MainAppContext/merge-data/finished")
            self.mergingSharedData = false
        }
    }
}
