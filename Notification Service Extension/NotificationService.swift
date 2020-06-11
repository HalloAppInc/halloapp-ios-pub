//
//  NotificationService.swift
//  Notification Service Extension
//
//  Created by Igor Solomennikov on 6/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import FirebaseCrashlytics
import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        initAppContext(AppExtensionContext.self, xmppControllerClass: XMPPController.self, contactStoreClass: ContactStore.self)

        guard let bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent) else {
            contentHandler(request.content)
            return
        }

        self.bestAttemptContent = bestAttemptContent
        self.contentHandler = contentHandler
        
        guard let metadata = NotificationUtility.Metadata(fromRequest: request) else {
            contentHandler(bestAttemptContent)
            return
        }

        // Contact name goes as title.
        let contactName = AppExtensionContext.shared.contactStore.fullName(for: metadata.fromId)
        bestAttemptContent.title = contactName

        // Populate notification body.
        var protoContainer: Proto_Container?
        if let protobufData = Data(base64Encoded: metadata.data) {
            do {
                protoContainer = try Proto_Container(serializedData: protobufData)
            }
            catch {
                Crashlytics.crashlytics().log("notification-se/protobuf/error [\(error)]")
            }
        }
        
        if (protoContainer != nil) {
            if protoContainer!.hasPost {
                bestAttemptContent.subtitle = "New Post"
                bestAttemptContent.body = protoContainer!.post.text
                if bestAttemptContent.body.isEmpty && protoContainer!.post.media.count > 0 {
                    bestAttemptContent.body = "\(protoContainer!.post.media.count) media"
                }
            } else if protoContainer!.hasComment {
                bestAttemptContent.body = "Commented: \(protoContainer!.comment.text)"
            } else if protoContainer!.hasChatMessage {
                bestAttemptContent.body = protoContainer!.chatMessage.text
            }
        }

        contentHandler(bestAttemptContent)
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

}
