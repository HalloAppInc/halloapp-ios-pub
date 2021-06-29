//
//  NoiseStream.swift
//  Core
//
//  Created by Garrett on 12/7/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaAsyncSocket
import CocoaLumberjackSwift
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
    func receivedPacket(_ packet: Server_Packet)
    func receivedAuthResult(_ authResult: Server_AuthResult)
    func updateConnectionState(_ connectionState: ConnectionState)
    func receivedServerStaticKey(_ key: Data, for userID: UserID)
}

public enum NoiseStreamError: Error {
    case packetDecryptionFailure
}

public final class NoiseStream: NSObject {

    public init(
        userAgent: String,
        userID: UserID,
        noiseKeys: NoiseKeys,
        serverStaticKey: Data?,
        passiveMode: Bool,
        delegate: NoiseDelegate)
    {
        self.userAgent = userAgent
        self.userID = userID
        self.passiveMode = passiveMode
        self.noiseKeys = noiseKeys
        self.serverStaticKey = serverStaticKey
        self.socket = GCDAsyncSocket()
        self.delegate = delegate

        super.init()

        socket.delegate = self
        socket.delegateQueue = socketQueue
    }

    public func connect(host: String, port: UInt16) {
        guard isReadyToConnect else {
            DDLogError("noise/connect/error not-ready")
            return
        }
        do {
            DDLogInfo("noise/connect [passiveMode: \(passiveMode), \(userAgent), \(UIDevice.current.getModelName()) (iOS \(UIDevice.current.systemVersion))]")
            try socket.connect(toHost: host, onPort: port)
            state = .connecting
        } catch {
            DDLogError("noise/connect/error [\(error)]")
        }
    }

    public func disconnect(afterSending: Bool = false) {
        DDLogInfo("noise/disconnect [afterSending=\(afterSending)]")
        state = .disconnecting
        if afterSending {
            socket.disconnectAfterWriting()
        } else {
            socket.disconnect()
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

    private func disconnectWithError(_ error: NoiseStreamError) {
        AppContext.shared.errorLogger?.logError(error)

        // Shut down socket immediately without transitioning to `disconnecting` state.
        // This will prompt service to treat it as any other socket error and reconnect.
        socket.disconnect()
        socketBuffer?.removeAll()
    }

    private func reconnect() {
        guard let host = socket.connectedHost else {
            DDLogError("noise/reconnect/error not connected")
            return
        }
        let port = socket.connectedPort
        disconnect()
        connect(host: host, port: port)
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
        let finalData: Data = {
            let length = data.count
            guard length < 2<<24 else {
                DDLogError("noise/writeToSocket/error data exceeds max packet size")
                return Data()
            }
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

        socket.write(finalData, withTimeout: -1, tag: SocketTag.writeStream.rawValue)
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
                let serializedConfig = try makeClientConfig().serializedData()
                let msgA = try handshake.writeMessage(payload: serializedConfig)

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
        socket.readData(withTimeout: -1, tag: SocketTag.readStream.rawValue)
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
            delegate?.receivedServerStaticKey(staticKey, for: userID)
            do {
                let serializedConfig = try makeClientConfig().serializedData()
                let msgB = try handshake.writeMessage(payload: serializedConfig)
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
            delegate?.receivedServerStaticKey(staticKey, for: userID)

            do {
                let serializedConfig = try makeClientConfig().serializedData()
                let msgC = try handshake.writeMessage(payload: serializedConfig)
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
            socket.disconnect()
            state = .disconnected
        case .connecting, .connected, .disconnected, .disconnecting:
            DDLogInfo("noise/handshake/could-not-fail [state=\(state)]")
        }
    }

    private func makeClientConfig() -> Server_AuthRequest {
        var clientConfig = Server_AuthRequest()
        clientConfig.clientMode.mode = passiveMode ? .passive : .active
        clientConfig.clientVersion.version = userAgent as String
        clientConfig.resource = "iphone"
        if let uid = Int64(userID) {
            clientConfig.uid = uid
        } else {
            DDLogError("noise/makeClientConfig/error invalid userID [\(userID)]")
        }
        return clientConfig
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
            case .authorizing(_, let recv):
                guard let decryptedData = try? recv.decryptWithAd(ad: Data(), ciphertext: packetData) else {
                    DDLogError("noise/receive/error could not decrypt auth result [\(packetData.base64EncodedString())]")
                    disconnectWithError(.packetDecryptionFailure)
                    break
                }
                guard let authResult = try? Server_AuthResult(serializedData: decryptedData) else {
                    DDLogError("noise/receive/error could not deserialize auth result [\(decryptedData.base64EncodedString())]")
                    break
                }
                handshakeTimeoutTask?.cancel()
                handleAuthResult(authResult)
            case .connected(_, let recv):
                guard let decryptedData = try? recv.decryptWithAd(ad: Data(), ciphertext: packetData) else {
                    DDLogError("noise/receive/error could not decrypt packet [\(packetData.base64EncodedString())]")
                    disconnectWithError(.packetDecryptionFailure)
                    break
                }
                guard let packet = try? Server_Packet(serializedData: decryptedData) else {
                    DDLogError("noise/receive/error could not deserialize packet [\(decryptedData.base64EncodedString())]")
                    break
                }
                delegate?.receivedPacket(packet)
            }

            offset = packetEnd
        }

        socketBuffer = offset < buffer.count ? buffer.subdata(in: offset..<buffer.count) : nil
    }

    /// Handle the authentication result.
    private func handleAuthResult(_ authResult: Server_AuthResult) {
        guard case .authorizing(let send, let recv) = state else {
            DDLogError("noise/auth/error received auth result in state \(state)")
            return
        }
        if authResult.resultString == "success" {
            state = .connected(send, recv)
        } else {
            state = .disconnected
        }

        self.delegate?.receivedAuthResult(authResult)
    }

    private let userAgent: String
    private let userID: UserID
    private let passiveMode: Bool

    private let socket: GCDAsyncSocket
    private let socketQueue = DispatchQueue(label: "hallo.noise", qos: .userInitiated)
    private var socketBuffer: Data?

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
            case .disconnecting:
                delegate?.updateConnectionState(.disconnecting)
            case .authorizing, .handshake:
                // internal states
                break
            }
        }
    }
}

