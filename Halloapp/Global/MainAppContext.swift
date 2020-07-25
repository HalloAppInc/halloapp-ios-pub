//
//  MainAppContext.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import Firebase
import Foundation

class MainAppContext: AppContext {
    // MARK: Constants
    private static let feedDatabaseFilename = "feed.sqlite"
    private static let chatDatabaseFilename = "chat.sqlite"

    // MARK: Global objects
    private(set) var avatarStore: AvatarStore!
    private(set) var feedData: FeedData!
    private(set) var chatData: ChatData!
    private(set) var syncManager: SyncManager!
    
    let didTapNotification = PassthroughSubject<NotificationUtility.Metadata, Never>()

    override var xmppController: XMPPControllerMain {
        get {
            super.xmppController as! XMPPControllerMain
        }
    }

    override var contactStore: ContactStoreMain {
        get {
            super.contactStore as! ContactStoreMain
        }
    }

    override var isAppExtension: Bool {
        get { false }
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

    // MARK: Initializer

    override class var shared: MainAppContext {
        get {
            return super.shared as! MainAppContext
        }
    }

    required init(xmppControllerClass: XMPPController.Type, contactStoreClass: ContactStore.Type) {
        FirebaseApp.configure()

        let logger = CrashlyticsLogger()
        logger.logFormatter = LogFormatter()
        DDLog.add(logger)

        super.init(xmppControllerClass: xmppControllerClass, contactStoreClass: contactStoreClass)

        // This is needed to encode/decode protobuf in FeedPostInfo.
        ValueTransformer.setValueTransformer(FeedPostReceiptInfoTransformer(), forName: .feedPostReceiptInfoTransformer)

        feedData = FeedData(xmppController: xmppController, contactStore: contactStore, userData: userData)
        chatData = ChatData(xmppController: xmppController, userData: userData)
        syncManager = SyncManager(contactStore: contactStore, xmppController: xmppController, userData: userData)
        avatarStore = AvatarStore()
        xmppController.avatarDelegate = avatarStore
    }
    
    private var mergingSharedData = false
    
    func mergeSharedData() {
        guard !mergingSharedData else { return }
        mergingSharedData = true
        
        DDLogInfo("MainAppContext/mergeSharedData/start")
        
        let mergeGroup = DispatchGroup()
        let sharedDataStore = SharedDataStore()
        
        mergeGroup.enter()
        feedData.mergeSharedData(using: sharedDataStore) {
            mergeGroup.leave()
        }
        
        // TODO: Merge Chats Here
        
        mergeGroup.notify(queue: .main) {
            DDLogInfo("MainAppContext/mergeSharedData/end")
            self.mergingSharedData = false
        }
    }
}
