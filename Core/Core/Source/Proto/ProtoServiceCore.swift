//
//  ProtoServiceCore.swift
//  Core
//
//  Created by Garrett on 8/25/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Foundation
import XMPPFramework

enum Stream {
    case proto(ProtoStream)
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

    public var isAppVersionKnownExpired = CurrentValueSubject<Bool, Never>(false)
    public var isAppVersionCloseToExpiry = CurrentValueSubject<Bool, Never>(false)

    public var isConnected: Bool { get { connectionState == .connected } }
    public var isDisconnected: Bool { get { connectionState == .disconnecting || connectionState == .notConnected } }

    public let didConnect = PassthroughSubject<Void, Never>()
    public let didDisconnect = PassthroughSubject<Void, Never>()

    private var stream: Stream?
    public let userData: UserData

    private lazy var isPlaintextFallbackSupported = !ServerProperties.isInternalUser

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
        case .proto(let proto):
            proto.send(data)
        case .none:
            DDLogError("proto/send/error no stream configured!")
        }
    }

    public func configureStream(with userData: UserData?) {
        DDLogInfo("proto/stream/configure [\(userData?.userId ?? "nil")]")
        switch userData?.credentials {
        case .v1(let userID, _):
            let proto = ProtoStream()
            proto.startTLSPolicy = .required
            proto.myJID = {
                return XMPPJID(user: userID, domain: "s.halloapp.net", resource: "iphone")
            }()
            proto.protoService = self

            let userAgent = NSString(string: AppContext.userAgent)
            proto.clientVersion = userAgent
            proto.addDelegate(self, delegateQueue: DispatchQueue.main)
            stream = .proto(proto)
        case .v2(let userID, let noiseKeys):
            let noise = NoiseStream(
                            userAgent: AppContext.userAgent,
                            userID: userID,
                            noiseKeys: noiseKeys,
                            serverStaticKey: Keychain.loadServerStaticKey(for: userID),
                            passiveMode: isPassiveMode,
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
        case .proto(let proto):
            if proto.myJID != nil && proto.isDisconnected {
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
        case .proto(let proto):
            connect(proto: proto)
        }

        // Retry if we're not connected in 10 seconds (cancel pending retry if it exists)
        retryConnectionTask?.cancel()
        let retryConnection = DispatchWorkItem { self.startConnectingIfNecessary() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: retryConnection)
        retryConnectionTask = retryConnection
    }

    public func connect(proto: ProtoStream) {
        guard proto.myJID != nil else { return }

        DDLogInfo("proto/connect [passiveMode: \(proto.passiveMode), \(proto.clientVersion), \(UIDevice.current.getModelName()) (iOS \(UIDevice.current.systemVersion))]")
            
        proto.hostName = userData.hostName
        proto.hostPort = userData.hostPort

        do {
            try proto.connect(withTimeout: XMPPStreamTimeoutNone)
        } catch {
            DDLogError("proto/connect/error \(error)")
            return
        }
    }

    public func disconnect() {
        DDLogInfo("proto/disconnect")

        shouldReconnectOnConnectionLoss = false
        retryConnectionTask?.cancel()
        connectionState = .disconnecting
        switch stream {
        case .noise(let noise):
            noise.disconnect(afterSending: true)
        case .proto(let proto):
            proto.disconnectAfterSending()
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
        case .proto(let proto):
            proto.disconnect()
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

    // MARK: Silent chats

    public func sendSilentChats(_ n: Int) {
        let contactIDs = AppContext.shared.contactStore.allRegisteredContactIDs().filter { $0 != userData.userId }
        var messagesRemaining = n
        while messagesRemaining > 0 {
            guard let toUserID = contactIDs.randomElement() else {
                DDLogError("Proto/sendSilentChats/error no contacts available")
                return
            }
            let silentChat = SilentChatMessage(from: userData.userId, to: toUserID)
            sendSilentChatMessage(silentChat) { _ in }
            messagesRemaining -= 1
        }
    }

    public func sendSilentChatMessage(_ message: ChatMessageProtocol, completion: @escaping ServiceRequestCompletion<Void>) {
        let fromUserID = userData.userId

        makeChatStanza(message) { chat, error in
            guard let chat = chat else {
                completion(.failure(RequestError.malformedRequest))
                return
            }

            var silentStanza = Server_SilentChatStanza()
            silentStanza.chatStanza = chat
            let packet = Server_Packet.msgPacket(
                from: fromUserID,
                to: message.toUserId,
                id: message.id,
                type: .chat,
                rerequestCount: message.rerequestCount,
                payload: .silentChatStanza(silentStanza))

            guard let packetData = try? packet.serializedData() else {
                AppContext.shared.eventMonitor.count(.encryption(error: .serialization))
                DDLogError("ProtoServiceCore/sendSilentChatMessage/\(message.id)/error could not serialize chat message!")
                completion(.failure(RequestError.malformedRequest))
                return
            }

            DispatchQueue.main.async {
                guard self.isConnected else {
                    DDLogInfo("ProtoServiceCore/sendSilentChatMessage/\(message.id) skipping (disconnected)")
                    completion(.failure(RequestError.notConnected))
                    return
                }
                AppContext.shared.eventMonitor.count(.encryption(error: error))
                DDLogInfo("ProtoServiceCore/sendSilentChatMessage/\(message.id) sending (\(error == nil ? "encrypted" : "unencrypted"))")
                self.send(packetData)
                completion(.success(()))
            }
        }
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
        case "invalid client version":
            DispatchQueue.main.async {
                self.isAppVersionKnownExpired.send(true)
            }
        default:
            DispatchQueue.main.async {
                self.userData.logout()
            }
        }
    }

    open func performOnConnect() {
        didConnect.send()
        retryConnectionTask?.cancel()
        shouldReconnectOnConnectionLoss = isAutoReconnectEnabled
        resendAllPendingRequests()
    }

    open func didReceive(packet: Server_Packet, requestID: String) {
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
    public func receivedPacket(_ packet: Server_Packet) {
        guard let requestID = packet.requestID else {
            // TODO: Remove this limitation (only present for parity with XMPP/ProtoStream behavior)
            DDLogError("proto/receivedPacket/error packet missing request ID [\(packet)]")
            return
        }
        didReceive(packet: packet, requestID: requestID)
    }

    public func receivedAuthResult(_ authResult: Server_AuthResult) {
        if authResult.result == "success" {
            authenticationSucceeded(with: authResult)
        } else {
            authenticationFailed(with: authResult)
        }
    }

    public func updateConnectionState(_ connectionState: ConnectionState) {
        self.connectionState = connectionState
    }

    public func receivedServerStaticKey(_ key: Data, for userID: UserID) {
        Keychain.saveServerStaticKey(key, for: userID)
    }
}

extension ProtoServiceCore: XMPPStreamDelegate {

    public func xmppStreamWillConnect(_ sender: XMPPStream) {
        DDLogInfo("proto/stream/willConnect")

        connectionState = .connecting
    }

    public func xmppStreamConnectDidTimeout(_ stream: XMPPStream) {
        DDLogInfo("proto/stream/connectDidTimeout")
    }

    public func xmppStreamDidDisconnect(_ sender: XMPPStream, withError error: Error?) {
        DDLogInfo("proto/stream/didDisconnect [\(String(describing: error))]")

        connectionState = .notConnected
    }

    public func xmppStream(_ sender: XMPPStream, socketDidConnect socket: GCDAsyncSocket) {
        DDLogInfo("proto/stream/socketDidConnect")
    }

    public func xmppStreamDidStartNegotiation(_ sender: XMPPStream) {
        DDLogInfo("proto/stream/didStartNegotiation")
    }

    public func xmppStream(_ sender: XMPPStream, willSecureWithSettings settings: NSMutableDictionary) {
        DDLogInfo("proto/stream/willSecureWithSettings [\(settings)]")

        settings.setObject(true, forKey:GCDAsyncSocketManuallyEvaluateTrust as NSCopying)
    }

    public func xmppStream(_ sender: XMPPStream, didReceive trust: SecTrust, completionHandler: ((Bool) -> Void)) {
        DDLogInfo("proto/stream/didReceiveTrust")

        if SecTrustEvaluateWithError(trust, nil) {
            completionHandler(true)
        } else {
            //todo: handle gracefully and reflect in global state
            completionHandler(false)
        }
    }

    public func xmppStreamDidSecure(_ sender: XMPPStream) {
        guard let credentials = userData.credentials, case .v1(_, let password) = credentials else {
            DDLogError("proto/stream/didSecure/error password missing")
            return
        }
        DDLogInfo("proto/stream/didSecure/sending auth request")
        if case .proto(let proto) = stream {
            proto.sendAuthRequestWithPassword(password: password)
        }
    }

    public func xmppStreamDidConnect(_ stream: XMPPStream) {
        DDLogInfo("proto/stream/didConnect")
    }

    public func xmppStreamDidAuthenticate(_ sender: XMPPStream) {
        DDLogError("proto/stream/didAuthenticate/error this delegate method should not be used")
    }

    public func xmppStream(_ sender: XMPPStream, didNotAuthenticate error: DDXMLElement) {
        DDLogError("proto/stream/didNotAuthenticate/error \(error)")
    }

    public func xmppStream(_ sender: XMPPStream, didReceiveError error: DDXMLElement) {
        DDLogInfo("proto/stream/didReceiveError [\(error)]")
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

    public func publishPost(_ post: FeedPostProtocol, feed: Feed, completion: @escaping ServiceRequestCompletion<Date>) {
        // Request will fail immediately if we're not connected, therefore delay sending until connected.
        ///TODO: add option of canceling posting.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            guard let request = ProtoPublishPostRequest(post: post, feed: feed, completion: completion) else {
                completion(.failure(.malformedRequest))
                return
            }
            self.enqueue(request: request)
        }
    }

    public func publishComment(_ comment: CommentData, groupId: GroupID?, completion: @escaping ServiceRequestCompletion<Date>) {
        // Request will fail immediately if we're not connected, therefore delay sending until connected.
        ///TODO: add option of canceling posting.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            guard let request = ProtoPublishCommentRequest(comment: comment, groupId: groupId, completion: completion) else {
                completion(.failure(.malformedRequest))
                return
            }
            self.enqueue(request: request)
        }
    }

    private func makeChatStanza(_ message: ChatMessageProtocol, completion: @escaping (Server_ChatStanza?, EncryptionError?) -> Void) {
        guard let messageData = try? message.protoContainer.serializedData() else {
            DDLogError("ProtoServiceCore/makeChatStanza/\(message.id)/error could not serialize chat message!")
            completion(nil, nil)
            return
        }

        AppContext.shared.messageCrypter.encrypt(messageData, for: message.toUserId) { result in
            switch result {
            case .success(let encryptedData):
                var chat = Server_ChatStanza()
                chat.senderLogInfo = self.dateTimeFormatterMonthDayTime.string(from: Date())
                chat.encPayload = encryptedData.data
                chat.oneTimePreKeyID = Int64(encryptedData.oneTimeKeyId)
                if let publicKey = encryptedData.identityKey {
                    chat.publicKey = publicKey
                } else {
                    DDLogInfo("ProtoServiceCore/makeChatStanza/\(message.id)/ skipping public key")
                }
                if ServerProperties.shouldSendClearTextChat {
                    chat.payload = messageData
                }
                completion(chat, nil)
            case .failure(let error):
                var chat = Server_ChatStanza()
                if ServerProperties.shouldSendClearTextChat {
                    chat.payload = messageData
                }
                completion(chat, error)
            }
        }
    }

    // MARK: Decryption

    /// May return a valid message with an error (i.e., there may be plaintext to fall back to even if decryption fails).
    public func decryptChat(_ serverChat: Server_ChatStanza, from fromUserID: UserID, completion: @escaping (Clients_ChatMessage?, DecryptionFailure?) -> Void) {
        let plainTextMessage = isPlaintextFallbackSupported ? Clients_ChatMessage(containerData: serverChat.payload) : nil
        AppContext.shared.messageCrypter.decrypt(
            EncryptedData(
                data: serverChat.encPayload,
                identityKey: serverChat.publicKey.isEmpty ? nil : serverChat.publicKey,
                oneTimeKeyId: Int(serverChat.oneTimePreKeyID)),
            from: fromUserID) { result in
            switch result {
            case .success(let decryptedData):
                guard let decryptedMessage = Clients_ChatMessage(containerData: decryptedData) else {
                    // Decryption deserialization failed, fall back to plaintext if possible
                    completion(plainTextMessage, DecryptionFailure(.deserialization))
                    return
                }
                if let plainTextMessage = plainTextMessage, plainTextMessage.text != decryptedMessage.text {
                    // Decrypted message does not match plaintext
                    completion(plainTextMessage, DecryptionFailure(.plaintextMismatch))
                } else {
                    if plainTextMessage == nil {
                        DDLogInfo("proto/decryptChat/plaintext not available")
                    }
                    completion(decryptedMessage, nil)
                }
            case .failure(let failure):
                completion(plainTextMessage, failure)
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
                self.sendSilentChats(ServerProperties.silentChatMessages)
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

    public func rerequestMessage(_ messageID: String, senderID: UserID, rerequestData: RerequestData, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoMessageRerequest(messageID: messageID, fromUserID: userData.userId, toUserID: senderID, rerequestData: rerequestData, completion: completion))
    }

    public func log(countableEvents: [CountableEvent], discreteEvents: [DiscreteEvent], completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoLoggingRequest(countableEvents: countableEvents, discreteEvents: discreteEvents, completion: completion))
    }
    
    // MARK: Key requests
        
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
