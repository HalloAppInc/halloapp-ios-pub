//
//  ProtoServiceCore.swift
//  Core
//
//  Created by Garrett on 8/25/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//
import CocoaLumberjackSwift
import Combine
import CoreCommon
import Foundation

let userDefaultsKeyForRequestLogs = "serverRequestedLogs"

open class ProtoServiceCore: ProtoServiceCoreCommon {

    private enum ProcessingState {
        case ready
        case busy
    }

    public let didGetNewWhisperMessage = PassthroughSubject<WhisperMessage, Never>()

    private var pendingWorkItems = [GroupID: [DispatchWorkItem]]()
    private var groupStates = [GroupID: ProcessingState]()

    private var pendingHomeWorkItems = [HomeSessionType: [DispatchWorkItem]]()
    private var homeStates = [HomeSessionType: ProcessingState]()

    private var isLogUploadInProgress: Bool = false

    private var uploadLogsTimer: DispatchSourceTimer?

    private  lazy var dateTimeFormatterMonthDayTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.setLocalizedDateFormatFromTemplate("jdMMMHHmm")
        return dateFormatter
    }()

    private func startUploadLogsTimer(interval: TimeInterval = 60) {
        let timer = DispatchSource.makeTimerSource(flags: [], queue: .main)
        timer.setEventHandler(handler: { [weak self] in
            self?.uploadLogsToServer()
        })
        timer.schedule(deadline: .now(), repeating: interval)
        timer.resume()
        uploadLogsTimer = timer
    }

    private func stopUploadLogsTimer() {
        uploadLogsTimer?.cancel()
        uploadLogsTimer = nil
    }

    public func uploadLogsToServerIfNecessary() {
        guard UserDefaults.shared.bool(forKey: userDefaultsKeyForRequestLogs) else {
            stopUploadLogsTimer()
            return
        }
        // reset uploadLogsTimer
        stopUploadLogsTimer()
        startUploadLogsTimer()
        uploadLogsToServer()
    }

    public func uploadLogsToServer() {
        guard !isLogUploadInProgress else {
            DDLogError("ProtoServiceCore/uploadLogsToServer/already uploading logs")
            return
        }
        isLogUploadInProgress = true
        UserDefaults.shared.set(true, forKey: userDefaultsKeyForRequestLogs)
        AppContext.shared.uploadLogsToServer() { result in
            DDLogInfo("ProtoServiceCore/uploadLogsToServer/result: \(result)")
            switch result {
            case .success:
                UserDefaults.shared.set(false, forKey: userDefaultsKeyForRequestLogs)
                self.stopUploadLogsTimer()
            default:
                break
            }
            self.isLogUploadInProgress = false
        }
    }

    public func uploadOneTimePreKeysIfNecessary() {
        guard UserDefaults.shared.bool(forKey: AppContextCommon.shared.keyData.userDefaultsKeyForOneTimePreKeys) else {
            DDLogInfo("ProtoServiceCore/uploadOneTimePreKeysIfNecessary/finished uploading OneTimePreKeys")
            return
        }
        AppContextCommon.shared.keyData.uploadMoreOneTimePreKeys()
    }

    override open func didReceive(packet: Server_Packet) {
        super.didReceive(packet: packet)

        if case .ack(let ack) = packet.stanza {
            if let completion = receiptCompletions[ack.id] {
                completion(.success(()))
                receiptCompletions[ack.id] = nil
            }
        }
    }

    // MARK: Receipts

    private var _receiptCompletionLock = NSLock()
    private var _receiptCompletions = [String: ServiceRequestCompletion<Void>]()
    private var receiptCompletions: [String: ServiceRequestCompletion<Void>] {
        get {
            _receiptCompletionLock.withLock {
                _receiptCompletions
            }
        }
        set {
            _receiptCompletionLock.withLock {
                _receiptCompletions = newValue
            }
        }
    }

    private func sendReceipt(_ receipt: HalloReceipt, to toUserID: UserID, messageID: String = PacketID.generate(), completion: @escaping ServiceRequestCompletion<Void>) {
        DDLogInfo("proto/sendReceipt/\(receipt.itemId)/wait to execute when connected")
        execute(whenConnectionStateIs: .connected, onQueue: .main) { [self] in
            let threadID: String = {
                switch receipt.thread {
                case .group(let threadID): return threadID
                case .feed: return "feed"
                case .none: return ""
                }
            }()

            let payloadContent: Server_Msg.OneOf_Payload = {
                switch receipt.type {
                case .delivery:
                    var deliveryReceipt = Server_DeliveryReceipt()
                    deliveryReceipt.id = receipt.itemId
                    deliveryReceipt.threadID = threadID
                    return .deliveryReceipt(deliveryReceipt)
                case .read:
                    var seenReceipt = Server_SeenReceipt()
                    seenReceipt.id = receipt.itemId
                    seenReceipt.threadID = threadID
                    return .seenReceipt(seenReceipt)
                case .played:
                    var playedReceipt = Server_PlayedReceipt()
                    playedReceipt.id = receipt.itemId
                    playedReceipt.threadID = threadID
                    return .playedReceipt(playedReceipt)
                case .screenshot:
                    var screenshotReceipt = Server_ScreenshotReceipt()
                    screenshotReceipt.id = receipt.itemId
                    screenshotReceipt.threadID = threadID
                    return .screenshotReceipt(screenshotReceipt)
                case .saved:
                    var savedReceipt = Server_SavedReceipt()
                    savedReceipt.id = receipt.itemId
                    savedReceipt.threadID = threadID
                    return .savedReceipt(savedReceipt)
                }
            }()

            let packet = Server_Packet.msgPacket(
                from: receipt.userId,
                to: toUserID,
                id: messageID,
                payload: payloadContent)

            if let data = try? packet.serializedData(), self.isConnected {
                DDLogInfo("proto/sendReceipt/\(receipt.itemId)/sending")
                self.receiptCompletions[messageID] = completion
                self.send(data)
            } else {
                DDLogInfo("proto/sendReceipt/\(receipt.itemId)/skipping (disconnected)")
                completion(.failure(.malformedRequest))
            }
        }
    }
}

extension ProtoServiceCore: CoreService {

