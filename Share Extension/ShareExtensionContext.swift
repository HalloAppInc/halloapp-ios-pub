//
//  AppExtensionContext.swift
//  Shared Extension
//
//  Created by Alan Luo on 7/8/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import Foundation

class ShareExtensionContext: AppExtensionContext {

    // MARK: Global objects
    private(set) var dataStore: ShareExtensionDataStore!
    private(set) var privacySettings: PrivacySettings!
    
    public var shareExtensionIsActive = false

    override class var shared: ShareExtensionContext {
        get {
            return super.shared as! ShareExtensionContext
        }
    }
    
    required init(xmppControllerClass: XMPPController.Type, contactStoreClass: ContactStore.Type) {
        super.init(xmppControllerClass: xmppControllerClass, contactStoreClass: contactStoreClass)
        dataStore = ShareExtensionDataStore(xmppController: xmppController)
        privacySettings = PrivacySettings(contactStore: contactStore)
    }

}
