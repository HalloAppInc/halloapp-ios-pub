//
//  WebClientManager.swift
//  HalloApp
//
//  Created by Garrett on 6/6/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import CoreCommon
import Foundation
import SwiftNoise

final class WebClientManager {

    init(service: CoreServiceCommon, noiseKeys: NoiseKeys) {
        self.service = service
        self.noiseKeys = noiseKeys
    }

    enum State {
        case disconnected
        case registering
        case handshaking(HandshakeState)
        case connected(CipherState, CipherState)
    }

    let service: CoreServiceCommon
    let noiseKeys: NoiseKeys
    var state = CurrentValueSubject<State, Never>(.disconnected)

    private let webQueue = DispatchQueue(label: "hallo.web", qos: .userInitiated)
    // TODO: Persist keys
    private(set) var webStaticKey: Data?
    private var keysToRemove = Set<Data>()
    private var isRemovingKeys = false


    func connect(staticKey: Data) {
        webQueue.async {
            if let oldKey = self.webStaticKey {
                if oldKey == staticKey {
                    DDLogInfo("WebClientManager/connect/skipping [matches-current-key] [\(oldKey)]")
                    return
                } else {
                    DDLogInfo("WebClientManager/connect/will-remove-old-key [\(oldKey)]")
                    self.keysToRemove.insert(oldKey)
                }
            }
            self.webStaticKey = staticKey
            self.state.value = .registering
            self.service.authenticateWebClient(staticKey: staticKey) { [weak self] result in
                switch result {
                case .success:
                    self?.startHandshake()

                case .failure:
                    self?.disconnect(shouldRemoveOldKey: false)
                }
            }
            self.removeOldKeysIfNecessary()
        }
    }

    func disconnect(shouldRemoveOldKey: Bool = true) {
        webQueue.async {
            if let webStaticKey = self.webStaticKey, shouldRemoveOldKey {
                self.keysToRemove.insert(webStaticKey)
            }
            self.webStaticKey = nil
            self.state.value = .disconnected
            self.removeOldKeysIfNecessary()
        }
    }

    func handleIncomingData(_ data: Data, from staticKey: Data) {
        webQueue.async {
            guard let container = try? Web_WebContainer(serializedData: data) else {
                DDLogError("WebClientManager/handleIncoming/error [deserialization]")
                return
            }
            guard staticKey == self.webStaticKey else {
                DDLogError("WebClientManager/handleIncoming/error [unrecognized-static-key: \(staticKey.base64EncodedString())] [expected: \(self.webStaticKey?.base64EncodedString() ?? "nil")]")
                return
            }
            switch container.payload {
            case .noiseMessage(let noiseMessage):
                self.continueHandshake(noiseMessage)
            case .none:
                DDLogError("WebClientManager/handleIncoming/error [missing-payload]")
            }
        }
    }

    func send(_ data: Data) {
        webQueue.async {
            guard case .connected(let send, _) = self.state.value else {
                DDLogError("WebClientManager/send/error [not-connected]")
                return
            }
            guard let key = self.webStaticKey else {
                DDLogError("WebClientManager/send/error [no-key]")
                return
            }
            do {
                let encryptedData = try send.encryptWithAd(ad: Data(), plaintext: data)
                self.service.sendToWebClient(staticKey: key, data: encryptedData) { _ in }
            } catch {
                DDLogError("WebClientManager/send/error [\(error)]")
            }
        }
    }

