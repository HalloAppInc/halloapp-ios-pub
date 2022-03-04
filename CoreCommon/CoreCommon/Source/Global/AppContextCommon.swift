//
//  AppContextCommon.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
import CocoaLumberjackSwift
import Combine
import Contacts
import Foundation
import PhoneNumberKit

fileprivate var sharedContext: AppContextCommon?

public typealias ServiceBuilder = (Credentials?) -> CoreServiceCommon

public func initAppContext(_ appContextClass: AppContextCommon.Type, serviceBuilder: ServiceBuilder, contactStoreClass: ContactStore.Type, appTarget: AppTarget) {
    sharedContext = appContextClass.init(serviceBuilder: serviceBuilder, contactStoreClass: contactStoreClass, appTarget: appTarget)
}
open class AppContextCommon {
    // MARK: Constants
    private static let appGroupName = "group.com.halloapp.shared"
    private static let contactsDatabaseFilename = "contacts.sqlite"
    private static let keysDatabaseFilename = "keys.sqlite"

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

    open var isAppExtension: Bool {
        get { true }
    }

    open class var isAppClip: Bool {
        get { false }
    }

    // MARK: Global objects
    public let userData: UserData
    public static let userDefaultsForAppGroup: UserDefaults! = UserDefaults(suiteName: appGroupName)
    public let userDefaults: UserDefaults! = AppContextCommon.userDefaultsForAppGroup
    public let keyStore: KeyStore
    public var keyData: KeyData!
    public let fileLogger: DDFileLogger
    public let phoneNumberFormatter = PhoneNumberKit(metadataCallback: AppContextCommon.phoneNumberKitMetadataCallback)
    public let eventMonitor = EventMonitor()

    public var coreServiceCommon: CoreServiceCommon
    public var errorLogger: ErrorLogger?
    private var cancellableSet: Set<AnyCancellable> = []

    public static let sharedDirectoryURL: URL! = {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppContextCommon.appGroupName)
    }()

    static let contactStoreURL = {
        sharedDirectoryURL.appendingPathComponent(AppContextCommon.contactsDatabaseFilename)
    }()

    static let keyStoreURL = {
        sharedDirectoryURL.appendingPathComponent(AppContextCommon.keysDatabaseFilename)
    }()

    // MARK: Initializer
    open class var shared: AppContextCommon {
        get {
            return sharedContext!
        }
    }

    required public init(serviceBuilder: ServiceBuilder, contactStoreClass: ContactStore.Type, appTarget: AppTarget) {
        let appGroupLogsDirectory = Self.sharedDirectoryURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        let fileLogger = DDFileLogger(logFileManager: LogFileManager(logsDirectory: appGroupLogsDirectory.path))
        fileLogger.rollingFrequency = TimeInterval(60*60*24)
        fileLogger.doNotReuseLogFiles = true
        fileLogger.logFileManager.maximumNumberOfLogFiles = 400
        fileLogger.logFormatter = FileLogFormatter()
        DDLog.add(fileLogger)
        self.fileLogger = fileLogger

        let osLogger = DDOSLogger.sharedInstance
        osLogger.logFormatter = LogFormatter()
        DDLog.add(osLogger)

        userData = UserData(storeDirectoryURL: Self.sharedDirectoryURL, isAppClip: Self.isAppClip)
        coreServiceCommon = serviceBuilder(userData.credentials)
        keyStore = KeyStore(userData: userData, appTarget: appTarget, userDefaults: userDefaults)
        keyData = KeyData(service: coreServiceCommon, userData: userData, keyStore: keyStore)

        cancellableSet.insert(
            userData.didLogIn.sink { [weak self] in
                self?.coreServiceCommon.credentials = self?.userData.credentials
            }
        )
        cancellableSet.insert(
            userData.didLogOff.sink { [weak self] in
                self?.coreServiceCommon.credentials = nil
            }
        )
        // When this class is initialized via a super class(AppContext), we are making sure the sharedContext of this class is set.
        sharedContext = self
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
}