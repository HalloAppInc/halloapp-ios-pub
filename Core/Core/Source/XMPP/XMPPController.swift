//
//  Jab.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/7/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Foundation
import XMPPFramework


open class XMPPController: NSObject {

    public enum ConnectionState {
        case notConnected
        case connecting
        case connected
        case disconnecting
    }

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
            DDLogDebug("xmpp/connectionState/change [\(oldValue)] -> [\(connectionState)]")
            runCallbacksForCurrentConnectionState()
        }
    }
    public var isConnected: Bool { get { connectionState == .connected } }
    public var isDisconnected: Bool { get { connectionState == .disconnecting || connectionState == .notConnected } }

    public let didConnect = PassthroughSubject<Void, Never>()

    public let xmppStream = XMPPStream()
    public let userData: UserData

    required public init(userData: UserData) {
        self.userData = userData

        super.init()

        configure(xmppStream: xmppStream)
        xmppStream.addDelegate(self, delegateQueue: DispatchQueue.main)

        // XMPP Modules
        let xmppReconnect = XMPPReconnect()
        xmppReconnect.addDelegate(self, delegateQueue: DispatchQueue.main)
        xmppReconnect.activate(xmppStream)

        let xmppPing = XMPPPing()
        xmppPing.addDelegate(self, delegateQueue: DispatchQueue.main)
        xmppPing.activate(xmppStream)
    }

    // MARK: Connection management

    open func configure(xmppStream: XMPPStream) {
        /* probably should be "required" once all servers including test servers are secured */
        xmppStream.startTLSPolicy = XMPPStreamStartTLSPolicy.preferred
        xmppStream.registerCustomElementNames(["ack"])
        xmppStream.myJID = userData.userJID
    }

    public func startConnectingIfNecessary() {
        if xmppStream.myJID != nil && xmppStream.isDisconnected {
            connect()
        }
    }

    public func connect() {
        guard xmppStream.myJID != nil else { return }

        DDLogInfo("xmpp/connect [version \(xmppStream.clientVersion)]")

        xmppStream.hostName = userData.hostName

        try! xmppStream.connect(withTimeout: XMPPStreamTimeoutNone) // this only throws if stream isn't configured which doesn't happen for us.

        /* we do our own manual connection timeout as the xmppStream.connect timeout is not working */
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            self.startConnectingIfNecessary()
        }
    }

    public func disconnect() {
        DDLogInfo("xmpp/disconnect")

        connectionState = .disconnecting
        xmppStream.disconnectAfterSending()
    }

    public func disconnectImmediately() {
        DDLogInfo("xmpp/disconnectImmediately")

        connectionState = .notConnected
        xmppStream.disconnect()
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

    // MARK: Acks

    public func sendAck(for message: XMPPMessage) {
        if let ack = XMPPAck.ack(for: message) {
            DDLogDebug("connection/send-ack id=[\(ack.id)] to=[\(ack.to)] from=[\(ack.from)]")
            self.xmppStream.send(ack.xmlElement)
        }
    }

    // MARK: Requests

    private var requestsInFlight: [XMPPRequest] = []

    private var requestsToSend: [XMPPRequest] = []

    private func isRequestPending(_ request: XMPPRequest) -> Bool {
        if self.requestsInFlight.contains(where: { $0.requestId == request.requestId }) {
            return true
        }
        if self.requestsToSend.contains(where: { $0.requestId == request.requestId }) {
            return true
        }
        return false
    }

    public func enqueue(request: XMPPRequest) {
        if self.xmppStream.isConnected {
            request.send(using: self)
            self.requestsInFlight.append(request)
        } else if request.retriesRemaining > 0 {
            self.requestsToSend.append(request)
        } else {
            request.failOnNoConnection()
        }
    }

    /**
     All requests in the queue are automatically resent when the connection is opened.
     */
    func resendAllPendingRequests() {
        guard !self.requestsToSend.isEmpty else {
            return
        }
        guard self.xmppStream.isConnected else {
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

    func cancelAllRequests() {
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

    // MARK: Override points for subclasses.

    open func performOnConnect() {
        self.didConnect.send()
        self.resendAllPendingRequests()
    }

    open func didReceive(message: XMPPMessage) {
        // Subclasses to implement.
    }

    open func didReceive(IQ iq: XMPPIQ) {
        if let requestId = iq.elementID {
            func removeRequest(with id: String, outOf requests: inout [XMPPRequest]) -> [XMPPRequest] {
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
            var matchingRequests: [XMPPRequest] = []
            matchingRequests.append(contentsOf: removeRequest(with: requestId, outOf: &self.requestsInFlight))
            matchingRequests.append(contentsOf: removeRequest(with: requestId, outOf: &self.requestsToSend))
            if matchingRequests.count > 1 {
                DDLogWarn("connection/response/\(requestId)/warning: found \(matchingRequests.count) requests")
            }
            for request in matchingRequests {
                DDLogInfo("connection/response/\(type(of: request))/\(requestId)")
                request.process(response: iq)
            }
        }
    }

    open func didReceive(ack: XMPPAck) {
        // Subclasses to implement.
    }

    open func didReceive(presence: XMPPPresence) {
        // Subclasses to implement.
    }
}

extension XMPPController: XMPPStreamDelegate {

    public func xmppStreamWillConnect(_ sender: XMPPStream) {
        DDLogInfo("xmpp/stream/willConnect")

        connectionState = .connecting
    }

    public func xmppStreamConnectDidTimeout(_ stream: XMPPStream) {
        DDLogInfo("xmpp/stream/connectDidTimeout")
    }

    public func xmppStreamDidDisconnect(_ sender: XMPPStream, withError error: Error?) {
        DDLogInfo("xmpp/stream/didDisconnect [\(String(describing: error))]")

        connectionState = .notConnected
        cancelAllRequests()
    }

    public func xmppStream(_ sender: XMPPStream, socketDidConnect socket: GCDAsyncSocket) {
        DDLogInfo("xmpp/stream/socketDidConnect")
    }

    public func xmppStreamDidStartNegotiation(_ sender: XMPPStream) {
        DDLogInfo("xmpp/stream/didStartNegotiation")
    }

    public func xmppStream(_ sender: XMPPStream, willSecureWithSettings settings: NSMutableDictionary) {
        DDLogInfo("xmpp/stream/willSecureWithSettings [\(settings)]")

        settings.setObject(true, forKey:GCDAsyncSocketManuallyEvaluateTrust as NSCopying)
    }

    public func xmppStream(_ sender: XMPPStream, didReceive trust: SecTrust, completionHandler: ((Bool) -> Void)) {
        DDLogInfo("xmpp/stream/didReceiveTrust")

        if SecTrustEvaluateWithError(trust, nil) {
            completionHandler(true)
        } else {
            //todo: handle gracefully and reflect in global state
            completionHandler(false)
        }
    }

    public func xmppStreamDidSecure(_ sender: XMPPStream) {
        DDLogInfo("xmpp/stream/didSecure")
    }

    public func xmppStreamDidConnect(_ stream: XMPPStream) {
        DDLogInfo("xmpp/stream/didConnect")

        try! stream.authenticate(withPassword: self.userData.password)
    }

    public func xmppStreamDidAuthenticate(_ sender: XMPPStream) {
        DDLogInfo("xmpp/stream/didAuthenticate")

        connectionState = .connected
        performOnConnect()
    }

    public func xmppStream(_ sender: XMPPStream, didNotAuthenticate error: DDXMLElement) {
        DDLogInfo("xmpp/stream/didNotAuthenticate")

        self.userData.logout()
    }

    public func xmppStream(_ sender: XMPPStream, didReceive message: XMPPMessage) {
        guard message.fromStr ?? "" != "pubsub.s.halloapp.net" else {
            // PubSub messages are handled through XMPPPubSub module.
            return
        }

        DDLogInfo("xmpp/stream/didReceiveMessage id=[\(message.elementID ?? "<empty>")]")

        didReceive(message: message)
    }

    public func xmppStream(_ sender: XMPPStream, didReceive iq: XMPPIQ) -> Bool {
        DDLogInfo("xmpp/stream/didReceiveIQ id=[\(iq.elementID ?? "<empty>")]")

        didReceive(IQ: iq)
        return false
    }

    public func xmppStream(_ sender: XMPPStream, didReceiveError error: DDXMLElement) {
        DDLogInfo("xmpp/stream/didReceiveError [\(error)]")

        if error.element(forName: "conflict") != nil {
            if let text = error.element(forName: "text")?.stringValue {
                if text == "User removed" {
                    DDLogInfo("Stream: Same user logged into another device, logging out of this one")
                    self.userData.logout()
                }
            }
        }
    }

    public func xmppStream(_ sender: XMPPStream, didReceive presence: XMPPPresence) {
        DDLogInfo("xmpp/stream/didReceivePresence")

        didReceive(presence: presence)
    }

    public func xmppStream(_ sender: XMPPStream, didReceiveCustomElement element: DDXMLElement) {
        DDLogInfo("xmpp/stream/didReceiveCustomElement [\(element)]")

        if element.name == "ack" {
            if let ack = XMPPAck(itemElement: element) {
                didReceive(ack: ack)
            } else {
                DDLogError("xmpp/ack/invalid [\(element)]")
            }
        }
    }
}

extension XMPPController: XMPPReconnectDelegate {

    public func xmppReconnect(_ sender: XMPPReconnect, didDetectAccidentalDisconnect connectionFlags: SCNetworkConnectionFlags) {
        DDLogInfo("xmpp/xmppReconnect/didDetectAccidentalDisconnect")
    }

    public func xmppReconnect(_ sender: XMPPReconnect, shouldAttemptAutoReconnect connectionFlags: SCNetworkConnectionFlags) -> Bool {
        return true
    }
}

extension XMPPController: XMPPPingDelegate {

    public func xmppPing(_ sender: XMPPPing!, didReceivePong pong: XMPPIQ!, withRTT rtt: TimeInterval) {
        DDLogInfo("xmpp/ping/didReceivePong")
    }

    public func xmppPing(_ sender: XMPPPing!, didNotReceivePong pingID: String!, dueToTimeout timeout: TimeInterval) {
        DDLogInfo("xmpp/ping/didNotReceivePong")
    }
}

