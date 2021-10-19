//
//  ProtoServiceCore.swift
//  Core
//
//  Created by Garrett on 8/25/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Foundation

enum Stream {
    case noise(NoiseStream)
}

open class ProtoServiceCore: NSObject, ObservableObject {

    // MARK: Avatar
    public weak var avatarDelegate: ServiceAvatarDelegate?
    public weak var keyDelegate: ServiceKeyDelegate?

    private class ConnectionStateCallback {
        let state: ConnectionState
        let work: (DispatchGroup) -> ()

        required init(state: ConnectionState, work: @escaping (DispatchGroup) -> ()) {
            self.state = state
            self.work = work
        }
    }

    // MARK: Connection State
    public private(set) var connectionState: ConnectionState = .notConnected {
        didSet {
            if oldValue == connectionState { return }
            DDLogDebug("proto/connectionState/change [\(oldValue)] -> [\(connectionState)]")
            if connectionState == .notConnected {
                cancelAllRequests()
                didDisconnect.send()
            }
            runCallbacksForCurrentConnectionState()
            if oldValue == .connected && connectionState == .notConnected {
                startReconnectTimerIfNecessary()
            }
        }
    }
    
    public var reachabilityState: ReachablilityState = .reachable

    public var isAppVersionKnownExpired = CurrentValueSubject<Bool, Never>(false)
    public var isAppVersionCloseToExpiry = CurrentValueSubject<Bool, Never>(false)

    public var isConnected: Bool { get { connectionState == .connected } }
    public var isDisconnected: Bool { get { connectionState == .disconnecting || connectionState == .notConnected } }
    public var isReachable: Bool { get { reachabilityState == .reachable } }

    public let didConnect = PassthroughSubject<Void, Never>()
    public let didDisconnect = PassthroughSubject<Void, Never>()

    private var stream: Stream?
    public let userData: UserData

    required public init(userData: UserData, passiveMode: Bool = false, automaticallyReconnect: Bool = true) {
        self.userData = userData
        self.isPassiveMode = passiveMode
        self.isAutoReconnectEnabled = automaticallyReconnect
        super.init()

        configureStream(with: userData)
    }

    // MARK: Connection management

    private let isPassiveMode: Bool
    private let isAutoReconnectEnabled: Bool

    public func send(_ data: Data) {
        switch stream {
        case .noise(let noise):
            noise.send(data)
        case .none:
            DDLogError("proto/send/error no stream configured!")
        }
    }

    public func configureStream(with userData: UserData?) {
        DDLogInfo("proto/stream/configure [\(userData?.userId ?? "nil")]")
        switch userData?.credentials {
        case .v2(let userID, let noiseKeys):
            let noise = NoiseStream(
                            noiseKeys: noiseKeys,
                            serverStaticKey: Keychain.loadServerStaticKey(for: userID),
                            delegate: self)
            stream = .noise(noise)
        case .none:
            return
        }
    }

    public func startConnectingIfNecessary() {
        guard let stream = stream else { return }
        switch stream {
        case .noise(let noise):
            if noise.isReadyToConnect {
                connect()
            }
        }
    }

    public func connect() {
        guard !isAppVersionKnownExpired.value else {
            DDLogInfo("proto/connect/skipping (expired app version)")
            return
        }
        guard let stream = stream else { return }
        switch stream {
        case .noise(let noise):
            noise.connect(host: userData.hostName, port: userData.hostPort)
        }

        // Retry if we're not connected in 10 seconds (cancel pending retry if it exists)
        retryConnectionTask?.cancel()
        let retryConnection = DispatchWorkItem {
            guard self.isReachable else {
                DDLogInfo("proto/retryConnectionTask/skipping (client is unreachable)")
                return
            }
            self.startConnectingIfNecessary()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: retryConnection)
        retryConnectionTask = retryConnection
    }

    public func disconnect() {
        DDLogInfo("proto/disconnect")

        shouldReconnectOnConnectionLoss = false
        retryConnectionTask?.cancel()
        connectionState = .disconnecting
        switch stream {
        case .noise(let noise):
            noise.disconnect(afterSending: true)
        case .none:
            break
        }
    }

    public func disconnectImmediately() {
        DDLogInfo("proto/disconnectImmediately")

        shouldReconnectOnConnectionLoss = false
        retryConnectionTask?.cancel()
        connectionState = .notConnected
        switch stream {
        case .noise(let noise):
            noise.disconnect()
        case .none:
            break
        }
    }

