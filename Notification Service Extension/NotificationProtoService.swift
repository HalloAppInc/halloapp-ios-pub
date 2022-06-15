//
//  NotificationProtoService.swift
//  Notification Service Extension
//
//  Created by Murali Balusu on 11/13/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import SwiftProtobuf
import UserNotifications
import CallKit
import CoreData

final class NotificationProtoService: ProtoServiceCore {

    private lazy var notificationDataStore = DataStore()
    private lazy var mainDataStore = AppContext.shared.mainDataStore
    private lazy var coreFeedData = AppContext.shared.coreFeedData
    private lazy var coreChatData = AppContext.shared.coreChatData

    private lazy var downloadManager: FeedDownloadManager = {
        let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let downloadManager = FeedDownloadManager(mediaDirectoryURL: tempDirectoryURL)
        downloadManager.delegate = self
        return downloadManager
    }()
    // List of notifications presented: used to update notification content after downloading media.
    private var pendingNotificationContent = [String: UNNotificationContent]()
    private var pendingRetractNotificationIds: [String] = []

    public required init(credentials: Credentials?, passiveMode: Bool = false, automaticallyReconnect: Bool = false, resource: ResourceType = .iphone_nse) {
        super.init(credentials: credentials, passiveMode: passiveMode, automaticallyReconnect: automaticallyReconnect, resource: resource)
        self.cancellableSet.insert(
            didDisconnect.sink { [weak self] in
                self?.downloadManager.suspendMediaDownloads()
                self?.processRetractNotifications()
            })
    }

    override func performOnConnect() {
        super.performOnConnect()
        resendAllPendingAcks()
        uploadLogsToServerIfNecessary()
    }

    override func authenticationFailed(with authResult: Server_AuthResult) {
        super.authenticationFailed(with: authResult)
    }

    private var cancellableSet = Set<AnyCancellable>()
    private let serviceQueue = DispatchQueue(label: "com.halloapp.proto.service", qos: .default)

    private func sendAck(messageID: String) {
        serviceQueue.async {
            self._sendAcks(messageIDs: [messageID])
        }
    }

    /// Should only be called on serviceQueue
    private func _sendAcks(messageIDs: [String]) {
        guard self.isConnected else {
            DDLogInfo("proto/_sendAcks/enqueueing (disconnected) [\(messageIDs.joined(separator: ","))]")
            self.pendingAcks += messageIDs
            return
        }

        let packets: [Server_Packet] = Set(messageIDs).map {
            var ack = Server_Ack()
            ack.id = $0
            var packet = Server_Packet()
            packet.stanza = .ack(ack)
            return packet
        }
        for packet in packets {
            if let data = try? packet.serializedData() {
                DDLogInfo("ProtoService/_sendAcks/\(packet.ack.id)/sending")
                send(data)
            } else {
                DDLogError("ProtoService/_sendAcks/\(packet.ack.id)/error could not serialize packet")
            }
        }
    }

    /// IDs for messages that we need to ack once we've connected. Should only be accessed on serviceQueue.
    private var pendingAcks = [String]()

    private func resendAllPendingAcks() {
        serviceQueue.async {
            guard self.isConnected else {
                DDLogInfo("proto/resendPendingAcks/skipping (disconnected)")
                return
            }
            guard !self.pendingAcks.isEmpty else {
                DDLogInfo("proto/resendPendingAcks/skipping (empty)")
                return
            }
            let acksToSend = self.pendingAcks
            self.pendingAcks.removeAll()
            self._sendAcks(messageIDs: acksToSend)
        }
    }


    override func didReceive(packet: Server_Packet) {
        super.didReceive(packet: packet)

        let requestID = packet.requestID ?? "unknown-id"

        switch packet.stanza {
        case .msg(let msg):
            handleMessage(msg)
        default:
            DDLogError("proto/didReceive/unknown-packet \(requestID)")
        }

    }

    // MARK: Calls

