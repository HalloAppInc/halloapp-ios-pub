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

enum ProtoServiceCoreError: Error {
    case deserialization
    case disconnected
    case serialization
}

enum Stream {
    case proto(ProtoStream)
    case noise(NoiseStream)
}

open class ProtoServiceCore: NSObject, ObservableObject {

    // MARK: Avatar
    public weak var avatarDelegate: ServiceAvatarDelegate?

    private class ConnectionStateCallback {
        let state: ConnectionState
        let work: (DispatchGroup) -> ()

        required init(state: ConnectionState, work: @escaping (DispatchGroup) -> ()) {
            self.state = state
            self.work = work
        }
    }

    // MARK: Connection State
    // TODO: Only allow stream to set this value (e.g. via delegate callback)
    @Published public var connectionState: ConnectionState = .notConnected {
        didSet {
            DDLogDebug("proto/connectionState/change [\(oldValue)] -> [\(connectionState)]")
            runCallbacksForCurrentConnectionState()
            if oldValue == .connected && connectionState == .notConnected {
                startReconnectTimerIfNecessary()
            }
        }
    }
    public var isConnected: Bool { get { connectionState == .connected } }
    public var isDisconnected: Bool { get { connectionState == .disconnecting || connectionState == .notConnected } }

    public let didConnect = PassthroughSubject<Void, Never>()

    private var stream: Stream?
    public let userData: UserData

    required public init(userData: UserData) {
        self.userData = userData
        super.init()

        configureStream(with: userData)
    }

    // MARK: Credentials

    public func receivedServerStaticKey(_ key: Data, for userID: UserID) {
        Keychain.saveServerStaticKey(key, for: userID)
    }

