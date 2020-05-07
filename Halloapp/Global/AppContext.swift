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
        self.fileLogger = DDFileLogger()
        fileLogger.rollingFrequency = TimeInterval(60*60*24)
        fileLogger.doNotReuseLogFiles = true
        fileLogger.logFileManager.maximumNumberOfLogFiles = 48

        DDLog.add(DDOSLogger.sharedInstance)
        DDLog.add(self.fileLogger)

        ValueTransformer.setValueTransformer(FeedPostReceiptInfoTransformer(), forName: .feedPostReceiptInfoTransformer)

        userData = UserData()
        xmppController = XMPPController(userData: userData)
        contactStore = ContactStore(xmppController: xmppController, userData: userData)
        feedData = FeedData(xmppController: xmppController, contactStore: contactStore, userData: userData)
        chatData = ChatData(xmppController: xmppController, userData: userData)
        syncManager = SyncManager(contactStore: contactStore, xmppController: xmppController, userData: userData)
    }
}
