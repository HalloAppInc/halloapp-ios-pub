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
import CoreData
import Foundation
import PhoneNumberKit
import FirebaseCore
import FirebaseCrashlytics

fileprivate var sharedContext: AppContext?

public typealias ServiceBuilder = (Credentials?) -> CoreService

public func initAppContext(_ appContextClass: AppContext.Type, serviceBuilder: ServiceBuilder, contactStoreClass: ContactStore.Type, appTarget: AppTarget) {
    sharedContext = appContextClass.init(serviceBuilder: serviceBuilder, contactStoreClass: contactStoreClass, appTarget: appTarget)
}

open class AppContext {
    // MARK: Constants
    private static let appGroupName = "group.com.halloapp.shared"
    private static let contactsDatabaseFilename = "contacts.sqlite"
    private static let keysDatabaseFilename = "keys.sqlite"
    private static let cryptoStatsDatabaseFilename = "cryptoStats.sqlite"
    private static let mediaHashDatabaseFilename = "mediaHash.sqlite"
    private static let notificationsDatabaseFilename = "notifications.sqlite"

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

    public static let appVersionForService: String = {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return ""
        }
        guard let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return "\(version)"
        }
        return "\(version).\(buildNumber)"
    }()

    public static let appStoreProductID = 1501583052
    public static let appStoreURL: URL? = URL(string: "itms-apps://apple.com/app/\(appStoreProductID)")

    public static let userAgent: String = { UserAgent(platform: .ios, version: appVersionForService).description }()

    public let didGetGroupInviteToken = PassthroughSubject<Void, Never>()

    open var applicationIconBadgeNumber: Int {
        get { userDefaults.integer(forKey: "ApplicationIconBadgeNumber") }
        set { userDefaults.set(newValue, forKey: "ApplicationIconBadgeNumber") }
    }

    open var isAppExtension: Bool {
        get { true }
    }
    
    open class var isAppClip: Bool {
        get { false }
    }

    // MARK: Global objects
    public let userData: UserData
    public static let userDefaultsForAppGroup: UserDefaults! = UserDefaults(suiteName: appGroupName)
    public let userDefaults: UserDefaults! = AppContext.userDefaultsForAppGroup
    public let keyStore: KeyStore
    public var keyData: KeyData!
    public let mediaHashStore: MediaHashStore
    public let notificationStore: NotificationStore
    public lazy var cryptoData: CryptoData = { CryptoData(persistentStoreURL: AppContext.cryptoStatsStoreURL) }()
    public let messageCrypter: MessageCrypter
    public let fileLogger: DDFileLogger
    public let phoneNumberFormatter = PhoneNumberKit(metadataCallback: AppContext.phoneNumberKitMetadataCallback)
    public lazy var eventMonitor: EventMonitor = {
        let monitor = EventMonitor()
        do {
            try monitor.loadReport(from: userDefaults)
        } catch {
            DDLogError("AppContext/EventMonitor/load/error \(error)")
        }
        return monitor
    }()

    public var coreService: CoreService
    public var errorLogger: ErrorLogger?

    private let contactStoreImpl: ContactStore
    open var contactStore: ContactStore {
        get {
            contactStoreImpl
        }
    }
    private let privacySettingsImpl: PrivacySettings
    open var privacySettings: PrivacySettings {
        get {
            privacySettingsImpl
        }
    }

    private var cancellableSet: Set<AnyCancellable> = []

    // MARK: Event monitoring

    public func startReportingEvents() {

        guard eventMonitorTimer == nil else {
            DDLogInfo("AppContext/startReportingEvents already started")
            return
        }

        let interval = TimeInterval(30)
        DDLogInfo("AppContext/startReportingEvents [interval=\(interval)]")

        let timer = DispatchSource.makeTimerSource(flags: [], queue: .main)
        timer.setEventHandler(handler: { [weak self] in
            self?.sendEventReport()
        })
        timer.schedule(deadline: .now(), repeating: interval)
        timer.resume()
        eventMonitorTimer = timer
    }

    public func stopReportingEvents() {
        DDLogInfo("AppContext/stopReportingEvents")
        eventMonitorTimer?.cancel()
        eventMonitorTimer = nil
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
    public static let sharedDirectoryURL: URL! = {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppContext.appGroupName)
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
    open class var shared: AppContext {
        get {
            return sharedContext!
        }
    }

    required public init(serviceBuilder: ServiceBuilder, contactStoreClass: ContactStore.Type, appTarget: AppTarget) {
        let appGroupLogsDirectory = Self.sharedDirectoryURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        let fileLogger = DDFileLogger(logFileManager: LogFileManager(logsDirectory: appGroupLogsDirectory.path))
        fileLogger.rollingFrequency = TimeInterval(60*60*24)
        fileLogger.doNotReuseLogFiles = true
        fileLogger.logFileManager.maximumNumberOfLogFiles = 400
        // It looks like CocoaLumberJack cleans up old log files that are greater than logFilesDiskQuota in size after rolling.
        // default value seems to be 20MB - which should be enough for us.
        // but disabling the cleanup logic to see if it fixes the issue.
        fileLogger.logFileManager.logFilesDiskQuota = 0
        fileLogger.logFormatter = FileLogFormatter()
        DDLog.add(fileLogger)
        self.fileLogger = fileLogger

        let osLogger = DDOSLogger.sharedInstance
        osLogger.logFormatter = LogFormatter()
        DDLog.add(osLogger)

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

        userData = UserData(storeDirectoryURL: Self.sharedDirectoryURL, isAppClip: Self.isAppClip)
        coreService = serviceBuilder(userData.credentials)
        contactStoreImpl = contactStoreClass.init(userData: userData)
        privacySettingsImpl = PrivacySettings(contactStore: contactStoreImpl)
        keyStore = KeyStore(userData: userData, appTarget: appTarget, userDefaults: userDefaults)
        keyData = KeyData(service: coreService, userData: userData, keyStore: keyStore)
        messageCrypter = MessageCrypter(service: coreService, keyStore: keyStore)
        keyStore.delegate = messageCrypter
        mediaHashStore = MediaHashStore(persistentStoreURL: AppContext.mediaHashStoreURL)
        notificationStore = NotificationStore(appTarget: appTarget, userDefaults: userDefaults)

        cancellableSet.insert(
            userData.didLogIn.sink { [weak self] in
                self?.coreService.credentials = self?.userData.credentials
            }
        )
        cancellableSet.insert(
            userData.didLogOff.sink { [weak self] in
                self?.coreService.credentials = nil
            }
        )

        FirebaseApp.configure()
        let logger = CrashlyticsLogger()
        logger.logFormatter = LogFormatter()
        DDLog.add(logger)
        // Add UserId to Crashlytics
        Crashlytics.crashlytics().setUserID(userData.userId)
        #if !DEBUG
        // Log errors to firebase
        errorLogger = logger
        #endif
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
}
