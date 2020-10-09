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
    @Published public private(set) var connectionState: ConnectionState = .notConnected {
        didSet {
            DDLogDebug("proto/connectionState/change [\(oldValue)] -> [\(connectionState)]")
            runCallbacksForCurrentConnectionState()
        }
    }
    public var isConnected: Bool { get { connectionState == .connected } }
    public var isDisconnected: Bool { get { connectionState == .disconnecting || connectionState == .notConnected } }

    public let didConnect = PassthroughSubject<Void, Never>()

    public let stream = ProtoStream()
    public let userData: UserData

    required public init(userData: UserData) {
        self.userData = userData

        super.init()

        configure(xmppStream: stream)
        stream.addDelegate(self, delegateQueue: DispatchQueue.main)

        // XMPP Modules
        let xmppReconnect = XMPPReconnect()
        xmppReconnect.addDelegate(self, delegateQueue: DispatchQueue.main)
        xmppReconnect.activate(stream)
    }

    // MARK: Connection management

    open func configure(xmppStream: ProtoStream) {
        stream.startTLSPolicy = .required
        stream.myJID = userData.userJID
        stream.protoService = self

        let appVersion = AppContext.appVersionForXMPP
        let userAgent = NSString(string: "HalloApp/iOS\(appVersion)")
        stream.clientVersion = userAgent
    }

    open func startConnectingIfNecessary() {
        if stream.myJID != nil && stream.isDisconnected {
            connect()
        }
    }

    public func connect() {
        guard stream.myJID != nil else { return }

        DDLogInfo("proto/connect [version: \(stream.clientVersion), passiveMode: \(stream.passiveMode)]")

        stream.hostName = userData.hostName
        stream.hostPort = userData.hostPort

        try! stream.connect(withTimeout: XMPPStreamTimeoutNone) // this only throws if stream isn't configured which doesn't happen for us.

        /* we do our own manual connection timeout as the xmppStream.connect timeout is not working */
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            self.startConnectingIfNecessary()
        }
    }

    public func disconnect() {
        DDLogInfo("proto/disconnect")

        connectionState = .disconnecting
        stream.disconnectAfterSending()
    }

    public func disconnectImmediately() {
        DDLogInfo("proto/disconnectImmediately")

        connectionState = .notConnected
        stream.disconnect()
    }

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

    private var requestsInFlight: [ProtoRequest] = []

    private var requestsToSend: [ProtoRequest] = []

    private func isRequestPending(_ request: ProtoRequest) -> Bool {
        if requestsInFlight.contains(where: { $0.requestId == request.requestId }) {
            return true
        }
        if requestsToSend.contains(where: { $0.requestId == request.requestId }) {
            return true
        }
        return false
    }

    public func enqueue(request: ProtoRequest) {
        if stream.isConnected {
            request.send(using: self)
            requestsInFlight.append(request)
        } else if request.retriesRemaining > 0 {
            requestsToSend.append(request)
        } else {
            request.failOnNoConnection()
        }
    }

    /**
     All requests in the queue are automatically resent when the connection is opened.
     */
    func resendAllPendingRequests() {
        guard !requestsToSend.isEmpty else {
            return
        }
        guard stream.isConnected else {
            DDLogWarn("connection/requests/resend/skipped [\(requestsToSend.count)] [no connection]")
            return
        }

        let allRequests = requestsToSend
        requestsToSend.removeAll()

        DDLogInfo("connection/requests/resend [\(allRequests.count)]")
        for request in allRequests {
            request.send(using: self)
        }
        requestsInFlight.append(contentsOf: allRequests)
    }

    func cancelAllRequests() {
        DDLogInfo("connection/requests/cancel/all [\(requestsInFlight.count)]")

        let allRequests = requestsInFlight + requestsToSend
        requestsInFlight.removeAll()
        requestsToSend.removeAll()

        for request in allRequests {
            if request.cancelAndPrepareFor(retry: true) {
                requestsToSend.append(request)
            }
        }
    }

    // MARK: Override points for subclasses.

    open func authenticationSucceeded(with authResult: Server_AuthResult) {
        connectionState = .connected
        performOnConnect()
    }

    open func authenticationFailed(with authResult: Server_AuthResult) {
        DDLogInfo("ProtoServiceCore/authenticationFailed")
        userData.logout()
    }

    open func performOnConnect() {
        didConnect.send()
        resendAllPendingRequests()
    }

    open func didReceive(packet: Server_Packet, requestID: String) {
        DDLogInfo("proto/didReceivePacket/\(requestID)")
        func removeRequest(with id: String, outOf requests: inout [ProtoRequest]) -> [ProtoRequest] {
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
        var matchingRequests: [ProtoRequest] = []
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
        DDLogInfo("proto/stream/didSecure")

        stream.sendAuthRequestWithPassword(password: userData.password)
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

        if error.element(forName: "conflict") != nil {
            if let text = error.element(forName: "text")?.stringValue {
                if text == "User removed" {
                    DDLogInfo("Stream: Same user logged into another device, logging out of this one")
                    userData.logout()
                }
            }
        }
    }
}

