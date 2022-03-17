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

    private enum GroupProcessingState {
        case ready
        case busy
    }

    public let didGetNewWhisperMessage = PassthroughSubject<WhisperMessage, Never>()

    // MARK: Avatar
    public weak var avatarDelegate: ServiceAvatarDelegate?

    private var pendingWorkItems = [GroupID: [DispatchWorkItem]]()
    private var groupStates = [GroupID: GroupProcessingState]()
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
}

extension ProtoServiceCore: CoreService {
    public func updateAvatar(_ avatarData: AvatarData?, for userID: UserID, completion: @escaping ServiceRequestCompletion<AvatarID?>) {
        var uploadAvatar = Server_UploadAvatar()
        uploadAvatar.id = userID
        if let thumbnailData = avatarData?.thumbnail {
            uploadAvatar.data = thumbnailData
        }
        if let fullData = avatarData?.full {
            uploadAvatar.fullData = fullData
        }

        let request = ProtoRequest<String?>(
            iqPacket: .iqPacket(type: .set, payload: .uploadAvatar(uploadAvatar)),
            transform: { (iq) in .success(iq.avatar.id) },
            completion: completion)

        enqueue(request: request)
    }

    public func requestMediaUploadURL(size: Int, downloadURL: URL?, completion: @escaping ServiceRequestCompletion<MediaURLInfo?>) {
        // Wait until connected to request URLs. User meanwhile can cancel posting.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: ProtoMediaUploadURLRequest(size: size, downloadURL: downloadURL, completion: completion))
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
                    completion(.failure(.aborted))
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
            DDLogInfo("ProtoServiceCore/publishPostInternal/\(post.id)/execute/begin")
            self.makePublishPostPayload(post, feed: feed) { result in
                switch result {
                case .failure(let error):
                    DDLogError("ProtoServiceCore/publishPostInternal/\(post.id)/makePublishPostPayload/error [\(error)]")
                    AppContext.shared.eventMonitor.count(.groupEncryption(error: error, itemType: .post))
                    completion(.failure(.malformedRequest))
                case .success(let iqPayload):
                    DDLogError("ProtoServiceCore/publishPostInternal/\(post.id)/makePublishPostPayload/success")
                    AppContext.shared.eventMonitor.count(.groupEncryption(error: nil, itemType: .post))
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

            makeGroupRerequestFeedItem(post, feed: feed, to: toUserID) { result in
                switch result {
                case .failure(let failure):
                    DDLogInfo("ProtoServiceCore/resendPost/\(post.id)/failure: \(failure), aborting to: \(toUserID)")
                    AppContext.shared.eventMonitor.count(.groupEncryption(error: failure, itemType: .post))
                    completion(.failure(RequestError.malformedRequest))
                case .success(let serverGroupFeedItem):
                    let messageID = PacketID.generate()
                    DDLogInfo("ProtoServiceCore/resendPost/\(post.id)/message/\(messageID)/to: \(toUserID)")
                    let packet = Server_Packet.msgPacket(
                        from: fromUserID,
                        to: toUserID,
                        id: messageID,
                        type: .groupchat,
                        rerequestCount: rerequestCount,
                        payload: .groupFeedItem(serverGroupFeedItem))

                    guard let packetData = try? packet.serializedData() else {
                        AppContext.shared.eventMonitor.count(.groupEncryption(error: .serialization, itemType: .post))
                        DDLogError("ProtoServiceCore/resendPost/\(post.id)/message/\(messageID)/error could not serialize groupFeedItem message!")
                        completion(.failure(RequestError.malformedRequest))
                        return
                    }

                    DispatchQueue.main.async {
                        guard self.isConnected else {
                            DDLogInfo("ProtoServiceCore/resendPost/\(post.id)/message/\(messageID) aborting (disconnected)")
                            completion(.failure(RequestError.notConnected))
                            return
                        }
                        AppContext.shared.eventMonitor.count(.groupEncryption(error: nil, itemType: .post))
                        DDLogInfo("ProtoServiceCore/resendPost/\(post.id)/message/\(messageID) sending encrypted")
                        self.send(packetData)
                        DDLogInfo("ProtoServiceCore/resendPost/\(post.id)/message/\(messageID) success")
                        completion(.success(()))
                    }
                }
            }
        }
    }

    public func resendComment(_ comment: CommentData, groupId: GroupID?, rerequestCount: Int32, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) { [self] in
            guard let fromUserID = credentials?.userID, self.isConnected else {
                DDLogInfo("ProtoServiceCore/resendComment/\(comment.id) skipping (disconnected)")
                completion(.failure(RequestError.notConnected))
                return
            }

            makeGroupRerequestFeedItem(comment, groupID: groupId, to: toUserID) { result in
                switch result {
                case .failure(let failure):
                    DDLogInfo("ProtoServiceCore/resendComment/\(comment.id)/failure: \(failure), aborting to: \(toUserID)")
                    AppContext.shared.eventMonitor.count(.groupEncryption(error: failure, itemType: .comment))
                    completion(.failure(RequestError.malformedRequest))
                case .success(let serverGroupFeedItem):
                    let messageID = PacketID.generate()
                    DDLogInfo("ProtoServiceCore/resendComment/\(comment.id)/message/\(messageID)/to: \(toUserID)")
                    let packet = Server_Packet.msgPacket(
                        from: fromUserID,
                        to: toUserID,
                        id: messageID,
                        type: .groupchat,
                        rerequestCount: rerequestCount,
                        payload: .groupFeedItem(serverGroupFeedItem))

                    guard let packetData = try? packet.serializedData() else {
                        AppContext.shared.eventMonitor.count(.groupEncryption(error: .serialization, itemType: .comment))
                        DDLogError("ProtoServiceCore/resendComment/\(comment.id)/message/\(messageID)/error could not serialize groupFeedItem message!")
                        completion(.failure(RequestError.malformedRequest))
                        return
                    }

                    DispatchQueue.main.async {
                        guard self.isConnected else {
                            DDLogInfo("ProtoServiceCore/resendComment/\(comment.id)/message/\(messageID) aborting (disconnected)")
                            completion(.failure(RequestError.notConnected))
                            return
                        }
                        AppContext.shared.eventMonitor.count(.groupEncryption(error: nil, itemType: .comment))
                        DDLogInfo("ProtoServiceCore/resendComment/\(comment.id)/message/\(messageID) sending encrypted")
                        self.send(packetData)
                        DDLogInfo("ProtoServiceCore/resendComment/\(comment.id)/message/\(messageID) success")
                        completion(.success(()))
                    }
                }
            }
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
                    AppContext.shared.eventMonitor.count(.groupEncryption(error: error, itemType: .comment))
                    completion(.failure(.malformedRequest))
                case .success(let iqPayload):
                    DDLogError("ProtoServiceCore/publishCommentInternal/\(comment.id)/makePublishCommentPayload/success")
                    AppContext.shared.eventMonitor.count(.groupEncryption(error: nil, itemType: .comment))
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
        guard let payloadData = try? post.clientContainer.serializedData() else {
            completion(.failure(.serialization))
            return
        }

        var serverPost = Server_Post()
        serverPost.payload = payloadData
        serverPost.id = post.id
        serverPost.publisherUid = Int64(post.userId) ?? 0
        serverPost.timestamp = Int64(post.timestamp.timeIntervalSince1970)

        // Add media counters.
        serverPost.mediaCounters = post.serverMediaCounters

        switch feed {
        case .group(let groupID):
            // Clear unencrypted payload if server prop is disabled.
            if !ServerProperties.sendClearTextGroupFeedContent {
                serverPost.payload = Data()
            }
            makeGroupEncryptedPayload(payloadData: payloadData, groupID: groupID, oneOfItem: .post(serverPost)) { result in
                switch result {
                case .failure(let failure):
                    completion(.failure(failure))
                case .success(let serverGroupFeedItem):
                    completion(.success(.groupFeedItem(serverGroupFeedItem)))
                }
            }
        case .personal(let audience):
            var serverAudience = Server_Audience()
            serverAudience.uids = audience.userIds.compactMap { Int64($0) }
            serverAudience.type = {
                switch audience.audienceType {
                case .all: return .all
                case .blacklist: return .except
                case .whitelist: return .only
                case .group:
                    DDLogError("ProtoServiceCore/makePublishPostPayload/error unsupported audience type [\(audience.audienceType)]")
                    return .only
                }
            }()
            serverPost.audience = serverAudience

            var item = Server_FeedItem()
            item.action = .publish
            item.item = .post(serverPost)

            completion(.success(.feedItem(item)))
        }
    }

    private func makePublishCommentPayload(_ comment: CommentData, groupID: GroupID?, completion: @escaping (Result<Server_Iq.OneOf_Payload, EncryptionError>) -> Void) {
        guard var serverComment = comment.serverComment else {
            completion(.failure(.serialization))
            return
        }
        let payloadData = serverComment.payload
        // Clear unencrypted payload if server prop is disabled.
        if !ServerProperties.sendClearTextGroupFeedContent {
            serverComment.payload = Data()
        }

        // Add media counters.
        serverComment.mediaCounters = comment.serverMediaCounters

        if let groupID = groupID {
            makeGroupEncryptedPayload(payloadData: payloadData, groupID: groupID, oneOfItem: .comment(serverComment)) { result in
                switch result {
                case .failure(let failure):
                    completion(.failure(failure))
                case .success(let serverGroupFeedItem):
                    completion(.success(.groupFeedItem(serverGroupFeedItem)))
                }
            }
        } else {
            var item = Server_FeedItem()
            item.action = .publish
            item.item = .comment(serverComment)

            completion(.success(.feedItem(item)))
        }
    }

    private func makeGroupEncryptedPayload(payloadData: Data, groupID: GroupID, oneOfItem: Server_GroupFeedItem.OneOf_Item, completion: @escaping (Result<Server_GroupFeedItem, EncryptionError>) -> Void) {
        var item = Server_GroupFeedItem()
        item.action = .publish
        item.gid = groupID
        item.senderClientVersion = AppContext.userAgent

        // encrypt the containerPayload
        AppContext.shared.messageCrypter.encrypt(payloadData, in: groupID) { result in
            switch result {
            case .failure(let error):
                DDLogError("ProtoServiceCore/makeGroupEncryptedPayload/\(groupID)/encryption/error [\(error)]")
                completion(.failure(.missingKeyBundle))
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
            case .failure(let error):
                DDLogError("ProtoServiceCore/makeGroupRerequestEncryptedPayload/\(groupID)/encryption/error [\(error)]")
                completion(.failure(.missingKeyBundle))
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

    private func makeChatStanza(_ message: ChatMessageProtocol, completion: @escaping (Server_ChatStanza?, EncryptionError?) -> Void) {
        guard let messageData = try? message.protoContainer?.serializedData() else {
            DDLogError("ProtoServiceCore/makeChatStanza/\(message.id)/error could not serialize chat message!")
            completion(nil, nil)
            return
        }

        AppContext.shared.messageCrypter.encrypt(messageData, for: message.toUserId) { result in
            switch result {
            case .success((let encryptedData, var logInfo)):
                logInfo["TS"] = self.dateTimeFormatterMonthDayTime.string(from: Date())

                var chat = Server_ChatStanza()
                chat.senderLogInfo = logInfo.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "; ")
                chat.encPayload = encryptedData.data
                chat.oneTimePreKeyID = Int64(encryptedData.oneTimeKeyId)

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

    private func makeGroupRerequestFeedItem(_ post: PostData, feed: Feed, to toUserID: UserID, completion: @escaping (Result<Server_GroupFeedItem, EncryptionError>) -> Void) {
        guard let payloadData = try? post.clientContainer.serializedData() else {
            completion(.failure(.serialization))
            return
        }

        var serverPost = Server_Post()
        serverPost.payload = payloadData
        serverPost.id = post.id
        serverPost.publisherUid = Int64(post.userId) ?? 0
        serverPost.timestamp = Int64(post.timestamp.timeIntervalSince1970)

        // Add media counters.
        serverPost.mediaCounters = post.serverMediaCounters

        switch feed {
        case .group(let groupID):
            // Clear unencrypted payload if server prop is disabled.
            if !ServerProperties.sendClearTextGroupFeedContent {
                serverPost.payload = Data()
            }
            var item = Server_GroupFeedItem()
            item.action = .publish
            item.gid = groupID
            item.senderClientVersion = AppContext.userAgent
            makeGroupRerequestEncryptedPayload(payloadData: payloadData, groupID: groupID, for: toUserID) { result in
                switch result {
                case .failure(let failure):
                    completion(.failure(failure))
                case .success((let clientEncryptedPayload, let senderStateWithKeyInfo)):
                    do {
                        serverPost.encPayload = try clientEncryptedPayload.serializedData()
                        item.item = .post(serverPost)
                        if let senderStateWithKeyInfo = senderStateWithKeyInfo {
                            item.senderState = senderStateWithKeyInfo
                        }
                        completion(.success(item))
                    } catch {
                        DDLogError("ProtoServiceCore/makeGroupRerequestFeedItem/\(groupID)/payload-serialization/error \(error)")
                        completion(.failure(.serialization))
                        return
                    }
                }
            }
        case .personal(_):
            DDLogError("ProtoServiceCore/makeGroupRerequestFeedItem/post/unsupported resending messages")
            completion(.failure(.missingKeyBundle))
        }
    }

    private func makeGroupRerequestFeedItem(_ comment: CommentData, groupID: GroupID?, to toUserID: UserID, completion: @escaping (Result<Server_GroupFeedItem, EncryptionError>) -> Void) {
        guard var serverComment = comment.serverComment else {
            completion(.failure(.serialization))
            return
        }
        let payloadData = serverComment.payload
        // Clear unencrypted payload if server prop is disabled.
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
                    completion(.failure(failure))
                case .success((let clientEncryptedPayload, let senderStateWithKeyInfo)):
                    do {
                        serverComment.encPayload = try clientEncryptedPayload.serializedData()
                        item.item = .comment(serverComment)
                        if let senderStateWithKeyInfo = senderStateWithKeyInfo {
                            item.senderState = senderStateWithKeyInfo
                        }
                        completion(.success(item))
                    } catch {
                        DDLogError("ProtoServiceCore/makeGroupRerequestFeedItem/\(groupID)/payload-serialization/error \(error)")
                        completion(.failure(.serialization))
                        return
                    }
                }
            }
        } else {
            DDLogError("ProtoServiceCore/makeGroupRerequestFeedItem/comment/unsupported resending messages")
            completion(.failure(.missingKeyBundle))
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
                contentType: "historyResend",
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
                newCompletion(nil, GroupDecryptionFailure(nil, nil, .missingPayload, .payload))
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
            }
            DDLogInfo("ProtoServiceCore/decryptGroupFeedPayload/contentId/\(item.gid)/\(contentId), publisherUid: \(publisherUid)/end")
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
                from: publisherUid) { [weak self] result in
                    guard let self = self else {
                        completion(.failure(GroupDecryptionFailure(contentId, publisherUid, .missingSenderState, .senderState)))
                        return
                    }
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
            completion(nil, GroupDecryptionFailure(nil, nil, .missingPayload, .payload))
            return
        }

        switch item.item {
        case .post(let serverPost):
            guard let post = PostData(id: serverPost.id,
                                      userId: publisherUid,
                                      timestamp: Date(timeIntervalSince1970: TimeInterval(serverPost.timestamp)),
                                      payload: payload,
                                      status: .received,
                                      isShared: false, audience: serverPost.audience) else {
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

    public func reportGroupDecryptionResult(error: DecryptionError?, contentID: String, contentType: String, groupID: GroupID, timestamp: Date, sender: UserAgent?, rerequestCount: Int) {
        if (error == .missingPayload) {
            DDLogInfo("proto/reportGroupDecryptionResult/\(contentID)/\(contentType)/\(groupID)/payload is missing - not error.")
            return
        }
        let errorString = error?.rawValue ?? ""
        DDLogInfo("proto/reportGroupDecryptionResult/\(contentID)/\(contentType)/\(groupID)/error value: \(errorString)")
        AppContext.shared.eventMonitor.count(.groupDecryption(error: error, itemTypeString: contentType, sender: sender))
        AppContext.shared.cryptoData.update(contentID: contentID,
                                            contentType: contentType,
                                            groupID: groupID,
                                            timestamp: timestamp,
                                            error: errorString,
                                            sender: sender,
                                            rerequestCount: rerequestCount)
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
        AppContext.shared.cryptoData.performOnBackgroundContextAndWait { managedObjectContext in
            guard let result = AppContext.shared.cryptoData.fetchGroupFeedItemDecryption(id: contentID, in: managedObjectContext) else {
                isGroupFeedItemDecrypted = false
                return
            }
            isGroupFeedItemDecrypted = result.isSuccess()
        }
        if isGroupFeedItemDecrypted {
            DDLogInfo("ProtoService/isGroupFeedItemDecryptedAndSaved/contentID \(contentID) success")
            return true
        }
        DDLogInfo("ProtoService/isGroupFeedItemDecryptedAndSaved/contentID \(contentID) - content is missing.")
        return false

        // Lets try using only the stats store this time and see how it works out.
    }

    public func rerequestGroupFeedItemIfNecessary(id contentID: String, groupID: GroupID, contentType: GroupFeedRerequestContentType, failure: GroupDecryptionFailure, completion: @escaping ServiceRequestCompletion<Void>) {
        guard let authorUserID = failure.fromUserId else {
            DDLogError("proto/rerequestGroupFeedItemIfNecessary/\(contentID)/decrypt/authorUserID missing")
            return
        }

        // Dont rerequest messages that were already decrypted and saved.
        if !isGroupFeedItemDecryptedAndSaved(contentID: contentID) {
            self.rerequestGroupFeedItem(contentId: contentID,
                                        groupID: groupID,
                                        authorUserID: authorUserID,
                                        rerequestType: failure.rerequestType,
                                        contentType: contentType,
                                        completion: completion)
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

    public func sendChatMessage(_ message: ChatMessageProtocol, completion: @escaping ServiceRequestCompletion<Void>) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            guard let fromUserID = self.credentials?.userID else {
                DDLogInfo("ProtoServiceCore/sendChatMessage/\(message.id) skipping (disconnected)")
                completion(.failure(RequestError.aborted))
                return
            }

            self.makeChatStanza(message) { chat, error in
                guard let chat = chat else {
                    completion(.failure(RequestError.malformedRequest))
                    return
                }

                // Dont send chat messages on encryption errors.
                if let error = error {
                    DDLogInfo("ProtoServiceCore/sendChatMessage/\(message.id)/error \(error)")
                    AppContext.shared.errorLogger?.logError(error)
                    DDLogInfo("ProtoServiceCore/sendChatMessage/\(message.id) aborted")
                    completion(.failure(RequestError.aborted))
                    return
                }

                let packet = Server_Packet.msgPacket(
                    from: fromUserID,
                    to: message.toUserId,
                    id: message.id,
                    type: .chat,
                    rerequestCount: message.rerequestCount,
                    payload: .chatStanza(chat))

                guard let packetData = try? packet.serializedData() else {
                    AppContext.shared.eventMonitor.count(.encryption(error: .serialization))
                    DDLogError("ProtoServiceCore/sendChatMessage/\(message.id)/error could not serialize chat message!")
                    completion(.failure(RequestError.malformedRequest))
                    return
                }

                DispatchQueue.main.async {
                    guard self.isConnected else {
                        DDLogInfo("ProtoServiceCore/sendChatMessage/\(message.id) aborting (disconnected)")
                        completion(.failure(RequestError.notConnected))
                        return
                    }
                    AppContext.shared.eventMonitor.count(.encryption(error: error))
                    DDLogInfo("ProtoServiceCore/sendChatMessage/\(message.id) sending encrypted")
                    self.send(packetData)
                    DDLogInfo("ProtoServiceCore/sendChatMessage/\(message.id) success")
                    completion(.success(()))
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

    public func rerequestMessage(_ messageID: String, senderID: UserID, failedEphemeralKey: Data?, contentType: Server_Rerequest.ContentType, completion: @escaping ServiceRequestCompletion<Void>) {
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            guard let userID = self.credentials?.userID else {
                DDLogError("proto/rerequestMessage/error no-user-id")
                completion(.failure(.notConnected))
                return
            }
            guard let identityKey = AppContext.shared.keyStore.keyBundle()?.identityPublicEdKey else {
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
}
