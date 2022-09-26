//
//  ProtoServiceCoreCommon.swift
//  Core
//
//  Created by Garrett on 8/25/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//
import CocoaLumberjackSwift
import Combine
import Foundation

public enum ResourceType: String {
    case iphone
    case iphone_nse
    case iphone_share
}

fileprivate let userDefaultsKeyForRequestLogs = "serverRequestedLogs"

open class ProtoServiceCoreCommon: NSObject, ObservableObject {

    public weak var keyDelegate: ServiceKeyDelegate?
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
    public private(set) var connectionState: ConnectionState = .notConnected {
        didSet {
            if oldValue == connectionState { return }
            DDLogDebug("proto/connectionState/change [\(oldValue)] -> [\(connectionState)]")
            if connectionState == .notConnected {
                cancelAllRequests()
                didDisconnect.send()
                switch oldValue {
                case .connected, .connecting:
                    startReconnectTimerIfNecessary()
                case .notConnected, .disconnecting:
                    break
                }
            }
            runCallbacksForCurrentConnectionState()
        }
    }

    public var reachabilityState: ReachablilityState = .reachable
    public var reachabilityConnectionType: String = "unknown"


    public var isAppVersionKnownExpired = CurrentValueSubject<Bool, Never>(false)
    public var isAppVersionCloseToExpiry = CurrentValueSubject<Bool, Never>(false)

    public var isConnected: Bool { get { connectionState == .connected } }
    public var isDisconnected: Bool { get { connectionState == .disconnecting || connectionState == .notConnected } }
    public var isReachable: Bool { get { reachabilityState == .reachable } }

    public let didConnect = PassthroughSubject<Void, Never>()
    public let didDisconnect = PassthroughSubject<Void, Never>()

    private var groupWorkQueue = DispatchQueue(label: "com.halloapp.group-work", qos: .default)
    private let resource: ResourceType

    private var stream: NoiseStream?
    public var credentials: Credentials? {
        didSet {
            DDLogInfo("proto/set-credentials [\(credentials?.userID ?? "nil")]")
            if let credentials = credentials {
                configureStream(with: credentials)
                connect()
            } else {
                disconnectImmediately()
            }
        }
    }

    required public init(credentials: Credentials?, passiveMode: Bool = false, automaticallyReconnect: Bool = true, resource: ResourceType = .iphone) {
        self.credentials = credentials
        self.isPassiveMode = passiveMode
        self.isAutoReconnectEnabled = automaticallyReconnect
        self.resource = resource
        super.init()

        if let credentials = credentials {
            configureStream(with: credentials)
        } else {
            DDLogInfo("proto/init/no-credentials")
        }
    }

    // MARK: Connection management
    private let isPassiveMode: Bool
    private let isAutoReconnectEnabled: Bool
    private let noisePort: UInt16 = 5222

    public var useTestServer: Bool {
        get {
            #if DEBUG
            if UserDefaults.shared.value(forKey: "UseTestServer") == nil {
                // Debug builds should default to test server
                return true
            }
            #endif
            return UserDefaults.shared.bool(forKey: "UseTestServer")
        }
        set {
            UserDefaults.shared.set(newValue, forKey: "UseTestServer")
        }
    }

    public var hostName: String {
        useTestServer ? "s-test.halloapp.net" : "s.halloapp.net"
    }

    public func send(_ data: Data) {
        guard let stream = stream else {
            DDLogError("proto/send/error no stream configured!")
            return
        }
        stream.send(data)
    }

    public func configureStream(with credentials: Credentials) {
        DDLogInfo("proto/stream/configure [\(credentials.userID)]")
        stream = NoiseStream(
            noiseKeys: credentials.noiseKeys,
            serverStaticKey: Keychain.loadServerStaticKey(for: credentials.userID),
            delegate: self)
    }

    public func startConnectingIfNecessary() {
        guard let stream = stream else { return }
        if stream.isReadyToConnect {
            connect()
        }
    }

    public func connect() {
        guard !isAppVersionKnownExpired.value else {
            DDLogInfo("proto/connect/skipping (expired app version)")
            return
        }
        guard let stream = stream else { return }
        DDLogInfo("proto/connect")

        shouldReconnectOnConnectionLoss = true
        reconnectDelay = 2

        stream.connect(host: hostName, port: noisePort)
    }

    public func disconnect() {
        DDLogInfo("proto/disconnect")

        shouldReconnectOnConnectionLoss = false
        retryConnectionTask?.cancel()
        connectionState = .disconnecting
        stream?.disconnect()
    }