// MARK: GCDAsyncSocketDelegate

extension NoiseStream: GCDAsyncSocketDelegate {
    public func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        DDLogInfo("noise/socket-did-connect")
        
        self.socket.perform {
            // adapted from https://groups.google.com/g/cocoaasyncsocket/c/DtkL7zd68wE/m/MAxYy994gdgJ
            var flag: Int = 1
            let result: Int32 = setsockopt(self.socket.socketFD(), IPPROTO_TCP, TCP_NODELAY, &flag, 32)
            if result != 0 {
                DDLogError("noise/socket couldn't set TCP_NODELAY flag (couldn't disable nagle)")
            } else {
                DDLogInfo("noise/socket TCP_NODELAY flag is set (nagle is disabled)")
            }
        }
        
        startHandshake()
    }

    public func socket(_ sock: GCDAsyncSocket, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        DDLogInfo("noise/socket-did-receive-trust")
    }

    public func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        DDLogInfo("noise/socket-did-accept")
    }

    public func socket(_ sock: GCDAsyncSocket, didReadPartialDataOfLength partialLength: UInt, tag: Int) {
        DDLogInfo("noise/socket-did-read-partial")
    }

    public func socket(_ sock: GCDAsyncSocket, didWritePartialDataOfLength partialLength: UInt, tag: Int) {
        DDLogInfo("noise/socket-did-write-partial")
    }

    public func socket(_ sock: GCDAsyncSocket, shouldTimeoutReadWithTag tag: Int, elapsed: TimeInterval, bytesDone length: UInt) -> TimeInterval {
        DDLogInfo("noise/socket-read-timeout")
        return 0
    }

    public func socket(_ sock: GCDAsyncSocket, shouldTimeoutWriteWithTag tag: Int, elapsed: TimeInterval, bytesDone length: UInt) -> TimeInterval {
        DDLogInfo("noise/socket-write-timeout")
        return 0
    }

    public func socketDidSecure(_ sock: GCDAsyncSocket) {
        DDLogInfo("noise/socket-did-secure")
    }

    public func socketDidDisconnect(_ sock: GCDAsyncSocket, withError error: Error?) {
        if let error = error {
            DDLogError("noise/socket-did-disconnect/error \(error)")
        } else {
            DDLogInfo("noise/socket-did-disconnect")
        }
        state = .disconnected
    }

    public func socket(_ sock: GCDAsyncSocket, didConnectTo url: URL) {
        DDLogInfo("noise/socket-did-connect/\(url)")
    }

    public func socketDidCloseReadStream(_ sock: GCDAsyncSocket) {
        DDLogInfo("noise/socket-did-close-read-stream")
    }

    public func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        receive(data)

        // Continue reading
        sock.readData(withTimeout: -1, tag: SocketTag.readStream.rawValue)
    }

    public func socket(_ sock: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
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

// MARK: - SocketTag

private enum SocketTag: Int {
    case readStart = 100
    case readStream = 101
    case writeStart = 200
    case writeStop = 201
    case writeStream = 202
    case writeReceipt = 203
}