    // MARK: Connection management

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
                            serverStaticKey: Keychain.loadServerStaticKey(for: userID))
            noise.noiseKeys = noiseKeys
            noise.protoService = self
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
        guard let stream = stream else { return }
        switch stream {
        case .noise(let noise):
            noise.connect(host: userData.hostName, port: userData.hostPort)
        case .proto(let proto):
            connect(proto: proto)
        }

        // Retry if we're not connected in 10 seconds
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

        isAutoReconnectEnabled = false
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

        isAutoReconnectEnabled = false
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
        guard isAutoReconnectEnabled else {
            return
        }
        DDLogInfo("proto/reconnect/timer start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            DDLogInfo("proto/reconnect/timer fired")
            // This only needs to be called once, connect() will reattempt as necessary
            self.startConnectingIfNecessary()
        }
    }

    private var isAutoReconnectEnabled = false

    private var retryConnectionTask: DispatchWorkItem?

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
        let contactIDs = AppContext.shared.contactStore.allInNetworkContactIDs().filter { $0 != userData.userId }
        var messagesRemaining = n
        while messagesRemaining > 0 {
            guard let toUserID = contactIDs.randomElement() else {
                DDLogError("Proto/sendSilentChats/error no contacts available")
                return
            }
            let silentChat = SilentChatMessage(from: userData.userId, to: toUserID)
            sendSilentChatMessage(silentChat, encryption: AppContext.shared.encryptOperation(for: toUserID)) { _ in }
            messagesRemaining -= 1
        }
    }

    public func sendSilentChatMessage(_ message: ChatMessageProtocol, encryption: EncryptOperation, completion: @escaping ServiceRequestCompletion<Void>) {
        let fromUserID = userData.userId

        makeChatStanza(message, encryption: encryption) { chat, error in
            guard let chat = chat else {
                completion(.failure(ProtoServiceCoreError.serialization))
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
                AppContext.shared.eventMonitor.observe(.encryption(error: .serialization))
                DDLogError("ProtoServiceCore/sendSilentChatMessage/\(message.id)/error could not serialize chat message!")
                completion(.failure(ProtoServiceCoreError.serialization))
                return
            }

            DispatchQueue.main.async {
                guard self.isConnected else {
                    DDLogInfo("ProtoServiceCore/sendSilentChatMessage/\(message.id) skipping (disconnected)")
                    completion(.failure(ProtoServiceCoreError.disconnected))
                    return
                }
                AppContext.shared.eventMonitor.observe(.encryption(error: error))
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
        performOnConnect()
    }

    open func authenticationFailed(with authResult: Server_AuthResult) {
        DDLogInfo("ProtoServiceCore/authenticationFailed [\(authResult)]")
        DispatchQueue.main.async {
            self.userData.logout()
        }
    }

    open func performOnConnect() {
        didConnect.send()
        isAutoReconnectEnabled = true
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
        cancelAllRequests()
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
    public func requestMediaUploadURL(size: Int, completion: @escaping ServiceRequestCompletion<MediaURLInfo>) {
        // Wait until connected to request URLs. User meanwhile can cancel posting.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: ProtoMediaUploadURLRequest(size: size, completion: completion))
        }
    }

    public func requestWhisperKeyBundle(userID: UserID, completion: @escaping ServiceRequestCompletion<WhisperKeyBundle>) {
        enqueue(request: ProtoWhisperGetBundleRequest(targetUserId: userID, completion: completion))
    }

    public func publishPost(_ post: FeedPostProtocol, feed: Feed, completion: @escaping ServiceRequestCompletion<Date>) {
        // Request will fail immediately if we're not connected, therefore delay sending until connected.
        ///TODO: add option of canceling posting.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: ProtoPublishPostRequest(post: post, feed: feed, completion: completion))
        }
    }

    public func publishComment(_ comment: FeedCommentProtocol, groupId: GroupID?, completion: @escaping ServiceRequestCompletion<Date>) {
        // Request will fail immediately if we're not connected, therefore delay sending until connected.
        ///TODO: add option of canceling posting.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: ProtoPublishCommentRequest(comment: comment, groupId: groupId, completion: completion))
        }
    }

    private func makeChatStanza(_ message: ChatMessageProtocol, encryption: EncryptOperation, completion: @escaping (Server_ChatStanza?, EncryptionError?) -> Void) {
        guard let messageData = try? message.protoContainer.serializedData() else {
            DDLogError("ProtoServiceCore/makeChatStanza/\(message.id)/error could not serialize chat message!")
            completion(nil, nil)
            return
        }

        encryption(messageData) { result in
            switch result {
            case .success(let encryptedData):
                var chat = Server_ChatStanza()
                chat.payload = messageData
                chat.encPayload = encryptedData.data
                chat.oneTimePreKeyID = Int64(encryptedData.oneTimeKeyId)
                if let publicKey = encryptedData.identityKey {
                    chat.publicKey = publicKey
                } else {
                    DDLogInfo("ProtoServiceCore/makeChatStanza/\(message.id)/ skipping public key")
                }
                completion(chat, nil)
            case .failure(let error):
                var chat = Server_ChatStanza()
                chat.payload = messageData
                completion(chat, error)
            }
        }
    }

    public func sendChatMessage(_ message: ChatMessageProtocol, encryption: EncryptOperation, completion: @escaping ServiceRequestCompletion<Void>) {
        guard self.isConnected else {
            DDLogInfo("ProtoServiceCore/sendChatMessage/\(message.id) skipping (disconnected)")
            completion(.failure(ProtoServiceCoreError.disconnected))
            return
        }

        let fromUserID = userData.userId

        makeChatStanza(message, encryption: encryption) { chat, error in
            guard let chat = chat else {
                completion(.failure(ProtoServiceCoreError.serialization))
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
                AppContext.shared.eventMonitor.observe(.encryption(error: .serialization))
                DDLogError("ProtoServiceCore/sendChatMessage/\(message.id)/error could not serialize chat message!")
                completion(.failure(ProtoServiceCoreError.serialization))
                return
            }

            DispatchQueue.main.async {
                guard self.isConnected else {
                    DDLogInfo("ProtoServiceCore/sendChatMessage/\(message.id) aborting (disconnected)")
                    completion(.failure(ProtoServiceCoreError.disconnected))
                    return
                }
                if let error = error {
                    DDLogInfo("ProtoServiceCore/sendChatMessage/\(message.id)/error \(error)")
                    AppContext.shared.errorLogger?.logError(error)
                }
                AppContext.shared.eventMonitor.observe(.encryption(error: error))
                DDLogInfo("ProtoServiceCore/sendChatMessage/\(message.id) sending (\(error == nil ? "encrypted" : "unencrypted"))")
                self.send(packetData)
                self.sendSilentChats(ServerProperties.silentChatMessages)
                completion(.success(()))
            }
        }
    }

    public func rerequestMessage(_ messageID: String, senderID: UserID, identityKey: Data, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoMessageRerequest(messageID: messageID, fromUserID: userData.userId, toUserID: senderID,  identityKey: identityKey, completion: completion))
    }

    public func log(events: [CountableEvent], completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoLoggingRequest(events: events, completion: completion))
    }
}