    public func disconnectImmediately() {
        DDLogInfo("proto/disconnectImmediately")

        shouldReconnectOnConnectionLoss = false
        retryConnectionTask?.cancel()
        connectionState = .notConnected
        stream?.disconnect()
    }

    private func startReconnectTimerIfNecessary() {
        guard shouldReconnectOnConnectionLoss else {
            DDLogInfo("proto/reconnect/timer/skipping [shouldReconnect == false]")
            return
        }

        retryConnectionTask?.cancel()
        let retryConnection = DispatchWorkItem {
            DDLogInfo("proto/reconnect/timer/fired")
            switch self.connectionState {
            case .connected, .disconnecting:
                DDLogInfo("proto/reconnect/aborting [state == \(self.connectionState)]")
                return
            case .notConnected:
                DDLogInfo("proto/reconnect/attempting [state == \(self.connectionState)]")
                self.startConnectingIfNecessary()
            case .connecting:
                DDLogInfo("proto/reconnect/waiting [state == \(self.connectionState)]")
            }
            self.startReconnectTimerIfNecessary()
        }
        DDLogInfo("proto/reconnect/timer/setting [delay: \(reconnectDelay)]")
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay, execute: retryConnection)
        reconnectDelay = min(10, max(reconnectDelay, 1) * 2)
        retryConnectionTask = retryConnection
    }

    private var shouldReconnectOnConnectionLoss = false

    private var retryConnectionTask: DispatchWorkItem?
    private var reconnectDelay: TimeInterval = 2

    // MARK: State Change Callbacks
    private var stateChangeCallbacks: [ConnectionStateCallback] = []
    private let stateChangeCallbackQueue = DispatchQueue(label: "StateChangeCallbackModificationQueue")

    public func execute(whenConnectionStateIs state: ConnectionState, onQueue queue: DispatchQueue, work: @escaping @convention(block) () -> Void) {
        let callback = ConnectionStateCallback(state: state) { (dispatchGroup) in
            queue.async(group: dispatchGroup, execute: work)
        }

        stateChangeCallbackQueue.sync {
            stateChangeCallbacks.append(callback)
        }

        if connectionState == state {
            runCallbacksForCurrentConnectionState()
        }
    }

    private func runCallbacksForCurrentConnectionState() {
        let currentState = connectionState

        stateChangeCallbackQueue.sync {
            let callbacks = stateChangeCallbacks.filter { $0.state == currentState }
            guard !callbacks.isEmpty else { return }

            stateChangeCallbacks.removeAll(where: { $0.state == currentState })

            let group = DispatchGroup()
            callbacks.forEach{ $0.work(group) }
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
        case .invalidClientVersion:
            DispatchQueue.main.async {
                self.isAppVersionKnownExpired.send(true)
            }
        case .accountDeleted, .invalidUidOrPassword, .spubMismatch, .unknownReason, .UNRECOGNIZED:
            switch authResult.result {
            case .failure:
                AppContextCommon.shared.userData.performSeriallyOnBackgroundContext { managedObjectContext in
                    AppContextCommon.shared.userData.logout(using: managedObjectContext)
                }
            case .UNRECOGNIZED, .unknown, .success:
                DDLogError("ProtoServiceCore/authenticationFailed/unexpected-result [\(authResult.result)] [\(authResult.reason)]")
            }
        case .invalidResource, .ok:
            DDLogError("ProtoServiceCore/authenticationFailed/unexpected-result [\(authResult.result)] [\(authResult.reason)]")
        }
    }

    open func performOnConnect() {
        didConnect.send()
        retryConnectionTask?.cancel()
        shouldReconnectOnConnectionLoss = isAutoReconnectEnabled
        reconnectDelay = 2
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

extension ProtoServiceCoreCommon: NoiseDelegate {
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
        clientConfig.clientVersion.version = AppContextCommon.userAgent
        clientConfig.resource = self.resource.rawValue
        clientConfig.deviceInfo = deviceInfo
        if let userID = credentials?.userID, let uid = Int64(userID) {
            clientConfig.uid = uid
        } else {
            DDLogError("ProtoServiceCore/connectionPayload/error invalid userID [\(credentials?.userID ?? "nil")]")
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
        guard let userID = credentials?.userID else { return }
        Keychain.saveServerStaticKey(key, for: userID)
    }
}

extension ProtoServiceCoreCommon: CoreServiceCommon {

    public func requestWhisperKeyBundle(userID: UserID, completion: @escaping ServiceRequestCompletion<WhisperKeyBundle>) {
        // Wait until connected to request key bundle - else, it will fail anyways.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: ProtoWhisperGetBundleRequest(targetUserId: userID, completion: completion))
        }
    }

    public func sendPresenceIfPossible(_ presenceType: PresenceType) {
        guard isConnected else { return }

        var presence = Server_Presence()
        presence.id = PacketID.generate(short: true)
        presence.type = {
            switch presenceType {
            case .away:
                return .away
            case .available:
                return .available
            }
        }()
        if let uid = Int64(AppContextCommon.shared.userData.userId) {
            presence.toUid = uid
        }

        var packet = Server_Packet()
        packet.presence = presence

        guard let packetData = try? packet.serializedData() else {
            DDLogError("ProtoService/sendPresenceIfPossible/error could not serialize")
            return
        }
        send(packetData)
    }

    public func requestAddOneTimeKeys(_ keys: [PreKey], completion: @escaping ServiceRequestCompletion<Void>) {
        // Wait until connected to upload one-time-keys - else, it will fail anyways.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: ProtoWhisperAddOneTimeKeysRequest(preKeys: keys, completion: completion))
        }
    }

    public func requestCountOfOneTimeKeys(completion: @escaping ServiceRequestCompletion<Int32>) {
        // Wait until connected to request key bundle - else, it will fail anyways.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: ProtoWhisperGetCountOfOneTimeKeysRequest(completion: completion))
        }
    }

    // MARK: Groups
    public func getGroupPreviewWithLink(inviteLink: String, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>) {
        enqueue(request: ProtoGroupPreviewWithLinkRequest(inviteLink: inviteLink, completion: completion))
    }

    public func joinGroupWithLink(inviteLink: String, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>) {
        enqueue(request: ProtoJoinGroupWithLinkRequest(inviteLink: inviteLink, completion: completion))
    }

    // MARK: Avatar

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

    // MARK: Web client

    public func authenticateWebClient(staticKey: Data, completion: @escaping ServiceRequestCompletion<Void>) {
        var webClientInfo = Server_WebClientInfo()
        webClientInfo.staticKey = staticKey
        webClientInfo.action = .authenticateKey

        let packet = Server_Packet.iqPacket(
            type: .set,
            payload: .webClientInfo(webClientInfo))

        let request = ProtoRequest(
            iqPacket: packet,
            transform: { _ in return .success(()) },
            completion: completion)

        enqueue(request: request)
    }

    public func removeWebClient(staticKey: Data, completion: @escaping ServiceRequestCompletion<Void>) {
        var webClientInfo = Server_WebClientInfo()
        webClientInfo.staticKey = staticKey
        webClientInfo.action = .removeKey

        let packet = Server_Packet.iqPacket(
            type: .set,
            payload: .webClientInfo(webClientInfo))

        let request = ProtoRequest(
            iqPacket: packet,
            transform: { _ in return .success(()) },
            completion: completion)

        enqueue(request: request)
    }

    public func sendToWebClient(staticKey: Data, data: Data, completion: @escaping ServiceRequestCompletion<Void>) {
        sendToWebClient(staticKey: staticKey, payload: .content(data), completion: completion)
    }

    public func sendToWebClient(staticKey: Data, noiseMessage: Server_NoiseMessage, completion: @escaping ServiceRequestCompletion<Void>) {
        sendToWebClient(staticKey: staticKey, payload: .noiseMessage(noiseMessage), completion: completion)
    }

    private func sendToWebClient(staticKey: Data, payload: Server_WebStanza.OneOf_Payload, completion: @escaping ServiceRequestCompletion<Void>) {
        guard let fromUserID = self.credentials?.userID else {
            DDLogError("ProtoServiceCore/sendToWebClient/error no-user-id")
            completion(.failure(.aborted))
            return
        }

        var webStanza = Server_WebStanza()
        webStanza.staticKey = staticKey
        webStanza.payload = payload

        let packet = Server_Packet.msgPacket(
            from: fromUserID,
            to: fromUserID, // web client has same user ID
            payload: .webStanza(webStanza))

        guard let packetData = try? packet.serializedData() else {
            DDLogError("ProtoServiceCore/sendToWebClient/error [serialization]")
            completion(.failure(RequestError.malformedRequest))
            return
        }

        DDLogInfo("ProtoServiceCore/sendToWebClient/sending")
        self.send(packetData)
        DDLogInfo("ProtoServiceCore/sendToWebClient/sent")
        completion(.success(()))
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

    static func msgPacket(
        from: UserID,
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
