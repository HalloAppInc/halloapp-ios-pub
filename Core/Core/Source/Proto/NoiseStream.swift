//
//  NoiseStream.swift
//  Core
//
//  Created by Garrett on 12/7/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Network
import Sodium
import SwiftNoise

private enum NoiseState {
    case disconnecting
    case disconnected
    case connecting
    case handshake(HandshakeState)
    case authorizing(CipherState, CipherState)
    case connected(CipherState, CipherState)
}

public protocol NoiseDelegate: AnyObject {
    func receivedPacketData(_ packetData: Data)
    func connectionPayload() -> Data?
    func receivedConnectionResponse(_ responseData: Data) -> Bool
    func updateConnectionState(_ connectionState: ConnectionState)
    func receivedServerStaticKey(_ key: Data)
}

public enum NoiseStreamError: Error {
    case handshakeFailure
    case packetDecryptionFailure
}

fileprivate let tcpTimeout: TimeInterval = 30.0

public final class NoiseStream: NSObject {

    public init(
        noiseKeys: NoiseKeys,
        serverStaticKey: Data?,
        delegate: NoiseDelegate)
    {
        self.noiseKeys = noiseKeys
        self.serverStaticKey = serverStaticKey
        self.delegate = delegate

        super.init()
    }

    public func connect(host: String, port: UInt16) {
        endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port))
        connectToEndpoint()
    }

    public func connectToEndpoint() {
        guard let endpoint = endpoint else {
            DDLogError("noise/connectToEndpoint/error [no-endpoint-defined]")
            return
        }
        guard isReadyToConnect else {
            DDLogError("noise/connectToEndpoint/error [not-ready]")
            return
        }

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true // Disable Nagle's algorithm
        tcp.connectionTimeout = Int(tcpTimeout)
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2
        tcp.keepaliveCount = 2
        tcp.keepaliveInterval = 2

        let params = NWParameters(tls: nil, tcp: tcp)
        let connectionID = UUID().uuidString

        let connection = NWConnection(to: endpoint, using: params)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            guard connectionID == self.connectionID else {
                DDLogInfo("noise/connection/state/ignoring (old connection) [\(state)]")
                return
            }
            DDLogInfo("noise/connection/state [\(state)]")
            switch state {
            case .ready:
                self.socketBuffer = nil
                self.startHandshake()
            case .waiting(let error):
                DDLogInfo("noise/connection/waiting [\(error.debugDescription)]")
            case .failed(let error):
                DDLogInfo("noise/connection/failed [\(error.debugDescription)]")
                self.state = .disconnected
                self.connection = nil
            case .cancelled:
                self.state = .disconnected
                self.connection = nil
            default:
                // Ignore other states
                break
            }
        }

        connection.betterPathUpdateHandler = { [weak self] isBetterPathAvailable in
            guard let self = self, isBetterPathAvailable else { return }
            guard connectionID == self.connectionID else {
                DDLogInfo("noise/connection/better-path-available/ignoring (old connection)")
                return
            }
            switch self.state {
            case .disconnected, .connected:
                // TODO: Don't drop old connection until we've established new connection.
                DDLogInfo("noise/connection/better-path-available/reconnect")
                self.reconnect()
            case .disconnecting, .connecting, .authorizing, .handshake:
                DDLogInfo("noise/connection/better-path-available/ignoring [\(self.state)]")
            }
        }

        self.connection?.cancel()
        self.connection = connection
        self.connectionID = connectionID
        self.state = .connecting

        connection.start(queue: socketQueue)
    }

    public func disconnect() {
        DDLogInfo("noise/disconnect")
        state = .disconnecting
        if let connection = connection {
            connection.cancel()
        } else {
            state = .disconnected
        }
    }

    public func send(_ data: Data) {
        guard case .connected(let send, _) = state else {
            DDLogError("noise/send/error not connected")
            return
        }
        socketQueue.async {
            do {
                let outgoingData = try send.encryptWithAd(ad: Data(), plaintext: data)
                self.writeToSocket(outgoingData)
            } catch {
                DDLogError("noise/send/encrypt/error \(error)")
            }
        }
    }

    public var isReadyToConnect: Bool {
        switch state {
        case .disconnecting, .disconnected:
            return true
        default:
            return false
        }
    }

    // MARK: Private

    private func disconnectWithError(_ error: NoiseStreamError, isDuringHandshake: Bool) {
        AppContext.shared.errorLogger?.logError(error)
        if case .packetDecryptionFailure = error {
            AppContext.shared.eventMonitor.count(.packetDecryption(duringHandshake: isDuringHandshake))
        }

        // Cancel connection immediately without transitioning to `disconnecting` state.
        // This will prompt service to treat it as any other socket error and reconnect.

        if let connection = connection {
            connection.forceCancel()
        } else {
            state = .disconnected
        }
    }

    private func reconnect() {
        shouldReconnectImmediately = true
        disconnect()
    }

    private func sendNoiseMessage(_ content: Data, type: Server_NoiseMessage.MessageType, timeout: TimeInterval? = 8, header: Data? = nil) {
        do {
            var msg = Server_NoiseMessage()
            msg.messageType = type
            msg.content = content
            let data = try msg.serializedData()
            DDLogInfo("noise/send/\(type) [\(data.count)]")
            writeToSocket(data, header: header)
        } catch {
            DDLogError("noise/sendNoiseMessage/error \(error)")
        }

        if let timeout = timeout {
            // Schedule a timeout. Must be canceled when response is received.
            handshakeTimeoutTask?.cancel()
            let handshakeTimeout = DispatchWorkItem { [weak self] in
                DDLogInfo("noise/handshake/timeout")
                self?.failHandshake()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: handshakeTimeout)
            handshakeTimeoutTask = handshakeTimeout
        }
    }

    private func writeToSocket(_ data: Data, header: Data? = nil) {
        let length = data.count
        guard length < 2<<24 else {
            DDLogError("noise/writeToSocket/error data exceeds max packet size")
            return
        }
        let finalData: Data = {
            let lengthHeader = Data(withUnsafeBytes(of: Int32(length).bigEndian, Array.init))
            guard let header = header else {
                return lengthHeader + data
            }
            return header + lengthHeader + data
        }()
        let nagleWarningThreshold: Int = 32
        if data.count < nagleWarningThreshold {
            // TODO(@ethan): send to server via client log
            DDLogWarn("noise/writeToSocket/warning sending \(data.count) bytes. consider coalescing packets as Nagle's is disabled")
        }

        connection?.send(content: finalData, completion: .contentProcessed { error in

            // NB: The server encodes the entire packet, but we'd like to only encode a prefix of the data.
            //     In order for our result to be a prefix of the server encoding, we should encode a multiple of 6 bits (Base64 stores 6 digits per digit).
            let base64String = data.prefix(24).base64EncodedString() + (length > 24 ? "..." : "")
            if let error = error {
                if let header = header {
                    DDLogError("noise/writeToSocket/error [\(error.debugDescription)] [header: \(header.base64EncodedString())] [packet-size: \(length)] [\(base64String)]")
                } else {
                    DDLogError("noise/writeToSocket/error [\(error.debugDescription)] [packet-size: \(length)] [\(base64String)]")
                }
            } else {
                if let header = header {
                    DDLogInfo("noise/writeToSocket/sent [header: \(header.base64EncodedString())] [packet-size: \(length)] [\(base64String)]")
                } else {
                    DDLogInfo("noise/writeToSocket/sent [packet-size: \(length)] [\(base64String)]")
                }
            }
        })
    }

    private func startHandshake() {

        // Generate new ephemeral keypair on every attempt for handshake
        // we use it for all our noise patterns - xx, ik, xxfallback
        self.clientEphemeralKeys = NoiseKeys()
        DDLogInfo("noise/connect/generate/ephemeralKeys - done]")

        guard let ephemeralKeys = clientEphemeralKeys else {
            DDLogError("noise/startHandshake/error missing ephemeralKeys")
            return
        }

        guard case .connecting = state else {
            DDLogError("noise/startHandshake/error invalid state [\(state)]")
            return
        }

        guard let handshakeSignature = "HA00".data(using: .utf8) else {
            DDLogError("noise/startHandshake/error invalid signature")
            return
        }

        let ephemeralKeyPair = ephemeralKeys.makeX25519KeyPair()
        if let serverStaticKey = serverStaticKey {

            DDLogInfo("noise/startHandshake/ik")

            do {
                let keypair = noiseKeys.makeX25519KeyPair()
                let handshake = try HandshakeState(pattern: .IK, initiator: true, prologue: Data(), s: keypair, e: ephemeralKeyPair, rs: serverStaticKey)
                let msgA = try handshake.writeMessage(payload: delegate?.connectionPayload() ?? Data())

                sendNoiseMessage(msgA, type: .ikA, header: handshakeSignature)
                state = .handshake(handshake)
            } catch {
                DDLogError("noise/startHandshake/ik/error \(error)")

                // IK setup failed for some reason, let's try clearing the static key and restarting with XX
                self.serverStaticKey = nil
                reconnect()
                return
            }
        } else {

            DDLogInfo("noise/startHandshake/xx")

            do {
                let keypair = noiseKeys.makeX25519KeyPair()
                let handshake = try HandshakeState(pattern: .XX, initiator: true, prologue: Data(), s: keypair, e: ephemeralKeyPair)
                let msgA = try handshake.writeMessage(payload: Data())

                sendNoiseMessage(msgA, type: .xxA, header: handshakeSignature)
                state = .handshake(handshake)
            } catch {
                DDLogError("noise/startHandshake/xx/error \(error)")
                return
            }
        }

        // Start reading
        listen()
    }

    private func continueHandshake(_ noiseMessage: Server_NoiseMessage) {
        if case .xxFallbackA = noiseMessage.messageType {
            guard let ephemeralKeys = clientEphemeralKeys else {
                DDLogError("noise/startHandshake/error missing ephemeralKeys")
                return
            }

            DDLogInfo("noise/handshake/xxfallback discard serverStaticKey. starting xxfallback")
            serverStaticKey = nil
            do {
                let keypair = noiseKeys.makeX25519KeyPair()
                let ephemeralKeypair = ephemeralKeys.makeX25519KeyPair()
                let handshake = try HandshakeState(pattern: .XXfallback, initiator: false, prologue: Data(), s: keypair, e: ephemeralKeypair)
                state = .handshake(handshake)
                DDLogInfo("noise/handshake/xxfallback reset HandshakeState")
            } catch {
                DDLogError("noise/startHandshake/xxfallback/error \(error)")
                reconnect()
                return
            }
        }

        guard case .handshake(let handshake) = state else {
            DDLogError("noise/handshake/error invalid state [\(state)]")
            return
        }

        let data: Data
        do {
            data = try handshake.readMessage(message: noiseMessage.content)
            DDLogInfo("noise/handshake/reading data")
        } catch {
            DDLogError("noise/handshake/error \(error)")
            failHandshake()
            return
        }
        DDLogInfo("noise/handshake/received [\(noiseMessage.messageType)] [\(data.count)]")

        switch noiseMessage.messageType {
        case .ikA, .xxA, .xxC, .xxFallbackB:
            DDLogError("noise/handshake/error received outgoing message type")
            failHandshake()
            return
        case .xxFallbackA:
            guard let staticKey = handshake.remoteS else {
                DDLogError("noise/handshake/xxfallback/error missing static key")
                failHandshake()
                return
            }
            guard NoiseStream.verify(staticKey: staticKey, certificate: data) else {
                DDLogError("noise/handshake/xxfallback/error unable to verify static key")
                failHandshake()
                return
            }
            serverStaticKey = staticKey
            delegate?.receivedServerStaticKey(staticKey)
            do {
                let msgB = try handshake.writeMessage(payload: delegate?.connectionPayload() ?? Data())
                sendNoiseMessage(msgB, type: .xxFallbackB)
                // server is the initiator and client is the responder, so key-split = (receive, send)
                let (receive, send) = try handshake.split()
                state = .authorizing(send, receive)
                DDLogInfo("noise/handshake/xxfallback, obtained keys to send and receive")
            } catch {
                DDLogError("noise/handshake/xxfallback/error \(error)")
                failHandshake()
                return
            }
        case .ikB:
            do {
                let (send, receive) = try handshake.split()
                state = .authorizing(send, receive)
            } catch {
                DDLogError("noise/handshake/ikB/error \(error)")
                failHandshake()
                return
            }
        case .xxB:

            guard let staticKey = handshake.remoteS else {
                DDLogError("noise/handshake/xxB/error missing static key")
                failHandshake()
                return
            }

            guard NoiseStream.verify(staticKey: staticKey, certificate: data) else {
                DDLogError("noise/handshake/xxB/error unable to verify static key")
                failHandshake()
                return
            }

            serverStaticKey = staticKey
            delegate?.receivedServerStaticKey(staticKey)

            do {
                let msgC = try handshake.writeMessage(payload: delegate?.connectionPayload() ?? Data())
                sendNoiseMessage(msgC, type: .xxC)
                let (send, receive) = try handshake.split()
                state = .authorizing(send, receive)
            } catch {
                DDLogError("noise/handshake/xxB/error \(error)")
                failHandshake()
                return
            }

        case .UNRECOGNIZED:
            DDLogError("noise/handshake/error received unknown message type [\(noiseMessage.messageType)]")
            failHandshake()
            return
        }
    }

    private static func verify(staticKey: Data, certificate: Data) -> Bool {
        let rootKey = Data.init(hex: "1dcd81dc096613759b186e93f354fff0a2f1e79390b8502a90bc461e08f98077")
        let messageStartIndex = certificate.count - staticKey.count
        guard messageStartIndex >= 0, certificate[messageStartIndex...].bytes == staticKey.bytes else {
            DDLogError("noise/verify/error signed message does not match static key")
            return false
        }

        return Sodium().sign.verify(signedMessage: certificate.bytes, publicKey: rootKey.bytes)
    }

    // Decrypt push content using Noise-X pattern.
    public static func decryptPushContent(noiseKeys: NoiseKeys, encryptedMessage: Data) -> Server_PushContent? {
        do {
            let handshake = try HandshakeState(pattern: .X, initiator: false, prologue: Data(), s: noiseKeys.makeX25519KeyPair())
            DDLogInfo("NoiseStream/decryptPushContent/encrypted message: \(encryptedMessage)")
            // Drop Header
            let encryptedContent = encryptedMessage.dropFirst(1)
            let data = try handshake.readMessage(message: encryptedContent)
            DDLogInfo("NoiseStream/decryptPushContent/data: \(data)")
            let pushContent = try Server_PushContent(serializedData: data)
            DDLogInfo("NoiseStream/decryptPushContent/noise/handshake/reading data")
            guard let staticKey = handshake.remoteS else {
                DDLogError("NoiseStream/decryptPushContent/noise/handshake/x/error missing static key")
                return nil
            }
            guard Self.verify(staticKey: staticKey, certificate: pushContent.certificate) else {
                DDLogError("NoiseStream/decryptPushContent/noise/handshake/x/error unable to verify static key")
                return nil
            }
            return pushContent
        } catch {
            DDLogError("NoiseStream/decryptPushContent/noise/error: \(error)")
            return nil
        }
    }

    private func failHandshake() {
        switch state {
        case .authorizing, .handshake:
            DDLogInfo("noise/handshake/failed")
            disconnectWithError(.handshakeFailure, isDuringHandshake: true)
        case .connecting, .connected, .disconnected, .disconnecting:
            DDLogInfo("noise/handshake/could-not-fail [state=\(state)]")
        }
    }

    private func listen() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, _, _, error) in
            if let error = error {
                DDLogError("noise/listen/receive/error [\(error.debugDescription)]")
            }
            if let data = data {
                self?.receive(data)
                self?.listen()
            } else {
                DDLogError("noise/listen/receive/error [no-data]")
            }
        }
    }

    private func receive(_ data: Data) {

        let buffer: Data = {
            guard let socketBuffer = socketBuffer else { return data }
            return socketBuffer + data
        }()

        var offset = 0
        while offset < buffer.count {
            // The socket may have read multiple proto packets. Split them up using 4-byte length headers.
            let lengthData = Data(bytes: Array(buffer.bytes[offset..<buffer.count]), count: 4)
            let length = Int(UInt32(bigEndian: lengthData.withUnsafeBytes { $0.load(as: UInt32.self)}))

            let packetStart = offset + 4
            let packetEnd = packetStart + length
            if packetEnd > buffer.count {
                DDLogInfo("noise/receive/buffering [\(packetEnd - buffer.count) of \(length) bytes remaining...]")
                break
            }
            let packetData = buffer.subdata(in: packetStart..<packetEnd)

            switch state {
            case .disconnecting:
                DDLogInfo("noise/receive/ignoring (disconnecting)")
            case .disconnected:
                DDLogError("noise/receive/error received packet while disconnected")
            case .connecting:
                DDLogError("noise/receive/error received packet before handshake")
            case .handshake:
                guard let noiseMessage = try? Server_NoiseMessage(serializedData: packetData) else {
                    DDLogError("noise/receive/error could not deserialize noise message [\(packetData.base64EncodedString())]")
                    break
                }
                handshakeTimeoutTask?.cancel()
                continueHandshake(noiseMessage)
            case .authorizing(let send, let recv):
                guard let decryptedData = try? recv.decryptWithAd(ad: Data(), ciphertext: packetData) else {
                    DDLogError("noise/receive/error could not decrypt auth result [\(packetData.base64EncodedString())]")
                    disconnectWithError(.packetDecryptionFailure, isDuringHandshake: true)
                    break
                }
                handshakeTimeoutTask?.cancel()
                if let delegate = delegate {
                    if delegate.receivedConnectionResponse(decryptedData) {
                        state = .connected(send, recv)
                    } else {
                        DDLogInfo("noise/receive/authorizing/connection-not-successful")
                        disconnect()
                    }
                } else {
                    DDLogError("noise/receive/error [no-delegate]")
                    disconnect()
                }
            case .connected(_, let recv):
                guard let decryptedData = try? recv.decryptWithAd(ad: Data(), ciphertext: packetData) else {
                    DDLogError("noise/receive/error could not decrypt packet [\(packetData.base64EncodedString())]")
                    disconnectWithError(.packetDecryptionFailure, isDuringHandshake: false)
                    break
                }
                delegate?.receivedPacketData(decryptedData)
            }

            offset = packetEnd
        }

        socketBuffer = offset < buffer.count ? buffer.subdata(in: offset..<buffer.count) : nil
    }

    private let socketQueue = DispatchQueue(label: "hallo.noise", qos: .userInitiated)
    private var socketBuffer: Data?

    private var endpoint: NWEndpoint?
    private var connection: NWConnection?
    private var shouldReconnectImmediately = false
    private var connectionID = ""

    private let noiseKeys: NoiseKeys
    private var clientEphemeralKeys: NoiseKeys?
    private var serverStaticKey: Data?

    private var handshakeTimeoutTask: DispatchWorkItem?

    private weak var delegate: NoiseDelegate?

    private var state: NoiseState = .disconnected {
        didSet {
            switch state {
            case .connected:
                delegate?.updateConnectionState(.connected)
            case .connecting:
                delegate?.updateConnectionState(.connecting)
            case .disconnected:
                delegate?.updateConnectionState(.notConnected)
                if shouldReconnectImmediately {
                    shouldReconnectImmediately = false
                    // New connection was not receiving data without this delay, not sure why it's needed.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.connectToEndpoint()
                    }
                }
            case .disconnecting:
                delegate?.updateConnectionState(.disconnecting)
            case .authorizing, .handshake:
                // internal states
                break
            }
        }
    }
}

