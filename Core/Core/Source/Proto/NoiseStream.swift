//
//  NoiseStream.swift
//  Core
//
//  Created by Garrett on 12/7/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaAsyncSocket
import CocoaLumberjack
import Sodium
import SwiftNoise

private enum NoiseState {
    case disconnecting
    case disconnected
    case handshake(HandshakeState)
    case authorizing(CipherState, CipherState)
    case connected(CipherState, CipherState)
}

public final class NoiseStream: NSObject {

    public init(userAgent: String, userID: UserID, serverStaticKey: Data?, passiveMode: Bool = false) {
        self.userAgent = userAgent
        self.userID = userID
        self.passiveMode = passiveMode
        self.serverStaticKey = serverStaticKey
        self.socket = GCDAsyncSocket()

        super.init()

        socket.delegate = self
        socket.delegateQueue = socketQueue
    }

    public func connect(host: String, port: UInt16) {
        do {
            DDLogInfo("noise/connect [passiveMode: \(passiveMode), \(userAgent), \(UIDevice.current.getModelName()) (iOS \(UIDevice.current.systemVersion))]")
            try socket.connect(toHost: host, onPort: port)
            protoService?.connectionState = .connecting
        } catch {
            DDLogError("noise/connect/error [\(error)]")
        }
    }

