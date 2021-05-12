//
//  AppExtensionContext.swift
//  Notification Service Extension
//
//  Created by Igor Solomennikov on 6/2/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import Foundation

class AppExtensionContext: AppContext {

    override class var shared: AppExtensionContext {
        get {
            return super.shared as! AppExtensionContext
        }
    }

    required init(serviceBuilder: ServiceBuilder, contactStoreClass: ContactStore.Type, appTarget: AppTarget) {
        asyncLoggingEnabled = false
        super.init(serviceBuilder: serviceBuilder, contactStoreClass: contactStoreClass, appTarget: appTarget)
    }

}