    private func reportIncomingCall(serverMsgPb: Data) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // Adding artificial delay here to finish up sending acks.
            // TODO: adding this to ensure things work - but we should get rid of this.
            self.disconnect()
        }
        // might have to add an artificial delay here to handle cleanup.
        if #available(iOSApplicationExtension 14.5, *) {
            DispatchQueue.main.async {
                let metadataContent = ["nse_content": serverMsgPb.base64EncodedString()]
                CXProvider.reportNewIncomingVoIPPushPayload(["metadata": metadataContent]) { error in
                    if let error = error {
                        DDLogError("NotificationProtoService/reportIncomingCall/failure: \(error)")
                    } else {
                        DDLogInfo("NotificationProtoService/reportIncomingCall/success")
                    }
                }
            }
        } else {
            // Fallback on earlier versions.
            // Test with always sending voip push on ios for versions < 14.5
        }
    }


    // MARK: Message

    private func handleMessage(_ msg: Server_Msg) {
        let ack = { self.sendAck(messageID: msg.id) }
        var hasAckBeenDelegated = false
        defer {
            // Ack any message where we haven't explicitly delegated the ack to someone else
            if !hasAckBeenDelegated {
                ack()
            }
        }

        let serverMsgPb: Data
        do {
            serverMsgPb = try msg.serializedData()
        } catch {
            DDLogError("NotificationMetadata/init/msg - unable to serialize it.")
            return
        }

        switch msg.payload {
        case .requestLogs:
            uploadLogsToServer()
            return
        case .endOfQueue(_):
            return
        case .whisperKeys(let pbKeys):
            if let whisperMessage = WhisperMessage(pbKeys) {
                // If ack fails, main app will ensure not to reset the 1-1 session again for update-whisper messages.
                keyDelegate?.service(self, didReceiveWhisperMessage: whisperMessage)
                didGetNewWhisperMessage.send(whisperMessage)
            } else {
                DDLogError("NotificationProtoService/didReceive/\(msg.id)/error could not read whisper message")
            }
            // Process the message above - We dont store this message to shared-msg-store anymore.
            return
        case .incomingCall(let incomingCall):
            // If incomingCall is not too late then
            // abort everything and just report the call to the main app.
            // else just save and move-on.
            hasAckBeenDelegated = true
            notificationDataStore.saveServerMsg(contentId: msg.id, serverMsgPb: serverMsgPb)
            // Ack the message and then start reporting the call.
            ack()
            if !incomingCall.isTooLate {
                reportIncomingCall(serverMsgPb: serverMsgPb)
            }
            return

        // Handle 1-1 rerequest stanzas.
        case .rerequest(let rerequest):
            let contentID = rerequest.id
            let fromUserID = UserID(msg.fromUid)
            // Check key integrity
            AppContext.shared.keyData.service(self, didReceiveRerequestWithRerequestCount: Int(msg.rerequestCount))
            // Protobuf object will contain a 0 if no one time pre key was used
            let oneTimePreKeyID: Int? = rerequest.oneTimePreKeyID > 0 ? Int(rerequest.oneTimePreKeyID) : nil
            // Reset 1-1 session.
            AppContext.shared.messageCrypter.receivedRerequest(
                RerequestData(
                    identityKey: rerequest.identityKey,
                    signedPreKeyID: Int(rerequest.signedPreKeyID),
                    oneTimePreKeyID: oneTimePreKeyID,
                    sessionSetupEphemeralKey: rerequest.sessionSetupEphemeralKey,
                    messageEphemeralKey: rerequest.messageEphemeralKey),
                from: fromUserID)

            if rerequest.contentType == .chat {
                hasAckBeenDelegated = true
                AppContext.shared.coreChatData.handleRerequest(for: contentID, from: fromUserID, ack: ack)
            } else if rerequest.contentType == .groupHistory {
                hasAckBeenDelegated = true
                AppContext.shared.coreFeedData.handleGroupFeedHistoryRerequest(for: contentID, from: fromUserID, ack: ack)
            }
            return

        // Handle group rerequest stanzas.
        case .groupFeedRerequest(let groupFeedRerequest):
            let contentID = groupFeedRerequest.id
            let fromUserID = UserID(msg.fromUid)

            switch groupFeedRerequest.rerequestType {
            case .payload:
                hasAckBeenDelegated = true
                AppContext.shared.coreFeedData.handleRerequest(for: contentID, contentType: groupFeedRerequest.contentType, from: fromUserID, ack: ack)
            case .senderState:
                hasAckBeenDelegated = true
                AppContext.shared.messageCrypter.resetWhisperSession(for: fromUserID)
                AppContext.shared.coreFeedData.handleRerequest(for: contentID, contentType: groupFeedRerequest.contentType, from: fromUserID, ack: ack)
            case .UNRECOGNIZED(_):
                return
            }

        default:
            break
        }

        // Extract notification related metadata from message if possible.
        // Else, just ack and store the message to process this later.
        guard let metadata = NotificationMetadata(msg: msg),
              !metadata.contentId.isEmpty else {
            DDLogDebug("didReceiveRequest/error missing messageId [\(msg)]")
            // TODO: murali: we need to handle some silent push messages here like: uploadLogs/rerequests/contactHash etc.
            // We need to migrate everything to shared container for some of these. revisit then.
            notificationDataStore.saveServerMsg(contentId: msg.id, serverMsgPb: serverMsgPb)
            return
        }

        switch metadata.contentType {
        case .feedPost:
            guard let postData = metadata.postData(audience: msg.feedItem.post.audience) else {
                DDLogError("didReceiveRequest/error Invalid fields in metadata.")
                return
            }
            hasAckBeenDelegated = true
            mainDataStore.performSeriallyOnBackgroundContext { context in
                if let feedPost = self.coreFeedData.feedPost(with: metadata.contentId, in: context), feedPost.status != .rerequesting {
                    DDLogError("didReceiveRequest/error duplicate feedPost [\(metadata.contentId)]")
                    ack()
                    return
                }
                self.processPostData(postData: postData, status: .received, metadata: metadata, ack: ack)
            }

        case .feedComment:
            guard let commentData = metadata.commentData() else {
                DDLogError("didReceiveRequest/error Invalid fields in metadata.")
                return
            }
            hasAckBeenDelegated = true
            mainDataStore.performSeriallyOnBackgroundContext { context in
                if let feedComment = self.coreFeedData.feedComment(with: metadata.contentId, in: context), feedComment.status != .rerequesting {
                    DDLogError("didReceiveRequest/error duplicate feedComment [\(metadata.contentId)]")
                    ack()
                    return
                }
                self.processCommentData(commentData: commentData, status: .received, metadata: metadata, ack: ack)
            }

        // Separate out groupFeedItems: we need to decrypt them, process and populate content accordingly.
        case .groupFeedPost, .groupFeedComment:
            let contentType: FeedElementType
            if metadata.contentType == .groupFeedPost {
                contentType = .post
            } else {
                contentType = .comment
            }

            hasAckBeenDelegated = true
            mainDataStore.performSeriallyOnBackgroundContext { context in
                if let feedPost = self.coreFeedData.feedPost(with: metadata.contentId, in: context), feedPost.status != .rerequesting {
                    DDLogError("didReceiveRequest/error duplicate groupFeedPost [\(metadata.contentId)]/status: \(feedPost.status)")
                    ack()
                    return
                } else if let feedComment = self.coreFeedData.feedComment(with: metadata.contentId, in: context), feedComment.status != .rerequesting {
                    DDLogError("didReceiveRequest/error duplicate groupFeedComment [\(metadata.contentId)]/status: \(feedComment.status)")
                    ack()
                    return
                }

                // Decrypt and process the payload now
                do {
                    guard let serverGroupFeedItemPb = metadata.serverGroupFeedItemPb else {
                        DDLogError("MetadataError/could not find serverGroupFeedItem stanza, contentId: \(metadata.contentId), contentType: \(metadata.contentType)")
                        ack()
                        return
                    }
                    let serverGroupFeedItem = try Server_GroupFeedItem(serializedData: serverGroupFeedItemPb)
                    DDLogInfo("NotificationExtension/requesting decryptGroupFeedItem \(metadata.contentId)")
                    self.decryptAndProcessGroupFeedItem(contentID: metadata.contentId, contentType: contentType, item: serverGroupFeedItem, metadata: metadata, ack: ack)
                } catch {
                    DDLogError("NotificationExtension/ChatMessage/Failed serverChatStanzaStr: \(String(describing: metadata.serverChatStanzaPb)), error: \(error)")
                }
            }

        case .chatMessage:
            let messageId = metadata.messageId
            // Check if message has already been received and decrypted successfully.
            // If yes - then dismiss notification, else continue processing.
            hasAckBeenDelegated = true
            mainDataStore.performSeriallyOnBackgroundContext { context in
                if let chatMessage = self.coreChatData.chatMessage(with: messageId, in: context), chatMessage.incomingStatus != .rerequesting {
                    DDLogError("didReceiveRequest/error duplicate message ID that was already decrypted[\(messageId)]")
                    ack()
                    return
                }

                do {
                    guard let serverChatStanzaPb = metadata.serverChatStanzaPb else {
                        DDLogError("MetadataError/could not find server_chat stanza, contentId: \(metadata.contentId), contentType: \(metadata.contentType)")
                        ack()
                        return
                    }
                    let serverChatStanza = try Server_ChatStanza(serializedData: serverChatStanzaPb)
                    DDLogInfo("NotificationExtension/requesting decryptChat \(metadata.contentId)")
                    // this function acks and sends rerequests accordingly.
                    self.decryptAndProcessChat(messageId: messageId, serverChatStanza: serverChatStanza, metadata: metadata)
                } catch {
                    DDLogError("NotificationExtension/ChatMessage/Failed serverChatStanzaStr: \(String(describing: metadata.serverChatStanzaPb)), error: \(error)")
                }
            }

        case .newInvitee, .newFriend, .newContact, .groupAdd:
            // save server message stanzas to process for these notifications.
            presentNotification(for: metadata)
            notificationDataStore.saveServerMsg(notificationMetadata: metadata)

        case .feedPostRetract, .groupFeedPostRetract:
            hasAckBeenDelegated = true
            let postID = metadata.contentId
            // removeNotification if available.
            removeNotification(id: metadata.contentId)

            let completion = {
                ack()
                // This could be a moment - so try and update moment notifications.
                // TODO: murali: we could try to improve this to run only on moments.
                self.updateMomentNotifications()
            }

            // Try and delete the content.
            mainDataStore.performSeriallyOnBackgroundContext { managedObjectContext in
                guard let feedPost = AppContext.shared.coreFeedData.feedPost(with: postID, in: managedObjectContext) else {
                    DDLogError("NotificationExtension/retract-post/error Missing post. [\(postID)]")
                    completion()
                    return
                }

                guard feedPost.status != .retracted  else {
                    DDLogError("NotificationExtension/retract-post/error Already retracted. [\(postID)]")
                    completion()
                    return
                }
                DDLogInfo("NotificationExtension/retract-post [\(postID)]/begin")

                // 1. Delete media.
                feedPost.media?.forEach { mediaItem in
                    self.cancelDownloadAndDeleteMedia(mediaItem: mediaItem)
                }

                // 2. Delete comments.
                feedPost.comments?.forEach { comment in
                    // Delete media if any.
                    comment.media?.forEach { mediaItem in
                        self.cancelDownloadAndDeleteMedia(mediaItem: mediaItem)
                    }
                    comment.linkPreviews?.forEach { linkPreview in
                        linkPreview.media?.forEach { mediaItem in
                            self.cancelDownloadAndDeleteMedia(mediaItem: mediaItem)
                        }
                    }
                    // TODO: it would be better to leave a tombstone and avoid using this everywhere else.
                    managedObjectContext.delete(comment)
                }

                // 3. Delete all notifications for this post.
                let notifications = AppContext.shared.coreFeedData.notifications(for: postID, in: managedObjectContext)
                notifications.forEach { managedObjectContext.delete($0)}

                // 4. Reset post data and mark post as deleted.
                feedPost.rawText = nil
                feedPost.status = .retracted

                if feedPost.isMoment {
                    // make the prompt card appear the top of the feed
                    AppContext.shared.coreFeedData.resetMomentPromptTimestamp()
                }

                if let groupID = feedPost.groupID,
                   let thread = AppContext.shared.mainDataStore.groupThread(for: groupID, in: managedObjectContext),
                   thread.lastFeedId == postID {
                    thread.lastFeedStatus = .retracted
                }

                self.mainDataStore.save(managedObjectContext)
                DDLogInfo("NotificationExtension/retract-post [\(postID)]/done")
                completion()
            }

        case .feedCommentRetract, .groupFeedCommentRetract:
            hasAckBeenDelegated = true
            let commentID = metadata.contentId
            // removeNotification if available.
            removeNotification(id: metadata.contentId)

            let completion = {
                ack()
            }

            // Try and delete the content.
            mainDataStore.performSeriallyOnBackgroundContext { managedObjectContext in
                guard let feedComment = AppContext.shared.coreFeedData.feedComment(with: commentID, in: managedObjectContext) else {
                    DDLogError("NotificationExtension/retract-comment/error Missing comment. [\(commentID)]")
                    completion()
                    return
                }
                guard feedComment.status != .retracted else {
                    DDLogError("NotificationExtension/retract-comment/error Already retracted. [\(commentID)]")
                    completion()
                    return
                }
                DDLogInfo("NotificationExtension/retract-comment [\(commentID)]")

                // 1. Reset comment text and mark comment as deleted.
                feedComment.rawText = ""
                feedComment.status = .retracted

                // 2. Delete comment media
                feedComment.media?.forEach { mediaItem in
                    self.cancelDownloadAndDeleteMedia(mediaItem: mediaItem)
                }
                feedComment.linkPreviews?.forEach { linkPreview in
                    linkPreview.media?.forEach { mediaItem in
                        self.cancelDownloadAndDeleteMedia(mediaItem: mediaItem)
                    }
                }

                // 3. Reset comment text copied over to notifications.
                let notifications = AppContext.shared.coreFeedData.notifications(for: feedComment.post.id, commentId: feedComment.id, in: managedObjectContext)
                notifications.forEach { (notification) in
                    notification.event = .retractedComment
                    notification.rawText = nil
                }
                self.mainDataStore.save(managedObjectContext)
                DDLogInfo("NotificationExtension/retract-comment [\(commentID)]/done")
                completion()
            }

        case .chatMessageRetract, .groupChatMessageRetract:
            // removeNotification if available.
            removeNotification(id: metadata.contentId)
            // save these messages to be processed by the main app.
            notificationDataStore.saveServerMsg(contentId: msg.id, serverMsgPb: serverMsgPb)

        case .groupChatMessage, .chatRerequest, .missedAudioCall, .missedVideoCall:
            notificationDataStore.saveServerMsg(contentId: msg.id, serverMsgPb: serverMsgPb)

        }
    }

    private func cancelDownloadAndDeleteMedia(mediaItem: CommonMedia) {
        DDLogInfo("FeedData/deleteMedia/id: \(mediaItem.id)")
        if let currentTask = self.downloadManager.currentTask(for: mediaItem) {
            DDLogInfo("FeedData/deleteMedia/cancelTask/task: \(currentTask.id)")
            currentTask.downloadRequest?.cancel(producingResumeData : false)
        }
        AppContext.shared.coreFeedData.deleteMedia(mediaItem: mediaItem)
    }

    // MARK: Handle Post or Comment content.

    private func processPostData(postData: PostData?, status: SharedFeedPost.Status, metadata: NotificationMetadata, ack: @escaping () -> ()) {
        guard let postData = postData else {
            DDLogError("NotificationExtension/processPostDataAndInvokeHandler/failed to get postData, contentId: \(metadata.contentId)")
            return
        }
        self.coreFeedData.savePostData(postData: postData, in: metadata.groupId, hasBeenProcessed: false) { result in
            switch result {
            case .success:
                DDLogInfo("NotificationExtension/processPostData/success saving post [\(postData.id)]")
                ack()
                // Download media and then present the notification.
                self.mainDataStore.performSeriallyOnBackgroundContext { context in
                    guard let post = self.coreFeedData.feedPost(with: postData.id, in: context) else {
                        return
                    }

                    if let firstOrderedMediaItem = post.orderedMedia.first,
                       let firstMediaItem = post.media?.filter({ $0.id == firstOrderedMediaItem.id }).first {
                        // Present notification immediately if the post is moment.
                        // Continue downloading media in the background.
                        if post.isMoment {
                            self.updateMomentNotifications(checkForDuplicates: true)
                        } else {
                            _ = self.extractAndHoldNotificationContent(for: metadata, using: postData)
                        }
                        let downloadTask = self.startDownloading(media: firstMediaItem)
                        downloadTask?.feedMediaObjectId = firstMediaItem.objectID
                    }  else if let firstMediaItem = post.linkPreviews?.first?.media?.first {
                        _ = self.extractAndHoldNotificationContent(for: metadata, using: postData)
                        let downloadTask = self.startDownloading(media: firstMediaItem)
                        downloadTask?.feedMediaObjectId = firstMediaItem.objectID
                    } else {
                        let notificationContent = self.extractAndHoldNotificationContent(for: metadata, using: postData)
                        self.presentNotification(for: metadata.contentId, with: notificationContent)
                    }
                }
            case .failure(let error):
                DDLogError("NotificationExtension/processPostData/error saving post [\(postData.id)]/error: \(error)")
            }
        }
    }

    private func processCommentData(commentData: CommentData?, status: SharedFeedComment.Status, metadata: NotificationMetadata, ack: @escaping () -> ()) {
        guard let commentData = commentData else {
            DDLogError("NotificationExtension/processCommentData/failed to get commentData, contentId: \(metadata.contentId)")
            return
        }
        self.coreFeedData.saveCommentData(commentData: commentData, in: metadata.groupId, hasBeenProcessed: false) { result in
            switch result {
            case .success:
                DDLogInfo("NotificationExtension/processCommentData/success saving comment [\(commentData.id)]")
                ack()
                self.presentCommentNotification(for: metadata, using: commentData)
            case .failure(let error):
                DDLogError("NotificationExtension/processCommentData/error saving comment [\(commentData.id)]/error: \(error)")
            }
        }
    }

    // MARK: Handle GroupFeed Items.

    // Decrypt, process and ack group feed items
    private func decryptAndProcessGroupFeedItem(contentID: String, contentType: FeedElementType,
                                                item: Server_GroupFeedItem, metadata: NotificationMetadata, ack: @escaping () -> ()) {
        decryptGroupFeedPayload(for: item, in: item.gid) { content, groupDecryptionFailure in
            if let content = content, groupDecryptionFailure == nil {
                DDLogError("NotificationExtension/decryptAndProcessGroupFeedItem/contentID/\(contentID)/success")
                switch content {
                case .newItems(let newItems):
                    guard let newItem = newItems.first, newItems.count == 1 else {
                        DDLogError("NotificationExtension/decryptAndProcessGroupFeedItem/contentID/\(contentID)/too many items - invalid decrypted payload.")
                        ack()
                        return
                    }
                    switch newItem {
                    case .post(let postData):
                        self.processPostData(postData: postData, status: .received, metadata: metadata, ack: ack)
                    case .comment(let commentData, _):
                        self.processCommentData(commentData: commentData, status: .received, metadata: metadata, ack: ack)
                    }
                case .retracts(_):
                    // This is not possible - since these are never encrypted in the first place as of now.
                    ack()
                    return
                }
            } else {
                DDLogError("NotificationExtension/decryptAndProcessGroupFeedItem/contentID/\(contentID)/failure \(groupDecryptionFailure.debugDescription)")
                if let groupId = metadata.groupId,
                   let decryptionFailure = groupDecryptionFailure,
                   let rerequestContentType = item.contentType {
                    // Use serverProp value to decide whether to fallback to plainTextContent.
                    let fallback = ServerProperties.useClearTextGroupFeedContent
                    self.rerequestGroupFeedItemIfNecessary(id: contentID, groupID: groupId, contentType: rerequestContentType, failure: decryptionFailure) { result in
                        switch result {
                        case .success: break
                        case .failure(let error):
                            DDLogError("NotificationExtension/decryptAndProcessGroupFeedItem/contentID/\(contentID)/failed rerequest: \(error)")
                        }
                        switch contentType {
                        case .post:
                            self.processPostData(postData: metadata.postData(status: .rerequesting, usePlainTextPayload: fallback, audience: item.post.audience), status: .decryptionError, metadata: metadata, ack: ack)
                        case .comment:
                            self.processCommentData(commentData: metadata.commentData(status: .rerequesting, usePlainTextPayload: fallback), status: .decryptionError, metadata: metadata, ack: ack)
                        }
                    }
                }
            }
            let contentTypeValue: GroupDecryptionReportContentType = {
                switch contentType {
                case .post:
                    return .post
                case .comment:
                    return .comment
                }
            }()
            self.reportGroupDecryptionResult(
                error: groupDecryptionFailure?.error,
                contentID: contentID,
                contentType: contentTypeValue,
                groupID: item.gid,
                timestamp: Date(),
                sender: UserAgent(string: item.senderClientVersion),
                rerequestCount: Int(metadata.rerequestCount))
        }
    }

    // MARK: Handle Chat Messages.

    // Decrypt, process, save, rerequest and ack chats!
    private func decryptAndProcessChat(messageId: String, serverChatStanza: Server_ChatStanza, metadata: NotificationMetadata) {
        let fromUserID = metadata.fromId
        decryptChat(serverChatStanza, from: fromUserID) { (content, context, decryptionFailure) in
            if let content = content, let context = context {
                DDLogInfo("NotificationExtension/decryptChat/successful/messageId \(messageId)")
                let chatMessage = XMPPChatMessage(content: content,
                                                  context: context,
                                                  timestamp: serverChatStanza.timestamp,
                                                  from: fromUserID,
                                                  to: AppContext.shared.userData.userId,
                                                  id: messageId,
                                                  retryCount: metadata.retryCount,
                                                  rerequestCount: metadata.rerequestCount)
                self.coreChatData.saveChatMessage(chatMessage: .decrypted(chatMessage), hasBeenProcessed: false) { result in
                    self.incrementApplicationIconBadgeNumber()
                    DDLogInfo("NotificationExtension/decryptChat/success/save message \(messageId)/result: \(result)")
                }
                // Check and copy moment media to preview media for moment replies in notifications.
                self.copyQuotedMomentForNotificationAttachment(chatMessage: chatMessage)
            } else {
                DDLogError("NotificationExtension/decryptChat/failed decryption, error: \(String(describing: decryptionFailure))")
                let tombstone = ChatMessageTombstone(id: messageId,
                                                     from: fromUserID,
                                                     to: AppContext.shared.userData.userId,
                                                     timestamp: Date(timeIntervalSince1970: TimeInterval(serverChatStanza.timestamp)))
                self.coreChatData.saveChatMessage(chatMessage: .notDecrypted(tombstone), hasBeenProcessed: false) { result in
                    DDLogInfo("NotificationExtension/decryptChat/failed/save tombstone \(messageId)/result: \(result)")
                }
            }

            if let senderClientVersion = metadata.senderClientVersion {
                DDLogInfo("NotificationExtension/decryptAndProcessChat/report result \(String(describing: decryptionFailure?.error))/ msg: \(messageId)")
                self.reportDecryptionResult(
                    error: decryptionFailure?.error,
                    messageID: messageId,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(serverChatStanza.timestamp)),
                    sender: UserAgent(string: senderClientVersion),
                    rerequestCount: Int(metadata.rerequestCount),
                    contentType: .chat)
            } else {
                DDLogError("NotificationExtension/decryptAndProcessChat/could not report result, messageId: \(messageId)")
            }
            self.processChat(chatContent: content, failure: decryptionFailure, metadata: metadata)
        }
    }

    private func copyQuotedMomentForNotificationAttachment(chatMessage: XMPPChatMessage) {
        // Copy quoted media content for notification attachment only for moments right now.
        // We will copy the file to the nse temporary directory - so this will cleaned up automatically by apple.
        self.mainDataStore.performSeriallyOnBackgroundContext { managedObjectContext in
            if let feedPostID = chatMessage.context.feedPostID,
               let feedPost = AppContext.shared.coreFeedData.feedPost(with: feedPostID, in: managedObjectContext),
               feedPost.isMoment,
               let mediaItem = feedPost.media?.first(where: { $0.order == chatMessage.context.feedPostMediaIndex }),
               let relativeFilePath = mediaItem.relativeFilePath {
                let sourceURL = AppContext.commonMediaStoreURL.appendingPathComponent(relativeFilePath, isDirectory: false)
                let destinationURL = self.downloadManager.fileURL(forRelativeFilePath: relativeFilePath)
                do {
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                } catch {
                    DDLogError("NotificationExtension/media/failed-to-copy/error \(error)")
                    return
                }
            }
        }
    }

    private func incrementApplicationIconBadgeNumber() {
        // Update application badge number.
        let badgeNum = AppExtensionContext.shared.applicationIconBadgeNumber
        let applicationIconBadgeNumber = badgeNum == -1 ? 1 : badgeNum + 1
        AppExtensionContext.shared.applicationIconBadgeNumber = applicationIconBadgeNumber
    }

    // Process Chats - ack/rerequest/download media if necessary.
    private func processChat(chatContent: ChatContent?, failure: DecryptionFailure?, metadata: NotificationMetadata) {
        let messageId = metadata.messageId

        if let failure = failure {
            self.logChatPushDecryptionError(with: metadata, error: failure.error)
            // We must first rerequest messages and then ack them.
            if let failedEphemeralKey = failure.ephemeralKey {
                let fromUserID = metadata.fromId
                rerequestMessage(messageId, senderID: fromUserID, failedEphemeralKey: failedEphemeralKey, contentType: .chat) { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .success(_):
                        DDLogInfo("NotificationExtension/processChat/sendRerequest/success sent rerequest, messageId: \(messageId)")
                        self.sendAck(messageID: messageId)
                    case .failure(let error):
                        DDLogError("NotificationExtension/processChat/sendRerequest/failure sending rerequest, messageId: \(messageId), error: \(error)")
                    }
                }
            } else {
                DDLogError("NotificationExtension/processChat/error: missing rerequest data, messageId: \(messageId)")
                sendAck(messageID: messageId)
            }
        } else {
            sendAck(messageID: messageId)
        }

        // If we failed to get decrypted chat content successfully - then just return!
        guard let chatContent = chatContent else {
            DDLogError("DecryptionError/decryptChat/failed to get chat content, messageId: \(messageId)")
            return
        }

        mainDataStore.performSeriallyOnBackgroundContext { context in
            guard let chatMessage = self.coreChatData.chatMessage(with: messageId, in: context) else {
                return
            }
            let notificationContent = self.extractAndHoldNotificationContent(for: metadata, using: chatContent)
            if let firstOrderedMediaItem = chatMessage.orderedMedia.first,
               let firstMediaItem = chatMessage.media?.filter({ $0.id == firstOrderedMediaItem.id }).first {
                let downloadTask = self.startDownloading(media: firstMediaItem)
                downloadTask?.feedMediaObjectId = firstMediaItem.objectID
            } else if let firstMediaItem = chatMessage.linkPreviews?.first?.media?.first {
                let downloadTask = self.startDownloading(media: firstMediaItem)
                downloadTask?.feedMediaObjectId = firstMediaItem.objectID
            } else if let quotedMediaItem = chatMessage.quoted?.media?.first,
                      quotedMediaItem.mediaDirectory == .commonMedia,
                      let relativeFilePath = quotedMediaItem.relativeFilePath {
                let attachment: UNNotificationAttachment
                do {
                    let fileURL = self.downloadManager.fileURL(forRelativeFilePath: relativeFilePath)
                    attachment = try UNNotificationAttachment(identifier: quotedMediaItem.id, url: fileURL, options: nil)
                    self.presentNotification(for: metadata.contentId, with: notificationContent, using: [attachment])
                } catch {
                    DDLogError("NotificationExtension/media/attachment-create/error \(error)")
                    self.presentNotification(for: metadata.contentId, with: notificationContent)
                }
            } else {
                self.presentNotification(for: metadata.contentId, with: notificationContent)
            }
        }
    }

    private func logChatPushDecryptionError(with metadata: NotificationMetadata, error: DecryptionError?) {
        let reportUserInfo = [
            "userId": AppExtensionContext.shared.userData.userId,
            "msgId": metadata.messageId,
            "error": "ChatPushDecryptionError",
            "reason": error?.rawValue ?? "unknownError"
        ]
        let customError = NSError.init(domain: "ChatPushDecryptionErrorTest", code: 1004, userInfo: reportUserInfo)
        AppExtensionContext.shared.errorLogger?.logError(customError)
    }

    // Download media items from home-feed post/group-feed post/chat messages.
    // Must be called only after presenting the notification to the user.
    private func downloadRemainingMedia(for contentID: String, with content: UNNotificationContent) {
        let contentTypeRaw = content.userInfo[NotificationMetadata.contentTypeKey] as? String ?? "unknown"
        switch NotificationContentType(rawValue: contentTypeRaw) {
        case .feedPost, .groupFeedPost:
            mainDataStore.performSeriallyOnBackgroundContext { context in
                guard let post = self.coreFeedData.feedPost(with: contentID, in: context) else {
                    return
                }
                post.media?.forEach { media in
                    if media.status != .downloaded {
                        let downloadTask = self.startDownloading(media: media)
                        downloadTask?.feedMediaObjectId = media.objectID
                    }
                }

                post.linkPreviews?.forEach { linkPreview in
                    linkPreview.media?.forEach { media in
                        if media.status != .downloaded {
                            let downloadTask = self.startDownloading(media: media)
                            downloadTask?.feedMediaObjectId = media.objectID
                        }
                    }
                }
            }
        case .chatMessage:
            mainDataStore.performSeriallyOnBackgroundContext { context in
                guard let chatMessage = self.coreChatData.chatMessage(with: contentID, in: context) else {
                    return
                }
                chatMessage.media?.forEach { media in
                    if media.status != .downloaded {
                        let downloadTask = self.startDownloading(media: media)
                        downloadTask?.feedMediaObjectId = media.objectID
                    }
                }

                chatMessage.linkPreviews?.forEach { linkPreview in
                    linkPreview.media?.forEach { media in
                        if media.status != .downloaded {
                            let downloadTask = self.startDownloading(media: media)
                            downloadTask?.feedMediaObjectId = media.objectID
                        }
                    }
                }
            }
        default:
            break
        }
    }

    // MARK: Present or Update Notifications

    private func extractAndHoldNotificationContent(for metadata: NotificationMetadata, using postData: PostData) -> UNMutableNotificationContent {
        let notificationContent = UNMutableNotificationContent()
        notificationContent.populate(from: metadata, contactStore: AppExtensionContext.shared.contactStore)
        notificationContent.populateFeedPostBody(from: postData, using: metadata, contactStore: AppExtensionContext.shared.contactStore)
        notificationContent.badge = AppExtensionContext.shared.applicationIconBadgeNumber as NSNumber?
        notificationContent.sound = UNNotificationSound.default
        notificationContent.userInfo[NotificationMetadata.contentTypeKey] = metadata.contentType.rawValue
        notificationContent.userInfo[NotificationMetadata.userDefaultsKeyRawData] = metadata.rawData
        self.pendingNotificationContent[metadata.contentId] = notificationContent
        return notificationContent
    }

    private func extractAndHoldNotificationContent(for metadata: NotificationMetadata, using chatContent: ChatContent) -> UNMutableNotificationContent {
        let notificationContent = UNMutableNotificationContent()
        notificationContent.populate(from: metadata, contactStore: AppExtensionContext.shared.contactStore)
        notificationContent.populateChatBody(from: chatContent, using: metadata, contactStore: AppExtensionContext.shared.contactStore)
        notificationContent.badge = AppExtensionContext.shared.applicationIconBadgeNumber as NSNumber?
        notificationContent.sound = UNNotificationSound.default
        notificationContent.userInfo[NotificationMetadata.contentTypeKey] = metadata.contentType.rawValue
        notificationContent.userInfo[NotificationMetadata.userDefaultsKeyRawData] = metadata.rawData
        self.pendingNotificationContent[metadata.contentId] = notificationContent
        return notificationContent
    }

    // Used to present contact/inviter notifications.
    private func presentNotification(for metadata: NotificationMetadata) {
        runIfNotificationWasNotPresented(for: metadata.contentId) { [self] in
            DDLogDebug("ProtoService/presentNotification")
            let notificationContent = UNMutableNotificationContent()
            notificationContent.populate(from: metadata, contactStore: AppExtensionContext.shared.contactStore)
            notificationContent.badge = AppExtensionContext.shared.applicationIconBadgeNumber as NSNumber?
            notificationContent.sound = UNNotificationSound.default
            notificationContent.userInfo[NotificationMetadata.userDefaultsKeyRawData] = metadata.rawData
            self.pendingNotificationContent[metadata.contentId] = notificationContent

            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.add(UNNotificationRequest(identifier: metadata.contentId, content: notificationContent, trigger: nil))
            recordPresentingNotification(for: metadata.contentId, type: metadata.contentType.rawValue)
        }
    }

    // Used to present comment notifications.
    private func presentCommentNotification(for metadata: NotificationMetadata, using commentData: CommentData) {
        // Notify important comments.
        let isImportantComment = metadata.messageTypeRawValue == Server_Msg.TypeEnum.headline.rawValue

        // Notify comments with mentions.
        let isUserMentioned = commentData.orderedMentions.contains(where: { mention in
            mention.userID == AppContext.shared.userData.userId
        })

        // Dont notify for comments from blocked users.
        let isUserBlocked = AppContext.shared.privacySettings.blocked.userIds.contains(metadata.fromId)

        // Notify comments from contacts on group posts.
        var isKnownPublisher = false
        AppContext.shared.contactStore.performOnBackgroundContextAndWait { managedObjectContext in
            isKnownPublisher = AppContext.shared.contactStore.isContactInAddressBook(userId: commentData.userId, in: managedObjectContext)
        }

        let isGroupComment = metadata.groupId != nil
        let isGroupCommentFromContact = ServerProperties.isGroupCommentNotificationsEnabled  && isGroupComment && isKnownPublisher

        // Notify comments from group posts that user commented on.
        // This is a hack until we move the data to the mainDataStore.
        let interestedPosts = AppContext.shared.userDefaults.value(forKey: AppContext.commentedGroupPostsKey) as? [FeedPostID] ?? []
        let isGroupCommentOnInterestedPost = Set(interestedPosts).contains(commentData.feedPostId)

        let isHomeFeedCommentFromContact = ServerProperties.isHomeCommentNotificationsEnabled && isKnownPublisher

        guard !isUserBlocked else {
            DDLogInfo("ProtoService/CommentNotification - skip comment from blocked user.")
            return
        }

        if isImportantComment || isUserMentioned || isGroupCommentFromContact || isGroupCommentOnInterestedPost || isHomeFeedCommentFromContact {
            runIfNotificationWasNotPresented(for: metadata.contentId) { [self] in
                guard NotificationSettings.isCommentsEnabled else {
                    DDLogDebug("ProtoService/CommentNotification - skip due to userPreferences")
                    return
                }
                DDLogDebug("ProtoService/presentCommentNotification")
                let notificationContent = UNMutableNotificationContent()
                notificationContent.populate(from: metadata, contactStore: AppExtensionContext.shared.contactStore)
                notificationContent.populateFeedCommentBody(from: commentData, using: metadata, contactStore: AppExtensionContext.shared.contactStore)
                notificationContent.badge = AppExtensionContext.shared.applicationIconBadgeNumber as NSNumber?
                notificationContent.sound = UNNotificationSound.default
                notificationContent.userInfo[NotificationMetadata.userDefaultsKeyRawData] = metadata.rawData
                self.pendingNotificationContent[metadata.contentId] = notificationContent

                let notificationCenter = UNUserNotificationCenter.current()
                notificationCenter.add(UNNotificationRequest(identifier: metadata.contentId, content: notificationContent, trigger: nil))
                recordPresentingNotification(for: metadata.contentId, type: metadata.contentType.rawValue)
            }
        } else {
            DDLogInfo("ProtoService/Ignoring push for this comment")
        }
    }

    private func updateMomentNotifications(checkForDuplicates: Bool = false) {
        DDLogInfo("ProtoService/updateMomentNotifications")
        mainDataStore.performSeriallyOnBackgroundContext { managedObjectContext in
            let moments = AppContext.shared.coreFeedData.feedPosts(predicate:
                                                                    NSPredicate(format: "isMoment = YES && statusValue == %d",
                                                                                FeedPost.Status.incoming.rawValue),
                                                                   in: managedObjectContext)
            DDLogInfo("ProtoService/updateMomentNotifications/count: \(moments.count)")
            guard moments.count > 0,
                  let firstMoment = moments.first,
                  let lastMoment = moments.last else {
                return
            }
            do {
                // We use the oldest notification identifier to replace that notification.
                // But the metadata in the notification refers to the last moment - so that tapping takes us to the latest moment.
                let notificationIdentifier = firstMoment.id
                let metadata = NotificationMetadata(contentId: lastMoment.id,
                                                    contentType: .feedPost,
                                                    fromId: lastMoment.userId,
                                                    timestamp: lastMoment.timestamp,
                                                    data: try lastMoment.postData.clientContainer.serializedData(),
                                                    messageId: nil,
                                                    pushName: nil)
                metadata.isMoment = true
                metadata.momentCount = moments.count
                let momentsPostData = moments.map { $0.postData }
                let content = NotificationMetadata.extractMomentNotification(for: metadata, using: momentsPostData)

                // Dont update the notification if nothing changed about moments.
                let notificationCenter = UNUserNotificationCenter.current()
                notificationCenter.getMomentNotification { oldMetadata in
                    // Check count and from userId for moments.
                    if oldMetadata?.momentCount == metadata.momentCount,
                       oldMetadata?.fromId == metadata.fromId {
                        DDLogInfo("ProtoService/updateMomentNotifications/skip - since nothing changed")
                        return
                    }
                    // We only check for duplicates only in the case of first moment - that is when we need a sound too.
                    // We avoid checking in all other cases including retractions.
                    let shouldCheckForDuplicates: Bool = (moments.count < 2) && checkForDuplicates
                    // Overwrite duplicates if any.
                    self.presentNotification(for: notificationIdentifier, with: content, checkForDuplicates: shouldCheckForDuplicates)
                }
            } catch {
                DDLogError("ProtoService/updateMomentNotifications/error: \(error)")
            }
        }
    }

    // Used to present post/chat notifications.
    // Presents notification and downloads remaining content if any.
    private func presentNotification(for identifier: String,
                                     with content: UNNotificationContent,
                                     using attachments: [UNNotificationAttachment] = [],
                                     checkForDuplicates: Bool = true) {
        let contentTypeRaw = content.userInfo[NotificationMetadata.contentTypeKey] as? String ?? "unknown"
        switch NotificationContentType(rawValue: contentTypeRaw) {
        case .feedPost, .groupFeedPost:
            guard NotificationSettings.isPostsEnabled else {
                DDLogInfo("ProtoService/PostNotification - skip due to userPreferences")
                return
            }
        default:
            break
        }

        // Skip notification from blocked users.
        guard let metadataRaw = content.userInfo[NotificationMetadata.userDefaultsKeyRawData] as? Data,
              let metadata = NotificationMetadata.load(from: metadataRaw),
              !AppContext.shared.privacySettings.blocked.userIds.contains(metadata.fromId) else {
            DDLogInfo("ProtoService/PostNotification - skip notification from blocker user or metadata missing")
            return
        }
        // Disable sound if we dont do duplicate checks.
        let sound = checkForDuplicates ? UNNotificationSound.default : nil
        // Completion block to present the notification.
        let completion: () -> Void = {
            DDLogInfo("ProtoService/presentNotification/\(identifier)")
            let notificationContent = UNMutableNotificationContent()
            notificationContent.title = content.title
            notificationContent.subtitle = content.subtitle
            notificationContent.body = content.body
            notificationContent.attachments = attachments
            notificationContent.userInfo = content.userInfo
            notificationContent.sound = sound
            notificationContent.badge = AppExtensionContext.shared.applicationIconBadgeNumber as NSNumber?

            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.add(UNNotificationRequest(identifier: identifier, content: notificationContent, trigger: nil))
            self.recordPresentingNotification(for: identifier, type: contentTypeRaw)

            // Start downloading remaining media only after presenting the notification.
            self.downloadRemainingMedia(for: identifier, with: content)
        }
        if checkForDuplicates {
            runIfNotificationWasNotPresented(for: identifier, completion: completion)
        } else {
            completion()
        }
    }

    private func removeNotification(id identifier: String) {
        // Try and remove notification immediately if possible.
        DispatchQueue.main.async {
            DDLogInfo("ProtoService/removeNotification/id: \(identifier)")
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        }
        // Try to remove notifications again after a couple of seconds.
        // Allows us more time to remove any notifications that had media to download.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            DDLogInfo("ProtoService/removeNotification/id: \(identifier)")
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        }
        // eitherway store it to clean it up further at the end.
        pendingRetractNotificationIds.append(identifier)
    }

    private func processRetractNotifications() {
        DDLogInfo("ProtoService/processRetractNotifications")
        pendingRetractNotificationIds.forEach { contentId in
            removeNotification(id: contentId)
        }
    }
}

