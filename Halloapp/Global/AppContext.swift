//
//  AppContext.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Contacts
import Foundation

fileprivate var sharedContext: AppContext?

class LogFormatter: NSObject, DDLogFormatter {

    static private func logLevel(for logMessage: DDLogMessage) -> String {
        switch logMessage.flag {
        case .error: return "LL_E"
        case .warning: return "LL_W"
        case .info: return "LL_I"
        case .debug: return "LL_D"
        default: return "LL_V"
        }
    }

    static func queueLabel(for logMessage: DDLogMessage) -> String {
        let label = logMessage.queueLabel
        var shortName = label.components(separatedBy: ".").last!
        let maxLength = 14
        if shortName.count > maxLength {
            let suffixLength = 4
            let prefix = shortName.prefix(maxLength - suffixLength - 1)
            let suffix = shortName.suffix(suffixLength)
            shortName = "\(prefix)…\(suffix)"
        } else {
            shortName = shortName.padding(toLength: maxLength, withPad: " ", startingAt: 0)
        }
        return shortName
    }

    func format(message logMessage: DDLogMessage) -> String? {
        let queueName = LogFormatter.queueLabel(for: logMessage)
        let logLevel = LogFormatter.logLevel(for: logMessage)
        let logMessageStr = logMessage.message.replacingOccurrences(of: "\n", with: "\n\(logLevel)")

        return "\(queueName) \(logLevel) \(logMessageStr)"
    }
}

class FileLogFormatter: LogFormatter {
    private let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter.locale = Locale(identifier: "en_US")
        return dateFormatter
    }()

    override func format(message logMessage: DDLogMessage) -> String? {
        if let logMessageStr = super.format(message: logMessage) {
            let dateStr = dateFormatter.string(from: logMessage.timestamp)
            return "\(dateStr) \(logMessage.threadID) \(logMessageStr)"
        }
        return nil
    }
}

struct AppContext {
    // MARK: - Constants
    static let appGroupName = "group.com.halloapp.shared"
    static let contactsDatabaseFilename = "contacts.sqlite"
    static let feedDatabaseFilename = "feed.sqlite"
    static let chatDatabaseFilename = "chat.sqlite"

    // MARK: - Global objects
    private(set) var userData: UserData
    private(set) var xmppController: XMPPController
    private(set) var feedData: FeedData
    private(set) var chatData: ChatData
    private(set) var contactStore: ContactStore
    private(set) var syncManager: SyncManager
    private(set) var fileLogger: DDFileLogger

    // MARK: - Paths
    static let sharedDirectoryURL = {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppContext.appGroupName)
    }()

    static let documentsDirectoryURL = {
        URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!)
    }()

    static let libraryDirectoryURL = {
        URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first!)
    }()

    static let mediaDirectoryURL = {
        AppContext.libraryDirectoryURL.appendingPathComponent("Media", isDirectory: false)
    }()

    static let chatMediaDirectoryURL = {
        AppContext.libraryDirectoryURL.appendingPathComponent("ChatMedia", isDirectory: false)
    }()
    
    static let contactStoreURL = {
        AppContext.sharedDirectoryURL!.appendingPathComponent(AppContext.contactsDatabaseFilename)
    }()

    static let feedStoreURL = {
        AppContext.documentsDirectoryURL.appendingPathComponent(AppContext.feedDatabaseFilename)
    }()

    static let chatStoreURL = {
        AppContext.documentsDirectoryURL.appendingPathComponent(AppContext.chatDatabaseFilename)
    }()

    
    // MARK: - Initializer
    static var shared: AppContext {
        get {
            return sharedContext!
        }
    }

    static func initContext() {
        sharedContext = AppContext()
    }

    init() {
        let fileLogger = DDFileLogger()
        fileLogger.rollingFrequency = TimeInterval(60*60*24)
        fileLogger.doNotReuseLogFiles = true
        fileLogger.logFileManager.maximumNumberOfLogFiles = 48
        fileLogger.logFormatter = FileLogFormatter()
        DDLog.add(fileLogger)
        self.fileLogger = fileLogger

        let osLogger = DDOSLogger.sharedInstance
        osLogger.logFormatter = LogFormatter()
        DDLog.add(osLogger)

        // This is needed to encode/decode protobuf in FeedPostInfo.
        ValueTransformer.setValueTransformer(FeedPostReceiptInfoTransformer(), forName: .feedPostReceiptInfoTransformer)

        userData = UserData()
        xmppController = XMPPController(userData: userData)
        contactStore = ContactStore(xmppController: xmppController, userData: userData)
        feedData = FeedData(xmppController: xmppController, contactStore: contactStore, userData: userData)
        chatData = ChatData(xmppController: xmppController, userData: userData)
        syncManager = SyncManager(contactStore: contactStore, xmppController: xmppController, userData: userData)
    }
}
