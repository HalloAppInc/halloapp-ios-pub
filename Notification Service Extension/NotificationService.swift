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
            populate(notification: bestAttemptContent, withDataFrom: protoContainer)
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

    static func notificationTextIcon(forMedia protoMedia: Proto_Media) -> String {
        switch protoMedia.type {
            case .image:
                return "📷"
            case .video:
                return "📹"
            default:
                return ""
        }
    }

    static func notificationText(forMedia media: [Proto_Media]) -> String {
        let numPhotos = media.filter { $0.type == .image }.count
        let numVideos = media.filter { $0.type == .video }.count
        var strings = [String]()
        if numPhotos > 1 {
            strings.append("📷 \(numPhotos) photos")
        } else if numPhotos > 0 {
            if numVideos > 0 {
                strings.append("📷 1 photo")
            } else {
                strings.append("📷 photo")
            }
        }
        if numVideos > 1 {
            strings.append("📹 \(numVideos) videos")
        } else if numVideos > 0 {
            if numPhotos > 0 {
                strings.append("📹 1 video")
            } else {
                strings.append("📹 video")
            }
        }
        return strings.joined(separator: ", ")
    }

    private func populate(notification: UNMutableNotificationContent, withDataFrom protoContainer: Proto_Container) {
        if protoContainer.hasPost {
            notification.subtitle = "New Post"
            notification.body = protoContainer.post.text
            if !protoContainer.post.media.isEmpty {
                // Display how many photos and videos post contains if there's no caption.
                if notification.body.isEmpty {
                    notification.body = Self.notificationText(forMedia: protoContainer.post.media)
                } else {
                    let mediaIcon = Self.notificationTextIcon(forMedia: protoContainer.post.media.first!)
                    notification.body = "\(mediaIcon) \(notification.body)"
                }
            }
        } else if protoContainer.hasComment {
            notification.body = "Commented: \(protoContainer.comment.text)"
        } else if protoContainer.hasChatMessage {
            notification.body = protoContainer.chatMessage.text
            if !protoContainer.chatMessage.media.isEmpty {
                // Display how many photos and videos message contains if there's no caption.
                if notification.body.isEmpty {
                    notification.body = Self.notificationText(forMedia: protoContainer.chatMessage.media)
                } else {
                    let mediaIcon = Self.notificationTextIcon(forMedia: protoContainer.chatMessage.media.first!)
                    notification.body = "\(mediaIcon) \(notification.body)"
                }
            }
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
