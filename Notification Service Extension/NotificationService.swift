//
//  NotificationService.swift
//  Notification Service Extension
//
//  Created by Igor Solomennikov on 6/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Alamofire
import CocoaLumberjack
import Core
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

        DDLogInfo("didReceiveRequest/begin \(request)")

        guard let bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent) else {
            contentHandler(request.content)
            return
        }

        self.bestAttemptContent = bestAttemptContent
        self.contentHandler = contentHandler
        
        guard let metadata = NotificationUtility.Metadata(fromRequest: request) else {
            DDLogError("didReceiveRequest/error Invalid metadata. \(request.content.userInfo)")
            contentHandler(bestAttemptContent)
            return
        }

        // Contact name goes as title.
        let contactName = AppExtensionContext.shared.contactStore.fullName(for: metadata.fromId)
        bestAttemptContent.title = contactName
        DDLogVerbose("didReceiveRequest/ Got contact name: \(contactName)")

        // Populate notification body.
        var invokeHandler = true
        if let protoContainer = metadata.protoContainer {
            NotificationUtility.populate(
                notification: bestAttemptContent,
                withDataFrom: protoContainer,
                mentionNameProvider: { userID in
                    AppExtensionContext.shared.contactStore.mentionName(
                        for: userID,
                        pushedName: protoContainer.mentionPushName(for: userID)) })
            if protoContainer.hasPost && !protoContainer.post.media.isEmpty {
                invokeHandler = !startDownloading(media: protoContainer.post.media, containerId: metadata.contentId)
            } else if protoContainer.hasChatMessage && !protoContainer.chatMessage.media.isEmpty {
                invokeHandler = !startDownloading(media: protoContainer.chatMessage.media, containerId: metadata.contentId)
            }
        } else {
            DDLogError("didReceiveRequest/error Invalid protobuf.")
        }

        if invokeHandler {
            DDLogInfo("Invoking completion handler now")
            contentHandler(bestAttemptContent)
        }
    }


    private var downloadTasks = [ FeedDownloadManager.Task ]()
    /**
     - returns:
     True if at least one download has been started.
     */
    private func startDownloading(media: [ Proto_Media ], containerId: String) -> Bool {
        let xmppMediaObjects = media.enumerated().compactMap { XMPPFeedMedia(id: "\(containerId)-\($0)", protoMedia: $1) }
        guard !xmppMediaObjects.isEmpty else {
            DDLogInfo("media/empty")
            return false
        }
        DDLogInfo("media/ \(xmppMediaObjects.count) objects")
        for xmppMedia in xmppMediaObjects {
            let (taskAdded, task) = downloadManager.downloadMedia(for: xmppMedia)
            if taskAdded {
                DDLogInfo("media/download/start \(task.id)")

                downloadTasks.append(task)

                // iOS doesn't show more than one attachment and therefore for now
                // only download the first media from the post.
                // Later, when we add support for using data downloaded by Notification Service Extension
                // in the main app we might start downloading all attachments.
                break
            }
        }
        return !downloadTasks.isEmpty
    }

    private func addNotificationAttachments() {
        guard let bestAttemptContent = bestAttemptContent else { return }
        var attachments = [UNNotificationAttachment]()
        for task in downloadTasks {
            guard task.completed else { continue }

            // Populate
            if task.error == nil {
                do {
                    let fileURL = downloadManager.fileURL(forRelativeFilePath: task.decryptedFilePath!)
                    let attachment = try UNNotificationAttachment(identifier: task.id, url: fileURL, options: nil)
                    attachments.append(attachment)
                }
                catch {
                    // TODO: Log
                }
            } else {
                // TODO: Log
            }
        }
        bestAttemptContent.attachments = attachments
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            DDLogWarn("timeWillExpire")
            DDLogInfo("Invoking completion handler now")
            // Use whatever finished downloading.
            addNotificationAttachments()
            contentHandler(bestAttemptContent)
        }
    }

}

extension NotificationService: FeedDownloadManagerDelegate {

    func feedDownloadManager(_ manager: FeedDownloadManager, didFinishTask task: FeedDownloadManager.Task) {
        guard let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent else {
            return
        }

        DDLogInfo("media/download/finished \(task.id)")

        // Present notification when all downloads have finished.
        if downloadTasks.filter({ !$0.completed }).isEmpty {
            DDLogInfo("Invoking completion handler now")
            addNotificationAttachments()
            contentHandler(bestAttemptContent)
        }
    }
}
