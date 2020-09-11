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

class NotificationService: UNNotificationServiceExtension, FeedDownloadManagerDelegate  {

    var contentHandler: ((UNNotificationContent) -> Void)!
    var bestAttemptContent: UNMutableNotificationContent!
    private lazy var dataStore = DataStore()

    private lazy var downloadManager: FeedDownloadManager = {
        let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let downloadManager = FeedDownloadManager(mediaDirectoryURL: tempDirectoryURL)
        downloadManager.delegate = self
        return downloadManager
    }()

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        initAppContext(AppExtensionContext.self, xmppControllerClass: XMPPController.self, contactStoreClass: ContactStore.self)

        DDLogInfo("didReceiveRequest/begin \(request)")

        guard let content = (request.content.mutableCopy() as? UNMutableNotificationContent) else {
            contentHandler(request.content)
            return
        }

        bestAttemptContent = content
        self.contentHandler = contentHandler
        
        guard let metadata = NotificationMetadata(notificationRequest: request) else {
            DDLogError("didReceiveRequest/error Invalid metadata. \(request.content.userInfo)")
            contentHandler(bestAttemptContent)
            return
        }

        // Populate contact name early because `userId` is stored outside of protobuf container (which isn't guaranteed).
        let userId = metadata.fromId
        let contactName = AppExtensionContext.shared.contactStore.fullName(for: userId)
        bestAttemptContent.title = contactName
        DDLogVerbose("didReceiveRequest/ Got contact name: \(contactName)")

        guard let protoContainer = metadata.protoContainer else {
            DDLogError("didReceiveRequest/error Invalid protobuf.")
            contentHandler(bestAttemptContent)
            return
        }

        // Populate notification body.
        bestAttemptContent.populate(withDataFrom: protoContainer, mentionNameProvider: { userID in
            AppExtensionContext.shared.contactStore.mentionName(for: userID, pushedName: protoContainer.mentionPushName(for: userID))
        })

        var invokeHandler = true
        if protoContainer.hasPost {
            let feedPost = dataStore.save(protoPost: protoContainer.post, notificationMetadata: metadata)
            if let firstMediaItem = feedPost.orderedMedia.first as? SharedMedia {
                let downloadTask = startDownloading(media: firstMediaItem)
                downloadTask?.feedMediaObjectId = firstMediaItem.objectID
                invokeHandler = downloadTask == nil
            }
        } else if protoContainer.hasChatMessage {
            let messageId = metadata.contentId
            if let chatMedia = protoContainer.chatMessage.media.first,
                let xmppMedia = XMPPFeedMedia(id: "\(messageId)", protoMedia: chatMedia) {
                let downloadTask = startDownloading(media: xmppMedia)
                invokeHandler = downloadTask == nil
            }
        }

        // Invoke completion handler now if there was nothing to download.
        if invokeHandler {
            DDLogInfo("Invoking completion handler now")
            contentHandler(bestAttemptContent)
        }
    }

    /**
      iOS doesn't show more than one attachment and therefore for now only download the first media from the post.

     - returns: Download task if download has started.
     */
    private func startDownloading(media: FeedMediaProtocol) -> FeedDownloadManager.Task? {
        let (taskAdded, task) = downloadManager.downloadMedia(for: media)
        if taskAdded {
            DDLogInfo("media/download/started \(task.id)")
            return task
        }
        return nil
    }

    func feedDownloadManager(_ downloadManager: FeedDownloadManager, didFinishTask task: FeedDownloadManager.Task) {
        DDLogInfo("media/download/finished \(task.id)")

        if let error = task.error {
            DDLogError("media/download/error \(error)")
            DDLogInfo("Invoking completion handler now")
            contentHandler(bestAttemptContent)
            return
        }

        let fileURL = downloadManager.fileURL(forRelativeFilePath: task.decryptedFilePath!)

        // Attach media to notification.
        do {
            let attachment = try UNNotificationAttachment(identifier: task.id, url: fileURL, options: nil)
            bestAttemptContent.attachments = [attachment]
        }
        catch {
            DDLogError("media/attachment-create/error \(error)")
        }

        // Copy downloaded media to shared file storage and update db with path to the media.
        if let objectId = task.feedMediaObjectId,
           let feedMediaItem = try? dataStore.sharedMediaObject(forObjectId: objectId) {

            let filename = fileURL.deletingPathExtension().lastPathComponent
            let relativeFilePath = SharedDataStore.relativeFilePath(forFilename: filename, mediaType: feedMediaItem.type)
            do {
                let destinationUrl = dataStore.fileURL(forRelativeFilePath: relativeFilePath)
                SharedDataStore.preparePathForWriting(destinationUrl)

                try FileManager.default.copyItem(at: fileURL, to: destinationUrl)
                DDLogDebug("SharedDataStore/attach-media/ copied [\(fileURL)] to [\(destinationUrl)]")

                feedMediaItem.relativeFilePath = relativeFilePath
                feedMediaItem.status = .downloaded
                dataStore.save(feedMediaItem.managedObjectContext!)
            }
            catch {
                DDLogError("media/copy-media/error [\(error)]")
            }
        }

        DDLogInfo("Invoking completion handler now")
        contentHandler(bestAttemptContent)
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            DDLogWarn("timeWillExpire")
            DDLogInfo("Invoking completion handler now")
            contentHandler(bestAttemptContent)
        }
    }

}