    public func disconnect(afterSending: Bool = false) {
        DDLogInfo("noise/disconnect [afterSending=\(afterSending)]")
        state = .disconnecting
        protoService?.connectionState = .disconnecting
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

    // TODO: Move this to a delegate relationship (stream should not depend on service)
    public weak var protoService: ProtoServiceCore?
    public var noiseKeys: NoiseKeys?

    public var isReadyToConnect: Bool {
        switch state {
        case .disconnecting, .disconnected:
            return noiseKeys != nil
        default:
            return false
        }
    }

    // MARK: Private

    private func reconnect() {
        guard let host = socket.connectedHost else {
            DDLogError("noise/reconnect/error not connected")
            return
        }
        let port = socket.connectedPort
        disconnect()
        connect(host: host, port: port)
    }

    private func sendNoiseMessage(_ content: Data, type: Server_NoiseMessage.MessageType) {
        do {
            var msg = Server_NoiseMessage()
            msg.messageType = type
            msg.content = content
            let data = try msg.serializedData()
            DDLogInfo("noise/send/\(type) [\(data.count)]")
            writeToSocket(data)
        } catch {
            DDLogError("noise/sendNoiseMessage/error \(error)")
        }
    }

    private func writeToSocket(_ data: Data, prependLengthHeader: Bool = true) {
        let finalData: Data = {
            guard prependLengthHeader else { return data }
            let length = data.count
            guard length < 2<<24 else {
                DDLogError("noise/writeToSocket/error data exceeds max packet size")
                return Data()
            }
            let lengthHeader = Data(withUnsafeBytes(of: Int32(length).bigEndian, Array.init))
            return lengthHeader + data
        }()

        socket.write(finalData, withTimeout: -1, tag: SocketTag.writeStream.rawValue)
    }

    private func startHandshake() {
        guard let noiseKeys = noiseKeys else {
            DDLogError("noise/startHandshake/error missing keys")
            return
        }

        guard case .disconnected = state else {
            DDLogError("noise/startHandshake/error invalid state [\(state)]")
            return
        }

        guard let handshakeSignature = "HA00".data(using: .utf8) else {
            DDLogError("noise/startHandshake/error invalid signature")
            return
        }

        writeToSocket(handshakeSignature, prependLengthHeader: false)

        if let serverStaticKey = serverStaticKey {

            DDLogInfo("noise/startHandshake/ik")

            do {
                let keypair = noiseKeys.makeX25519KeyPair()
                let handshake = try HandshakeState(pattern: .IK, initiator: true, prologue: Data(), s: keypair, rs: serverStaticKey)
                let serializedConfig = try makeClientConfig().serializedData()
                let msgA = try handshake.writeMessage(payload: serializedConfig)

                sendNoiseMessage(msgA, type: .ikA)
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
                let handshake = try HandshakeState(pattern: .XX, initiator: true, prologue: Data(), s: keypair)
                let msgA = try handshake.writeMessage(payload: Data())

                sendNoiseMessage(msgA, type: .xxA)
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
        guard case .handshake(let handshake) = state else {
            DDLogError("noise/handshake/error invalid state [\(state)]")
            return
        }

        if case .xxFallbackA = noiseMessage.messageType {
            DDLogInfo("noise/handshake/error server requested fallback (unimplemented). restarting xx.")
            serverStaticKey = nil
            reconnect()
            return
        }

        let data: Data
        do {
            data = try handshake.readMessage(message: noiseMessage.content)
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
            DDLogError("noise/handshake/error unimplemented")
            failHandshake()
            return
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

            guard verify(staticKey: staticKey, certificate: data) else {
                DDLogError("noise/handshake/xxB/error unable to verify static key")
                failHandshake()
                return
            }

            serverStaticKey = staticKey
            protoService?.receivedServerStaticKey(staticKey, for: userID)

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

    private func verify(staticKey: Data, certificate: Data) -> Bool {
        let rootKey = Data.init(hex: "1dcd81dc096613759b186e93f354fff0a2f1e79390b8502a90bc461e08f98077")
        let messageStartIndex = certificate.count - staticKey.count
        guard messageStartIndex >= 0, certificate[messageStartIndex...].bytes == staticKey.bytes else {
            DDLogError("noise/verify/error signed message does not match static key")
            return false
        }

        return Sodium().sign.verify(signedMessage: certificate.bytes, publicKey: rootKey.bytes)
    }

    private func failHandshake() {
        DDLogInfo("noise/handshake/failed")
        state = .disconnected
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
            case .handshake:
                guard let noiseMessage = try? Server_NoiseMessage(serializedData: packetData) else {
                    DDLogError("noise/receive/error could not deserialize noise message [\(packetData.base64EncodedString())]")
                    break
                }
                continueHandshake(noiseMessage)
            case .authorizing(_, let recv):
                guard let decryptedData = try? recv.decryptWithAd(ad: Data(), ciphertext: packetData) else {
                    DDLogError("noise/receive/error could not decrypt auth result [\(packetData.base64EncodedString())]")
                    break
                }
                guard let authResult = try? Server_AuthResult(serializedData: decryptedData) else {
                    DDLogError("noise/receive/error could not deserialize auth result [\(decryptedData.base64EncodedString())]")
                    break
                }
                handleAuthResult(authResult)
            case .connected(_, let recv):
                guard let decryptedData = try? recv.decryptWithAd(ad: Data(), ciphertext: packetData) else {
                    DDLogError("noise/receive/error could not decrypt packet [\(packetData.base64EncodedString())]")
                    break
                }
                guard let packet = try? Server_Packet(serializedData: decryptedData) else {
                    DDLogError("noise/receive/error could not deserialize packet [\(decryptedData.base64EncodedString())]")
                    break
                }
                guard let requestID = packet.requestID else {
                    // TODO: Remove this limitation (only present for parity with XMPP/ProtoStream behavior)
                    DDLogError("noise/receive/error packet missing request ID [\(packet)]")
                    break
                }
                protoService?.didReceive(packet: packet, requestID: requestID)
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
        if authResult.result == "success" {
            state = .connected(send, recv)

            DispatchQueue.main.async {
                self.protoService?.authenticationSucceeded(with: authResult)
            }
        } else {
            state = .disconnected
            protoService?.authenticationFailed(with: authResult)
        }
    }

    private let userAgent: String
    private let userID: UserID
    private let passiveMode: Bool

    private let socket: GCDAsyncSocket
    private let socketQueue = DispatchQueue(label: "hallo.noise", qos: .userInitiated)
    private var socketBuffer: Data?

    private var clientKeyPair: NoiseKeys?
    private var serverStaticKey: Data?

    private var state: NoiseState = .disconnected
}

// MARK: GCDAsyncSocketDelegate

extension NoiseStream: GCDAsyncSocketDelegate {
    public func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        DDLogInfo("noise/socket-did-connect")
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
        protoService?.connectionState = .notConnected
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
