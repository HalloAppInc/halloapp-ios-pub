//
//  AppContext.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
import CocoaLumberjackSwift
import Combine
import Contacts
import CoreCommon
import CoreData
import Foundation
import PhoneNumberKit

public var sharedContext: AppContext? {
    get {
        sharedContextCommon as? AppContext
    }
    set {
        sharedContextCommon = newValue
    }
}
public func initAppContext(_ appContextClass: AppContext.Type, serviceBuilder: ServiceBuilder, contactStoreClass: ContactStore.Type, appTarget: AppTarget) {
    sharedContext = appContextClass.init(serviceBuilder: serviceBuilder, contactStoreClass: contactStoreClass, appTarget: appTarget)
}

open class AppContext: AppContextCommon {
    // MARK: Constants
    private static let appGroupName = "group.com.halloapp.shared"
    private static let mainStoreDatabaseFilename = "mainStore.sqlite"
    private static let contactsDatabaseFilename = "contacts.sqlite"
    private static let keysDatabaseFilename = "keys.sqlite"
    private static let cryptoStatsDatabaseFilename = "cryptoStats.sqlite"
    private static let mediaHashDatabaseFilename = "mediaHash.sqlite"
    private static let notificationsDatabaseFilename = "notifications.sqlite"
    private static let userDefaultsUserIDKey = "main.store.userID"

    // Key to store content-ids from notification extension - used to refresh ui
    public static let nsePostsKey = "nsePostsKey"
    public static let nseCommentsKey = "nseCommentsKey"
    public static let nseMessagesKey = "nseMessagesKey"
    // Key to store content-ids from share extension - used to refresh ui
    public static let shareExtensionPostsKey = "sharePostsKey"
    public static let shareExtensionMessagesKey = "shareMessagesKey"

    // Temporary hack until we move all data to the mainDataStore.
    // Once we have that i can create a new entity for this that can be easily updated for retracted or expired posts.
    public static let commentedGroupPostsKey = "commentedGroupPosts"

