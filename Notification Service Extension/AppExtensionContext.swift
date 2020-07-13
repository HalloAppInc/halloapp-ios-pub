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

    required init(xmppControllerClass: XMPPController.Type, contactStoreClass: ContactStore.Type) {
        asyncLoggingEnabled = false
        super.init(xmppControllerClass: xmppControllerClass, contactStoreClass: contactStoreClass)
    }

}
