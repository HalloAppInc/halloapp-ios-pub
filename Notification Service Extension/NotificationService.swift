//
//  NotificationService.swift
//  Notification Service Extension
//
//  Created by Igor Solomennikov on 6/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Alamofire
import Core
import FirebaseCrashlytics
import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    private lazy var downloadManager: FeedDownloadManager = {
        let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let downloadManager = FeedDownloadManager(mediaDirectoryURL: tempDirectoryURL)
        downloadManager.delegate = self
        return downloadManager
    }()

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
        var invokeHandler = true
        if let protobufData = Data(base64Encoded: metadata.data) {
            do {
                let protoContainer = try Proto_Container(serializedData: protobufData)
                populate(notification: bestAttemptContent, withDataFrom: protoContainer)
                if protoContainer.hasPost && !protoContainer.post.media.isEmpty {
                    invokeHandler = !startDownloadingMedia(in: protoContainer.post.media.first!)
                } else if protoContainer.hasChatMessage && !protoContainer.chatMessage.media.isEmpty {
                    invokeHandler = !startDownloadingMedia(in: protoContainer.chatMessage.media.first!)
                }
            }
            catch {
                Crashlytics.crashlytics().log("notification-se/protobuf/error [\(error)]")
            }
        }

        if invokeHandler {
            contentHandler(bestAttemptContent)
        }
    }

    private func populate(notification: UNMutableNotificationContent, withDataFrom protoContainer: Proto_Container) {
        if protoContainer.hasPost {
            notification.subtitle = "New Post"
            notification.body = protoContainer.post.text
            if notification.body.isEmpty && protoContainer.post.media.count > 0 {
                notification.body = "\(protoContainer.post.media.count) media"
            }
        } else if protoContainer.hasComment {
            notification.body = "Commented: \(protoContainer.comment.text)"
        } else if protoContainer.hasChatMessage {
            notification.body = protoContainer.chatMessage.text
            if notification.body.isEmpty, let protoMedia = protoContainer.chatMessage.media.first {
                let notificationSubtitle: String = {
                    switch protoMedia.type {
                    case .image: return "Sent you a photo"
                    case .video: return "Sent you a video"
                    default: return ""
                    }
                }()
                notification.subtitle = notificationSubtitle
            }
        }
    }

    private func startDownloadingMedia(in protoMedia: Proto_Media) -> Bool {
        guard let xmppMedia = XMPPFeedMedia(protoMedia: protoMedia) else { return false }
        let (taskAdded, _) = downloadManager.downloadMedia(for: xmppMedia)
        return taskAdded
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

}

extension NotificationService: FeedDownloadManagerDelegate {

    func feedDownloadManager(_ manager: FeedDownloadManager, didFinishTask task: FeedDownloadManager.Task) {
        guard let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent else {
            return
        }

        // Populate
        if task.error == nil {
            do {
                let fileURL = manager.fileURL(forRelativeFilePath: task.decryptedFilePath!)
                let attachment = try UNNotificationAttachment(identifier: task.id, url: fileURL, options: nil)
                bestAttemptContent.attachments = [ attachment ]
            }
            catch {
                // TODO: Log
            }
        } else {
            // TODO: Log
        }

        contentHandler(bestAttemptContent)
    }
}
