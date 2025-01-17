//
//  AppClipContext.swift
//  HalloAppClip
//
//  Created by Nandini Shetty on 6/11/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CoreCommon
import Foundation

class AppClipContext: AppContextCommon {

    override class var shared: AppClipContext {
        get {
            return super.shared as! AppClipContext
        }
    }
    
    override class var isAppClip: Bool {
        get { true }
    }

    // TODO(@dini) check if you should be extending from AppExtensionContext
    required init(serviceBuilder: ServiceBuilder, contactStoreClass: ContactStore.Type, appTarget: AppTarget) {
        super.init(serviceBuilder: serviceBuilder, contactStoreClass: contactStoreClass, appTarget: appTarget)
    }
}
