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
    private(set) var avatarStore = AvatarStore()
    private(set) var dataStore: DataStore!
    private(set) var privacySettings: PrivacySettings!
    
    public var shareExtensionIsActive = false

    override class var shared: ShareExtensionContext {
        get {
            return super.shared as! ShareExtensionContext
        }
    }

    required init(serviceBuilder: ServiceBuilder, contactStoreClass: ContactStore.Type, appTarget: AppTarget) {
        super.init(serviceBuilder: serviceBuilder, contactStoreClass: contactStoreClass, appTarget: appTarget)
        dataStore = DataStore(service: coreService)
        privacySettings = PrivacySettings(contactStore: contactStore)
    }

}
