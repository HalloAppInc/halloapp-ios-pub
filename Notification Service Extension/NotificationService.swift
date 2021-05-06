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

    private let serviceBuilder: ServiceBuilder = {
        return ProtoServiceCore(userData: $0, passiveMode: true, automaticallyReconnect: false)
    }
    private var service: CoreService? = nil
    private func recordPushEvent(requestID: String, messageID: String?) {
        AppContext.shared.observeAndSave(event: .pushReceived(id: messageID ?? requestID, timestamp: Date()))
    }

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        initAppContext(AppExtensionContext.self, serviceBuilder: serviceBuilder, contactStoreClass: ContactStore.self)
        service = AppExtensionContext.shared.coreService
        service?.startConnectingIfNecessary()

        DDLogInfo("didReceiveRequest/begin \(request)")

        guard let content = (request.content.mutableCopy() as? UNMutableNotificationContent) else {
            recordPushEvent(requestID: request.identifier, messageID: nil)
            contentHandler(request.content)
            return
        }

        bestAttemptContent = content
        self.contentHandler = contentHandler
        
        guard let metadata = NotificationMetadata.load(from: request, userData: AppExtensionContext.shared.userData) else {
            DDLogError("didReceiveRequest/error Invalid metadata. \(request.content.userInfo)")
            recordPushEvent(requestID: request.identifier, messageID: nil)
            contentHandler(bestAttemptContent)
            return
        }
        bestAttemptContent.populate(from: metadata, contactStore: AppExtensionContext.shared.contactStore)
        recordPushEvent(requestID: request.identifier, messageID: metadata.messageId)
        DDLogVerbose("didReceiveRequest/ Updated title: \(bestAttemptContent.title)")

        var invokeHandler = true
        switch metadata.contentType {
        case .feedPost, .groupFeedPost:
            guard let protoContainer = metadata.protoContainer else {
                DDLogError("didReceiveRequest/error Invalid protobuf.")
                invokeCompletionHandler()
                return
            }
            // Continue checking for duplicate posts.
            // TODO(murali@): test and remove this.
            guard !dataStore.posts().contains(where: { $0.id == metadata.feedPostId }) else {
                DDLogError("didReceiveRequest/error duplicate post ID [\(metadata.feedPostId ?? "nil")]")
                contentHandler(bestAttemptContent)
                return
            }
            let feedPost = dataStore.save(protoPost: protoContainer.post, notificationMetadata: metadata)
            if let firstMediaItem = feedPost.orderedMedia.first as? SharedMedia {
                let downloadTask = startDownloading(media: firstMediaItem)
                downloadTask?.feedMediaObjectId = firstMediaItem.objectID
                invokeHandler = downloadTask == nil
            }
        case .feedComment, .groupFeedComment:
            guard let protoContainer = metadata.protoContainer else {
                DDLogError("didReceiveRequest/error Invalid protobuf.")
                invokeCompletionHandler()
                return
            }
            dataStore.save(protoComment: protoContainer.comment, notificationMetadata: metadata)
        case .chatMessage:
            guard let messageId = metadata.messageId, !dataStore.messages().contains(where: { $0.id == metadata.messageId }) else {
                DDLogError("didReceiveRequest/error duplicate message ID [\(String(describing: metadata.messageId))]")
                contentHandler(bestAttemptContent)
                return
            }
            // Update application badge number.
            let badgeNum = AppExtensionContext.shared.applicationIconBadgeNumber
            let applicationIconBadgeNumber = badgeNum == -1 ? 1 : badgeNum + 1
            bestAttemptContent.badge = NSNumber(value: applicationIconBadgeNumber)
            AppExtensionContext.shared.applicationIconBadgeNumber = applicationIconBadgeNumber
            do {
                guard let serverChatStanzaPb = metadata.serverChatStanzaPb else {
                    DDLogError("MetadataError/could not find server_chat stanza, contentId: \(metadata.contentId), contentType: \(metadata.contentType)")
                    invokeCompletionHandler()
                    return
                }
                let serverChatStanza = try Server_ChatStanza(serializedData: serverChatStanzaPb)
                DDLogInfo("NotificationExtension/requesting decryptChat \(metadata.contentId)")
                decryptAndProcessChat(messageId: messageId, serverChatStanza: serverChatStanza, metadata: metadata)
                invokeHandler = false
            } catch {
                DDLogError("NotificationExtension/ChatMessage/Failed serverChatStanzaStr: \(String(describing: metadata.serverChatStanzaPb)), error: \(error)")
            }
        case .newInvitee, .newFriend, .newContact, .groupAdd:
            // save server message stanzas to process for these notifications.
            // todo(murali@): extend this to other types as well.
            dataStore.saveServerMsg(notificationMetadata: metadata)
        case .groupChatMessage, .feedPostRetract, .groupFeedPostRetract,
             .feedCommentRetract, .groupFeedCommentRetract, .chatMessageRetract, .groupChatMessageRetract:
            // If notification is anything else just invoke completion handler.
            break
        }

        // Invoke completion handler now if there was nothing to download.
        if invokeHandler {
            invokeCompletionHandler()
        }
    }

    private func invokeCompletionHandler() {
        DDLogInfo("Invoking completion handler now")
        contentHandler(bestAttemptContent)
        
    }

    // Decrypt, save and process chats!
    private func decryptAndProcessChat(messageId: String, serverChatStanza: Server_ChatStanza, metadata: NotificationMetadata) {
        let fromUserID = metadata.fromId
        service?.decryptChat(serverChatStanza, from: fromUserID) { [self] (clientChatMessage, decryptionError) in
            // Save this message to our sharedDataStore
            let messageStatus: SharedChatMessage.Status
            if let decryptionError = decryptionError {
                logChatPushDecryptionError(with: metadata, error: decryptionError.error)
                DDLogError("NotificationExtension/decryptChat/failed decryption, error: \(decryptionError)")
                messageStatus = .decryptionError
            } else {
                DDLogInfo("NotificationExtension/decryptChat/successful/messageId \(messageId)")
                messageStatus = .received
            }
            guard let chatMessage = dataStore.save(clientChatMsg: clientChatMessage, metadata: metadata, status: messageStatus, failure: decryptionError) else {
                DDLogError("DecryptionError/decryptChat/failed to save message, contentId: \(metadata.contentId)")
                invokeCompletionHandler()
                return
            }
            processChatAndInvokeHandler(chatMessage: chatMessage, clientChatMessage: clientChatMessage, metadata: metadata)
        }
    }

    // Process Chats - ack/rerequest/download media if necessary.
    private func processChatAndInvokeHandler(chatMessage: SharedChatMessage, clientChatMessage: Clients_ChatMessage?, metadata: NotificationMetadata) {
        let messageId = metadata.messageId ?? "" // messageId is never expected to be nil here.
        // send pending acks for any pending chat messages
        sendPendingAcksAndRerequests(dataStore: dataStore)
        // If we failed to get decrypted chat message successfully - then just return!
        guard let clientChatMessage = clientChatMessage else {
            DDLogError("DecryptionError/decryptChat/failed to get chat message, messageId: \(messageId)")
            invokeCompletionHandler()
            return
        }
        // Populate chat content from the payload
        bestAttemptContent.populateChatBody(from: clientChatMessage, using: metadata, contactStore: AppExtensionContext.shared.contactStore)
        if let firstMediaItem = chatMessage.orderedMedia.first as? SharedMedia {
            let downloadTask = startDownloading(media: firstMediaItem)
            downloadTask?.feedMediaObjectId = firstMediaItem.objectID
            DDLogInfo("NotificationExtension/decryptChat/downloadingMedia/messageId \(messageId), downloadTask: \(String(describing: downloadTask?.id))")
        } else {
            invokeCompletionHandler()
        }
    }

    // Send acks and rerequests for all pending chat messages.
    private func sendPendingAcksAndRerequests(dataStore: DataStore) {
        // TODO(murali@): extend this part to send rerequests as well.
        // currently we only fetch messages with status = .received
        let sharedChatMessages = dataStore.getChatMessagesToAck()
        sharedChatMessages.forEach{ sharedChatMessage in
            let msgId = sharedChatMessage.id
            service?.sendAck(messageId: msgId) { result in
                switch result {
                case .success(_):
                    DDLogInfo("sendAck/success sent ack, msgId: \(msgId)")
                    dataStore.updateMessageStatus(for: msgId, status: .received)
                case .failure(let error):
                    DDLogError("sendAck/failure sending ack, msgId: \(msgId), error: \(error)")
                }
            }
        }
    }

    private func logChatPushDecryptionError(with metadata: NotificationMetadata, error: DecryptionError?) {
        let reportUserInfo = [
            "userId": AppExtensionContext.shared.userData.userId,
            "msgId": metadata.messageId ?? "",
            "error": "ChatPushDecryptionError",
            "reason": error?.rawValue ?? ""
        ]
        let customError = NSError.init(domain: "ChatPushDecryptionErrorTest", code: 1004, userInfo: reportUserInfo)
        AppExtensionContext.shared.errorLogger?.logError(customError)
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
