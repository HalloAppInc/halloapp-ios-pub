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
        return ProtoServiceCore(userData: $0, passiveMode: true, automaticallyReconnect: true)
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
            invokeCompletionHandler()
            return
        }
        bestAttemptContent.populate(from: metadata, contactStore: AppExtensionContext.shared.contactStore)
        recordPushEvent(requestID: request.identifier, messageID: metadata.messageId)
        DDLogVerbose("didReceiveRequest/ Updated title: \(bestAttemptContent.title)")

        var invokeHandler = true
        switch metadata.contentType {
        case .feedPost:
            guard let postData = metadata.postData() else {
                DDLogError("didReceiveRequest/error Invalid fields in metadata.")
                invokeCompletionHandler()
                return
            }
            // Continue checking for duplicate posts.
            // TODO(murali@): test and remove this.
            guard !dataStore.posts().contains(where: { $0.id == metadata.feedPostId }) else {
                DDLogError("didReceiveRequest/error duplicate post ID [\(metadata.feedPostId ?? "nil")]")
                invokeCompletionHandler()
                return
            }
            self.processPostDataAndInvokeHandler(postData: postData, status: .received, metadata: metadata)
            invokeHandler = false
        case .feedComment:
            guard let commentData = metadata.commentData() else {
                DDLogError("didReceiveRequest/error Invalid fields in metadata.")
                invokeCompletionHandler()
                return
            }
            self.processCommentDataAndInvokeHandler(commentData: commentData, status: .received, metadata: metadata)
            invokeHandler = true

        // Separate out groupFeedItems: we need to decrypt them, process and populate content accordingly.
        case .groupFeedPost, .groupFeedComment:
            guard metadata.messageId != nil, !metadata.contentId.isEmpty else {
                DDLogError("didReceiveRequest/error missing messageId [\(String(describing: metadata))]")
                dismissNotification()
                return
            }
            let contentType: FeedElementType
            if metadata.contentType == .groupFeedPost {
                contentType = .post
            } else {
                contentType = .comment
            }

            if let sharedPost = dataStore.sharedFeedPost(for: metadata.contentId), sharedPost.status == .received {
                DDLogError("didReceiveRequest/error duplicate groupFeedPost [\(metadata.contentId)]")
                dismissNotification()
                return
            } else if let sharedComment = dataStore.sharedFeedComment(for: metadata.contentId), sharedComment.status == .received {
                DDLogError("didReceiveRequest/error duplicate groupFeedComment [\(metadata.contentId)]")
                dismissNotification()
                return
            }

            // Decrypt and process the payload now
            do {
                guard let serverGroupFeedItemPb = metadata.serverGroupFeedItemPb else {
                    DDLogError("MetadataError/could not find serverGroupFeedItem stanza, contentId: \(metadata.contentId), contentType: \(metadata.contentType)")
                    invokeCompletionHandler()
                    return
                }
                let serverGroupFeedItem = try Server_GroupFeedItem(serializedData: serverGroupFeedItemPb)
                DDLogInfo("NotificationExtension/requesting decryptGroupFeedItem \(metadata.contentId)")
                decryptAndProcessGroupFeedItem(contentID: metadata.contentId, contentType: contentType, item: serverGroupFeedItem, metadata: metadata)
                invokeHandler = false
            } catch {
                DDLogError("NotificationExtension/ChatMessage/Failed serverChatStanzaStr: \(String(describing: metadata.serverChatStanzaPb)), error: \(error)")
            }

        case .chatMessage:
            // TODO: add id as the constraint to the db and then remove this check.
            guard let messageId = metadata.messageId else {
                DDLogError("didReceiveRequest/error missing messageId [\(String(describing: metadata))]")
                dismissNotification()
                return
            }
            // Check if message has already been received and decrypted successfully.
            // If yes - then dismiss notification, else continue processing.
            if let sharedChatMessage = dataStore.sharedChatMessage(for: messageId), sharedChatMessage.status == .received {
                DDLogError("didReceiveRequest/error duplicate message ID that was already decrypted[\(String(describing: metadata.messageId))]")
                dismissNotification()
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
             .feedCommentRetract, .groupFeedCommentRetract, .chatMessageRetract, .groupChatMessageRetract, .chatRerequest:
            // If notification is anything else just invoke completion handler and return
            dismissNotification()
            return
        }

        // Invoke completion handler now if there was nothing to download.
        if invokeHandler {
            invokeCompletionHandler()
        }
    }

    private func invokeCompletionHandler() {
        DDLogInfo("Going to try to disconnect and invoke completion handler now")
        // Try and disconnect after 1 second.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            DDLogInfo("disconnect now")
            service?.disconnect()
            DDLogInfo("Invoking completion handler now")
            contentHandler(bestAttemptContent)
        }
    }

    private func dismissNotification() {
        DDLogInfo("Going to try to disconnect and dismiss notification now")
        // Try and disconnect after 1 second.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            DDLogInfo("disconnect now")
            service?.disconnect()
            DDLogInfo("Invoking completion handler now")
            contentHandler(UNNotificationContent())
        }
    }

    // Decrypt, save and process chats!
    private func decryptAndProcessGroupFeedItem(contentID: String, contentType: FeedElementType, item: Server_GroupFeedItem, metadata: NotificationMetadata) {
        service?.decryptGroupFeedPayload(for: item) { content, groupDecryptionFailure in
            if let content = content, groupDecryptionFailure == nil {
                DDLogError("NotificationExtension/decryptAndProcessGroupFeedItem/contentID/\(contentID)/success")
                switch content {
                case .newItems(let newItems):
                    guard let newItem = newItems.first, newItems.count == 1 else {
                        DDLogError("NotificationExtension/decryptAndProcessGroupFeedItem/contentID/\(contentID)/too many items - invalid decrypted payload.")
                        return
                    }
                    switch newItem {
                    case .post(let postData):
                        self.processPostDataAndInvokeHandler(postData: postData, status: .received, metadata: metadata)
                    case .comment(let commentData, _):
                        self.processCommentDataAndInvokeHandler(commentData: commentData, status: .received, metadata: metadata)
                    }
                case .retracts(_):
                    // This is not possible - since these are never encrypted in the first place as of now.
                    return
                }
            } else {
                DDLogError("NotificationExtension/decryptAndProcessGroupFeedItem/contentID/\(contentID)/failure \(groupDecryptionFailure.debugDescription)")
                switch contentType {
                case .post:
                    self.processPostDataAndInvokeHandler(postData: metadata.postData(status: .rerequesting), status: .decryptionError, metadata: metadata)
                case .comment:
                    self.processCommentDataAndInvokeHandler(commentData: metadata.commentData(status: .rerequesting), status: .decryptionError, metadata: metadata)
                case .linkPreview:
                    DDLogError("NotificationExtension/decryptAndProcessGroupFeedItem/contentID/\(contentID)/received link preview")
                }
            }
            self.reportGroupDecryptionResult(
                error: groupDecryptionFailure?.error,
                contentID: contentID,
                itemType: contentType,
                groupID: item.gid,
                timestamp: Date(),
                rerequestCount: Int(metadata.rerequestCount))
        }
    }

    private func processPostDataAndInvokeHandler(postData: PostData?, status: SharedFeedPost.Status, metadata: NotificationMetadata) {
        dataStore.save(postData: postData, status: status, notificationMetadata: metadata) { sharedFeedPost in
            // If we failed to get postData successfully - then just return!
            guard let postData = postData else {
                DDLogError("NotificationExtension/processPostDataAndInvokeHandler/failed to get postData, contentId: \(metadata.contentId)")
                self.invokeCompletionHandler()
                return
            }
            self.bestAttemptContent.populateFeedPostBody(from: postData, using: metadata, contactStore: AppExtensionContext.shared.contactStore)
            if let firstMediaItem = sharedFeedPost.orderedMedia.first as? SharedMedia {
                let downloadTask = self.startDownloading(media: firstMediaItem)
                downloadTask?.feedMediaObjectId = firstMediaItem.objectID
            } else {
                self.invokeCompletionHandler()
            }
            // TODO: murali@: send acks and rerequests here as necessary.
        }
    }

    private func processCommentDataAndInvokeHandler(commentData: CommentData?, status: SharedFeedComment.Status, metadata: NotificationMetadata) {
        dataStore.save(commentData: commentData, status: status, notificationMetadata: metadata) { sharedFeedComment in
            // If we failed to get commentData successfully - then just return!
            guard let commentData = commentData else {
                DDLogError("NotificationExtension/processCommentDataAndInvokeHandler/failed to get postData, contentId: \(metadata.contentId)")
                self.invokeCompletionHandler()
                return
            }
            self.bestAttemptContent.populateFeedCommentBody(from: commentData, using: metadata, contactStore: AppExtensionContext.shared.contactStore)
            self.invokeCompletionHandler()
            // TODO: murali@: send acks and rerequests here as necessary.
        }
    }

    private func reportGroupDecryptionResult(error: DecryptionError?, contentID: String, itemType: FeedElementType, groupID: GroupID, timestamp: Date, rerequestCount: Int) {
        let errorString = error?.rawValue ?? ""
        DDLogInfo("NotificationExtension/reportGroupDecryptionResult/\(contentID)/\(itemType)/\(groupID)/error value: \(errorString)")
        AppContext.shared.eventMonitor.count(.groupDecryption(error: error, itemType: itemType))
        AppContext.shared.cryptoData.update(contentID: contentID,
                                            contentType: itemType.rawString,
                                            groupID: groupID,
                                            timestamp: timestamp,
                                            error: errorString,
                                            rerequestCount: rerequestCount)
    }

    // Decrypt, save and process chats!
    private func decryptAndProcessChat(messageId: String, serverChatStanza: Server_ChatStanza, metadata: NotificationMetadata) {
        let fromUserID = metadata.fromId
        AppExtensionContext.shared.messageCrypter.decrypt(
            EncryptedData(
                data: serverChatStanza.encPayload,
                identityKey: serverChatStanza.publicKey.isEmpty ? nil : serverChatStanza.publicKey,
                oneTimeKeyId: Int(serverChatStanza.oneTimePreKeyID)),
            from: fromUserID) { result in

            // TODO: Refactor this now that we don't send plaintext (success/failure values mutually exclusive)
            let protobufToSave: MessageProtobuf?
            let messageStatus: SharedChatMessage.Status
            let decryptionFailure: DecryptionFailure?

            switch result {
            case .success(let decryptedData):
                DDLogInfo("NotificationExtension/decryptChat/successful/messageId \(messageId)")
                messageStatus = .received
                decryptionFailure = nil

                if let container = Clients_ChatContainer(containerData: decryptedData) {
                    protobufToSave = .container(container)
                } else if let legacyMessage = Clients_ChatMessage(containerData: decryptedData) {
                    protobufToSave = .legacy(legacyMessage)
                } else {
                    protobufToSave = nil
                }
            case .failure(let decryptionError):
                self.logChatPushDecryptionError(with: metadata, error: decryptionError.error)
                DDLogError("NotificationExtension/decryptChat/failed decryption, error: \(decryptionError)")
                messageStatus = .decryptionError
                decryptionFailure = decryptionError
                protobufToSave = nil
            }

            self.dataStore.save(protobuf: protobufToSave, metadata: metadata, status: messageStatus, failure: decryptionFailure) { sharedChatMessage in
                self.processChatAndInvokeHandler(chatMessage: sharedChatMessage, protobuf: protobufToSave, metadata: metadata)
            }
        }
    }

    // Process Chats - ack/rerequest/download media if necessary.
    private func processChatAndInvokeHandler(chatMessage: SharedChatMessage, protobuf: MessageProtobuf?, metadata: NotificationMetadata) {
        let messageId = metadata.messageId ?? "" // messageId is never expected to be nil here.
        // send pending acks for any pending chat messages
        sendPendingAcksAndRerequests(dataStore: dataStore)
        // If we failed to get decrypted chat content successfully - then just return!
        guard let chatContent = protobuf?.chatContent else {
            DDLogError("DecryptionError/decryptChat/failed to get chat content, messageId: \(messageId)")
            invokeCompletionHandler()
            return
        }
        // Populate chat content from the payload
        bestAttemptContent.populateChatBody(from: chatContent, using: metadata, contactStore: AppExtensionContext.shared.contactStore)
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
        // We must first rerequest messages and then ack them.

        // We rerequest messages with status = .decryptionError
        dataStore.getChatMessagesToRerequest() { [self] sharedChatMessagesToRerequest in
            sharedChatMessagesToRerequest.forEach{ sharedChatMessage in
                let msgId = sharedChatMessage.id
                if let failedEphemeralKey = sharedChatMessage.ephemeralKey, let serverMsgPb = sharedChatMessage.serverMsgPb {
                    do {
                        let serverMsg = try Server_Msg(serializedData: serverMsgPb)
                        service?.rerequestMessage(serverMsg, failedEphemeralKey: failedEphemeralKey) { result in
                            switch result {
                            case .success(_):
                                DDLogInfo("sendRerequest/success sent rerequest, msgId: \(msgId)")
                                dataStore.updateMessageStatus(for: msgId, status: .rerequesting)
                            case .failure(let error):
                                DDLogError("sendRerequest/failure sending rerequest, msgId: \(msgId), error: \(error)")
                            }
                        }
                    } catch {
                        DDLogError("sendRerequest/Unable to initialize Server_Msg")
                    }
                }
            }
        }

        // We ack messages only that are successfully decrypted or successfully rerequested.
        dataStore.getChatMessagesToAck() { [self] sharedChatMessagesToAck in
            sharedChatMessagesToAck.forEach{ sharedChatMessage in
                let msgId = sharedChatMessage.id
                service?.sendAck(messageId: msgId) { result in
                    let finalStatus: SharedChatMessage.Status
                    switch sharedChatMessage.status {
                    case .received:
                        finalStatus = .acked
                    case .rerequesting:
                        finalStatus = .rerequesting
                    case .acked, .sendError, .sent, .none, .decryptionError:
                        return
                    }
                    switch result {
                    case .success(_):
                        DDLogInfo("sendAck/success sent ack, msgId: \(msgId)")
                        dataStore.updateMessageStatus(for: msgId, status: finalStatus)
                    case .failure(let error):
                        DDLogError("sendAck/failure sending ack, msgId: \(msgId), error: \(error)")
                    }
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
        let (taskAdded, task) = downloadManager.downloadMedia(for: media, feedElementType: .post)
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
            invokeCompletionHandler()
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

        invokeCompletionHandler()
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        DDLogWarn("timeWillExpire")
        service?.disconnectImmediately()
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            DDLogInfo("Invoking completion handler now")
            contentHandler(bestAttemptContent)
        }
    }

}