    public func requestMediaUploadURL(type: Server_UploadMedia.TypeEnum, size: Int, downloadURL: URL?, completion: @escaping ServiceRequestCompletion<MediaURLInfo?>) {
        // Wait until connected to request URLs. User meanwhile can cancel posting.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: ProtoMediaUploadURLRequest(type: type, size: size, downloadURL: downloadURL, completion: completion))
        }
    }

    public func shareGroupHistory(items: Server_GroupFeedItems, with userID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        let groupID = items.gid
        do {
            DDLogInfo("ProtoServiceCore/shareGroupHistory/\(groupID)/begin")
            let payload = try items.serializedData()
            let groupFeedHistoryID = PacketID.generate()
            AppContext.shared.mainDataStore.saveGroupHistoryInfo(id: groupFeedHistoryID, groupID: groupID, payload: payload)
            sendGroupFeedHistoryPayload(id: groupFeedHistoryID, groupID: groupID, payload: payload, to: userID, rerequestCount: 0, completion: completion)
        } catch {
            DDLogError("ProtoServiceCore/shareGroupHistory/\(groupID)/error could not serialize items")
            completion(.failure(.aborted))
        }
    }

    public func sendGroupFeedHistoryPayload(id groupFeedHistoryID: String, groupID: GroupID, payload: Data, to userID: UserID, rerequestCount: Int32, completion: @escaping ServiceRequestCompletion<Void>) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) { [self] in
            guard let ownUserID = credentials?.userID,
                  let fromUID = Int64(ownUserID),
                  self.isConnected else {
                DDLogInfo("ProtoServiceCore/sendGroupFeedHistoryPayload/\(groupFeedHistoryID)/\(groupID) skipping (disconnected)")
                completion(.failure(RequestError.notConnected))
                return
            }
            guard let toUID = Int64(userID) else {
                DDLogError("ProtoServiceCore/sendGroupFeedHistoryPayload/\(groupFeedHistoryID)/\(groupID) error invalid to uid")
                completion(.failure(.aborted))
                return
            }
            AppContext.shared.messageCrypter.encrypt(payload, for: userID) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    DDLogError("ProtoServiceCore/sendGroupFeedHistoryPayload/\(groupFeedHistoryID)/\(groupID)/failed to encrypt packet for \(userID): \(error)")
                    completion(.failure(.aborted))
                case .success((let encryptedData, _)):
                    var groupFeedHistory = Server_GroupFeedHistory()
                    groupFeedHistory.gid = groupID
                    groupFeedHistory.id = groupFeedHistoryID
                    groupFeedHistory.encPayload = encryptedData.data
                    groupFeedHistory.publicKey = encryptedData.identityKey ?? Data()
                    groupFeedHistory.oneTimePreKeyID = Int32(encryptedData.oneTimeKeyId)
                    groupFeedHistory.senderClientVersion = AppContext.userAgent

                    var packet = Server_Packet()
                    packet.msg.toUid = toUID
                    packet.msg.fromUid = fromUID
                    packet.msg.id = PacketID.generate()
                    packet.msg.type = .chat
                    packet.msg.rerequestCount = rerequestCount
                    packet.msg.payload = .groupFeedHistory(groupFeedHistory)

                    guard let packetData = try? packet.serializedData() else {
                        DDLogError("ProtoServiceCore/sendGroupFeedHistoryPayload/\(groupFeedHistoryID)/\(groupID)/error could not serialize packet")
                        completion(.failure(.aborted))
                        return
                    }

                    DDLogInfo("ProtoServiceCore/sendGroupFeedHistoryPayload/\(groupFeedHistoryID)/\(groupID)/success")
                    self.send(packetData)
                    completion(.success(()))
                }
            }
        }
    }

    public func resendHistoryResendPayload(id historyResendID: String, groupID: GroupID, payload: Data, to userID: UserID, rerequestCount: Int32, completion: @escaping ServiceRequestCompletion<Void>) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) { [self] in
            guard let ownUserID = credentials?.userID,
                  let fromUID = Int64(ownUserID),
                  self.isConnected else {
                DDLogInfo("ProtoServiceCore/resendHistoryResendPayload/\(historyResendID)/\(groupID) skipping (disconnected)")
                completion(.failure(RequestError.notConnected))
                return
            }
            guard let toUID = Int64(userID) else {
                DDLogError("ProtoServiceCore/resendHistoryResendPayload/\(historyResendID)/\(groupID) error invalid to uid")
                completion(.failure(.aborted))
                return
            }

            makeGroupRerequestEncryptedPayload(payloadData: payload, groupID: groupID, for: userID) { result in
                switch result {
                case .failure(let error):
                    DDLogError("ProtoServiceCore/resendHistoryResendPayload/\(historyResendID)/\(groupID)/failed to encrypt packet for \(userID): \(error)")
                    completion(.failure(error.serviceError()))
                case .success((let clientEncryptedPayload, let senderStateWithKeyInfo)):
                    var historyResend = Server_HistoryResend()
                    historyResend.id = historyResendID
                    historyResend.gid = groupID
                    if let senderStateWithKeyInfo = senderStateWithKeyInfo {
                        historyResend.senderState = senderStateWithKeyInfo
                    }
                    guard let encPayload = try? clientEncryptedPayload.serializedData() else {
                        DDLogError("ProtoServiceCore/resendHistoryResendPayload/\(historyResendID)/\(groupID)/error could not serialize payload")
                        completion(.failure(.aborted))
                        return
                    }
                    historyResend.encPayload = encPayload
                    historyResend.payload = payload
                    historyResend.senderClientVersion = AppContext.userAgent
                    let messageID = PacketID.generate()

                    var packet = Server_Packet()
                    packet.msg.toUid = toUID
                    packet.msg.fromUid = fromUID
                    packet.msg.id = messageID
                    packet.msg.type = .groupchat
                    packet.msg.rerequestCount = rerequestCount
                    packet.msg.payload = .historyResend(historyResend)

                    guard let packetData = try? packet.serializedData() else {
                        DDLogError("ProtoServiceCore/resendHistoryResendPayload/\(historyResendID)/\(groupID)/error could not serialize packet")
                        completion(.failure(.aborted))
                        return
                    }

                    DDLogInfo("ProtoServiceCore/resendHistoryResendPayload/\(historyResendID)/\(groupID)/success")
                    self.send(packetData)
                    completion(.success(()))
                }
            }
        }
    }

    public func publishPost(_ post: PostData, feed: Feed, completion: @escaping ServiceRequestCompletion<Date>) {
        // TODO: murali@: this code is not great.
        // Ideally we should have a more general framework to retry iqs on specific errors.
        DDLogInfo("ProtoServiceCore/publishPost/\(post.id)/execute/begin")
        publishPostInternal(post, feed: feed) { result in
            switch result {
            case .success(_):
                completion(result)
            case .failure(.audienceHashMismatch):
                DDLogInfo("ProtoServiceCore/publishPost/\(post.id)/execute/retrying on audienceHashMismatch")
                self.publishPostInternal(post, feed: feed, completion: completion)
            case .failure(_):
                completion(result)
            }
        }
    }

    private func publishPostInternal(_ post: PostData, feed: Feed, completion: @escaping ServiceRequestCompletion<Date>) {
        // Request will fail immediately if we're not connected, therefore delay sending until connected.
        ///TODO: add option of canceling posting.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            DDLogInfo("ProtoServiceCore/publishPostInternal/\(post.id)/execute/begin/feed: \(feed)")
            self.makePublishPostPayload(post, feed: feed) { result in
                switch result {
                case .failure(let error):
                    DDLogError("ProtoServiceCore/publishPostInternal/\(post.id)/makePublishPostPayload/error [\(error)]")
                    completion(.failure(.malformedRequest))
                case .success(let iqPayload):
                    DDLogError("ProtoServiceCore/publishPostInternal/\(post.id)/makePublishPostPayload/success")
                    let request = ProtoRequest<Server_Iq.OneOf_Payload>(
                        iqPacket: .iqPacket(type: .set, payload: iqPayload),
                        transform: { (iq) in
                            let iqPayload: Server_Iq.OneOf_Payload = {
                                switch feed {
                                case .group(_):
                                    return .groupFeedItem(iq.groupFeedItem)
                                case .personal(_):
                                    return .feedItem(iq.feedItem)
                                }
                            }()
                            return .success(iqPayload)
                        }) { result in
                            switch result {
                            case .success(let iqPayload):
                                switch iqPayload {
                                case .groupFeedItem(let groupFeedItem):
                                    DDLogInfo("ProtoServiceCore/publishPostInternal/\(post.id)/success, groupFeedItem \(groupFeedItem.post.id)")
                                    let receiverUids = groupFeedItem.senderStateBundles.map{ UserID($0.uid) }
                                    AppContext.shared.messageCrypter.removePending(userIds: receiverUids, in: groupFeedItem.gid)
                                    completion(.success(Date(timeIntervalSince1970: TimeInterval(groupFeedItem.post.timestamp))))
                                case .feedItem(let feedItem):
                                    switch feed {
                                    case .personal(let feedAudience):
                                        AppContext.shared.messageCrypter.removePending(userIds: Array(feedAudience.userIds), for: feedAudience.homeSessionType)
                                    case .group(_):
                                        break
                                    }
                                    DDLogInfo("ProtoServiceCore/publishPostInternal/\(post.id)/success, feedItem \(feedItem.post.id)")
                                    completion(.success(Date(timeIntervalSince1970: TimeInterval(feedItem.post.timestamp))))
                                default:
                                    DDLogInfo("ProtoServiceCore/publishPostInternal\(post.id)/: invalid payload")
                                    completion(.failure(.malformedResponse))
                                }
                            case .failure(RequestError.serverError("audience_hash_mismatch")):
                                DDLogError("ProtoServiceCore/publishPostInternal/\(post.id)/error audience_hash_mismatch")
                                switch feed {
                                case .group(let groupID):
                                    AppContext.shared.messageCrypter.updateAudienceHash(for: groupID)
                                case .personal(_):
                                    break
                                }
                                completion(.failure(.audienceHashMismatch))
                            case .failure(let failure):
                                DDLogError("ProtoServiceCore/publishPostInternal/\(post.id)/error [\(failure)]")
                                completion(.failure(failure))
                            }
                        }
                    DispatchQueue.main.async {
                        self.enqueue(request: request)
                    }
                }
            }
        }
    }

    public func resendPost(_ post: PostData, feed: Feed, rerequestCount: Int32, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        DDLogInfo("ProtoServiceCore/resendPost/\(post.id)/begin")
        execute(whenConnectionStateIs: .connected, onQueue: .main) { [self] in
            guard let fromUserID = credentials?.userID, self.isConnected else {
                DDLogInfo("ProtoServiceCore/resendPost/\(post.id) skipping (disconnected)")
                completion(.failure(RequestError.notConnected))
                return
            }

            let payloadCompletion: (Result<Server_Msg.OneOf_Payload, EncryptionError>) -> Void = { result in
                switch result {
                case .success(let payload):
                    let messageID = PacketID.generate()
                    let packet = Server_Packet.msgPacket(
                        from: fromUserID,
                        to: toUserID,
                        id: messageID,
                        type: .normal,
                        rerequestCount: rerequestCount,
                        payload: payload)

                    guard let packetData = try? packet.serializedData() else {
                        DDLogError("ProtoServiceCore/resendPost/\(post.id)/message/\(messageID)/error could not serialize groupFeedItem message!")
                        completion(.failure(.aborted))
                        return
                    }

                    DispatchQueue.main.async {
                        guard self.isConnected else {
                            DDLogInfo("ProtoServiceCore/resendPost/\(post.id)/message/\(messageID) aborting (disconnected)")
                            completion(.failure(RequestError.notConnected))
                            return
                        }
                        DDLogInfo("ProtoServiceCore/resendPost/\(post.id)/message/\(messageID) sending encrypted")
                        self.send(packetData)
                        DDLogInfo("ProtoServiceCore/resendPost/\(post.id)/message/\(messageID) success")
                        completion(.success(()))
                    }
                case .failure(let error):
                    DDLogError("ProtoServiceCore/resendPost/\(post.id)/error: \(error)")
                    completion(.failure(error.serviceError()))
                }
            }

            makePostRerequestFeedItem(post, feed: feed, to: toUserID, completion: payloadCompletion)
        }
    }

    public func resendComment(_ comment: CommentData, groupId: GroupID?, rerequestCount: Int32, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) { [self] in
            guard let fromUserID = credentials?.userID, self.isConnected else {
                DDLogInfo("ProtoServiceCore/resendComment/\(comment.id) skipping (disconnected)")
                completion(.failure(RequestError.notConnected))
                return
            }

            let payloadCompletion: (Result<Server_Msg.OneOf_Payload, EncryptionError>) -> Void = { result in
                switch result {
                case .success(let payload):
                    let messageID = PacketID.generate()
                    let packet = Server_Packet.msgPacket(
                        from: fromUserID,
                        to: toUserID,
                        id: messageID,
                        type: .normal,
                        rerequestCount: rerequestCount,
                        payload: payload)

                    guard let packetData = try? packet.serializedData() else {
                        DDLogError("ProtoServiceCore/resendComment/\(comment.id)/message/\(messageID)/error could not serialize groupFeedItem message!")
                        completion(.failure(.aborted))
                        return
                    }

                    DispatchQueue.main.async {
                        guard self.isConnected else {
                            DDLogInfo("ProtoServiceCore/resendComment/\(comment.id)/message/\(messageID) aborting (disconnected)")
                            completion(.failure(RequestError.notConnected))
                            return
                        }
                        DDLogInfo("ProtoServiceCore/resendComment/\(comment.id)/message/\(messageID) sending encrypted")
                        self.send(packetData)
                        DDLogInfo("ProtoServiceCore/resendComment/\(comment.id)/message/\(messageID) success")
                        completion(.success(()))
                    }
                case .failure(let error):
                    DDLogError("ProtoServiceCore/resendComment/\(comment.id)/error: \(error)")
                    completion(.failure(error.serviceError()))
                }
            }

            makeCommentRerequestFeedItem(comment, groupID: groupId, to: toUserID, completion: payloadCompletion)
        }
    }

    public func publishComment(_ comment: CommentData, groupId: GroupID?, completion: @escaping ServiceRequestCompletion<Date>) {
        DDLogInfo("ProtoServiceCore/publishComment/\(comment.id)/execute/begin")
        publishCommentInternal(comment, groupId: groupId) { result in
            switch result {
            case .success(_):
                completion(result)
            case .failure(.audienceHashMismatch):
                DDLogInfo("ProtoServiceCore/publishComment/\(comment.id)/execute/retrying on audienceHashMismatch")
                self.publishCommentInternal(comment, groupId: groupId, completion: completion)
            case .failure(_):
                completion(result)
            }
        }
    }

    public func publishCommentInternal(_ comment: CommentData, groupId: GroupID?, completion: @escaping ServiceRequestCompletion<Date>) {
        // Request will fail immediately if we're not connected, therefore delay sending until connected.
        ///TODO: add option of canceling posting.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            DDLogInfo("ProtoServiceCore/publishCommentInternal/\(comment.id)/execute/begin")
            self.makePublishCommentPayload(comment, groupID: groupId) { result in
                switch result {
                case .failure(let error):
                    DDLogError("ProtoServiceCore/publishCommentInternal/\(comment.id)/makePublishCommentPayload/error [\(error)]")
                    completion(.failure(.malformedRequest))
                case .success(let iqPayload):
                    DDLogError("ProtoServiceCore/publishCommentInternal/\(comment.id)/makePublishCommentPayload/success")
                    let request = ProtoRequest<Server_Iq.OneOf_Payload>(
                        iqPacket: .iqPacket(type: .set, payload: iqPayload),
                        transform: { (iq) in
                            let iqPayload: Server_Iq.OneOf_Payload = {
                                if groupId != nil {
                                    return .groupFeedItem(iq.groupFeedItem)
                                } else {
                                    return .feedItem(iq.feedItem)
                                }
                            }()
                            return .success(iqPayload)
                        }) { result in
                            switch result {
                            case .success(let iqPayload):
                                switch iqPayload {
                                case .groupFeedItem(let groupFeedItem):
                                    DDLogInfo("ProtoServiceCore/publishCommentInternal/\(comment.id)/success, groupFeedItem \(groupFeedItem.comment.id)")
                                    let receiverUids = groupFeedItem.senderStateBundles.map{ UserID($0.uid) }
                                    AppContext.shared.messageCrypter.removePending(userIds: receiverUids, in: groupFeedItem.gid)
                                    completion(.success(Date(timeIntervalSince1970: TimeInterval(groupFeedItem.comment.timestamp))))
                                case .feedItem(let feedItem):
                                    DDLogInfo("ProtoServiceCore/publishCommentInternal/\(comment.id)/success, feedItem \(feedItem.comment.id)")
                                    completion(.success(Date(timeIntervalSince1970: TimeInterval(feedItem.comment.timestamp))))
                                default:
                                    DDLogInfo("ProtoServiceCore/publishCommentInternal\(comment.id)/: invalid payload")
                                    completion(.failure(.malformedResponse))
                                }
                            case .failure(RequestError.serverError("audience_hash_mismatch")):
                                DDLogError("ProtoServiceCore/publishCommentInternal/\(comment.id)/error audience_hash_mismatch")
                                if let groupID = groupId {
                                    AppContext.shared.messageCrypter.updateAudienceHash(for: groupID)
                                }
                                // we could return a better error here to FeedData - so that we can auto retry i guess?
                                completion(.failure(.audienceHashMismatch))
                            case .failure(let failure):
                                DDLogError("ProtoServiceCore/publishCommentInternal/\(comment.id)/error \(failure)")
                                completion(.failure(failure))
                            }
                        }

                    DispatchQueue.main.async {
                        self.enqueue(request: request)
                    }
                }
            }
        }
    }

    private func makePublishPostPayload(_ post: PostData, feed: Feed, completion: @escaping (Result<Server_Iq.OneOf_Payload, EncryptionError>) -> Void) {
        guard let payloadData = try? post.clientContainer.serializedData(),
              var serverPost = post.serverPost else {
            completion(.failure(.serialization))
            return
        }

        switch feed {
        case .group(let groupID):
            if !ServerProperties.sendClearTextGroupFeedContent {
                serverPost.payload = Data()
            }
            makeGroupEncryptedPayload(payloadData: payloadData, groupID: groupID, oneOfItem: .post(serverPost), expiryTimestamp: post.expiration.flatMap { Int64($0.timeIntervalSince1970) } ?? -1) { result in
                switch result {
                case .failure(let failure):
                    AppContext.shared.eventMonitor.count(.groupEncryption(error: failure, itemType: .post))
                    completion(.failure(failure))
                case .success(let serverGroupFeedItem):
                    AppContext.shared.eventMonitor.count(.groupEncryption(error: nil, itemType: .post))
                    completion(.success(.groupFeedItem(serverGroupFeedItem)))
                }
            }
        case .personal(let audience):
            makeHomePostEncryptedPayload(post: post, audience: audience) { result in
                switch result {
                case .success(let feedItem):
                    AppContext.shared.eventMonitor.count(.homeEncryption(error: nil, itemType: .post))
                    completion(.success(.feedItem(feedItem)))
                case .failure(let error):
                    AppContext.shared.eventMonitor.count(.homeEncryption(error: error, itemType: .post))
                    completion(.failure(error))
                }
            }
        }
    }

    private func makePublishCommentPayload(_ comment: CommentData, groupID: GroupID?, completion: @escaping (Result<Server_Iq.OneOf_Payload, EncryptionError>) -> Void) {
        guard var serverComment = comment.serverComment else {
            completion(.failure(.serialization))
            return
        }
        let payloadData = serverComment.payload
        if !ServerProperties.sendClearTextGroupFeedContent {
            serverComment.payload = Data()
        }
        if let groupID = groupID {
            makeGroupEncryptedPayload(payloadData: payloadData, groupID: groupID, oneOfItem: .comment(serverComment)) { result in
                switch result {
                case .failure(let failure):
                    AppContext.shared.eventMonitor.count(.groupEncryption(error: failure, itemType: .comment))
                    completion(.failure(failure))
                case .success(let serverGroupFeedItem):
                    AppContext.shared.eventMonitor.count(.groupEncryption(error: nil, itemType: .comment))
                    completion(.success(.groupFeedItem(serverGroupFeedItem)))
                }
            }
        } else {
            makeHomeCommentEncryptedPayload(comment: comment) { result in
                switch result {
                case .success(let feedItem):
                    AppContext.shared.eventMonitor.count(.homeEncryption(error: nil, itemType: .comment))
                    completion(.success(.feedItem(feedItem)))
                case .failure(let error):
                    AppContext.shared.eventMonitor.count(.homeEncryption(error: error, itemType: .comment))
                    completion(.failure(error))
                }
            }
        }
    }

    private func makeGroupEncryptedPayload(payloadData: Data, groupID: GroupID, oneOfItem: Server_GroupFeedItem.OneOf_Item, expiryTimestamp: Int64? = nil, completion: @escaping (Result<Server_GroupFeedItem, EncryptionError>) -> Void) {
        var item = Server_GroupFeedItem()
        item.action = .publish
        item.gid = groupID
        item.senderClientVersion = AppContext.userAgent
        if let expiryTimestamp = expiryTimestamp {
            item.expiryTimestamp = expiryTimestamp
        }

        // encrypt the containerPayload
        AppContext.shared.messageCrypter.encrypt(payloadData, in: groupID) { result in
            switch result {
            case .failure(let error):
                DDLogError("ProtoServiceCore/makeGroupEncryptedPayload/\(groupID)/encryption/error [\(error)]")
                completion(.failure(error))
            case .success(let groupEncryptedData):
                item.audienceHash = groupEncryptedData.audienceHash
                item.senderStateBundles = groupEncryptedData.senderStateBundles
                do {
                    switch oneOfItem {
                    case .comment(var serverComment):
                        var clientEncryptedPayload = Clients_EncryptedPayload()
                        clientEncryptedPayload.senderStateEncryptedPayload = groupEncryptedData.data
                        serverComment.encPayload = try clientEncryptedPayload.serializedData()
                        item.item = .comment(serverComment)
                    case .post(var serverPost):
                        var clientEncryptedPayload = Clients_EncryptedPayload()
                        clientEncryptedPayload.senderStateEncryptedPayload = groupEncryptedData.data
                        serverPost.encPayload = try clientEncryptedPayload.serializedData()
                        item.item = .post(serverPost)
                    }
                    DDLogInfo("proto/makeGroupEncryptedPayload/\(groupID)/success")
                    completion(.success(item))
                } catch {
                    DDLogError("proto/makeGroupEncryptedPayload/\(groupID)/payload-serialization/error \(error)")
                    completion(.failure(.serialization))
                }
            }
        }
    }

    private func makeGroupRerequestEncryptedPayload(payloadData: Data, groupID: GroupID, for userID: UserID, completion: @escaping (Result<(Clients_EncryptedPayload, Server_SenderStateWithKeyInfo?), EncryptionError>) -> Void) {

        // Block to encrypt item payload using 1-1 channel.
        let itemPayloadEncryptionCompletion: ((Server_SenderStateWithKeyInfo?) -> Void) = { senderStateWithKeyInfo in
            // Set group feed post/comment properly.
            AppContext.shared.messageCrypter.encrypt(payloadData, for: userID) { result in
                switch result {
                case .failure(let error):
                    DDLogError("ProtoServiceCore/makeGroupRerequestEncryptedPayload/\(groupID)/failed to encrypt for userID: \(userID)")
                    completion(.failure(error))
                    return
                case .success((let oneToOneEncryptedData, _)):
                    DDLogError("ProtoServiceCore/makeGroupRerequestEncryptedPayload/\(groupID)/success for userID: \(userID)")
                    var clientEncryptedPayload = Clients_EncryptedPayload()
                    clientEncryptedPayload.oneToOneEncryptedPayload = oneToOneEncryptedData.data
                    completion(.success((clientEncryptedPayload, senderStateWithKeyInfo)))
                }
            }
        }

        // Block to first fetchSenderState and then encryptSenderState in 1-1 payload and then call the payload encryption block.
        AppContext.shared.messageCrypter.fetchSenderState(in: groupID) { result in
            switch result {
            case .failure(.invalidUid):
                DDLogError("ProtoServiceCore/makeGroupRerequestEncryptedPayload/\(groupID)/encryption/error: invalidUid/\(userID)")
                itemPayloadEncryptionCompletion(nil)
            case .failure(.invalidGroup):
                DDLogError("ProtoServiceCore/makeGroupRerequestEncryptedPayload/\(groupID)/encryption/error: invalidGroup/\(groupID) for \(userID)")
                itemPayloadEncryptionCompletion(nil)
            case .failure(let error):
                DDLogError("ProtoServiceCore/makeGroupRerequestEncryptedPayload/\(groupID)/encryption/error [\(error)]")
                completion(.failure(error))
            case .success(let groupSenderState):
                // construct own senderState
                var senderKey = Clients_SenderKey()
                senderKey.chainKey = groupSenderState.senderKey.chainKey
                senderKey.publicSignatureKey = groupSenderState.senderKey.publicSignatureKey
                var senderState = Clients_SenderState()
                senderState.senderKey = senderKey
                senderState.currentChainIndex = groupSenderState.chainIndex
                do{
                    let senderStatePayload = try senderState.serializedData()
                    // Encrypt senderState here and then call the payload encryption block.
                    AppContext.shared.messageCrypter.encrypt(senderStatePayload, for: userID) { result in
                        switch result {
                        case .failure(let error):
                            DDLogError("ProtoServiceCore/makeGroupRerequestEncryptedPayload/\(groupID)/failed to encrypt for userID: \(userID)")
                            completion(.failure(error))
                            return
                        case .success((let encryptedData, _)):
                            var senderStateWithKeyInfo = Server_SenderStateWithKeyInfo()
                            if let publicKey = encryptedData.identityKey, !publicKey.isEmpty {
                                senderStateWithKeyInfo.publicKey = publicKey
                                senderStateWithKeyInfo.oneTimePreKeyID = Int64(encryptedData.oneTimeKeyId)
                            }
                            senderStateWithKeyInfo.encSenderState = encryptedData.data
                            itemPayloadEncryptionCompletion(senderStateWithKeyInfo)
                        }
                    }
                } catch {
                    DDLogError("proto/makeGroupRerequestEncryptedPayload/\(groupID)/senderState-serialization/error \(error)")
                    completion(.failure(.serialization))
                    return
                }
            }
        }
    }

    private func makeHomePostEncryptedPayload(post: PostData, audience: FeedAudience, completion: @escaping (Result<Server_FeedItem, EncryptionError>) -> Void) {
        var item = Server_FeedItem()
        item.action = .publish
        item.senderClientVersion = AppContext.userAgent

        var serverAudience = Server_Audience()
        var type: HomeSessionType = .all
        serverAudience.uids = audience.userIds.compactMap { Int64($0) }
        switch audience.audienceType {
        case .all:
            type = .all
            serverAudience.type = .all
        case .whitelist:
            type = .favorites
            serverAudience.type = .only
        case .group, .blacklist:
            DDLogError("ProtoServiceCore/makeHomePostEncryptedPayload/error unsupported audience type [\(audience.audienceType)]")
            type = .favorites
            serverAudience.type = .only
        }
        let postID = post.id

        // encrypt the containerPayload
        AppContext.shared.messageCrypter.fetchCommentKey(postID: postID, for: type) { commentResult in
            switch commentResult {
            case .success(let data):
                var postData = post
                postData.commentKey = data
                if let serverPostData = postData.serverPost {
                    var serverPost = serverPostData
                    serverPost.audience = serverAudience
                    let audienceUserIds = Array(audience.userIds)
                    AppContext.shared.messageCrypter.encrypt(serverPost.payload,
                                                             with: postID,
                                                             for: type,
                                                             audienceMemberUids: audienceUserIds) { result in
                        // Clear unencrypted payload if server prop is disabled.
                        if !ServerProperties.sendClearTextHomeFeedContent {
                            serverPost.payload = Data()
                        }
                        switch result {
                        case .success(let homeEncryptedData):
                            do {
                                var clientEncryptedPayload = Clients_EncryptedPayload()
                                clientEncryptedPayload.senderStateEncryptedPayload = homeEncryptedData.data
                                serverPost.encPayload = try clientEncryptedPayload.serializedData()
                                item.item = .post(serverPost)
                                item.senderStateBundles = homeEncryptedData.senderStateBundles
                                DDLogError("ProtoServiceCore/makeHomePostEncryptedPayload/\(type)/postID: \(postID)/success")
                                completion(.success(item))
                            } catch {
                                DDLogError("ProtoServiceCore/makeHomePostEncryptedPayload/\(type)/postID: \(postID)/error [\(error)]")
                                completion(.failure(.serialization))
                            }
                        case .failure(let error):
                            DDLogError("ProtoServiceCore/makeHomePostEncryptedPayload/\(type)/postID: \(postID)/error [\(error)]")
                            completion(.failure(error))
                        }
                    }
                } else {
                    DDLogError("ProtoServiceCore/makeHomePostEncryptedPayload/\(type)/postID: \(postID)/error serialization")
                    completion(.failure(.serialization))
                }
            case .failure(let error):
                DDLogError("ProtoServiceCore/makeHomePostEncryptedPayload/\(type)/postID: \(postID)/error \(error)")
                completion(.failure(error))
            }
        }
    }

    private func makeHomeCommentEncryptedPayload(comment: CommentData, completion: @escaping (Result<Server_FeedItem, EncryptionError>) -> Void) {
        var item = Server_FeedItem()
        item.action = .publish
        item.senderClientVersion = AppContext.userAgent

        let type: HomeSessionType = .all
        let postID = comment.feedPostId

        guard var serverComment = comment.serverComment else {
            completion(.failure(.serialization))
            return
        }
        let payloadData = serverComment.payload
        // Clear unencrypted payload if server prop is disabled.
        if !ServerProperties.sendClearTextHomeFeedContent {
            serverComment.payload = Data()
        }

        AppContext.shared.messageCrypter.encrypt(payloadData, with: postID, for: type) { result in
            switch result {
            case .success(let data):
                do {
                    var clientEncryptedPayload = Clients_EncryptedPayload()
                    clientEncryptedPayload.commentKeyEncryptedPayload = data
                    serverComment.encPayload = try clientEncryptedPayload.serializedData()
                    item.item = .comment(serverComment)
                    DDLogError("ProtoServiceCore/makeHomeCommentEncryptedPayload/\(comment.id)/\(type)/postID: \(postID)/success")
                    completion(.success(item))
                } catch {
                    DDLogError("ProtoServiceCore/makeHomeCommentEncryptedPayload/\(comment.id)/\(type)/postID: \(postID)/error [\(error)]")
                    completion(.failure(.serialization))
                }
            case .failure(.missingCommentKey):
                // TODO: We should fail here eventually.
                // For now - allow this since old posts wont have comment keys.
                serverComment.encPayload = Data()
                item.item = .comment(serverComment)
                DDLogError("ProtoServiceCore/makeHomeCommentEncryptedPayload/\(comment.id)/\(type)/postID: \(postID)/posting without encryption")
                completion(.success(item))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func makeHomeRerequestEncryptedPayload(post: PostData, type: HomeSessionType, for userID: UserID, completion: @escaping (Result<Server_FeedItem, EncryptionError>) -> Void) {

        // Block to encrypt item payload using 1-1 channel.
        let itemPayloadEncryptionCompletion: ((PostData, Server_SenderStateWithKeyInfo?) -> Void) = { (newPost, senderStateWithKeyInfo) in
            guard var serverPostData = newPost.serverPost else {
                completion(.failure(.serialization))
                return
            }
            AppContext.shared.messageCrypter.encrypt(serverPostData.payload, for: userID) { result in
                switch result {
                case .failure(let error):
                    DDLogError("ProtoServiceCore/makeHomeRerequestEncryptedPayload/\(type)/failed to encrypt for userID: \(userID)")
                    completion(.failure(error))
                    return
                case .success((let oneToOneEncryptedData, _)):
                    do {
                        DDLogInfo("ProtoServiceCore/makeHomeRerequestEncryptedPayload/\(type)/success for userID: \(userID)")
                        var clientEncryptedPayload = Clients_EncryptedPayload()
                        clientEncryptedPayload.oneToOneEncryptedPayload = oneToOneEncryptedData.data
                        var item = Server_FeedItem()
                        item.action = .publish
                        item.senderClientVersion = AppContext.userAgent
                        serverPostData.encPayload = try clientEncryptedPayload.serializedData()
                        item.item = .post(serverPostData)
                        if let senderStateWithKeyInfo = senderStateWithKeyInfo {
                            item.senderState = senderStateWithKeyInfo
                        }
                        completion(.success(item))
                    } catch {
                        DDLogError("ProtoServiceCore/makeHomeRerequestEncryptedPayload/\(type)/payload-serialization/error \(error)")
                        completion(.failure(.serialization))
                        return
                    }
                }
            }
        }

        let commentKeyFetchCompletion: ((Server_SenderStateWithKeyInfo?) -> Void) = { senderStateWithKeyInfo in
            AppContext.shared.messageCrypter.fetchCommentKey(postID: post.id, for: .all) { result in
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let data):
                    var newPost = post
                    newPost.commentKey = data
                    itemPayloadEncryptionCompletion(newPost, senderStateWithKeyInfo)
                }
            }
        }

        // Block to first fetchSenderState and then encryptSenderState in 1-1 payload and then call the payload encryption block.
        AppContext.shared.messageCrypter.fetchSenderState(for: type) { result in
            switch result {
            case .failure(let error):
                DDLogError("ProtoServiceCore/makeHomeRerequestEncryptedPayload/\(type)/encryption/error [\(error)]")
                completion(.failure(error))
            case .success(let homeSenderState):
                // construct own senderState
                var senderKey = Clients_SenderKey()
                senderKey.chainKey = homeSenderState.senderKey.chainKey
                senderKey.publicSignatureKey = homeSenderState.senderKey.publicSignatureKey
                var senderState = Clients_SenderState()
                senderState.senderKey = senderKey
                senderState.currentChainIndex = homeSenderState.chainIndex
                do{
                    let senderStatePayload = try senderState.serializedData()
                    // Encrypt senderState here and then call the payload encryption block.
                    AppContext.shared.messageCrypter.encrypt(senderStatePayload, for: userID) { result in
                        switch result {
                        case .failure(let error):
                            DDLogError("ProtoServiceCore/makeHomeRerequestEncryptedPayload/\(type)/failed to encrypt for userID: \(userID)")
                            completion(.failure(error))
                            return
                        case .success((let encryptedData, _)):
                            var senderStateWithKeyInfo = Server_SenderStateWithKeyInfo()
                            if let publicKey = encryptedData.identityKey, !publicKey.isEmpty {
                                senderStateWithKeyInfo.publicKey = publicKey
                                senderStateWithKeyInfo.oneTimePreKeyID = Int64(encryptedData.oneTimeKeyId)
                            }
                            senderStateWithKeyInfo.encSenderState = encryptedData.data
                            commentKeyFetchCompletion(senderStateWithKeyInfo)
                        }
                    }
                } catch {
                    DDLogError("proto/makeHomeRerequestEncryptedPayload/\(type)/senderState-serialization/error \(error)")
                    completion(.failure(.serialization))
                    return
                }
            }
        }
    }

    public func retractPost(_ id: FeedPostID, in groupID: GroupID?, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        // Request will fail immediately if we're not connected, therefore delay sending until connected.
        ///TODO: add option of canceling posting.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            guard let toUID = Int64(toUserID) else {
                completion(.failure(.aborted))
                return
            }
            guard let userID = self.credentials?.userID, let fromUID = Int64(userID) else {
                DDLogError("ProtoService/retractPost/error invalid sender uid")
                completion(.failure(.aborted))
                return
            }

            var packet = Server_Packet()
            packet.msg.toUid = toUID
            packet.msg.fromUid = fromUID
            packet.msg.id = PacketID.generate()
            packet.msg.type = .normal

            var serverPost = Server_Post()
            serverPost.id = id
            serverPost.publisherUid = fromUID

            if let groupID = groupID {
                var groupFeedItem = Server_GroupFeedItem()
                groupFeedItem.action = .retract
                groupFeedItem.item = .post(serverPost)
                groupFeedItem.gid = groupID

                packet.msg.payload = .groupFeedItem(groupFeedItem)
            } else {
                var feedItem = Server_FeedItem()
                feedItem.action = .retract
                feedItem.item = .post(serverPost)

                packet.msg.payload = .feedItem(feedItem)
            }

            guard let packetData = try? packet.serializedData() else {
                DDLogError("ProtoService/retractPost/error could not serialize packet")
                completion(.failure(.malformedRequest))
                return
            }

            DDLogInfo("ProtoService/retractPost/\(id)/group: \(groupID ?? "nil")/to:\(toUserID)")
            self.send(packetData)
            completion(.success(()))
        }
    }

    public func retractComment(_ id: FeedPostCommentID, postID: FeedPostID, in groupID: GroupID?, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        // Request will fail immediately if we're not connected, therefore delay sending until connected.
        ///TODO: add option of canceling posting.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            // TODO: murali@: we should add an acknowledgement for all message stanzas
            // currently we only do this for receipts.

            guard let toUID = Int64(toUserID) else {
                completion(.failure(.aborted))
                return
            }
            guard let userID = self.credentials?.userID, let fromUID = Int64(userID) else {
                DDLogError("ProtoService/retractComment/error invalid sender uid")
                completion(.failure(.aborted))
                return
            }

            var packet = Server_Packet()
            packet.msg.toUid = toUID
            packet.msg.fromUid = fromUID
            packet.msg.id = PacketID.generate()
            packet.msg.type = .normal

            var serverComment = Server_Comment()
            serverComment.id = id
            serverComment.postID = postID
            serverComment.publisherUid = fromUID

            if let groupID = groupID {
                var groupFeedItem = Server_GroupFeedItem()
                groupFeedItem.action = .retract
                groupFeedItem.item = .comment(serverComment)
                groupFeedItem.gid = groupID

                packet.msg.payload = .groupFeedItem(groupFeedItem)
            } else {
                var feedItem = Server_FeedItem()
                feedItem.action = .retract
                feedItem.item = .comment(serverComment)

                packet.msg.payload = .feedItem(feedItem)
            }

            guard let packetData = try? packet.serializedData() else {
                DDLogError("ProtoService/retractComment/error could not serialize packet")
                completion(.failure(.malformedRequest))
                return
            }

            DDLogInfo("ProtoService/retractComment/\(id)/group: \(groupID ?? "nil")/to:\(toUserID)")
            self.send(packetData)
            completion(.success(()))
        }
    }

    private func makeChatStanza(_ message: ChatMessageProtocol, completion: @escaping (Server_ChatStanza?, EncryptionError?) -> Void) {
        guard let messageData = try? message.protoContainer?.serializedData() else {
            DDLogError("ProtoServiceCore/makeChatStanza/\(message.id)/error could not serialize chat message!")
            completion(nil, nil)
            return
        }
        guard let toUserId = message.chatMessageRecipient.toUserId else {
            DDLogError("ProtoServiceCore/makeChatStanza/\(message.id)/ error toUserId not set for message: \(message.id)")
            completion(nil, nil)
            return
        }

        AppContext.shared.messageCrypter.encrypt(messageData, for: toUserId) { result in
            switch result {
            case .success((let encryptedData, var logInfo)):
                logInfo["TS"] = self.dateTimeFormatterMonthDayTime.string(from: Date())

                var chat = Server_ChatStanza()
                chat.senderLogInfo = logInfo.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "; ")
                chat.encPayload = encryptedData.data
                chat.oneTimePreKeyID = Int64(encryptedData.oneTimeKeyId)
                switch message.content {
                case .reaction:
                    chat.chatType = .chatReaction
                case .text, .album, .files, .voiceNote, .location, .unsupported:
                    chat.chatType = .chat
                }
                // Add media counters.
                chat.mediaCounters = message.serverMediaCounters

                if let publicKey = encryptedData.identityKey {
                    chat.publicKey = publicKey
                } else {
                    DDLogInfo("ProtoServiceCore/makeChatStanza/\(message.id)/ skipping public key")
                }
                completion(chat, nil)
            case .failure(let error):
                completion(nil, error)
            }
        }
    }

    private func makePostRerequestFeedItem(_ post: PostData, feed: Feed, to toUserID: UserID, completion: @escaping (Result<Server_Msg.OneOf_Payload, EncryptionError>) -> Void) {
        guard let payloadData = try? post.clientContainer.serializedData(),
              var serverPost = post.serverPost else {
            completion(.failure(.serialization))
            return
        }

        switch feed {
        case .group(let groupID):
            if !ServerProperties.sendClearTextGroupFeedContent {
                serverPost.payload = Data()
            }
            var item = Server_GroupFeedItem()
            item.action = .publish
            item.gid = groupID
            item.senderClientVersion = AppContext.userAgent
            item.expiryTimestamp = post.expiration.flatMap { Int64($0.timeIntervalSince1970) } ?? -1
            makeGroupRerequestEncryptedPayload(payloadData: payloadData, groupID: groupID, for: toUserID) { result in
                switch result {
                case .failure(let failure):
                    AppContext.shared.eventMonitor.count(.groupEncryption(error: failure, itemType: .post))
                    completion(.failure(failure))
                case .success((let clientEncryptedPayload, let senderStateWithKeyInfo)):
                    AppContext.shared.eventMonitor.count(.groupEncryption(error: nil, itemType: .post))
                    do {
                        serverPost.encPayload = try clientEncryptedPayload.serializedData()
                        item.item = .post(serverPost)
                        if let senderStateWithKeyInfo = senderStateWithKeyInfo {
                            item.senderState = senderStateWithKeyInfo
                        }
                        completion(.success(.groupFeedItem(item)))
                    } catch {
                        DDLogError("ProtoServiceCore/makePostRerequestFeedItem/\(groupID)/payload-serialization/error \(error)")
                        completion(.failure(.serialization))
                        return
                    }
                }
            }
        case .personal(let audience):
            // Clear unencrypted payload if server prop is disabled.
            if !ServerProperties.sendClearTextHomeFeedContent {
                serverPost.payload = Data()
            }
            var item = Server_FeedItem()
            item.action = .publish
            item.senderClientVersion = AppContext.userAgent
            makeHomeRerequestEncryptedPayload(post: post, type: audience.homeSessionType, for: toUserID) { result in
                switch result {
                case .failure(let failure):
                    AppContext.shared.eventMonitor.count(.homeEncryption(error: failure, itemType: .post))
                    completion(.failure(failure))
                case .success(let item):
                    AppContext.shared.eventMonitor.count(.homeEncryption(error: nil, itemType: .post))
                    completion(.success(.feedItem(item)))
                }
            }
        }
    }

    private func makeCommentRerequestFeedItem(_ comment: CommentData, groupID: GroupID?, to toUserID: UserID, completion: @escaping (Result<Server_Msg.OneOf_Payload, EncryptionError>) -> Void) {
        guard var serverComment = comment.serverComment else {
            completion(.failure(.serialization))
            return
        }
        let payloadData = serverComment.payload
        if !ServerProperties.sendClearTextGroupFeedContent {
            serverComment.payload = Data()
        }
        // Add media counters.
        serverComment.mediaCounters = comment.serverMediaCounters

        if let groupID = groupID {
            var item = Server_GroupFeedItem()
            item.action = .publish
            item.gid = groupID
            item.senderClientVersion = AppContext.userAgent
            makeGroupRerequestEncryptedPayload(payloadData: payloadData, groupID: groupID, for: toUserID) { result in
                switch result {
                case .failure(let failure):
                    AppContext.shared.eventMonitor.count(.groupEncryption(error: failure, itemType: .comment))
                    completion(.failure(failure))
                case .success((let clientEncryptedPayload, let senderStateWithKeyInfo)):
                    AppContext.shared.eventMonitor.count(.groupEncryption(error: nil, itemType: .comment))
                    do {
                        serverComment.encPayload = try clientEncryptedPayload.serializedData()
                        item.item = .comment(serverComment)
                        if let senderStateWithKeyInfo = senderStateWithKeyInfo {
                            item.senderState = senderStateWithKeyInfo
                        }
                        completion(.success(.groupFeedItem(item)))
                    } catch {
                        DDLogError("ProtoServiceCore/makeGroupRerequestFeedItem/\(groupID)/payload-serialization/error \(error)")
                        completion(.failure(.serialization))
                        return
                    }
                }
            }
        } else {
            // Same as initial encryption - since comment key will be present already.
            makeHomeCommentEncryptedPayload(comment: comment) { result in
                switch result {
                case .success(let feedItem):
                    AppContext.shared.eventMonitor.count(.homeEncryption(error: nil, itemType: .comment))
                    completion(.success(.feedItem(feedItem)))
                case .failure(let error):
                    AppContext.shared.eventMonitor.count(.homeEncryption(error: error, itemType: .comment))
                    completion(.failure(error))
                }
            }
        }
    }

    public func decryptHomeFeedPayload(for item: Server_FeedItem, completion: @escaping (FeedContent?, HomeDecryptionFailure?) -> Void) {
        let sessionType = item.sessionType
        let newCompletion: (FeedContent?, HomeDecryptionFailure?) -> Void = { [weak self] content, decryptionFailure in
            guard let self = self else { return }
            completion(content, decryptionFailure)
            DispatchQueue.main.async {
                self.homeStates[sessionType] = .ready
                self.executePendingWorkItems(for: sessionType)
            }
        }

        let work = DispatchWorkItem {
            guard let contentId = item.contentId,
                  let publisherUid = item.publisherUid,
                  let encryptedPayload = item.encryptedPayload else {
                newCompletion(nil, HomeDecryptionFailure(item.contentId, item.publisherUid, .missingPayload, .payload))
                return
            }

            guard let contentType = item.contentType else {
                newCompletion(nil, HomeDecryptionFailure(contentId, publisherUid, .missingPayload, .payload))
                return
            }

            switch contentType {
            case .post:
                DDLogInfo("ProtoServiceCore/decryptHomeFeedPayload/contentId/\(sessionType)/\(contentId), publisherUid: \(publisherUid)/begin")
                self.decryptHomePostPayloadAndSenderState(encryptedPayload, postID: contentId, type: sessionType, with: item.senderState, from: publisherUid) { result in
                    switch result {
                    case .failure(let homeDecryptionFailure):
                        newCompletion(nil, homeDecryptionFailure)
                    case .success(let decryptedPayload):
                        self.parseHomePayloadContent(payload: decryptedPayload, item: item, completion: newCompletion)
                    }
                    DDLogInfo("ProtoServiceCore/decryptHomeFeedPayload/contentId/\(sessionType)/\(contentId), publisherUid: \(publisherUid)/end")
                }
            case .comment, .commentReaction, .postReaction:
                DDLogInfo("ProtoServiceCore/decryptHomeFeedPayload/contentId/\(sessionType)/\(contentId), publisherUid: \(publisherUid)/begin")
                self.decryptHomeCommentPayload(encryptedPayload, commentID: contentId, postID: item.comment.postID, type: sessionType, from: publisherUid) { result in
                    switch result {
                    case .failure(let homeDecryptionFailure):
                        newCompletion(nil, homeDecryptionFailure)
                    case .success(let decryptedPayload):
                        self.parseHomePayloadContent(payload: decryptedPayload, item: item, completion: newCompletion)
                    }
                    DDLogInfo("ProtoServiceCore/decryptHomeFeedPayload/contentId/\(sessionType)/\(contentId), publisherUid: \(publisherUid)/end")
                }

            case .unknown, .UNRECOGNIZED:
                newCompletion(nil, HomeDecryptionFailure(contentId, publisherUid, .invalidPayload, .payload))
            }
        }

        DispatchQueue.main.async { [self] in
            // Append task to pendingWorkItems and try to perform task.
            if var pendingHomeItems = pendingHomeWorkItems[sessionType] {
                pendingHomeItems.append(work)
                self.pendingHomeWorkItems[sessionType] = pendingHomeItems
            } else {
                pendingHomeWorkItems[sessionType] = [work]
            }
            executePendingWorkItems(for: sessionType)
        }
    }

    public func processHomeFeedRetract(for item: Server_FeedItem, completion: @escaping () -> Void) {
        let sessionType = item.sessionType

        let newCompletion: () -> Void = { [weak self] in
            guard let self = self else { return }
            completion()
            DispatchQueue.main.async {
                self.homeStates[sessionType] = .ready
                self.executePendingWorkItems(for: sessionType)
            }
        }

        let work = DispatchWorkItem {
            newCompletion()
        }

        DispatchQueue.main.async { [self] in
            // Append task to pendingWorkItems and try to perform task.
            if var pendingHomeItems = pendingHomeWorkItems[sessionType] {
                pendingHomeItems.append(work)
                self.pendingHomeWorkItems[sessionType] = pendingHomeItems
            } else {
                pendingHomeWorkItems[sessionType] = [work]
            }
            executePendingWorkItems(for: sessionType)
        }
    }

    public func processGroupFeedRetract(for item: Server_GroupFeedItem, in groupID: GroupID, completion: @escaping () -> Void) {
        let newCompletion: () -> Void = { [weak self] in
            guard let self = self else { return }
            completion()
            DispatchQueue.main.async {
                self.groupStates[groupID] = .ready
                self.executePendingWorkItems(for: groupID)
            }
        }

        let work = DispatchWorkItem {
            newCompletion()
        }

        DispatchQueue.main.async { [self] in
            // Append task to pendingWorkItems and try to perform task.
            if var pendingGroupWorkItems = pendingWorkItems[groupID] {
                pendingGroupWorkItems.append(work)
                self.pendingWorkItems[groupID] = pendingGroupWorkItems
            } else {
                pendingWorkItems[groupID] = [work]
            }
            executePendingWorkItems(for: groupID)
        }
    }

    public func processGroupStanza(for groupStanza: Server_GroupStanza, in groupID: GroupID,
                                   completion: @escaping (Clients_GroupHistoryPayload?, Bool) -> Void) {
        let newCompletion: (Clients_GroupHistoryPayload?, Bool) -> Void = { [weak self] (groupHistoryPayload, shouldSendAck)  in
            guard let self = self else { return }
            completion(groupHistoryPayload, shouldSendAck)
            DispatchQueue.main.async {
                self.groupStates[groupID] = .ready
                self.executePendingWorkItems(for: groupID)
            }
        }

        let work = DispatchWorkItem {
            guard !groupStanza.historyResend.encPayload.isEmpty && UserID(groupStanza.senderUid) != self.credentials?.userID else {
                newCompletion(nil, true)
                DDLogWarn("ProtoServiceCore/processGroupStanza/group: \(groupID)/historyResend payload is invalid")
                return
            }
            DDLogInfo("ProtoServiceCore/processGroupStanza/historyResend/group: \(groupID)/begin")
            let historyResend = groupStanza.historyResend
            let publisherUid = UserID(groupStanza.senderUid)
            self.processHistoryResendStanza(historyResend: historyResend, fromUserId: publisherUid, rerequestCount: 0, completion: newCompletion)
        }

        DispatchQueue.main.async { [self] in
            // Append task to pendingWorkItems and try to perform task.
            if var pendingGroupWorkItems = pendingWorkItems[groupID] {
                pendingGroupWorkItems.append(work)
                self.pendingWorkItems[groupID] = pendingGroupWorkItems
            } else {
                pendingWorkItems[groupID] = [work]
            }
            executePendingWorkItems(for: groupID)
        }
    }

    public func processHistoryResendStanza(historyResend: Server_HistoryResend, fromUserId: UserID, rerequestCount: Int32, completion: @escaping (Clients_GroupHistoryPayload?, Bool) -> Void) {
        let groupID = historyResend.gid
        DDLogInfo("ProtoServiceCore/processGroupStanza/historyResend/group: \(groupID)/begin")
        decryptGroupPayloadAndSenderState(historyResend.encPayload,
                                          contentId: historyResend.id,
                                          in: groupID,
                                          with: historyResend.senderState,
                                          from: fromUserId) { result in
            var groupDecryptionFailure: GroupDecryptionFailure?
            switch result {
            case .failure(let failure):
                DDLogError("ProtoServiceCore/processGroupStanza/historyResend/group: \(groupID)/failed: \(failure)")
                self.rerequestGroupFeedItemIfNecessary(id: historyResend.id, groupID: groupID, contentType: .historyResend, failure: failure) { result in
                    switch result {
                    case .success:
                        DDLogInfo("ProtoServiceCore/processGroupStanza/historyResend/\(historyResend.id)/sent rerequest")
                        completion(nil, true)
                    case .failure(let error):
                        DDLogError("ProtoServiceCore/processGroupStanza/historyResend/\(historyResend.id)/failed rerequesting: \(error)")
                        completion(nil, false)
                    }
                }
                groupDecryptionFailure = failure
            case .success(let decryptedPayload):
                guard let groupHistoryPayload = try? Clients_GroupHistoryPayload(serializedData: decryptedPayload) else {
                    DDLogError("ProtoServiceCore/processGroupStanza/historyResend/Could not deserialize groupHistoryPayload [\(groupID)]")
                    completion(nil, true)
                    return
                }
                DDLogInfo("ProtoServiceCore/processGroupStanza/historyResend/group: \(groupID)/success")
                completion(groupHistoryPayload, true)
                groupDecryptionFailure = nil
            }
            self.reportGroupDecryptionResult(
                error: groupDecryptionFailure?.error,
                contentID: historyResend.id,
                contentType: .historyResend,
                groupID: groupID,
                timestamp: Date(),
                sender: UserAgent(string: historyResend.senderClientVersion),
                rerequestCount: Int(rerequestCount))
        }
    }


    public func decryptGroupFeedPayload(for item: Server_GroupFeedItem, in groupID: GroupID, completion: @escaping (FeedContent?, GroupDecryptionFailure?) -> Void) {
        let newCompletion: (FeedContent?, GroupDecryptionFailure?) -> Void = { [weak self] content, decryptionFailure in
            guard let self = self else { return }
            completion(content, decryptionFailure)
            DispatchQueue.main.async {
                self.groupStates[groupID] = .ready
                self.executePendingWorkItems(for: groupID)
            }
        }

        let work = DispatchWorkItem {
            guard let contentId = item.contentId,
                  let publisherUid = item.publisherUid,
                  let encryptedPayload = item.encryptedPayload else {
                newCompletion(nil, GroupDecryptionFailure(item.contentId, item.publisherUid, .missingPayload, .payload))
                return
            }

            DDLogInfo("ProtoServiceCore/decryptGroupFeedPayload/contentId/\(item.gid)/\(contentId), publisherUid: \(publisherUid)/begin")
            self.decryptGroupPayloadAndSenderState(encryptedPayload, contentId: contentId, in: groupID, with: item.senderState, from: publisherUid) { result in
                switch result {
                case .failure(let groupDecryptionFailure):
                    newCompletion(nil, groupDecryptionFailure)
                case .success(let decryptedPayload):
                    self.parseGroupPayloadContent(payload: decryptedPayload, item: item, completion: newCompletion)
                }
                DDLogInfo("ProtoServiceCore/decryptGroupFeedPayload/contentId/\(item.gid)/\(contentId), publisherUid: \(publisherUid)/end")
            }
        }

        DispatchQueue.main.async { [self] in
            // Append task to pendingWorkItems and try to perform task.
            if var pendingGroupWorkItems = pendingWorkItems[groupID] {
                pendingGroupWorkItems.append(work)
                self.pendingWorkItems[groupID] = pendingGroupWorkItems
            } else {
                pendingWorkItems[groupID] = [work]
            }
            executePendingWorkItems(for: groupID)
        }
    }


    /// this function must run on main queue asynchronously.
    /// that ensures that the state and pendingWorkItems variables are always modified on the same queue.
    private func executePendingWorkItems(for groupID: GroupID) {
        if groupStates[groupID] != .busy {
            DDLogInfo("proto/executePendingWorkItems/gid:\(groupID)/checking!")
            if var pendingGroupItems = pendingWorkItems[groupID],
               !pendingGroupItems.isEmpty,
               let firstWork = pendingGroupItems.first {
                DDLogInfo("proto/executePendingWorkItems/gid:\(groupID)/working on it!")
                groupStates[groupID] = .busy
                pendingGroupItems.removeFirst()
                pendingWorkItems[groupID] = pendingGroupItems
                firstWork.perform()
            } else {
                DDLogInfo("proto/executePendingWorkItems/gid:\(groupID)/done!")
                groupStates[groupID] = .ready
                pendingWorkItems[groupID] = nil
            }
        } else {
            DDLogInfo("proto/executePendingWorkItems/gid:\(groupID)/waiting!")
        }
    }

    public func decryptGroupPayloadAndSenderState(_ payload: Data,
                                                  contentId: String,
                                                  in groupID: GroupID,
                                                  with clientSenderState: Server_SenderStateWithKeyInfo,
                                                  from publisherUid: UserID,
                                                  completion: @escaping (Result<Data, GroupDecryptionFailure>) -> Void) {
        if !clientSenderState.encSenderState.isEmpty {
            // We might already have an e2e session setup with this user.
            // but we have to overwrite our current session with this user. our code does this.
            AppContext.shared.messageCrypter.decrypt(
                EncryptedData(
                    data: clientSenderState.encSenderState,
                    identityKey: clientSenderState.publicKey.isEmpty ? nil : clientSenderState.publicKey,
                    oneTimeKeyId: Int(clientSenderState.oneTimePreKeyID)),
                from: publisherUid) { [self] result in
                    // After decrypting sender state.
                    switch result {
                    case .success(let decryptedData):
                        DDLogInfo("proto/decryptGroupFeedPayload/\(groupID)/success/decrypted senderState successfully")
                        do {
                            let senderState = try Clients_SenderState(serializedData: decryptedData)
                            self.decryptGroupPayload(payload, contentId: contentId, in: groupID, with: senderState, from: publisherUid, completion: completion)
                        } catch {
                            DDLogError("proto/decryptGroupFeedPayload/\(groupID)/error/invalid senderState \(error)")
                        }
                    case .failure(let failure):
                        DDLogError("proto/decryptGroupFeedPayload/\(groupID)/error/\(failure.error)")
                        completion(.failure(GroupDecryptionFailure(contentId, publisherUid, failure.error, .senderState)))
                        return
                    }
            }
        } else {
            decryptGroupPayload(payload, contentId: contentId, in: groupID, with: nil, from: publisherUid, completion: completion)
        }
    }

    public func decryptGroupPayload(_ payload: Data,
                                    contentId: String,
                                    in groupID: GroupID,
                                    with senderState: Clients_SenderState?,
                                    from publisherUid: UserID,
                                    completion: @escaping (Result<Data, GroupDecryptionFailure>) -> Void) {

        // Decrypt payload using the group channel.
        let groupDecryptPayloadCompletion: ((Clients_SenderState?, Data) -> Void) = { (senderState, groupEncryptedPayload) in
            // Decrypt the actual payload now.
            AppContext.shared.messageCrypter.decrypt(groupEncryptedPayload, from: publisherUid, in: groupID, with: senderState) { groupResult in
                switch groupResult {
                case .success(let decryptedPayload):
                    completion(.success(decryptedPayload))
                case .failure(let error):
                    DDLogError("proto/inspectAndDecryptClientEncryptedPayload/\(groupID)/error/\(error)")
                    completion(.failure(GroupDecryptionFailure(contentId, publisherUid, error, .payload)))
                }
            }
        }

        // Decrypt payload using the 1-1 channel.
        let oneToOneDecryptPayloadCompletion: ((Data) -> Void) = { oneToOneEncryptedPayload in
            // Decrypt the actual payload now.
            AppContext.shared.messageCrypter.decrypt(EncryptedData(
                data: oneToOneEncryptedPayload,
                identityKey: nil,
                oneTimeKeyId: 0),
            from: publisherUid) { result in
                switch result {
                case .success(let decryptedPayload):
                    completion(.success(decryptedPayload))
                case .failure(let error):
                    DDLogError("proto/inspectAndDecryptClientEncryptedPayload/\(groupID)/error/\(error)")
                    completion(.failure(GroupDecryptionFailure(contentId, publisherUid, error.error, .payload)))
                }
            }
        }

        do {
            // Call the appropriate completion block to decrypt the payload using the group channel or the 1-1 channel.
            let clientEncryptedPayload = try Clients_EncryptedPayload(serializedData: payload)
            switch clientEncryptedPayload.payload {
            case .oneToOneEncryptedPayload(let oneToOneEncryptedPayload):
                oneToOneDecryptPayloadCompletion(oneToOneEncryptedPayload)
                AppContext.shared.messageCrypter.updateSenderState(with: senderState, for: publisherUid, in: groupID)
            case .senderStateEncryptedPayload(let groupEncryptedPayload):
                groupDecryptPayloadCompletion(senderState, groupEncryptedPayload)
            default:
                DDLogError("proto/decryptGroupFeedPayload/\(groupID)/error/invalid payload")
                completion(.failure(GroupDecryptionFailure(contentId, publisherUid, .invalidPayload, .payload)))
                return
            }
        } catch {
            DDLogError("proto/decryptGroupFeedPayload/\(groupID)/error/invalid payload \(error)")
            completion(.failure(GroupDecryptionFailure(contentId, publisherUid, .deserialization, .payload)))
            return
        }
    }

    private func parseGroupPayloadContent(payload: Data, item: Server_GroupFeedItem, completion: @escaping (FeedContent?, GroupDecryptionFailure?) -> Void) {
        guard let contentId = item.contentId,
              let publisherUid = item.publisherUid,
              item.encryptedPayload != nil else {
            completion(nil, GroupDecryptionFailure(item.contentId, item.publisherUid, .missingPayload, .payload))
            return
        }

        switch item.item {
        case .post(let serverPost):
            let timestamp = Date(timeIntervalSince1970: TimeInterval(serverPost.timestamp))
            let expiration: Date?

            if item.expiryTimestamp != 0 {
                expiration = item.expiryTimestamp > 0 ? Date(timeIntervalSince1970: TimeInterval(item.expiryTimestamp)) : nil
            } else {
                expiration = timestamp.addingTimeInterval(FeedPost.defaultExpiration)
            }
            guard let post = PostData(id: serverPost.id,
                                      userId: publisherUid,
                                      timestamp: timestamp,
                                      expiration: expiration,
                                      payload: payload,
                                      status: .received,
                                      isShared: false,
                                      audience: serverPost.audience) else {
                DDLogError("proto/parseGroupPayloadContent/\(item.gid)/post/\(serverPost.id)/error could not make post object")
                completion(nil, GroupDecryptionFailure(contentId, publisherUid, .invalidPayload, .payload))
                return
            }
            DDLogInfo("proto/parseGroupPayloadContent/\(item.gid)/post/\(post.id)/success")
            completion(.newItems([.post(post)]), nil)
        case .comment(let serverComment):
            guard let comment = CommentData(id: serverComment.id,
                                            userId: publisherUid,
                                            feedPostId: serverComment.postID,
                                            parentId: serverComment.parentCommentID.isEmpty ? nil: serverComment.parentCommentID,
                                            timestamp: Date(timeIntervalSince1970: TimeInterval(serverComment.timestamp)),
                                            payload: payload,
                                            status: .received) else {
                DDLogError("proto/parseGroupPayloadContent/\(item.gid)/comment/\(serverComment.id)/error could not make comment object")
                completion(nil, GroupDecryptionFailure(contentId, publisherUid, .invalidPayload, .payload))
                return
            }
            DDLogInfo("proto/parseGroupPayloadContent/\(item.gid)/comment/\(comment.id)/success")
            completion(.newItems([.comment(comment, publisherName: serverComment.publisherName)]), nil)
        default:
            DDLogError("proto/parseGroupPayloadContent/\(item.gid)/error/invalidPayload")
            completion(nil, GroupDecryptionFailure(contentId, publisherUid, .invalidPayload, .payload))
        }
    }

    /// this function must run on main queue asynchronously.
    /// that ensures that the state and pendingWorkItems variables are always modified on the same queue.
    private func executePendingWorkItems(for type: HomeSessionType) {
        if homeStates[type] != .busy {
            DDLogInfo("proto/executePendingWorkItems/gid:\(type)/checking!")
            if var pendingHomeItems = pendingHomeWorkItems[type],
               !pendingHomeItems.isEmpty,
               let firstWork = pendingHomeItems.first {
                DDLogInfo("proto/executePendingWorkItems/type:\(type)/working on it!")
                homeStates[type] = .busy
                pendingHomeItems.removeFirst()
                pendingHomeWorkItems[type] = pendingHomeItems
                firstWork.perform()
            } else {
                DDLogInfo("proto/executePendingWorkItems/type:\(type)/done!")
                homeStates[type] = .ready
                pendingHomeWorkItems[type] = nil
            }
        } else {
            DDLogInfo("proto/executePendingWorkItems/type:\(type)/waiting!")
        }
    }

    public func decryptHomePostPayloadAndSenderState(_ payload: Data,
                                                     postID: FeedPostID,
                                                     type: HomeSessionType,
                                                     with clientSenderState: Server_SenderStateWithKeyInfo,
                                                     from publisherUid: UserID,
                                                     completion: @escaping (Result<Data, HomeDecryptionFailure>) -> Void) {
        if !clientSenderState.encSenderState.isEmpty {
            // We might already have an e2e session setup with this user.
            // but we have to overwrite our current session with this user. our code does this.
            AppContext.shared.messageCrypter.decrypt(
                EncryptedData(
                    data: clientSenderState.encSenderState,
                    identityKey: clientSenderState.publicKey.isEmpty ? nil : clientSenderState.publicKey,
                    oneTimeKeyId: Int(clientSenderState.oneTimePreKeyID)),
                from: publisherUid) { [self] result in
                    // After decrypting sender state.
                    switch result {
                    case .success(let decryptedData):
                        DDLogInfo("proto/decryptHomePostPayloadAndSenderState/\(type)/success/decrypted senderState successfully")
                        do {
                            let senderState = try Clients_SenderState(serializedData: decryptedData)
                            self.decryptHomePostPayload(payload, postID: postID, type: type, with: senderState, from: publisherUid, completion: completion)
                        } catch {
                            DDLogError("proto/decryptHomePostPayloadAndSenderState/\(type)/error/invalid senderState \(error)")
                        }
                    case .failure(let failure):
                        DDLogError("proto/decryptHomePostPayloadAndSenderState/\(type)/error/\(failure.error)")
                        completion(.failure(HomeDecryptionFailure(postID, publisherUid, failure.error, .senderState)))
                        return
                    }
            }
        } else {
            decryptHomePostPayload(payload, postID: postID, type: type, with: nil, from: publisherUid, completion: completion)
        }
    }

    public func decryptHomePostPayload(_ payload: Data,
                                       postID: FeedPostID,
                                       type: HomeSessionType,
                                       with senderState: Clients_SenderState?,
                                       from publisherUid: UserID,
                                       completion: @escaping (Result<Data, HomeDecryptionFailure>) -> Void) {

        // Decrypt payload using the home channel.
        let homeDecryptPayloadCompletion: ((Clients_SenderState?, Data) -> Void) = { (senderState, homeEncryptedPayload) in
            // Decrypt the actual payload now.
            AppContext.shared.messageCrypter.decrypt(homeEncryptedPayload, from: publisherUid, postID: postID, with: senderState, for: type) { result in
                switch result {
                case .success(let decryptedPayload):
                    completion(.success(decryptedPayload))
                case .failure(let error):
                    DDLogError("proto/decryptHomePostPayload/\(type)/error/\(error)")
                    completion(.failure(HomeDecryptionFailure(postID, publisherUid, error, .payload)))
                }
            }
        }

        // Decrypt payload using the 1-1 channel.
        let oneToOneDecryptPayloadCompletion: ((Data) -> Void) = { oneToOneEncryptedPayload in
            // Decrypt the actual payload now.
            AppContext.shared.messageCrypter.decrypt(EncryptedData(
                data: oneToOneEncryptedPayload,
                identityKey: nil,
                oneTimeKeyId: 0),
            from: publisherUid) { result in
                switch result {
                case .success(let decryptedPayload):
                    completion(.success(decryptedPayload))
                case .failure(let error):
                    DDLogError("proto/decryptHomePostPayload/\(type)/error/\(error)")
                    completion(.failure(HomeDecryptionFailure(postID, publisherUid, error.error, .payload)))
                }
            }
        }

        do {
            // Call the appropriate completion block to decrypt the payload using the group channel or the 1-1 channel.
            let clientEncryptedPayload = try Clients_EncryptedPayload(serializedData: payload)
            switch clientEncryptedPayload.payload {
            case .oneToOneEncryptedPayload(let oneToOneEncryptedPayload):
                DDLogInfo("proto/decryptHomePostPayload/oneToOneEncryptedPayload")
                oneToOneDecryptPayloadCompletion(oneToOneEncryptedPayload)
                AppContext.shared.messageCrypter.updateSenderState(with: senderState, for: publisherUid, type: type)
            case .senderStateEncryptedPayload(let groupEncryptedPayload):
                DDLogInfo("proto/decryptHomePostPayload/senderStateEncryptedPayload")
                homeDecryptPayloadCompletion(senderState, groupEncryptedPayload)
            default:
                DDLogError("proto/decryptHomePostPayload/\(type)/error/invalid payload")
                completion(.failure(HomeDecryptionFailure(postID, publisherUid, .invalidPayload, .payload)))
                return
            }
        } catch {
            DDLogError("proto/decryptHomePostPayload/\(type)/error/invalid payload \(error)")
            completion(.failure(HomeDecryptionFailure(postID, publisherUid, .deserialization, .payload)))
            return
        }
    }

    public func decryptHomeCommentPayload(_ payload: Data,
                                          commentID: FeedPostCommentID,
                                          postID: FeedPostID,
                                          type: HomeSessionType,
                                          from publisherUid: UserID,
                                          completion: @escaping (Result<Data, HomeDecryptionFailure>) -> Void) {
        do {
            // Call the appropriate completion block to decrypt the payload using the group channel or the 1-1 channel.
            let clientEncryptedPayload = try Clients_EncryptedPayload(serializedData: payload)
            switch clientEncryptedPayload.payload {
            case .commentKeyEncryptedPayload(let data):
                AppContext.shared.messageCrypter.decrypt(data, from: publisherUid, postID: postID, for: type) { result in
                    switch result {
                    case .success(let decryptedPayload):
                        completion(.success(decryptedPayload))
                    case .failure(let error):
                        DDLogError("proto/decryptHomeCommentPayload/error/\(error)")
                        completion(.failure(HomeDecryptionFailure(commentID, publisherUid, error, .payload)))
                    }
                }
            default:
                DDLogError("proto/decryptHomeCommentPayload/error/invalid payload")
                completion(.failure(HomeDecryptionFailure(commentID, publisherUid, .invalidPayload, .payload)))
                return
            }
        } catch {
            DDLogError("proto/decryptHomeCommentPayload/error/invalid payload \(error)")
            completion(.failure(HomeDecryptionFailure(commentID, publisherUid, .deserialization, .payload)))
            return
        }
    }

    private func parseHomePayloadContent(payload: Data, item: Server_FeedItem, completion: @escaping (FeedContent?, HomeDecryptionFailure?) -> Void) {
        guard let contentId = item.contentId,
              let publisherUid = item.publisherUid,
              item.encryptedPayload != nil else {
            completion(nil, HomeDecryptionFailure(item.contentId, item.publisherUid, .missingPayload, .payload))
            return
        }

        switch item.item {
        case .post(let serverPost):
            let timestamp = Date(timeIntervalSince1970: TimeInterval(serverPost.timestamp))
            let expiration = timestamp.addingTimeInterval(FeedPost.defaultExpiration)
            guard var post = PostData(id: serverPost.id,
                                      userId: publisherUid,
                                      timestamp: timestamp,
                                      expiration: expiration,
                                      payload: payload,
                                      status: .received,
                                      isShared: false,
                                      audience: serverPost.audience) else {
                DDLogError("proto/parseHomePayloadContent/post/\(serverPost.id)/error could not make post object")
                completion(nil, HomeDecryptionFailure(contentId, publisherUid, .invalidPayload, .payload))
                return
            }
            DDLogInfo("proto/parseHomePayloadContent/post/\(post.id)/success")
            if let commentKey = post.commentKey,
               let homeSessionType = post.audience?.homeSessionType {
                DDLogInfo("proto/parseHomePayloadContent/post/\(post.id)/try and saveCommentKey")
                AppContext.shared.messageCrypter.saveCommentKey(postID: serverPost.id, commentKey: commentKey, for: homeSessionType)
            } else {
                DDLogError("proto/parseHomePayloadContent/post/\(post.id)/failed to extract commentKey")
                // TODO: need to send rerequest on post stanza here - since we failed to get comment key.
                // The only way to get commentKey would be to rerequest the post.
            }

            post.update(with: serverPost)
            completion(.newItems([.post(post)]), nil)
        case .comment(let serverComment):
            guard let comment = CommentData(id: serverComment.id,
                                            userId: publisherUid,
                                            feedPostId: serverComment.postID,
                                            parentId: serverComment.parentCommentID.isEmpty ? nil: serverComment.parentCommentID,
                                            timestamp: Date(timeIntervalSince1970: TimeInterval(serverComment.timestamp)),
                                            payload: payload,
                                            status: .received) else {
                DDLogError("proto/parseHomePayloadContent/comment/\(serverComment.id)/error could not make comment object")
                completion(nil, HomeDecryptionFailure(contentId, publisherUid, .invalidPayload, .payload))
                return
            }
            DDLogInfo("proto/parseHomePayloadContent/comment/\(comment.id)/success")
            completion(.newItems([.comment(comment, publisherName: serverComment.publisherName)]), nil)
        default:
            DDLogError("proto/parseHomePayloadContent/error/invalidPayload")
            completion(nil, HomeDecryptionFailure(contentId, publisherUid, .invalidPayload, .payload))
        }
    }

    public func reportGroupDecryptionResult(error: DecryptionError?, contentID: String, contentType: GroupDecryptionReportContentType, groupID: GroupID, timestamp: Date, sender: UserAgent?, rerequestCount: Int) {
        if (error == .missingPayload) {
            DDLogInfo("proto/reportGroupDecryptionResult/\(contentID)/\(contentType)/\(groupID)/payload is missing - not error.")
            return
        }
        let errorString = error?.rawValue ?? ""
        let logString = error == nil ? "success" : "error [\(errorString)]"
        DDLogInfo("proto/reportGroupDecryptionResult/\(contentID)/\(contentType)/\(groupID)/\(logString)")
        AppContext.shared.eventMonitor.count(.groupDecryption(error: error, itemTypeString: contentType.rawValue, sender: sender))
        AppContext.shared.cryptoData.update(contentID: contentID,
                                            contentType: contentType,
                                            groupID: groupID,
                                            timestamp: timestamp,
                                            error: errorString,
                                            sender: sender,
                                            rerequestCount: rerequestCount)
    }

    public func updateGroupDecryptionResult(error: DecryptionError?, contentID: String, contentType: GroupDecryptionReportContentType, groupID: GroupID, timestamp: Date, sender: UserAgent?, rerequestCount: Int) {
        if (error == .missingPayload) {
            DDLogInfo("proto/reportGroupDecryptionResult/\(contentID)/\(contentType)/\(groupID)/payload is missing - not error.")
            return
        }
        let errorString = error?.rawValue ?? ""
        let logString = error == nil ? "success" : "error [\(errorString)]"
        DDLogInfo("proto/reportGroupDecryptionResult/\(contentID)/\(contentType)/\(groupID)/\(logString)")
        AppContext.shared.cryptoData.update(contentID: contentID,
                                            contentType: contentType,
                                            groupID: groupID,
                                            timestamp: timestamp,
                                            error: errorString,
                                            sender: sender,
                                            rerequestCount: rerequestCount)
    }

    public func reportHomeDecryptionResult(error: DecryptionError?, contentID: String, contentType: HomeDecryptionReportContentType, type: HomeSessionType, timestamp: Date, sender: UserAgent?, rerequestCount: Int) {

        let audienceType: HomeDecryptionReportAudienceType
        switch type {
        case .all:
            audienceType = .all
        case .favorites:
            audienceType = .only
        }

        if (error == .missingPayload) {
            DDLogInfo("proto/reportHomeDecryptionResult/\(contentID)/\(contentType)/\(audienceType)/payload is missing - not error.")
            return
        }
        let errorString = error?.rawValue ?? ""
        let logString = error == nil ? "success" : "error [\(errorString)]"
        DDLogInfo("proto/reportHomeDecryptionResult/\(contentID)/\(contentType)/\(audienceType)/\(logString)")
        AppContext.shared.eventMonitor.count(.homeDecryption(error: error, itemTypeString: contentType.rawValue, sender: sender))
        AppContext.shared.cryptoData.update(contentID: contentID,
                                            contentType: contentType,
                                            audienceType: audienceType,
                                            timestamp: timestamp,
                                            error: errorString,
                                            sender: sender,
                                            rerequestCount: rerequestCount)
    }

    public func updateHomeDecryptionResult(error: DecryptionError?, contentID: String, contentType: HomeDecryptionReportContentType, type: HomeSessionType, timestamp: Date, sender: UserAgent?, rerequestCount: Int) {

        let audienceType: HomeDecryptionReportAudienceType
        switch type {
        case .all:
            audienceType = .all
        case .favorites:
            audienceType = .only
        }

        if (error == .missingPayload) {
            DDLogInfo("proto/reportHomeDecryptionResult/\(contentID)/\(contentType)/\(audienceType)/payload is missing - not error.")
            return
        }
        let errorString = error?.rawValue ?? ""
        let logString = error == nil ? "success" : "error [\(errorString)]"
        DDLogInfo("proto/reportHomeDecryptionResult/\(contentID)/\(contentType)/\(audienceType)/\(logString)")
        AppContext.shared.cryptoData.update(contentID: contentID,
                                            contentType: contentType,
                                            audienceType: audienceType,
                                            timestamp: timestamp,
                                            error: errorString,
                                            sender: sender,
                                            rerequestCount: rerequestCount)
    }

    // Checks if the message is decrypted and saved in the main app's data store.
    // TODO: discuss with garrett on other options here.
    // We should move the cryptoData keystore to be accessible by all extensions and the main app.
    // It would be cleaner that way - having these checks after merging still leads to some flakiness in my view.
    public func isMessageDecryptedAndSaved(msgId: String) -> Bool {
        var isMessageAlreadyInLocalStore = false

        AppContext.shared.mainDataStore.performOnBackgroundContextAndWait { managedObjectContext in
            if let message = AppContext.shared.coreChatData.chatMessage(with: msgId, in: managedObjectContext), message.incomingStatus != .rerequesting {
                DDLogInfo("ProtoService/isMessageDecryptedAndSaved/msgId \(msgId) - message is available in local store.")
                isMessageAlreadyInLocalStore = true
            } else if let reaction = AppContext.shared.coreChatData.commonReaction(with: msgId, in: managedObjectContext), reaction.incomingStatus != .rerequesting {
                DDLogInfo("ProtoService/isMessageDecryptedAndSaved/msgId \(msgId) - reaction is available in local store.")
                isMessageAlreadyInLocalStore = true
            }
        }

        if isMessageAlreadyInLocalStore {
            return true
        }

        DDLogInfo("ProtoService/isMessageDecryptedAndSaved/msgId \(msgId) - message is missing.")
        return false
    }

    // Checks if the oneToOne content is decrypted and saved in the stats dataStore.
    public func isOneToOneContentDecryptedAndSaved(contentID: String) -> Bool {
        var isOneToOneContentDecrypted = false
        AppContext.shared.cryptoData.performOnBackgroundContextAndWait { managedObjectContext in
            guard let result = AppContext.shared.cryptoData.fetchMessageDecryption(id: contentID, in: managedObjectContext) else {
                isOneToOneContentDecrypted = false
                return
            }
            isOneToOneContentDecrypted = result.isSuccess()
        }
        if isOneToOneContentDecrypted {
            DDLogInfo("ProtoService/isOneToOneContentDecrypted/contentID \(contentID) success")
            return true
        }
        DDLogInfo("ProtoService/isOneToOneContentDecrypted/contentID \(contentID) - content is missing.")
        return false

        // Lets try using only the stats store this time and see how it works out.
    }

    // Checks if the groupFeedItem is decrypted and saved in the stats dataStore.
    public func isGroupFeedItemDecryptedAndSaved(contentID: String) -> Bool {
        var isGroupFeedItemDecrypted = false

        AppContext.shared.mainDataStore.performOnBackgroundContextAndWait { managedObjectContext in
            if let post = AppContext.shared.coreFeedData.feedPost(with: contentID, in: managedObjectContext), post.status != .rerequesting {
                isGroupFeedItemDecrypted = true
            } else if let comment = AppContext.shared.coreFeedData.feedComment(with: contentID, in: managedObjectContext), comment.status != .rerequesting {
                isGroupFeedItemDecrypted = true
            } else if let reaction = AppContext.shared.coreChatData.commonReaction(with: contentID, in: managedObjectContext), reaction.incomingStatus != .rerequesting {
                isGroupFeedItemDecrypted = true
            }
        }

        if isGroupFeedItemDecrypted {
            DDLogInfo("ProtoService/isGroupFeedItemDecryptedAndSaved/contentID \(contentID) success")
            return true
        }
        DDLogInfo("ProtoService/isGroupFeedItemDecryptedAndSaved/contentID \(contentID) - content is missing.")
        return false
    }

    public func rerequestGroupFeedItemIfNecessary(id contentID: String, groupID: GroupID, contentType: GroupFeedRerequestContentType, failure: GroupDecryptionFailure, completion: @escaping ServiceRequestCompletion<Void>) {
        guard let authorUserID = failure.fromUserId else {
            DDLogError("proto/rerequestGroupFeedItemIfNecessary/\(contentID)/decrypt/authorUserID missing")
            completion(.failure(.aborted))
            return
        }

        // Dont rerequest messages that were already decrypted and saved.
        if !isGroupFeedItemDecryptedAndSaved(contentID: contentID) {
            DDLogInfo("proto/rerequestGroupFeedItemIfNecessary/\(contentID)/decrypt/content is missing - so send a rerequest")
            self.rerequestGroupFeedItem(contentId: contentID,
                                        groupID: groupID,
                                        authorUserID: authorUserID,
                                        rerequestType: failure.rerequestType,
                                        contentType: contentType,
                                        completion: completion)
        } else {
            DDLogInfo("proto/rerequestGroupFeedItemIfNecessary/\(contentID)/decrypt/content already exists")
            completion(.success(()))
        }
    }

    private func rerequestGroupFeedItem(contentId: String, groupID: String, authorUserID: UserID, rerequestType: Server_GroupFeedRerequest.RerequestType, contentType: GroupFeedRerequestContentType, completion: @escaping ServiceRequestCompletion<Void>) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            guard let fromUserID = self.credentials?.userID else {
                DDLogError("ProtoServiceCore/rerequestGroupFeedItem/error no-user-id")
                completion(.failure(.aborted))
                return
            }

            var groupFeedRerequest = Server_GroupFeedRerequest()
            groupFeedRerequest.gid = groupID
            groupFeedRerequest.id = contentId
            groupFeedRerequest.rerequestType = rerequestType
            groupFeedRerequest.contentType = contentType
            DDLogInfo("ProtoServiceCore/rerequestGroupFeedItem/\(contentId) rerequesting")

            let packet = Server_Packet.msgPacket(
                from: fromUserID,
                to: authorUserID,
                id: PacketID.generate(),
                type: .groupchat,
                rerequestCount: 0,
                payload: .groupFeedRerequest(groupFeedRerequest))

            guard let packetData = try? packet.serializedData() else {
                DDLogError("ProtoServiceCore/rerequestGroupFeedItem/\(contentId)/error could not serialize rerequest stanza!")
                completion(.failure(.malformedRequest))
                return
            }

            DispatchQueue.main.async {
                guard self.isConnected else {
                    DDLogInfo("ProtoServiceCore/rerequestGroupFeedItem/\(contentId) aborting (disconnected)")
                    completion(.failure(.notConnected))
                    return
                }

                DDLogInfo("ProtoServiceCore/rerequestGroupFeedItem/\(contentId) sending")
                self.send(packetData)
                DDLogInfo("ProtoServiceCore/rerequestGroupFeedItem/\(contentId) success")
                completion(.success(()))
            }
        }
    }

    public func rerequestGroupChatMessageIfNecessary(id messageId: String, groupID: GroupID, contentType: Server_GroupChatStanza.ChatType, failure: GroupDecryptionFailure, completion: @escaping ServiceRequestCompletion<Void>) {
        guard let authorUserID = failure.fromUserId else {
            DDLogError("proto/rerequestGroupChatMessageIfNecessary/\(messageId)/decrypt/authorUserID missing")
            completion(.failure(.aborted))
            return
        }
        let rerequestContentType: GroupFeedRerequestContentType
        switch contentType {
        case .chat:
            rerequestContentType = .message
        case .chatReaction:
            rerequestContentType = .messageReaction
        case .UNRECOGNIZED:
            DDLogError("proto/rerequestGroupChatMessageIfNecessary/\(messageId)/invalid contentType")
            completion(.failure(.aborted))
            return
        }
        // Dont rerequest messages that were already decrypted and saved.
        if !isMessageDecryptedAndSaved(msgId: messageId) {
            DDLogInfo("proto/rerequestGroupChatMessageIfNecessary/\(messageId)/decrypt/content is missing - so send a rerequest")
            self.rerequestGroupFeedItem(contentId: messageId,
                                        groupID: groupID,
                                        authorUserID: authorUserID,
                                        rerequestType: failure.rerequestType,
                                        contentType: rerequestContentType,
                                        completion: completion)
        } else {
            DDLogInfo("proto/rerequestGroupChatMessageIfNecessary/\(messageId)/decrypt/content already exists")
            completion(.success(()))
        }
    }

    // Checks if the home feed item is decrypted and saved in the dataStore.
    public func isHomeFeedItemDecryptedAndSaved(contentID: String) -> Bool {
        var isHomeFeedItemDecrypted = false

        AppContext.shared.mainDataStore.performOnBackgroundContextAndWait { managedObjectContext in
            if let post = AppContext.shared.coreFeedData.feedPost(with: contentID, in: managedObjectContext), post.status != .rerequesting {
                isHomeFeedItemDecrypted = true
            } else if let comment = AppContext.shared.coreFeedData.feedComment(with: contentID, in: managedObjectContext), comment.status != .rerequesting {
                isHomeFeedItemDecrypted = true
            } else if let reaction = AppContext.shared.coreChatData.commonReaction(with: contentID, in: managedObjectContext), reaction.incomingStatus != .rerequesting {
                isHomeFeedItemDecrypted = true
            }
        }

        if isHomeFeedItemDecrypted {
            DDLogInfo("ProtoService/isHomeFeedItemDecryptedAndSaved/contentID \(contentID) success")
            return true
        }
        DDLogInfo("ProtoService/isHomeFeedItemDecryptedAndSaved/contentID \(contentID) - content is missing.")
        return false
    }

    public func rerequestHomeFeedItemIfNecessary(id contentID: String, contentType: HomeFeedRerequestContentType, failure: HomeDecryptionFailure, completion: @escaping ServiceRequestCompletion<Void>) {
        guard let authorUserID = failure.fromUserId else {
            DDLogError("proto/rerequestHomeFeedItemIfNecessary/\(contentID)/decrypt/authorUserID missing")
            completion(.failure(.malformedRequest))
            return
        }

        // Dont rerequest messages that were already decrypted and saved.
        if !isHomeFeedItemDecryptedAndSaved(contentID: contentID) {
            DDLogInfo("proto/rerequestHomeFeedItemIfNecessary/\(contentID)/decrypt/content is missing - so send a rerequest")
            self.rerequestHomeFeedItem(contentId: contentID,
                                       authorUserID: authorUserID,
                                       rerequestType: failure.rerequestType,
                                       contentType: contentType,
                                       completion: completion)
        } else {
            DDLogInfo("proto/rerequestHomeFeedItemIfNecessary/\(contentID)/decrypt/content already exists")
            completion(.success(()))
        }
    }

    public func rerequestHomeFeedPost(id contentID: String, completion: @escaping ServiceRequestCompletion<Void>) {
        AppContext.shared.mainDataStore.performOnBackgroundContextAndWait { managedObjectContext in
            if let post = AppContext.shared.coreFeedData.feedPost(with: contentID, in: managedObjectContext) {
                // We rerequest post here due to missingCommentKeys.
                // This basically means we most likely dont have a senderState from the user
                // Always rerequest content with sender state here to be on the safe side.
                DDLogInfo("proto/rerequestHomeFeedPost/\(contentID)/sending a rerequest to userID: \(post.userID)")
                self.rerequestHomeFeedItem(contentId: contentID,
                                           authorUserID: post.userID,
                                           rerequestType: .senderState,
                                           contentType: .post,
                                           completion: completion)
            } else {
                AppContext.shared.errorLogger?.logError(NSError(domain: "missingPostToRerequest", code: 1012))
                DDLogError("proto/rerequestHomeFeedPost/\(contentID)/missing post info to send a rerequest")
                completion(.failure(.aborted))
            }
        }
    }

    private func rerequestHomeFeedItem(contentId: String, authorUserID: UserID, rerequestType: HomeFeedRerequestType, contentType: HomeFeedRerequestContentType, completion: @escaping ServiceRequestCompletion<Void>) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            guard let fromUserID = self.credentials?.userID else {
                DDLogError("ProtoServiceCore/rerequestHomeFeedItem/error no-user-id")
                completion(.failure(.aborted))
                return
            }

            var homeFeedRerequest = Server_HomeFeedRerequest()
            homeFeedRerequest.id = contentId
            homeFeedRerequest.rerequestType = rerequestType
            homeFeedRerequest.contentType = contentType
            DDLogInfo("ProtoServiceCore/rerequestHomeFeedItem/\(contentId) rerequesting")

            let packet = Server_Packet.msgPacket(
                from: fromUserID,
                to: authorUserID,
                id: PacketID.generate(),
                type: .normal,
                rerequestCount: 0,
                payload: .homeFeedRerequest(homeFeedRerequest))

            guard let packetData = try? packet.serializedData() else {
                DDLogError("ProtoServiceCore/rerequestHomeFeedItem/\(contentId)/error could not serialize rerequest stanza!")
                completion(.failure(.malformedRequest))
                return
            }

            DispatchQueue.main.async {
                guard self.isConnected else {
                    DDLogInfo("ProtoServiceCore/rerequestHomeFeedItem/\(contentId) aborting (disconnected)")
                    completion(.failure(.notConnected))
                    return
                }

                DDLogInfo("ProtoServiceCore/rerequestHomeFeedItem/\(contentId) sending")
                self.send(packetData)
                DDLogInfo("ProtoServiceCore/rerequestHomeFeedItem/\(contentId) success")
                completion(.success(()))
            }
        }
    }

    public func handleContentMissing(_ contentMissing: Server_ContentMissing, ack: (() -> Void)?) {
        // We get this message when client rerequest content from another user when they dont have the content.
        let contentID = contentMissing.contentID
        let senderUserAgent = UserAgent(string: contentMissing.senderClientVersion)
        let error = DecryptionError.missingContent
        let contentType = contentMissing.contentType
        DDLogInfo("ProtoServiceCore/handleContentMissing/contentID: \(contentID)/contentType: \(contentType)/ua: \(String(describing: senderUserAgent))")

        let maxCount = 5
        // Set rerequestCount to 5 to indicate max.
        // Set gid to be empty - where necessary.
        // Set audienceType to all - where necessary
        // We got contentMissing upon sending a rerequest so we wont update gid/audienceType on the counter anyways.
        switch contentType {
        case .chat:
            // Update 1-1 stats.
            reportDecryptionResult(error: error, messageID: contentID, timestamp: Date(), sender: senderUserAgent, rerequestCount: maxCount, contentType: .chat)
        case .groupHistory:
            // Update 1-1 stats.
            reportDecryptionResult(error: error, messageID: contentID, timestamp: Date(), sender: senderUserAgent, rerequestCount: maxCount, contentType: .groupHistory)
        case .chatReaction:
            // Update 1-1 stats.
            reportDecryptionResult(error: error, messageID: contentID, timestamp: Date(), sender: senderUserAgent, rerequestCount: maxCount, contentType: .chatReaction)

        case .groupFeedPost:
            // Update group stats.
            reportGroupDecryptionResult(error: error, contentID: contentID, contentType: .post,
                                        groupID: "", timestamp: Date(), sender: senderUserAgent, rerequestCount: maxCount)
        case .groupFeedComment:
            // Update group stats.
            reportGroupDecryptionResult(error: error, contentID: contentID, contentType: .comment,
                                        groupID: "", timestamp: Date(), sender: senderUserAgent, rerequestCount: maxCount)
        case .groupChatReaction:
            // Update group stats.
            reportGroupDecryptionResult(error: error, contentID: contentID, contentType: .chatReaction,
                                        groupID: "", timestamp: Date(), sender: senderUserAgent, rerequestCount: maxCount)
        case .groupChat:
            // Update group stats.
            reportGroupDecryptionResult(error: error, contentID: contentID, contentType: .chat,
                                        groupID: "", timestamp: Date(), sender: senderUserAgent, rerequestCount: maxCount)
        case .groupPostReaction:
            // Update group stats.
            reportGroupDecryptionResult(error: error, contentID: contentID, contentType: .postReaction,
                                        groupID: "", timestamp: Date(), sender: senderUserAgent, rerequestCount: maxCount)
        case .historyResend:
            // Update group stats.
            reportGroupDecryptionResult(error: error, contentID: contentID, contentType: .historyResend,
                                        groupID: "", timestamp: Date(), sender: senderUserAgent, rerequestCount: maxCount)
        case .groupCommentReaction:
            // Update group stats.
            reportGroupDecryptionResult(error: error, contentID: contentID, contentType: .commentReaction,
                                        groupID: "", timestamp: Date(), sender: senderUserAgent, rerequestCount: maxCount)

        case .call:
            // TODO: murali@: check if we are we reporting call stats on 1-1 channel.
            break
        case .homeFeedPost:
            reportHomeDecryptionResult(error: error, contentID: contentID, contentType: .post,
                                       type: .all, timestamp: Date(), sender: senderUserAgent, rerequestCount: maxCount)
        case .homeFeedComment:
            reportHomeDecryptionResult(error: error, contentID: contentID, contentType: .comment,
                                       type: .all, timestamp: Date(), sender: senderUserAgent, rerequestCount: maxCount)
        case .homeCommentReaction:
            reportHomeDecryptionResult(error: error, contentID: contentID, contentType: .commentReaction,
                                       type: .all, timestamp: Date(), sender: senderUserAgent, rerequestCount: maxCount)
        case .homePostReaction:
            reportHomeDecryptionResult(error: error, contentID: contentID, contentType: .post,
                                       type: .all, timestamp: Date(), sender: senderUserAgent, rerequestCount: maxCount)


        case .UNRECOGNIZED, .unknown:
            break
        }
        ack?()
    }

    // MARK: Groups

    public func getGroupInfo(groupID: GroupID, completion: @escaping ServiceRequestCompletion<HalloGroup>) {
        enqueue(request: ProtoGroupInfoRequest(groupID: groupID, completion: completion))
    }

    // MARK: Decryption
    public func decryptGroupFeedHistory(_ groupFeedHistory: Server_GroupFeedHistory, from fromUserID: UserID,
                                        completion: @escaping (Result<Server_GroupFeedItems, DecryptionFailure>) -> Void) {
        AppContext.shared.messageCrypter.decrypt(
            EncryptedData(
                data: groupFeedHistory.encPayload,
                identityKey: groupFeedHistory.publicKey.isEmpty ? nil : groupFeedHistory.publicKey,
                oneTimeKeyId: Int(groupFeedHistory.oneTimePreKeyID)),
            from: fromUserID) { result in
            switch result {
            case .success(let decryptedData):
                if let groupFeedItems = try? Server_GroupFeedItems(serializedData: decryptedData) {
                    completion(.success(groupFeedItems))
                } else {
                    completion(.failure(DecryptionFailure(.deserialization)))
                }
            case .failure(let failure):
                completion(.failure(failure))
            }
        }
    }

    public func decryptGroupChatStanza(_ serverGroupChat: Server_GroupChatStanza, msgId contentId: String, from fromUserID: UserID, in groupID: GroupID, completion: @escaping (ChatContent?, ChatContext?, GroupDecryptionFailure?) -> Void) {
        let newCompletion: (ChatContent?, ChatContext?, GroupDecryptionFailure?) -> Void = { [weak self] content, context, decryptionFailure in
            guard let self = self else { return }
            completion(content, context, decryptionFailure)
            DispatchQueue.main.async {
                self.groupStates[groupID] = .ready
                self.executePendingWorkItems(for: groupID)
            }
        }

        let work = DispatchWorkItem {

            DDLogInfo("ProtoServiceCore/decryptGroupChatStanza/contentId/\(serverGroupChat.gid)/\(contentId), fromUserID: \(fromUserID)/begin")
            self.decryptGroupPayloadAndSenderState(serverGroupChat.encPayload, contentId: contentId, in: groupID, with: serverGroupChat.senderState, from: fromUserID) { result in
                switch result {
                case .failure(let groupDecryptionFailure):
                    newCompletion(nil, nil, groupDecryptionFailure)
                case .success(let decryptedPayload):
                    if let container = try? Clients_Container(serializedData: decryptedPayload) {
                        newCompletion(container.chatContainer.chatContent, container.chatContainer.chatContext, nil)
                    } else {
                        DDLogError("ProtoServiceCore/decryptGroupChatStanza/ failes to deserialize data")
                    }
                }
                DDLogInfo("ProtoServiceCore/decryptGroupChatStanza/contentId/\(serverGroupChat.gid)/\(contentId), fromUserID: \(fromUserID)/end")
            }
        }
        DispatchQueue.main.async { [self] in
            // Append task to pendingWorkItems and try to perform task.
            if var pendingGroupWorkItems = pendingWorkItems[groupID] {
                pendingGroupWorkItems.append(work)
                self.pendingWorkItems[groupID] = pendingGroupWorkItems
            } else {
                pendingWorkItems[groupID] = [work]
            }
            executePendingWorkItems(for: groupID)
        }
    }

    /// TODO: Convert to Result now that success and failure are mutually exclusive (no more plaintext)
    public func decryptChat(_ serverChat: Server_ChatStanza, from fromUserID: UserID, completion: @escaping (ChatContent?, ChatContext?, DecryptionFailure?) -> Void) {
        AppContext.shared.messageCrypter.decrypt(
            EncryptedData(
                data: serverChat.encPayload,
                identityKey: serverChat.publicKey.isEmpty ? nil : serverChat.publicKey,
                oneTimeKeyId: Int(serverChat.oneTimePreKeyID)),
            from: fromUserID) { result in
            switch result {
            case .success(let decryptedData):
                if let container = try? Clients_Container(serializedData: decryptedData) {
                    completion(container.chatContainer.chatContent, container.chatContainer.chatContext, nil)
                } else {
                    completion(nil, nil, DecryptionFailure(.deserialization))
                }
            case .failure(let failure):
                completion(nil, nil, failure)
            }
        }
    }

    public func reportDecryptionResult(error: DecryptionError?, messageID: String, timestamp: Date, sender: UserAgent?, rerequestCount: Int, contentType: DecryptionReportContentType) {
        AppContext.shared.eventMonitor.count(.decryption(error: error, sender: sender))

        if let sender = sender {
            AppContext.shared.cryptoData.update(
                messageID: messageID,
                timestamp: timestamp,
                result: error?.rawValue ?? "success",
                rerequestCount: rerequestCount,
                sender: sender,
                contentType: contentType)
        } else {
            DDLogError("proto/reportDecryptionResult/\(messageID)/decrypt/stats/error missing sender user agent")
        }
    }

    public func sendChatMessage(_ message: ChatMessageProtocol, completion: @escaping ServiceRequestCompletion<Void>) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            guard let fromUserID = self.credentials?.userID else {
                DDLogInfo("ProtoServiceCore/sendChatMessage/\(message.id) skipping (disconnected)")
                completion(.failure(RequestError.aborted))
                return
            }

            if let toUserId = message.chatMessageRecipient.toUserId {
                self.sendOneToOneChatMessage(fromUserID: fromUserID, toUserId: toUserId, message: message, completion: completion)
            } else if let toGroupId = message.chatMessageRecipient.toGroupId {
                self.sendGroupChatMessage(fromUserID: fromUserID, toGroupId: toGroupId, message: message, completion: completion)
            } else {
                DDLogError("ProtoServiceCore/sendChatMessage/\(message.id)/ recipientId not set for chat message")
                completion(.failure(.malformedRequest))
                return
            }
        }
    }

    private func sendOneToOneChatMessage(fromUserID: UserID, toUserId: UserID, message: ChatMessageProtocol, completion: @escaping ServiceRequestCompletion<Void>) {
        makeChatStanza(message) { chat, error in
            guard let chat = chat else {
                completion(.failure(.aborted))
                return
            }

            // Dont send chat messages on encryption errors.
            if let error = error {
                DDLogInfo("ProtoServiceCore/sendOneToOneChatMessage/\(message.id)/error \(error)")
                AppContext.shared.errorLogger?.logError(error)
                DDLogInfo("ProtoServiceCore/sendOneToOneChatMessage/\(message.id) aborted")
                completion(.failure(RequestError.aborted))
                return
            }

            let packet = Server_Packet.msgPacket(
                from: fromUserID,
                to: toUserId,
                id: message.id,
                type: .chat,
                rerequestCount: message.rerequestCount,
                payload: .chatStanza(chat))

            guard let packetData = try? packet.serializedData() else {
                AppContext.shared.eventMonitor.count(.encryption(error: .serialization))
                DDLogError("ProtoServiceCore/sendOneToOneChatMessage/\(message.id)/error could not serialize chat message!")
                completion(.failure(RequestError.malformedRequest))
                return
            }

            DispatchQueue.main.async {
                guard self.isConnected else {
                    DDLogInfo("ProtoServiceCore/sendOneToOneChatMessage/\(message.id) aborting (disconnected)")
                    completion(.failure(RequestError.notConnected))
                    return
                }
                AppContext.shared.eventMonitor.count(.encryption(error: error))
                DDLogInfo("ProtoServiceCore/sendOneToOneChatMessage/\(message.id) sending encrypted")
                self.send(packetData)
                DDLogInfo("ProtoServiceCore/sendOneToOneChatMessage/\(message.id) success")
                completion(.success(()))
            }
        }
    }

    public func resendGroupChatMessage(_ message: ChatMessageProtocol, groupId: GroupID, to toUserID: UserID, rerequestCount: Int32, completion: @escaping ServiceRequestCompletion<Void>) {
        makeRerequestGroupChatStanza(message, for: toUserID, in: groupId) { chat, error in
            guard let chat = chat else {
                completion(.failure(.aborted))
                return
            }

            // Dont send chat messages on encryption errors.
            if let error = error {
                DDLogInfo("ProtoServiceCore/resendGroupChatMessage/\(message.id)/error \(error)")
                AppContext.shared.errorLogger?.logError(error)
                DDLogInfo("ProtoServiceCore/resendGroupChatMessage/\(message.id) aborted")
                completion(.failure(RequestError.aborted))
                return
            }

            let packet = Server_Packet.msgPacket(
                from: message.fromUserId,
                to: toUserID,
                id: message.id,
                type: .groupchat,
                rerequestCount: rerequestCount,
                payload: .groupChatStanza(chat))

            guard let packetData = try? packet.serializedData() else {
                AppContext.shared.eventMonitor.count(.encryption(error: .serialization))
                DDLogError("ProtoServiceCore/resendGroupChatMessage/\(message.id)/error could not serialize chat message!")
                completion(.failure(RequestError.malformedRequest))
                return
            }

            DispatchQueue.main.async {
                guard self.isConnected else {
                    DDLogInfo("ProtoServiceCore/resendGroupChatMessage/\(message.id) aborting (disconnected)")
                    completion(.failure(RequestError.notConnected))
                    return
                }
                AppContext.shared.eventMonitor.count(.encryption(error: error))
                DDLogInfo("ProtoServiceCore/resendGroupChatMessage/\(message.id) sending encrypted")
                self.send(packetData)
                DDLogInfo("ProtoServiceCore/resendGroupChatMessage/\(message.id) success")
                completion(.success(()))
            }
        }
    }

    private func sendGroupChatMessage(fromUserID: UserID, toGroupId: GroupID, message: ChatMessageProtocol, completion: @escaping ServiceRequestCompletion<Void>) {
        makeGroupChatStanza(message) { chat, error in
            guard let chat = chat else {
                completion(.failure(.aborted))
                return
            }

            // Dont send chat messages on encryption errors.
            if let error = error {
                DDLogInfo("ProtoServiceCore/sendGroupChatMessage/\(message.id)/error \(error)")
                AppContext.shared.errorLogger?.logError(error)
                DDLogInfo("ProtoServiceCore/sendGroupChatMessage/\(message.id) aborted")
                completion(.failure(RequestError.aborted))
                return
            }

            let packet = Server_Packet.msgPacket(
                from: fromUserID,
                id: message.id,
                type: .groupchat,
                rerequestCount: message.rerequestCount,
                payload: .groupChatStanza(chat))

            guard let packetData = try? packet.serializedData() else {
                AppContext.shared.eventMonitor.count(.encryption(error: .serialization))
                DDLogError("ProtoServiceCore/sendGroupChatMessage/\(message.id)/error could not serialize chat message!")
                completion(.failure(RequestError.malformedRequest))
                return
            }

            DispatchQueue.main.async {
                guard self.isConnected else {
                    DDLogInfo("ProtoServiceCore/sendGroupChatMessage/\(message.id) aborting (disconnected)")
                    completion(.failure(RequestError.notConnected))
                    return
                }
                AppContext.shared.eventMonitor.count(.encryption(error: error))
                DDLogInfo("ProtoServiceCore/sendGroupChatMessage/\(message.id) sending encrypted")
                self.send(packetData)
                DDLogInfo("ProtoServiceCore/sendGroupChatMessage/\(message.id) success")
                completion(.success(()))
            }
        }
        
    }

    private func makeGroupChatStanza(_ message: ChatMessageProtocol, completion: @escaping (Server_GroupChatStanza?, EncryptionError?) -> Void) {
        guard let messageData = try? message.protoContainer?.serializedData() else {
            DDLogError("ProtoServiceCore/makeGroupChatStanza/\(message.id)/error could not serialize group chat message!")
            completion(nil, nil)
            return
        }
        guard let toGroupId = message.chatMessageRecipient.toGroupId else {
            DDLogError("ProtoServiceCore/makeGroupChatStanza/\(message.id)/ error toGroupId not set for message: \(message.id)")
            completion(nil, nil)
            return
        }
        AppContext.shared.messageCrypter.encrypt(messageData, in: toGroupId) { result in
            switch result {
            case .success(let groupEncryptedData):
                DDLogInfo("ProtoServiceCore/makeGroupChatStanza/\(toGroupId)/encryption/success")
                var groupChatStanza = Server_GroupChatStanza()
                groupChatStanza.gid = toGroupId
                if !ServerProperties.sendClearTextGroupFeedContent {
                    groupChatStanza.payload = Data()
                }
                groupChatStanza.audienceHash = groupEncryptedData.audienceHash
                groupChatStanza.senderStateBundles = groupEncryptedData.senderStateBundles
                groupChatStanza.senderClientVersion = AppContext.userAgent
                do {
                    var clientEncryptedPayload = Clients_EncryptedPayload()
                    clientEncryptedPayload.senderStateEncryptedPayload = groupEncryptedData.data
                    groupChatStanza.encPayload = try clientEncryptedPayload.serializedData()
                    switch message.content {
                    case .reaction:
                        groupChatStanza.chatType = .chatReaction
                    case .text, .album, .files, .voiceNote, .location, .unsupported:
                        groupChatStanza.chatType = .chat
                    }
                    groupChatStanza.mediaCounters = message.serverMediaCounters
                    completion(groupChatStanza, nil)
                } catch {
                    DDLogError("proto/makeGroupChatStanza/\(toGroupId)/payload-serialization/error \(error)")
                    completion(nil, .serialization)
                }
            case .failure(let error):
                DDLogError("ProtoServiceCore/makeGroupChatStanza/\(toGroupId)/encryption/error [\(error)]")
                completion(nil, error)
            }
        }
    }

    private func makeRerequestGroupChatStanza(_ message: ChatMessageProtocol, for toUserID: UserID, in groupID: GroupID, completion: @escaping (Server_GroupChatStanza?, EncryptionError?) -> Void) {
        guard let messageData = try? message.protoContainer?.serializedData() else {
            DDLogError("ProtoServiceCore/makeRerequestGroupChatStanza/\(message.id)/error could not serialize group chat message!")
            completion(nil, nil)
            return
        }
        guard let toGroupId = message.chatMessageRecipient.toGroupId else {
            DDLogError("ProtoServiceCore/makeRerequestGroupChatStanza/\(message.id)/ error toGroupId not set for message: \(message.id)")
            completion(nil, nil)
            return
        }
        makeGroupRerequestEncryptedPayload(payloadData: messageData, groupID: groupID, for: toUserID) { result in
            switch result {
            case .failure(let failure):
                DDLogError("ProtoServiceCore/makeRerequestGroupChatStanza/\(toGroupId)/encryption/failure: \(failure)")
                completion(nil, failure)

            case .success((let clientEncryptedPayload, let senderStateWithKeyInfo)):
                DDLogInfo("ProtoServiceCore/makeRerequestGroupChatStanza/\(toGroupId)/encryption/success")
                var groupChatStanza = Server_GroupChatStanza()
                groupChatStanza.gid = toGroupId
                if !ServerProperties.sendClearTextGroupFeedContent {
                    groupChatStanza.payload = Data()
                }
                if let senderStateWithKeyInfo = senderStateWithKeyInfo {
                    groupChatStanza.senderState = senderStateWithKeyInfo
                }
                groupChatStanza.senderClientVersion = AppContext.userAgent
                do {
                    groupChatStanza.encPayload = try clientEncryptedPayload.serializedData()
                    switch message.content {
                    case .reaction:
                        groupChatStanza.chatType = .chatReaction
                    case .text, .album, .files, .voiceNote, .location, .unsupported:
                        groupChatStanza.chatType = .chat
                    }
                    groupChatStanza.mediaCounters = message.serverMediaCounters
                    completion(groupChatStanza, nil)
                } catch {
                    DDLogError("proto/makeRerequestGroupChatStanza/\(toGroupId)/payload-serialization/error \(error)")
                    completion(nil, .serialization)
                }
            }
        }
    }

    public func sendAck(messageId: String, completion: @escaping ServiceRequestCompletion<Void>) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            guard self.isConnected else {
                DDLogInfo("ProtoServiceCore/sendAck/\(messageId) skipping (disconnected)")
                completion(.failure(RequestError.notConnected))
                return
            }
            var ack = Server_Ack()
            ack.id = messageId
            var packet = Server_Packet()
            packet.stanza = .ack(ack)
            guard let packetData = try? packet.serializedData() else {
                DDLogError("ProtoServiceCore/sendAck/\(messageId)/error could not serialize ack!")
                completion(.failure(.malformedRequest))
                return
            }
            DispatchQueue.main.async {
                guard self.isConnected else {
                    DDLogInfo("ProtoServiceCore/sendAck/\(messageId) aborting (disconnected)")
                    completion(.failure(.notConnected))
                    return
                }
                DDLogInfo("ProtoServiceCore/sendAck/\(messageId))")
                self.send(packetData)
                completion(.success(()))
            }
        }
    }

    public func sendContentMissing(id contentID: String, type contentType: Server_ContentMissing.ContentType,
                                   to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            guard let fromUserID = self.credentials?.userID else {
                DDLogInfo("ProtoServiceCore/sendContentMissing/\(contentID) skipping (disconnected)")
                completion(.failure(RequestError.aborted))
                return
            }

            var contentMissing = Server_ContentMissing()
            contentMissing.contentID = contentID
            contentMissing.contentType = contentType
            contentMissing.senderClientVersion = AppContext.userAgent

            let packet = Server_Packet.msgPacket(
                from: fromUserID,
                to: toUserID,
                id: PacketID.generate(),
                payload: .contentMissing(contentMissing))

            guard let packetData = try? packet.serializedData() else {
                AppContext.shared.eventMonitor.count(.encryption(error: .serialization))
                DDLogError("ProtoServiceCore/sendContentMissing/\(contentID)/error could not serialize contentMissing!")
                completion(.failure(RequestError.malformedRequest))
                return
            }

            DDLogInfo("ProtoServiceCore/sendContentMissing/\(contentID) sending encrypted")
            self.send(packetData)
            DDLogInfo("ProtoServiceCore/sendContentMissing/\(contentID) success")
            completion(.success(()))
        }
    }

    public func rerequestMessage(_ messageID: String, senderID: UserID, failedEphemeralKey: Data?, contentType: Server_Rerequest.ContentType, completion: @escaping ServiceRequestCompletion<Void>) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            guard let userID = self.credentials?.userID else {
                DDLogError("proto/rerequestMessage/error no-user-id")
                completion(.failure(.notConnected))
                return
            }
            guard let identityKey = AppContext.shared.keyStore.keyBundle(in: AppContext.shared.keyStore.viewContext)?.identityPublicEdKey else {
                DDLogError("ProtoService/rerequestMessage/\(messageID)/error could not retrieve identity key")
                completion(.failure(.aborted))
                return
            }

            AppContext.shared.messageCrypter.sessionSetupInfoForRerequest(from: senderID) { setupInfo in
                guard let setupInfo = setupInfo else {
                    completion(.failure(.aborted))
                    return
                }
                var rerequest = Server_Rerequest()
                rerequest.id = messageID
                rerequest.identityKey = identityKey
                rerequest.signedPreKeyID = Int64(0)
                rerequest.oneTimePreKeyID = Int64(setupInfo.1)
                rerequest.sessionSetupEphemeralKey = setupInfo.0
                rerequest.messageEphemeralKey = failedEphemeralKey ?? Data()
                rerequest.contentType = contentType

                DDLogInfo("ProtoService/rerequestMessage/\(messageID) rerequesting")

                let packet = Server_Packet.msgPacket(
                    from: userID,
                    to: senderID,
                    id: PacketID.generate(),
                    type: .chat,
                    rerequestCount: 0,
                    payload: .rerequest(rerequest))

                guard let packetData = try? packet.serializedData() else {
                    DDLogError("ProtoServiceCore/rerequestMessage/\(messageID)/error could not serialize rerequest stanza!")
                    completion(.failure(.malformedRequest))
                    return
                }

                DispatchQueue.main.async {
                    guard self.isConnected else {
                        DDLogInfo("ProtoServiceCore/rerequestMessage/\(messageID) aborting (disconnected)")
                        completion(.failure(.notConnected))
                        return
                    }

                    DDLogInfo("ProtoServiceCore/rerequestMessage/\(messageID) sending")
                    self.send(packetData)
                    DDLogInfo("ProtoServiceCore/rerequestMessage/\(messageID) success")
                    completion(.success(()))
                }
            }
        }
    }

    public func retractChatMessage(messageID: String, toUserID: UserID, messageToRetractID: String, completion: @escaping ServiceRequestCompletion<Void>) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            guard let toUID = Int64(toUserID) else {
                DDLogError("ProtoServiceCore/retractChatMessage: \(messageToRetractID)/error invalid touid")
                completion(.failure(.aborted))
                return
            }
            guard let userID = self.credentials?.userID, let fromUID = Int64(userID) else {
                DDLogError("ProtoServiceCore/retractChatMessage: \(messageToRetractID)/error invalid sender uid")
                completion(.failure(.aborted))
                return
            }

            var packet = Server_Packet()
            packet.msg.toUid = toUID
            packet.msg.fromUid = fromUID
            packet.msg.id = messageID
            packet.msg.type = .chat

            var chatRetract = Server_ChatRetract()
            chatRetract.id = messageToRetractID

            packet.msg.payload = .chatRetract(chatRetract)

            guard let packetData = try? packet.serializedData() else {
                DDLogError("ProtoServiceCore/retractChatMessage: \(messageToRetractID)/error could not serialize packet")
                completion(.failure(.malformedRequest))
                return
            }

            DDLogInfo("ProtoServiceCore/retractChatMessage: \(messageToRetractID)/sending")
            self.send(packetData)
            DDLogInfo("ProtoServiceCore/retractChatMessage: \(messageToRetractID)/success")
            completion(.success(()))
        }
    }

    public func retractGroupChatMessage(messageID: String, groupID: GroupID, messageToRetractID: String, completion: @escaping ServiceRequestCompletion<Void>) {
        guard let userID = credentials?.userID, let fromUID = Int64(userID) else {
            DDLogError("ProtoService/retractChatGroupMessage/error invalid sender uid")
            completion(.failure(.aborted))
            return
        }

        var packet = Server_Packet()
        packet.msg.fromUid = fromUID
        packet.msg.id = messageID
        packet.msg.type = .groupchat

        var groupChatRetract = Server_GroupChatRetract()
        groupChatRetract.id = messageToRetractID
        groupChatRetract.gid = groupID

        packet.msg.payload = .groupchatRetract(groupChatRetract)

        guard let packetData = try? packet.serializedData() else {
            DDLogError("ProtoService/retractChatGroupMessage/error could not serialize packet")
            completion(.failure(.malformedRequest))
            return
        }

        DDLogInfo("ProtoService/retractChatGroupMessage")
        send(packetData)
        DDLogInfo("ProtoServiceCore/retractChatGroupMessage: \(messageToRetractID)/success")
        completion(.success(()))
    }

    public func retractGroupChatMessage(messageID: String, groupID: GroupID, to toUserID: UserID, messageToRetractID: String, completion: @escaping ServiceRequestCompletion<Void>) {
        guard let userID = credentials?.userID, let fromUID = Int64(userID) else {
            DDLogError("ProtoService/retractChatGroupMessage/error invalid sender uid")
            completion(.failure(.aborted))
            return
        }
        guard let toUID = Int64(toUserID) else {
            DDLogError("ProtoService/retractChatGroupMessage/error invalid to uid")
            completion(.failure(.aborted))
            return
        }

        var packet = Server_Packet()
        packet.msg.fromUid = fromUID
        packet.msg.toUid = toUID
        packet.msg.id = messageID
        packet.msg.type = .groupchat

        var groupChatRetract = Server_GroupChatRetract()
        groupChatRetract.id = messageToRetractID
        groupChatRetract.gid = groupID

        packet.msg.payload = .groupchatRetract(groupChatRetract)

        guard let packetData = try? packet.serializedData() else {
            DDLogError("ProtoService/retractChatGroupMessage/error could not serialize packet")
            completion(.failure(.malformedRequest))
            return
        }

        DDLogInfo("ProtoService/retractChatGroupMessage")
        send(packetData)
        DDLogInfo("ProtoServiceCore/retractChatGroupMessage: \(messageToRetractID)/success")
        completion(.success(()))
    }

    public func log(countableEvents: [CountableEvent], discreteEvents: [DiscreteEvent], completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoLoggingRequest(countableEvents: countableEvents, discreteEvents: discreteEvents, completion: completion))
    }

    // MARK: Key requests
    public func getGroupMemberIdentityKeys(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Server_GroupStanza>) {
        // Wait until connected to retry getting identity keys of group members.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: ProtoGroupMemberKeysRequest(groupID: groupID, completion: completion))
        }
    }

    public func getAudienceIdentityKeys(members: [UserID], completion: @escaping ServiceRequestCompletion<Server_WhisperKeysCollection>) {
        // Wait until connected to retry getting identity keys of various members.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: ProtoWhisperCollectionKeysRequest(members: members, completion: completion))
        }
    }

    // MARK: Receipts

    public func sendReceipt(itemID: String, thread: HalloReceipt.Thread, type: HalloReceipt.`Type`, fromUserID: UserID, toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        let receipt = HalloReceipt(itemId: itemID, userId: fromUserID, type: type, timestamp: nil, thread: thread)
        sendReceipt(receipt, to: toUserID, completion: completion)
    }

    // MARK: Usernames

    public func updateUsername(username: String, completion: @escaping ServiceRequestCompletion<Server_UsernameResponse>) {
        enqueue(request: ProtoUsernameRequest(username: username, action: .set, completion: completion))
    }

    public func checkUsernameAvailability(username: String, completion: @escaping ServiceRequestCompletion<Server_UsernameResponse>) {
        enqueue(request: ProtoUsernameRequest(username: username, action: .isAvailable, completion: completion))
    }

    // MARK: Links

    public func addProfileLink(type: Server_Link.TypeEnum, text: String, completion: @escaping ServiceRequestCompletion<Server_SetLinkResult>) {
        enqueue(request: ProtoLinkRequest(action: .set, type: type, string: text, completion: completion))
    }

    public func removeProfileLink(type: Server_Link.TypeEnum, text: String, completion: @escaping ServiceRequestCompletion<Server_SetLinkResult>) {
        enqueue(request: ProtoLinkRequest(action: .remove, type: type, string: text, completion: completion))
    }

    // MARK: Friendship

    public func modifyFriendship(userID: UserID,
                                 action: Server_FriendshipRequest.Action,
                                 completion: @escaping ServiceRequestCompletion<Server_HalloappUserProfile>) {

        enqueue(request: ProtoFriendshipRequest(userID: userID, action: action, completion: completion))
    }

    public func friendList(action: Server_FriendListRequest.Action,
                           cursor: String,
                           completion: @escaping ServiceRequestCompletion<(profiles: [Server_FriendProfile], cursor: String)>) {

        enqueue(request: ProtoFriendListRequest(action: action, cursor: cursor, completion: completion))
    }

    // MARK: Profile lookup

    public func userProfile(userID: UserID, completion: @escaping ServiceRequestCompletion<Server_HalloappUserProfile>) {
        enqueue(request: ProtoProfileRequest(userID: userID, completion: completion))
    }

    public func userProfile(username: String, completion: @escaping ServiceRequestCompletion<Server_HalloappUserProfile>) {
        enqueue(request: ProtoProfileRequest(username: username, completion: completion))
    }

    // MARK: Search

    public func searchUsernames(string: String, completion: @escaping ServiceRequestCompletion<[Server_HalloappUserProfile]>) {
        enqueue(request: ProtoUserSearchRequest(string: string, completion: completion))
    }
}