    // MARK: Global App Properties
    public static let appVersionForDisplay: String = {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return ""
        }
        guard let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return "\(version)"
        }
        return "\(version) (\(buildNumber))"
    }()

    open var applicationIconBadgeNumber: Int {
        get { userDefaults.integer(forKey: "ApplicationIconBadgeNumber") }
        set { userDefaults.set(newValue, forKey: "ApplicationIconBadgeNumber") }
    }

    private var mediaHashStoreImpl: MediaHashStore!
    open var mediaHashStore: MediaHashStore {
        mediaHashStoreImpl
    }

    private var notificationStoreImpl: NotificationStore!
    open var notificationStore: NotificationStore {
        notificationStoreImpl
    }
    public lazy var cryptoData: CryptoData = { CryptoData(persistentStoreURL: AppContext.cryptoStatsStoreURL) }()
    private var messageCrypterImpl: MessageCrypter!
    open var messageCrypter: MessageCrypter {
        messageCrypterImpl
    }
    public var coreService: CoreService {
        get {
            coreServiceCommon as! CoreService
        }
        set {
            coreServiceCommon = newValue
        }
    }

    private var contactStoreImpl: ContactStore!
    open var contactStore: ContactStore {
        get {
            contactStoreImpl
        }
    }
    private var privacySettingsImpl: PrivacySettings!
    open var privacySettings: PrivacySettings {
        get {
            privacySettingsImpl
        }
    }

    private var mainDataStoreImpl: MainDataStore!
    open var mainDataStore: MainDataStore {
        mainDataStoreImpl
    }

    private(set) var coreFeedDataImpl: CoreFeedData!
    open var coreFeedData: CoreFeedData {
        coreFeedDataImpl
    }

    private(set) var coreChatDataImpl: CoreChatData!
    open var coreChatData: CoreChatData {
        coreChatDataImpl
    }

    // MARK: Event monitoring
    /// Loads any saved events from user defaults and starts reporting at interval
    public func startReportingEvents(atInterval interval: TimeInterval = 30) {

        guard eventMonitorTimer == nil else {
            DDLogInfo("AppContext/startReportingEvents already started")
            return
        }

        do {
            try eventMonitor.loadReport(from: userDefaults)
        } catch {
            DDLogError("AppContext/EventMonitor/load/error \(error)")
        }

        DDLogInfo("AppContext/startReportingEvents [interval=\(interval)]")

        let timer = DispatchSource.makeTimerSource(flags: [], queue: .main)
        timer.setEventHandler(handler: { [weak self] in
            self?.sendEventReport()
        })
        timer.schedule(deadline: .now(), repeating: interval)
        timer.resume()
        eventMonitorTimer = timer
    }

    /// Cancels event reporting timer and saves unreported events to user defaults.
    public func stopReportingEvents() {
        DDLogInfo("AppContext/stopReportingEvents")
        eventMonitorTimer?.cancel()
        eventMonitorTimer = nil
        eventMonitor.saveReport(to: userDefaults)
    }

    public func observeAndSave(event: DiscreteEvent) {
        eventMonitor.observe(event)
        eventMonitor.saveReport(to: userDefaults)
    }

    private var eventMonitorTimer: DispatchSourceTimer?

    private func sendEventReport() {
        DDLogInfo("AppContext/sendEventReport")
        eventMonitor.generateReport { [weak self] countable, discrete in
            #if DEBUG
            DDLogInfo("AppContext/sendEventReport skipping (debug)")
            return
            #else
            guard !countable.isEmpty || !discrete.isEmpty else {
                DDLogInfo("AppContext/sendEventReport skipping (no events)")
                return
            }
            self?.coreService.log(countableEvents: countable, discreteEvents: discrete) { [weak self] result in
                switch result {
                case .success:
                    DDLogInfo("AppContext/sendEventReport/success [\(countable.count)] [\(discrete.count)]")
                case .failure(let error):
                    DDLogError("AppContext/sendEventReport/error \(error)")
                    self?.eventMonitor.count(countable)
                    for event in discrete {
                        self?.eventMonitor.observe(event)
                    }
                }
            }
            #endif
        }
    }
    
    // MARK: Paths
    public static let documentsDirectoryURL = {
        URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!)
    }()

    public static let libraryDirectoryURL = {
        URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first!)
    }()

    static let mainStoreURL = {
        sharedDirectoryURL.appendingPathComponent(AppContext.mainStoreDatabaseFilename)
    }()

    static let contactStoreURL = {
        sharedDirectoryURL.appendingPathComponent(AppContext.contactsDatabaseFilename)
    }()

    static let keyStoreURL = {
        sharedDirectoryURL.appendingPathComponent(AppContext.keysDatabaseFilename)
    }()

    static let cryptoStatsStoreURL = {
        sharedDirectoryURL.appendingPathComponent(AppContext.cryptoStatsDatabaseFilename)
    }()

    static let mediaHashStoreURL = {
        sharedDirectoryURL.appendingPathComponent(AppContext.mediaHashDatabaseFilename)
    }()

    static let notificationStoreURL = {
        sharedDirectoryURL.appendingPathComponent(AppContext.notificationsDatabaseFilename)
    }()
    
    public func deleteSharedDirectory() {
        do {
            try FileManager.default.removeItem(at: Self.sharedDirectoryURL.absoluteURL)
            DDLogInfo("AppContext/deleteSharedDirectory: Deleted shared data")
        } catch {
            DDLogError("AppContext/deleteSharedDirectory: Error deleting shared data: \(error)")
        }
    }
    
    // MARK: Initializer
    override open class var shared: AppContext {
        get {
            return sharedContext!
        }
    }

    required public init(serviceBuilder: ServiceBuilder, contactStoreClass: ContactStore.Type, appTarget: AppTarget) {
        super.init(serviceBuilder: serviceBuilder, contactStoreClass: contactStoreClass, appTarget: appTarget)
        // Migrate saved user data to app group container.
        let userDataDatabaseLocationInAppContainer = NSPersistentContainer.defaultDirectoryURL()
        if FileManager.default.fileExists(atPath: userDataDatabaseLocationInAppContainer.appendingPathComponent("Halloapp.sqlite").path) {
            let userDataDatabaseLocationInAppGroup = AppContext.sharedDirectoryURL!
            for fileExtension in [ "sqlite", "sqlite-shm", "sqlite-wal" ] {
                let fromURL = userDataDatabaseLocationInAppContainer.appendingPathComponent("Halloapp").appendingPathExtension(fileExtension)
                let toURL = userDataDatabaseLocationInAppGroup.appendingPathComponent("UserData").appendingPathExtension(fileExtension)
                do {
                    try FileManager.default.moveItem(at: fromURL, to: toURL)
                    DDLogInfo("Moved UserData from [\(fromURL)] to [\(toURL)]")
                }
                catch {
                    DDLogError("Failed to move UserData from [\(fromURL)] to [\(toURL)]")
                }
            }
        }
        // This is needed to encode/decode values in coredata entities
        ValueTransformer.setValueTransformer(FeedPostReceiptInfoTransformer(), forName: .feedPostReceiptInfoTransformer)
        ValueTransformer.setValueTransformer(MentionValueTransformer(), forName: .mentionValueTransformer)
        mainDataStoreImpl = MainDataStore(userData: userData, appTarget: appTarget, userDefaults: userDefaults)
        contactStoreImpl = contactStoreClass.init(userData: userData)
        privacySettingsImpl = PrivacySettings(contactStore: contactStoreImpl)
        messageCrypterImpl = MessageCrypter(service: coreService, keyStore: keyStore)
        keyStore.delegate = messageCrypter
        mediaHashStoreImpl = MediaHashStore(persistentStoreURL: AppContext.mediaHashStoreURL)
        notificationStoreImpl = NotificationStore(appTarget: appTarget, userDefaults: userDefaults)
        coreFeedDataImpl = CoreFeedData(mainDataStore: mainDataStore)
        coreChatDataImpl = CoreChatData(mainDataStore: mainDataStore)

        DispatchQueue.global(qos: .background).async {
            self.migrateLogFilesIfNeeded()
        }

        userData.didLogIn.sink {
            if let previousID = self.userDefaults?.string(forKey: Self.userDefaultsUserIDKey),
               previousID == self.userData.userId
            {
                DDLogInfo("MainAppContext/didLogIn Login matches prior user ID. Not unloading.")
            } else {
                DDLogInfo("MainAppContext/didLogin Login does not match prior user ID. Unloading data store.")
                self.mainDataStore.deleteAllEntities()
                self.userDefaults?.setValue(self.userData.userId, forKey: Self.userDefaultsUserIDKey)
            }
        }.store(in: &cancellableSet)

        coreService.didConnect.sink {
            if self.userDefaults?.string(forKey: Self.userDefaultsUserIDKey) == nil {
                // NB: This value is used to retain content when a user logs back in to the same account.
                //     Earlier builds did not set it at login, so let's set it in didConnect to support already logged-in users.
                DDLogInfo("MainAppContext/didConnect Storing user ID \(self.userData.userId)")
                self.userDefaults?.setValue(self.userData.userId, forKey: Self.userDefaultsUserIDKey)
            }
        }.store(in: &cancellableSet)
    }

    static func phoneNumberKitMetadataCallback() throws -> Data? {
        // TODO: proper path for app extensions
        guard let lz4Path = Bundle.main.path(forResource: "PhoneNumberMetadata", ofType: "json.lz4"),
              let compressedData = NSData(contentsOf: URL(fileURLWithPath: lz4Path)) else
        {
            throw PhoneNumberError.metadataNotFound
        }

        let decompressedData = try compressedData.decompressed(using: .lz4)
        return decompressedData as Data
    }

    public func getchatMsgSerialId() -> Int32 {
        // TODO: make the key name a separate variable.
        let serialID = userDefaults.integer(forKey: "chatMessageSerialId") + 1
        userDefaults.set(serialID, forKey: "chatMessageSerialId")
        return Int32(serialID)
    }

    // Moves log files from Library/Caches to Library/Application Support
    private func migrateLogFilesIfNeeded() {
        let legacyLogDirectory = Self.sharedDirectoryURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        let logFiles = try? FileManager.default.contentsOfDirectory(at: legacyLogDirectory,
                                                                    includingPropertiesForKeys: [])
        guard let logFiles = logFiles, !logFiles.isEmpty else {
            return
        }

        let logDirectory = URL(fileURLWithPath: fileLogger.logFileManager.logsDirectory)

        logFiles.forEach { fromURL in
            let toURL = logDirectory.appendingPathComponent(fromURL.lastPathComponent)
            do {
                try FileManager.default.moveItem(at: fromURL, to: toURL)
                DDLogInfo("Moved log file from [\(fromURL)] to [\(toURL)]")
            }
            catch {
                DDLogError("Failed to move log file from [\(fromURL)] to [\(toURL)]")
            }
        }

        do {
            try FileManager.default.removeItem(at: legacyLogDirectory)
            DDLogInfo("Deleted legacy log directory")
        }
        catch {
            DDLogError("Failed to delete legacy log directory")
        }
    }
}