// MARK: Check and Record push notifications

extension NotificationProtoService {

    public func runIfNotificationWasNotPresented(for contentId: String, completion: @escaping () -> Void) {
        AppContext.shared.notificationStore.runIfNotificationWasNotPresented(for: contentId, completion: completion)
    }

    public func recordPresentingNotification(for contentId: String, type: String) {
        AppContext.shared.notificationStore.save(id: contentId, type: type)
    }
}

// MARK: Downloading media items

extension NotificationProtoService: FeedDownloadManagerDelegate {

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
        DDLogInfo("ProtoService/media/download/finished \(task.id)")

        // Copy downloaded media to shared file storage and update db with path to the media.
        if let objectId = task.feedMediaObjectId,
           let feedMediaItem = try? mainDataStore.commonMediaObject(forObjectId: objectId) {

            if let error = task.error {
                DDLogError("ProtoService/media/download/error \(error)")
                // Try to present something to the user.
                if let contentId = feedMediaItem.contentOwnerID,
                   let content = pendingNotificationContent[contentId] {
                    presentNotification(for: contentId, with: content, using: [])
                }
                return
            }

            let fileURL = downloadManager.fileURL(forRelativeFilePath: task.decryptedFilePath!)
            // Attach media to notification.
            let attachment: UNNotificationAttachment
            do {
                attachment = try UNNotificationAttachment(identifier: task.id, url: fileURL, options: nil)
            } catch {
                DDLogError("ProtoService/media/attachment-create/error \(error)")
                // Try to present something to the user.
                if let contentId = feedMediaItem.contentOwnerID,
                   let content = pendingNotificationContent[contentId] {
                    presentNotification(for: contentId, with: content, using: [])
                }
                return
            }

            let filename = fileURL.deletingPathExtension().lastPathComponent
            let relativeFilePath = SharedDataStore.relativeFilePath(forFilename: filename, mediaType: feedMediaItem.type)
            do {
                // Try and include this media item in the notification now.
                if let contentId = feedMediaItem.contentOwnerID,
                   let content = pendingNotificationContent[contentId] {
                    presentNotification(for: contentId, with: content, using: [attachment])
                }
                let destinationUrl = notificationDataStore.fileURL(forRelativeFilePath: relativeFilePath)
                SharedDataStore.preparePathForWriting(destinationUrl)

                try FileManager.default.copyItem(at: fileURL, to: destinationUrl)
                DDLogDebug("ProtoService/attach-media/copied [\(fileURL)] to [\(destinationUrl)]")

                feedMediaItem.relativeFilePath = relativeFilePath
                feedMediaItem.mediaDirectory = .commonMedia
                feedMediaItem.status = task.isPartialChunkedDownload ? .downloadedPartial : .downloaded
                if task.isPartialChunkedDownload, let chunkSet = task.downloadedChunkSet {
                    DDLogDebug("ProtoService/media/\(task.id)/feedDownloadManager chunkSet=[\(chunkSet)]")
                    feedMediaItem.chunkSet = chunkSet.data
                }
                mainDataStore.save(feedMediaItem.managedObjectContext!)
            } catch {
                DDLogError("ProtoService/media/copy-media/error [\(error)]")
            }
        }
    }
}
