//
//  AppContext.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Contacts
import Foundation

fileprivate var sharedContext: AppContext?

struct AppContext {
    // MARK: - Constants
    static let appGroupName = "group.com.halloapp.shared"
    static let contactsDatabaseFilename = "contacts.sqlite"

    // MARK: - Global objects
    private(set) var userData: UserData
    private(set) var metaData: MetaData
    private(set) var xmppController: XMPPController
    private(set) var contacts: Contacts
    private(set) var feedData: FeedData
    private(set) var contactStore: ContactStore

    // MARK: - Paths
    static let sharedDirectoryURL = {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppContext.appGroupName)
    }

    static let documentsDirectoryPath = {
        NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
    }

    static let contactStoreURL = {
        AppContext.sharedDirectoryURL()!.appendingPathComponent(AppContext.contactsDatabaseFilename)
    }

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
        self.userData = UserData()
        self.metaData = MetaData()
        self.xmppController = XMPPController(userData: self.userData, metaData: self.metaData)
        self.contacts = Contacts(xmppController: self.xmppController, userData: self.userData)
        self.feedData = FeedData(xmppController: self.xmppController, userData: self.userData)
        self.contactStore = ContactStore(xmppController: self.xmppController)
    }
}