    private func startReconnectTimerIfNecessary() {
        guard shouldReconnectOnConnectionLoss else {
            return
        }
        DDLogInfo("proto/reconnect/timer start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            DDLogInfo("proto/reconnect/timer fired")
            // This only needs to be called once, connect() will reattempt as necessary
            self.startConnectingIfNecessary()
        }
    }

    private var shouldReconnectOnConnectionLoss = false

    private var retryConnectionTask: DispatchWorkItem?

    private lazy var dateTimeFormatterMonthDayTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.setLocalizedDateFormatFromTemplate("jdMMMHHmm")
        return dateFormatter
    }()

    // MARK: State Change Callbacks

    private var stateChangeCallbacks: [ConnectionStateCallback] = []

    public func execute(whenConnectionStateIs state: ConnectionState, onQueue queue: DispatchQueue, work: @escaping @convention(block) () -> Void) {
        stateChangeCallbacks.append(ConnectionStateCallback(state: state) { (dispatchGroup) in
            queue.async(group: dispatchGroup, execute: work)
        })

        if connectionState == state {
            runCallbacksForCurrentConnectionState()
        }
    }

    private func runCallbacksForCurrentConnectionState() {
        let currentState = connectionState

        let callbacks = stateChangeCallbacks.filter { $0.state == currentState }
        guard !callbacks.isEmpty else { return }

        stateChangeCallbacks.removeAll(where: { $0.state == currentState })

        let group = DispatchGroup()
        callbacks.forEach{ $0.work(group) }
    }

    // MARK: Requests

    private let requestsQueue = DispatchQueue(label: "com.halloapp.proto.requests", qos: .userInitiated)

    private var requestsInFlight: [ProtoRequestBase] = []

    private var requestsToSend: [ProtoRequestBase] = []

    public func enqueue(request: ProtoRequestBase) {
        requestsQueue.async {
            if self.isConnected {
                request.send(using: self)
                self.requestsInFlight.append(request)
            } else if request.retriesRemaining > 0 {
                self.requestsToSend.append(request)
            } else {
                request.failOnNoConnection()
            }
        }
    }

    /**
     All requests in the queue are automatically resent when the connection is opened.
     */
    func resendAllPendingRequests() {
        requestsQueue.async {
            guard !self.requestsToSend.isEmpty else {
                return
            }
            guard self.isConnected else {
                DDLogWarn("connection/requests/resend/skipped [\(self.requestsToSend.count)] [no connection]")
                return
            }

            let allRequests = self.requestsToSend
            self.requestsToSend.removeAll()

            DDLogInfo("connection/requests/resend [\(allRequests.count)]")
            for request in allRequests {
                request.send(using: self)
            }
            self.requestsInFlight.append(contentsOf: allRequests)
        }
    }

    func cancelAllRequests() {
        requestsQueue.async {
            DDLogInfo("connection/requests/cancel/all [\(self.requestsInFlight.count)]")

            let allRequests = self.requestsInFlight + self.requestsToSend
            self.requestsInFlight.removeAll()
            self.requestsToSend.removeAll()

            for request in allRequests {
                if request.cancelAndPrepareFor(retry: true) {
                    self.requestsToSend.append(request)
                }
            }
        }
    }

    // MARK: Override points for subclasses.

    open func authenticationSucceeded(with authResult: Server_AuthResult) {
        DDLogInfo("ProtoServiceCore/authenticationSucceeded")
        connectionState = .connected
        DispatchQueue.main.async {
            self.performOnConnect()
        }

        // check the time left for version to expire.
        // if it's too close - we need to present a warning to the user.
        let numDaysLeft = authResult.versionTtl/86400
        DDLogInfo("ProtoServiceCore/versionTtl/days left: \(numDaysLeft)")
        if numDaysLeft < 10 {
            DispatchQueue.main.async {
                self.isAppVersionCloseToExpiry.send(true)
            }
        }
    }

    open func authenticationFailed(with authResult: Server_AuthResult) {
        DDLogInfo("ProtoServiceCore/authenticationFailed [\(authResult)]")
        switch authResult.reason {
        case .invalidClientVersion:
            DispatchQueue.main.async {
                self.isAppVersionKnownExpired.send(true)
            }
        case .accountDeleted, .invalidResource, .invalidUidOrPassword, .ok, .spubMismatch, .unknownReason, .UNRECOGNIZED:
            switch authResult.result {
            case .failure:
                DispatchQueue.main.async {
                    self.userData.logout()
                }
            case .UNRECOGNIZED, .unknown, .success:
                DDLogError("ProtoServiceCore/authenticationFailed/unexpected-result [\(authResult.result)] [\(authResult.reason)]")
            }
        }
    }

    open func performOnConnect() {
        didConnect.send()
        retryConnectionTask?.cancel()
        shouldReconnectOnConnectionLoss = isAutoReconnectEnabled
        resendAllPendingRequests()
    }

    open func didReceive(packet: Server_Packet) {
        let requestID = packet.requestID ?? "unknown-id"
        DDLogInfo("proto/didReceivePacket/\(requestID)")
        func removeRequest(with id: String, outOf requests: inout [ProtoRequestBase]) -> [ProtoRequestBase] {
            let filteredSequence = requests.enumerated().filter { $0.element.requestId == id }
            let indexes = filteredSequence.map { $0.offset }
            let results = filteredSequence.map { $0.element }
            requests = requests.enumerated().filter { !indexes.contains($0.offset) }.map { $0.element }
            return results
        }

        // Process request responses.  We should theoretically only get back
        // responses for requests that we have sent, but in case of accidentally
        // sending a duplicated request or delayed processing related to dropping
        // a connection, we should still check both arrays.
        requestsQueue.async {
            var matchingRequests: [ProtoRequestBase] = []
            matchingRequests.append(contentsOf: removeRequest(with: requestID, outOf: &self.requestsInFlight))
            matchingRequests.append(contentsOf: removeRequest(with: requestID, outOf: &self.requestsToSend))
            if matchingRequests.count > 1 {
                DDLogWarn("connection/response/\(requestID)/warning: found \(matchingRequests.count) requests")
            }
            for request in matchingRequests {
                DDLogInfo("connection/response/\(type(of: request))/\(requestID)")
                request.process(response: packet)
            }
        }
    }
}

