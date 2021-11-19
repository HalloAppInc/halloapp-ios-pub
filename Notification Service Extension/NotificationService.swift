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
import UserNotifications

class NotificationService: UNNotificationServiceExtension  {

    // NSE can run upto 30 seconds in most cases and 10 seconds should usually be good enough.
    let extensionRunTimeSec = 25.0
    var contentHandler: ((UNNotificationContent) -> Void)!
    private let serviceBuilder: ServiceBuilder = {
        return NotificationProtoService(credentials: $0, passiveMode: false, automaticallyReconnect: false)
    }
    private var service: CoreService? = nil
    private func recordPushEvent(requestID: String, messageID: String?) {
        let timestamp = Date()
        DDLogInfo("NotificationService/recordPushEvent/requestId: \(requestID), timestamp: \(timestamp)")
        AppContext.shared.observeAndSave(event: .pushReceived(id: messageID ?? requestID, timestamp: timestamp))
    }

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            return self.processDidReceive(request: request, contentHandler: contentHandler)
        }
    }

    private func processDidReceive(request: UNNotificationRequest, contentHandler: @escaping (UNNotificationContent) -> Void) {
        DDLogInfo("didReceiveRequest/begin \(request) [\(AppContext.userAgent)]")
        initAppContext(AppExtensionContext.self, serviceBuilder: serviceBuilder, contactStoreClass: ContactStore.self, appTarget: AppTarget.notificationExtension)
        service = AppExtensionContext.shared.coreService
        service?.startConnectingIfNecessary()

        DDLogInfo("didReceiveRequest/begin processing \(request)")

//        recordPushEvent(requestID: request.identifier, messageID: nil)
        self.contentHandler = contentHandler
        invokeCompletionHandlerLater()
    }

    private func invokeCompletionHandlerLater() {
        DDLogInfo("Going to try to disconnect and invoke handler after some time.")
        // Try and disconnect after some time.
        DispatchQueue.main.asyncAfter(deadline: .now() + extensionRunTimeSec) { [self] in
            DDLogInfo("disconnect now")
            service?.disconnect()
            DDLogInfo("Invoking completion handler now")
            contentHandler(UNNotificationContent())
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        DDLogWarn("timeWillExpire")
        DispatchQueue.main.async { [self] in
            service?.disconnectImmediately()
            if let contentHandler = contentHandler {
                DDLogInfo("Invoking completion handler now")
                contentHandler(UNNotificationContent())
            }
        }
    }

}
