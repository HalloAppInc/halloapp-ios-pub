//
//  MainAppContext.swift
//  HalloAppClip
//
//  Created by Nandini Shetty on 6/11/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import Foundation

class MainAppContext: AppContext {
    override class var shared: MainAppContext {
        get {
            return super.shared as! MainAppContext
        }
    }

    // TODO check if you should be extending from AppExtension context instead - YES.. look at ShareExtensionContext
    required init(serviceBuilder: ServiceBuilder, contactStoreClass: ContactStore.Type, appTarget: AppTarget) {
        super.init(serviceBuilder: serviceBuilder, contactStoreClass: contactStoreClass, appTarget: appTarget)
    }
}