extension ProtoServiceCore: NoiseDelegate {
    public func receivedPacketData(_ packetData: Data) {
        guard let packet = try? Server_Packet(serializedData: packetData) else {
            DDLogError("proto/received/error could not deserialize packet [\(packetData.base64EncodedString())]")
            return
        }
        didReceive(packet: packet)
    }

    public func connectionPayload() -> Data? {
        var deviceInfo = Server_DeviceInfo()
        deviceInfo.device = UIDevice.current.getModelName()
        deviceInfo.osVersion = UIDevice.current.systemVersion

        var clientConfig = Server_AuthRequest()
        clientConfig.clientMode.mode = isPassiveMode ? .passive : .active
        clientConfig.clientVersion.version = AppContext.userAgent
        clientConfig.resource = "iphone"
        clientConfig.deviceInfo = deviceInfo
        if let uid = Int64(userData.userId) {
            clientConfig.uid = uid
        } else {
            DDLogError("ProtoServiceCore/connectionPayload/error invalid userID [\(userData.userId)]")
        }
        DDLogInfo("ProtoServiceCore/connectionPayload [passiveMode: \(isPassiveMode)]")
        return try? clientConfig.serializedData()
    }

    public func receivedConnectionResponse(_ responseData: Data) -> Bool {
        guard let authResult = try? Server_AuthResult(serializedData: responseData) else {
            return false
        }

        switch authResult.result {
        case .success:
            authenticationSucceeded(with: authResult)
            return true
        case .failure, .unknown, .UNRECOGNIZED:
            // Consider any non-success result a failure (user won't necessarily be logged out)
            authenticationFailed(with: authResult)
            return false
        }
    }

    public func updateConnectionState(_ connectionState: ConnectionState) {
        self.connectionState = connectionState
    }

    public func receivedServerStaticKey(_ key: Data) {
        Keychain.saveServerStaticKey(key, for: userData.userId)
    }
}