extension ProtoServiceCore: XMPPReconnectDelegate {

    open func xmppReconnect(_ sender: XMPPReconnect, didDetectAccidentalDisconnect connectionFlags: SCNetworkConnectionFlags) {
        DDLogInfo("proto/xmppReconnect/didDetectAccidentalDisconnect")
    }

    open func xmppReconnect(_ sender: XMPPReconnect, shouldAttemptAutoReconnect connectionFlags: SCNetworkConnectionFlags) -> Bool {
        return true
    }
}

extension ProtoServiceCore: CoreService {
    public func requestMediaUploadURL(size: Int, completion: @escaping ServiceRequestCompletion<MediaURLInfo>) {
        // Wait until connected to request URLs. User meanwhile can cancel posting.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: ProtoMediaUploadURLRequest(size: size, completion: completion))
        }
    }

    public func publishPost(_ post: FeedPostProtocol, feed: Feed, completion: @escaping ServiceRequestCompletion<Date?>) {
        // Request will fail immediately if we're not connected, therefore delay sending until connected.
        ///TODO: add option of canceling posting.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: ProtoPublishPostRequest(post: post, feed: feed, completion: completion))
        }
    }

    public func publishComment(_ comment: FeedCommentProtocol, groupId: GroupID?, completion: @escaping ServiceRequestCompletion<Date?>) {
        // Request will fail immediately if we're not connected, therefore delay sending until connected.
        ///TODO: add option of canceling posting.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: ProtoPublishCommentRequest(comment: comment, groupId: groupId, completion: completion))
        }
    }

    public func sendChatMessage(_ message: ChatMessageProtocol, encryption: EncryptOperation?) {

        guard let messageData = try? message.protoContainer.serializedData(),
            let fromUID = Int64(userData.userId),
            let toUID = Int64(message.toUserId) else
        {
            return
        }

        var packet = Server_Packet()
        packet.msg.toUid = toUID
        packet.msg.fromUid = fromUID
        packet.msg.id = message.id
        packet.msg.type = .chat

        var chat = Server_ChatStanza()
        chat.payload = messageData

        if let encrypt = encryption {
            encrypt(messageData) { encryptedData in
                if let encryptedPayload = encryptedData.data {
                    chat.encPayload = encryptedPayload
                } else {
                    DDLogError("ProtoServiceCore/sendChatMessage/\(message.id)/error encrypted data missing!")
                }

                if let publicKey = encryptedData.identityKey {
                    chat.publicKey = publicKey
                } else {
                    DDLogError("ProtoServiceCore/sendChatMessage/\(message.id)/error public key missing!")
                }

                chat.oneTimePreKeyID = Int64(encryptedData.oneTimeKeyId)
                packet.msg.payload = .chatStanza(chat)
                guard let packetData = try? packet.serializedData() else {
                    DDLogError("ProtoServiceCore/sendChatMessage/\(message.id)/error could not serialize chat message!")
                    return
                }
                DDLogInfo("ProtoServiceCore/sendChatMessage/\(message.id) sending (encrypted)")
                self.stream.send(packetData)
            }
        } else {
            packet.msg.payload = .chatStanza(chat)
            guard let packetData = try? packet.serializedData() else {
                DDLogError("ProtoServiceCore/sendChatMessage/\(message.id)/error could not serialize chat message!")
                return
            }
            DDLogInfo("ProtoServiceCore/sendChatMessage/\(message.id) sending (unencrypted)")
            stream.send(packetData)
        }
    }
}