// MARK: - NoiseKeys

public struct NoiseKeys: Codable {
    public init(privateEdKey: Data, publicEdKey: Data) {
        self.privateEdKey = privateEdKey
        self.publicEdKey = publicEdKey
    }

    public init?() {
        guard let keys = Sodium().sign.keyPair() else {
            DDLogError("NoiseKeys/init/unable to generate keypair")
            return nil
        }
        self = NoiseKeys(privateEdKey: Data(keys.secretKey), publicEdKey: Data(keys.publicKey))
    }

    /// Ed25519 format
    public var privateEdKey: Data

    public var publicEdKey: Data

    public func sign(_ data: Data) -> Data? {
        let signingKey = Sign.KeyPair.SecretKey(privateEdKey)
        guard let signedMessage = Sodium().sign.sign(message: data.bytes, secretKey: signingKey) else {
            DDLogError("noise/sign/error unable to sign data")
            return nil
        }
        return Data(signedMessage)
    }
}

private extension NoiseKeys {
    func makeX25519KeyPair() -> KeyPair? {
        let edKeys = Sign.KeyPair(publicKey: publicEdKey.bytes, secretKey: privateEdKey.bytes)
        guard let x25519Keys = Sodium().sign.convertToX25519KeyPair(keyPair: edKeys) else {
            DDLogError("noise/error could not convert noise keys to x25519")
            return nil
        }
        return KeyPair(
            publicKey: Data(x25519Keys.publicKey),
            secretKey: Data(x25519Keys.secretKey)
        )
    }
}
