//
//  AppExtensionContext.swift
//  Notification Service Extension
//
//  Created by Igor Solomennikov on 6/2/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import Foundation
import Reachability

class AppExtensionContext: AppContext {

    override class var shared: AppExtensionContext {
        get {
            return super.shared as! AppExtensionContext
        }
    }

    required init(serviceBuilder: ServiceBuilder, contactStoreClass: ContactStore.Type, appTarget: AppTarget) {
        asyncLoggingEnabled = false
        super.init(serviceBuilder: serviceBuilder, contactStoreClass: contactStoreClass, appTarget: appTarget)
        setUpReachability()
    }

    // MARK: Reachability

    var reachability: Reachability?

    func setUpReachability() {
        DDLogInfo("NotificationService/setUpReachability")
        reachability = try? Reachability()
        reachability?.whenReachable = { [weak self] reachability in
            guard let self = self else {
                return
            }
            DDLogInfo("NotificationService/Reachability/reachable/\(reachability.connection)")
            self.coreService.reachabilityState = .reachable
            self.coreService.reachabilityConnectionType = reachability.connection.description
            self.coreService.startConnectingIfNecessary()
        }
        reachability?.whenUnreachable = { [weak self] reachability in
            guard let self = self else {
                return
            }
            DDLogInfo("NotificationService/Reachability/unreachable/\(reachability.connection)")
            self.coreService.reachabilityState = .unreachable
            self.coreService.reachabilityConnectionType = reachability.connection.description
        }
        do {
            try reachability?.startNotifier()
        } catch {
            DDLogError("NotificationService/Reachability/Failed to start notifier/\(reachability?.connection.description ?? "nil")")
        }
    }
}
