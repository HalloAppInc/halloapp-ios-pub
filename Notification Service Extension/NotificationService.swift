//
//  NotificationService.swift
//  Notification Service Extension
//
//  Created by Igor Solomennikov on 6/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Alamofire
import CocoaLumberjackSwift
import Core
import CoreCommon
import Combine
import UserNotifications
import Reachability

class NotificationService: UNNotificationServiceExtension  {

    // dispatch_once semantics
    private static let initializeAppContext: Void = {
        DDLogInfo("NotificationService/initializeAppContext")
        let serviceBuilder: ServiceBuilder = {
            return NotificationProtoService(credentials: $0, passiveMode: false, automaticallyReconnect: true)
        }
        initAppContext(AppExtensionContext.self,
                       serviceBuilder: serviceBuilder,
                       contactStoreClass: ContactStore.self,
                       appTarget: AppTarget.notificationExtension)
    }()

    // I found this queue to be blocked sometimes for some reason in user's logs.
    // I showed this file to apple engineers and they never pointed out this to be a problem.
    // We switched to main queue originally because we accessed some coredata view contexts.
    // but then switched to the processing queue since the main queue could be busy.
    // Switching away from this model for now.
    // private let processingQueue = DispatchQueue(label: "NotificationService", qos: .default)

    // NSE can run upto 30 seconds in most cases and 10 seconds should usually be good enough.
    private lazy var extensionRunTimeSec = ServerProperties.nseRuntimeSec
    let finalCleanupRunTimeSec = 3.0
    var contentHandler: ((UNNotificationContent) -> Void)!
    private var service: CoreService? = nil
    private var cancellableSet = Set<AnyCancellable>()
    private func recordPushEvent(requestID: String) {
        let timestamp = Date()
        DDLogInfo("NotificationService/recordPushEvent/requestId: \(requestID), timestamp: \(timestamp)")
        AppContext.shared.observeAndSave(event: .pushReceived(id: requestID, timestamp: timestamp))
    }

    // MARK: Reachability

    var reachability: Reachability?

    func setUpReachability() {
        DDLogInfo("NotificationService/setUpReachability")
        reachability = try? Reachability()
        reachability?.whenReachable = { reachability in
            DDLogInfo("NotificationService/Reachability/reachable/\(reachability.connection)")
            AppContext.shared.coreService.reachabilityState = .reachable
            AppContext.shared.coreService.reachabilityConnectionType = reachability.connection.description
            AppContext.shared.coreService.startConnectingIfNecessary()
        }
        reachability?.whenUnreachable = { reachability in
            DDLogInfo("NotificationService/Reachability/unreachable/\(reachability.connection)")
            AppContext.shared.coreService.reachabilityState = .unreachable
            AppContext.shared.coreService.reachabilityConnectionType = reachability.connection.description
        }
        do {
            try reachability?.startNotifier()
        } catch {
            DDLogError("NotificationService/Reachability/Failed to start notifier/\(reachability?.connection.description ?? "nil")")
        }
    }

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        DDLogInfo("processDidReceive/begin \(request)")
        self.processDidReceive(request: request, contentHandler: contentHandler)
    }

    private func processDidReceive(request: UNNotificationRequest, contentHandler: @escaping (UNNotificationContent) -> Void) {
        DDLogInfo("NotificationService/processDidReceive/start")
        DDLogInfo("didReceiveRequest/begin \(request) [\(AppContext.userAgent)]")
        Self.initializeAppContext
        setUpReachability()
        service = AppExtensionContext.shared.coreService
        service?.startConnectingIfNecessary()
        recordPushEvent(requestID: request.identifier)
        if let coreService = service {
            self.cancellableSet.insert(
                coreService.didDisconnect.sink { [weak self] in
                    guard let self = self else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.finalCleanupRunTimeSec) {
                        self.terminateNseAndInvokeHandler()
                    }
                })
        }

        DDLogInfo("didReceiveRequest/begin processing \(request)")

        self.contentHandler = contentHandler
        invokeCompletionHandlerLater()
    }

    private func invokeCompletionHandlerLater() {
        DDLogInfo("Going to try to disconnect and invoke handler after some time.")
        // Try and disconnect after some time.
        DispatchQueue.main.asyncAfter(deadline: .now() + extensionRunTimeSec) { [self] in
            DDLogInfo("disconnect now")
            service?.disconnect()
            DispatchQueue.main.asyncAfter(deadline: .now() + finalCleanupRunTimeSec) { [self] in
                DDLogInfo("Invoking completion handler now")
                terminateNseAndInvokeHandler()
            }
        }
    }

    private func terminateNseAndInvokeHandler() {
        if let contentHandler = contentHandler {
            DDLogInfo("Invoking contentHandler now")
            contentHandler(UNNotificationContent())
        }
    }

    override func serviceExtensionTimeWillExpire() {
        DDLogWarn("NotificationService/serviceExtensionTimeWillExpire")
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        service?.disconnectImmediately()
        DDLogInfo("Invoking completion handler now")
        terminateNseAndInvokeHandler()
    }

}