    private func startHandshake() {
        guard let ephemeralKeys = NoiseKeys() else {
            DDLogError("WebClientManager/startHandshake/error [keygen-failure]")
            disconnect()
            return
        }
        let handshake: HandshakeState
        do {
            handshake = try HandshakeState(
                pattern: .IK,
                initiator: true,
                prologue: Data(),
                s: noiseKeys.makeX25519KeyPair(),
                e: ephemeralKeys.makeX25519KeyPair(),
                rs: webStaticKey)
        } catch {
            DDLogError("WebClientManager/startHandshake/error [\(error)]")
            disconnect()
            return
        }
        self.state.value = .handshaking(handshake)
        do {
            let msgA = try handshake.writeMessage(payload: Data())
            self.sendNoiseMessage(msgA, type: .ikA)
            // TODO: Set timeout
        } catch {
            DDLogError("WebClientManager/startHandshake/error [\(error)]")
        }
    }

    private func continueHandshake(_ noiseMessage: Web_NoiseMessage) {
        guard case .handshaking(let handshake) = state.value else {
            DDLogError("WebClientManager/handshake/error [state: \(state.value)]")
            return
        }
        do {
            let data = try handshake.readMessage(message: noiseMessage.content)
            DDLogInfo("WebClientManager/handshake/reading data [\(data.count) bytes]")
        } catch {
            DDLogError("WebClientManager/handshake/error [\(error)]")
            return
        }
        switch noiseMessage.messageType {
        case .kkA, .kkB, .ikA, .UNRECOGNIZED:
            DDLogError("WebClientManager/handshake/error [message-type: \(noiseMessage.messageType)]")
        case .ikB:
            do {
                let (send, receive) = try handshake.split()
                self.state.value = .connected(send, receive)
            } catch {
                DDLogError("WebClientManager/handshake/ikB/error [\(error)]")
            }
        }
    }

    private func sendNoiseMessage(_ content: Data, type: Web_NoiseMessage.MessageType) {
        guard let webStaticKey = webStaticKey else {
            DDLogError("WebClientManager/sendNoiseMessage/error [no-key]")
            return
        }

        do {
            var msg = Web_NoiseMessage()
            msg.messageType = type
            msg.content = content

            var container = Web_WebContainer()
            container.payload = .noiseMessage(msg)

            let data = try container.serializedData()
            DDLogInfo("WebClientManager/sendNoiseMessage/\(type) [\(data.count)]")

            service.sendToWebClient(staticKey: webStaticKey, data: data) { _ in }
        } catch {
            DDLogError("WebClientManager/sendNoiseMessage/error \(error)")
        }
    }

    // TODO: Schedule this on timer
    private func removeOldKeysIfNecessary() {
        guard !keysToRemove.isEmpty else {
            DDLogInfo("WebClientManager/removeOldKeys/skipping [no-keys]")
            return
        }
        guard !isRemovingKeys else {
            DDLogInfo("WebClientManager/removeOldKeys/skipping [in-progress]")
            return
        }

        isRemovingKeys = true
        let group = DispatchGroup()
        group.notify(queue: webQueue) { [weak self] in
            self?.isRemovingKeys = false
        }
        for key in keysToRemove {
            DDLogInfo("WebClientManager/removeOldKeys/start [\(key.base64EncodedString())]")
            group.enter()
            service.removeWebClient(staticKey: key) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    DDLogError("WebClientManager/removeOldKeys/error [\(key.base64EncodedString())] [\(error)]")
                    group.leave()
                case .success:
                    DDLogInfo("WebClientManager/removeOldKeys/success [\(key.base64EncodedString())]")
                    self.webQueue.async {
                        self.keysToRemove.remove(key)
                        group.leave()
                    }
                }
            }
        }
    }
}

public enum WebClientQRCodeResult {
    case unsupportedOrInvalid
    case invalid
    case valid(Data)

    static func from(qrCodeData: Data) -> WebClientQRCodeResult {
        // NB: Website QR code currently encoded as base 64 string
        let bytes: [UInt8] = Data(base64Encoded: qrCodeData)?.bytes ?? qrCodeData.bytes
        if let version = bytes.first, version != 1 {
            return .unsupportedOrInvalid
        } else if bytes.count != 33 {
            return .invalid
        } else {
            return .valid(Data(bytes[1...32]))
        }
    }
}