extension ProtoServiceCore: CoreService {
    public func requestMediaUploadURL(size: Int, downloadURL: URL?, completion: @escaping ServiceRequestCompletion<MediaURLInfo?>) {
        // Wait until connected to request URLs. User meanwhile can cancel posting.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: ProtoMediaUploadURLRequest(size: size, downloadURL: downloadURL, completion: completion))
        }
    }

    public func requestWhisperKeyBundle(userID: UserID, completion: @escaping ServiceRequestCompletion<WhisperKeyBundle>) {
        enqueue(request: ProtoWhisperGetBundleRequest(targetUserId: userID, completion: completion))
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
        guard self.isConnected else {
            DDLogInfo("ProtoServiceCore/resendPost/\(post.id) skipping (disconnected)")
            completion(.failure(RequestError.notConnected))
            return
        }

        let fromUserID = userData.userId
        makeGroupFeedMessage(post, feed: feed, to: toUserID) { result in
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

    public func resendComment(_ comment: CommentData, groupId: GroupID?, rerequestCount: Int32, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        guard self.isConnected else {
            DDLogInfo("ProtoServiceCore/resendComment/\(comment.id) skipping (disconnected)")
            completion(.failure(RequestError.notConnected))
            return
        }

        let fromUserID = userData.userId

        makeGroupFeedMessage(comment, groupID: groupId, to: toUserID) { result in
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
                    DDLogError("ProtoServiceCore/publishCommentInternal/\(comment.id)/makePublishPostPayload/success")
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
        guard let payloadData = try? post.clientContainer?.serializedData() else {
            completion(.failure(.serialization))
            return
        }

        var serverPost = Server_Post()
        serverPost.payload = payloadData
        serverPost.id = post.id
        serverPost.publisherUid = Int64(post.userId) ?? 0
        serverPost.timestamp = Int64(post.timestamp.timeIntervalSince1970)

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

        // encrypt the containerPayload
        AppContext.shared.messageCrypter.encrypt(payloadData, in: groupID) { result in
            switch result {
            case .failure(let error):
                DDLogError("ProtoServiceCore/makeGroupEncryptedPayload/\(groupID)/encryption/error [\(error)]")
                completion(.failure(.missingKeyBundle))
            case .success(let groupEncryptedData):
                guard let audienceHash = groupEncryptedData.audienceHash else {
                    DDLogError("ProtoServiceCore/makeGroupEncryptedPayload/\(groupID)/encryption/error missingAudienceHash")
                    completion(.failure(.missingAudienceHash))
                    return
                }
                item.audienceHash = audienceHash
                // We need to construct senderStateBundles for all the receiverUids necessary and then publish the post/comment.
                var senderStateBundles: [Server_SenderStateBundle] = []
                var numberOfFailedEncrypts = 0
                let encryptGroup = DispatchGroup()
                let encryptCompletion: (Result<(EncryptedData, EncryptionLogInfo), EncryptionError>) -> Void = { result in
                    switch result {
                    case .failure(_):
                        numberOfFailedEncrypts += 1
                        DDLogError("ProtoServiceCore/makeGroupEncryptedPayload/\(groupID)/encryptCompletion/error \(numberOfFailedEncrypts)")
                    default:
                        break
                    }
                    encryptGroup.leave()
                }

                do {
                    if !groupEncryptedData.receiverUids.isEmpty {
                        guard let chainKey = groupEncryptedData.senderKey?.chainKey,
                              let signKey = groupEncryptedData.senderKey?.publicSignatureKey,
                              let chainIndex = groupEncryptedData.chainIndex else {
                                  completion(.failure(.missingKeyBundle))
                                  DDLogError("ProtoServiceCore/makeGroupEncryptedPayload/\(groupID)/missingSenderState")
                                  return
                              }

                        // construct own senderState
                        var senderKey = Clients_SenderKey()
                        senderKey.chainKey = chainKey
                        senderKey.publicSignatureKey = signKey
                        var senderState = Clients_SenderState()
                        senderState.senderKey = senderKey
                        senderState.currentChainIndex = chainIndex
                        let senderStatePayload = try senderState.serializedData()

                        // encrypt senderState using 1-1 channel for all the receivers.
                        for receiverUserID in groupEncryptedData.receiverUids {
                            encryptGroup.enter()
                            AppContext.shared.messageCrypter.encrypt(senderStatePayload, for: receiverUserID) { result in
                                var senderStateWithKeyInfo = Server_SenderStateWithKeyInfo()
                                var senderStateBundle = Server_SenderStateBundle()
                                senderStateBundle.uid = Int64(receiverUserID) ?? 0
                                switch result {
                                case .failure(_):
                                    DDLogError("ProtoServiceCore/makeGroupEncryptedPayload/\(groupID)/failed to encrypt for userID: \(receiverUserID)")
                                    break
                                case .success((let encryptedData, _)):
                                    if let publicKey = encryptedData.identityKey, !publicKey.isEmpty {
                                        senderStateWithKeyInfo.publicKey = publicKey
                                        senderStateWithKeyInfo.oneTimePreKeyID = Int64(encryptedData.oneTimeKeyId)
                                    }
                                    senderStateWithKeyInfo.encSenderState = encryptedData.data
                                }
                                senderStateBundle.senderState = senderStateWithKeyInfo
                                senderStateBundles.append(senderStateBundle)
                                encryptCompletion(result)
                            }
                        }
                    }

                    encryptGroup.notify(queue: .main) {
                        // After successfully obtaining the senderStateBundles
                        // construct the encPayload and senderStateBundles in the feeditem and payload(post/comment) stanza
                        // publish it
                        if numberOfFailedEncrypts > 0 {
                            DDLogError("proto/makeGroupEncryptedPayload/\(groupID)/encryption/error numberOfFailedEncrypts: \(numberOfFailedEncrypts)")
                            completion(.failure(.aesError))
                        } else {
                            DDLogInfo("proto/makeGroupEncryptedPayload/\(groupID)/encryption - obtained senderStateBundles for all receivers")
                            item.senderStateBundles = senderStateBundles
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
                                return
                            }
                        }
                    }
                } catch {
                    DDLogError("proto/makeGroupEncryptedPayload/\(groupID)/senderState-serialization/error \(error)")
                    completion(.failure(.serialization))
                    return
                }
            }
        }
    }

    private func makeGroupRerequestEncryptedPayload(payloadData: Data, groupID: GroupID, for userID: UserID, oneOfItem: Server_GroupFeedItem.OneOf_Item, completion: @escaping (Result<Server_GroupFeedItem, EncryptionError>) -> Void) {
        var item = Server_GroupFeedItem()
        item.action = .publish
        item.gid = groupID

        // Block to encrypt item payload using 1-1 channel.
        let itemPayloadEncryptionCompletion: (() -> Void) = {
            // Set group feed post/comment properly.
            AppContext.shared.messageCrypter.encrypt(payloadData, for: userID) { result in
                switch result {
                case .failure(let error):
                    DDLogError("ProtoServiceCore/makeGroupRerequestEncryptedPayload/\(groupID)/failed to encrypt for userID: \(userID)")
                    completion(.failure(error))
                    return
                case .success((let oneToOneEncryptedData, _)):
                    DDLogError("ProtoServiceCore/makeGroupRerequestEncryptedPayload/\(groupID)/success for userID: \(userID)")
                    do {
                        switch oneOfItem {
                        case .comment(var serverComment):
                            var clientEncryptedPayload = Clients_EncryptedPayload()
                            clientEncryptedPayload.oneToOneEncryptedPayload = oneToOneEncryptedData.data
                            serverComment.encPayload = try clientEncryptedPayload.serializedData()
                            item.item = .comment(serverComment)
                        case .post(var serverPost):
                            var clientEncryptedPayload = Clients_EncryptedPayload()
                            clientEncryptedPayload.oneToOneEncryptedPayload = oneToOneEncryptedData.data
                            serverPost.encPayload = try clientEncryptedPayload.serializedData()
                            item.item = .post(serverPost)
                        }
                        completion(.success(item))
                    } catch {
                        DDLogError("proto/makeGroupRerequestEncryptedPayload/\(groupID)/payload-serialization/error \(error)")
                        completion(.failure(.serialization))
                        return
                    }
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
                            item.senderState = senderStateWithKeyInfo
                            itemPayloadEncryptionCompletion()
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

    private func makeGroupFeedMessage(_ post: PostData, feed: Feed, to toUserID: UserID, completion: @escaping (Result<Server_GroupFeedItem, EncryptionError>) -> Void) {
        guard let payloadData = try? post.clientContainer?.serializedData() else {
            completion(.failure(.serialization))
            return
        }

        var serverPost = Server_Post()
        serverPost.payload = payloadData
        serverPost.id = post.id
        serverPost.publisherUid = Int64(post.userId) ?? 0
        serverPost.timestamp = Int64(post.timestamp.timeIntervalSince1970)

        switch feed {
        case .group(let groupID):
            // Clear unencrypted payload if server prop is disabled.
            if !ServerProperties.sendClearTextGroupFeedContent {
                serverPost.payload = Data()
            }
            makeGroupRerequestEncryptedPayload(payloadData: payloadData, groupID: groupID, for: toUserID, oneOfItem: .post(serverPost)) { result in
                switch result {
                case .failure(let failure):
                    completion(.failure(failure))
                case .success(let serverGroupFeedItem):
                    completion(.success(serverGroupFeedItem))
                }
            }
        case .personal(_):
            DDLogError("ProtoServiceCore/makeGroupFeedMessage/post/unsupported resending messages")
            completion(.failure(.missingKeyBundle))
        }
    }

    private func makeGroupFeedMessage(_ comment: CommentData, groupID: GroupID?, to toUserID: UserID, completion: @escaping (Result<Server_GroupFeedItem, EncryptionError>) -> Void) {
        guard var serverComment = comment.serverComment else {
            completion(.failure(.serialization))
            return
        }
        let payloadData = serverComment.payload
        // Clear unencrypted payload if server prop is disabled.
        if !ServerProperties.sendClearTextGroupFeedContent {
            serverComment.payload = Data()
        }

        if let groupID = groupID {
            makeGroupRerequestEncryptedPayload(payloadData: payloadData, groupID: groupID, for: toUserID, oneOfItem: .comment(serverComment)) { result in
                switch result {
                case .failure(let failure):
                    completion(.failure(failure))
                case .success(let serverGroupFeedItem):
                    completion(.success(serverGroupFeedItem))
                }
            }
        } else {
            DDLogError("ProtoServiceCore/makeGroupFeedMessage/comment/unsupported resending messages")
            completion(.failure(.missingKeyBundle))
        }
    }

    public func decryptGroupFeedPayload(for item: Server_GroupFeedItem, completion: @escaping (FeedContent?, GroupDecryptionFailure?) -> Void) {

        guard let contentId = item.contentId,
              let publisherUid = item.publisherUid,
              let encryptedPayload = item.encryptedPayload else {
            completion(nil, GroupDecryptionFailure(nil, nil, .missingPayload, .payload))
            return
        }

        DDLogInfo("ProtoServiceCore/decryptGroupFeedPayload/contentId/\(item.gid)/\(contentId), publisherUid: \(publisherUid)/begin")

        if !item.senderState.encSenderState.isEmpty {
            // We might already have an e2e session setup with this user.
            // but we have to overwrite our current session with this user. our code does this.
            AppContext.shared.messageCrypter.decrypt(
                EncryptedData(
                    data: item.senderState.encSenderState,
                    identityKey: item.senderState.publicKey.isEmpty ? nil : item.senderState.publicKey,
                    oneTimeKeyId: Int(item.senderState.oneTimePreKeyID)),
                from: publisherUid) { result in
                    // After decrypting sender state.
                    switch result {
                    case .success(let decryptedData):
                        DDLogInfo("proto/decryptGroupFeedPayload/\(item.gid)/success/decrypted senderState successfully")
                        do {
                            let senderState = try Clients_SenderState(serializedData: decryptedData)
                            self.inspectAndDecryptClientEncryptedPayload(payload: encryptedPayload, senderState: senderState, item: item, completion: completion)
                        } catch {
                            DDLogError("proto/decryptGroupFeedPayload/\(item.gid)/error/invalid senderState \(error)")
                        }
                    case .failure(let failure):
                        DDLogError("proto/decryptGroupFeedPayload/\(item.gid)/error/\(failure.error)")
                        AppContext.shared.eventMonitor.count(.sessionReset(true))
                        completion(nil, GroupDecryptionFailure(contentId, publisherUid, failure.error, .senderState))
                        return
                    }
            }
        } else {
            self.inspectAndDecryptClientEncryptedPayload(payload: encryptedPayload, senderState: nil, item: item, completion: completion)
        }
    }

    public func inspectAndDecryptClientEncryptedPayload(payload: Data, senderState: Clients_SenderState?, item: Server_GroupFeedItem, completion: @escaping (FeedContent?, GroupDecryptionFailure?) -> Void) {
        guard let contentId = item.contentId,
              let publisherUid = item.publisherUid,
              item.encryptedPayload != nil else {
                  completion(nil, GroupDecryptionFailure(nil, nil, .missingPayload, .payload))
            return
        }

        // Decrypt payload using the group channel.
        let groupDecryptPayloadCompletion: ((Clients_SenderState?, Data) -> Void) = { (senderState, groupEncryptedPayload) in
            // Decrypt the actual payload now.
            AppContext.shared.messageCrypter.decrypt(groupEncryptedPayload, from: publisherUid, in: item.gid, with: senderState) { groupResult in
                switch groupResult {
                case .success(let decryptedPayload):
                    self.parseGroupPayloadContent(payload: decryptedPayload, item: item, completion: completion)
                case .failure(let error):
                    DDLogError("proto/inspectAndDecryptClientEncryptedPayload/\(item.gid)/error/\(error)")
                    completion(nil, GroupDecryptionFailure(contentId, publisherUid, error, .payload))
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
                    self.parseGroupPayloadContent(payload: decryptedPayload, item: item, completion: completion)
                case .failure(let error):
                    DDLogError("proto/inspectAndDecryptClientEncryptedPayload/\(item.gid)/error/\(error)")
                    completion(nil, GroupDecryptionFailure(contentId, publisherUid, error.error, .payload))
                }
            }
        }

        do {
            // Call the appropriate completion block to decrypt the payload using the group channel or the 1-1 channel.
            let clientEncryptedPayload = try Clients_EncryptedPayload(serializedData: payload)
            switch clientEncryptedPayload.payload {
            case .oneToOneEncryptedPayload(let oneToOneEncryptedPayload):
                oneToOneDecryptPayloadCompletion(oneToOneEncryptedPayload)
                AppContext.shared.messageCrypter.updateSenderState(with: senderState, for: publisherUid, in: item.gid)
            case .senderStateEncryptedPayload(let groupEncryptedPayload):
                groupDecryptPayloadCompletion(senderState, groupEncryptedPayload)
            default:
                DDLogError("proto/decryptGroupFeedPayload/\(item.gid)/error/invalid payload")
                completion(nil, GroupDecryptionFailure(contentId, publisherUid, .invalidPayload, .payload))
                return
            }
        } catch {
            DDLogError("proto/decryptGroupFeedPayload/\(item.gid)/error/invalid payload \(error)")
            completion(nil, GroupDecryptionFailure(contentId, publisherUid, .deserialization, .payload))
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
                                      isShared: false) else {
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

    public func rerequestGroupFeedItem(contentId: String, groupID: String, authorUserID: UserID, rerequestType: Server_GroupFeedRerequest.RerequestType, completion: @escaping ServiceRequestCompletion<Void>) {
        // TODO: murali@: why are we using ProtoRequest based on iqs? -- fix this?
        enqueue(request: ProtoGroupFeedRerequest(groupID: groupID,
                                                 contentId: contentId,
                                                 fromUserID: userData.userId,
                                                 toUserID: authorUserID,
                                                 rerequestType: rerequestType,
                                                 completion: completion))
    }

    // MARK: Decryption

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
                if let legacyMessage = Clients_ChatMessage(containerData: decryptedData) {
                    completion(legacyMessage.chatContent, legacyMessage.chatContext, nil)
                } else if let container = try? Clients_Container(serializedData: decryptedData) {
                    completion(container.chatContainer.chatContent, container.chatContainer.chatContext, nil)
                } else {
                    completion(nil, nil, DecryptionFailure(.deserialization))
                }
            case .failure(let failure):
                AppContext.shared.eventMonitor.count(.sessionReset(true))
                completion(nil, nil, failure)
            }
        }
    }

    public func sendChatMessage(_ message: ChatMessageProtocol, completion: @escaping ServiceRequestCompletion<Void>) {
        guard self.isConnected else {
            DDLogInfo("ProtoServiceCore/sendChatMessage/\(message.id) skipping (disconnected)")
            completion(.failure(RequestError.notConnected))
            return
        }

        let fromUserID = userData.userId

        makeChatStanza(message) { chat, error in
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

    public func rerequestMessage(_ message: Server_Msg, failedEphemeralKey: Data?, completion: @escaping ServiceRequestCompletion<Void>) {
        guard let identityKey = AppContext.shared.keyStore.keyBundle()?.identityPublicEdKey else {
            DDLogError("ProtoService/rerequestMessage/\(message.id)/error could not retrieve identity key")
            return
        }

        let fromUserID = UserID(message.fromUid)

        AppContext.shared.messageCrypter.sessionSetupInfoForRerequest(from: fromUserID) { setupInfo in
            let rerequestData = RerequestData(
                identityKey: identityKey,
                signedPreKeyID: 0,
                oneTimePreKeyID: setupInfo?.1,
                sessionSetupEphemeralKey: setupInfo?.0 ?? Data(),
                messageEphemeralKey: failedEphemeralKey)

            DDLogInfo("ProtoService/rerequestMessage/\(message.id) rerequesting")
            self.rerequestMessage(message.id, senderID: fromUserID, rerequestData: rerequestData, completion: completion)
        }
    }

    public func rerequestMessage(_ messageID: String, senderID: UserID, rerequestData: RerequestData, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoMessageRerequest(messageID: messageID, fromUserID: userData.userId, toUserID: senderID, rerequestData: rerequestData, completion: completion))
    }

    public func log(countableEvents: [CountableEvent], discreteEvents: [DiscreteEvent], completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoLoggingRequest(countableEvents: countableEvents, discreteEvents: discreteEvents, completion: completion))
    }
    
    // MARK: Key requests

    public func getGroupMemberIdentityKeys(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Server_GroupStanza>) {
        enqueue(request: ProtoGroupMemberKeysRequest(groupID: groupID, completion: completion))
    }
        
    public func uploadWhisperKeyBundle(_ bundle: WhisperKeyBundle, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoWhisperUploadRequest(keyBundle: bundle, completion: completion))
    }

    public func requestAddOneTimeKeys(_ keys: [PreKey], completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoWhisperAddOneTimeKeysRequest(preKeys: keys, completion: completion))
    }

    public func requestCountOfOneTimeKeys(completion: @escaping ServiceRequestCompletion<Int32>) {
        enqueue(request: ProtoWhisperGetCountOfOneTimeKeysRequest(completion: completion))
    }

    // MARK: Groups
    
    public func getGroupPreviewWithLink(inviteLink: String, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>) {
        enqueue(request: ProtoGroupPreviewWithLinkRequest(inviteLink: inviteLink, completion: completion))
    }

    public func joinGroupWithLink(inviteLink: String, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>) {
        enqueue(request: ProtoJoinGroupWithLinkRequest(inviteLink: inviteLink, completion: completion))
    }
}

public extension Server_Packet {
    static func iqPacketWithID() -> Server_Packet {
        var packet = Server_Packet()
        packet.iq.id = PacketID.generate()
        return packet
    }

    static func iqPacket(type: Server_Iq.TypeEnum, payload: Server_Iq.OneOf_Payload) -> Server_Packet {
        var packet = Server_Packet.iqPacketWithID()
        packet.iq.type = type
        packet.iq.payload = payload
        return packet
    }

    static func msgPacket(
        from: UserID,
        to: UserID,
        id: String = PacketID.generate(),
        type: Server_Msg.TypeEnum = .normal,
        rerequestCount: Int32 = 0,
        payload: Server_Msg.OneOf_Payload) -> Server_Packet
    {
        var msg = Server_Msg()

        if let fromUID = Int64(from) {
            msg.fromUid = fromUID
        } else {
            DDLogError("Server_Packet/\(id)/error invalid from user ID \(from)")
        }

        if let toUID = Int64(to) {
            msg.toUid = toUID
        } else {
            DDLogError("Server_Packet/\(id)/error invalid to user ID \(to)")
        }

        msg.type = type
        msg.id = id
        msg.payload = payload
        msg.rerequestCount = rerequestCount

        var packet = Server_Packet()
        packet.msg = msg

        return packet
    }

    var requestID: String? {
        guard let stanza = stanza else {
            return nil
        }
        switch stanza {
        case .msg(let msg):
            return msg.id
        case .iq(let iq):
            return iq.id
        case .ack(let ack):
            return ack.id
        case .presence(let presence):
            return presence.id
        case .chatState:
            return PacketID.generate(short: true) // throwaway id, chat states don't use them
        case .haError:
            return nil
        }
    }
}
