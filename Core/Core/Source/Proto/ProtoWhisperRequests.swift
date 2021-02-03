//
//  ProtoWhisperRequests.swift
//  Core
//
//  Created by Garrett on 8/30/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjack
import Foundation

final public class ProtoWhisperUploadRequest: ProtoRequest<Void> {

    public init(keyBundle: WhisperKeyBundle, completion: @escaping Completion) {
        var keys = Server_WhisperKeys()

        // todo: error if following conditionals fail?

        if let identity = keyBundle.identity {
            var protoIdentityKey = Clients_IdentityKey()
            protoIdentityKey.publicKey = identity

            if let data = try? protoIdentityKey.serializedData() {
                keys.identityKey = data
            }
        }

        if let signed = keyBundle.signed, let signature = keyBundle.signature {
            var protoSignedPreKey = Clients_SignedPreKey()
            protoSignedPreKey.id = signed.id
            protoSignedPreKey.publicKey = signed.publicKey
            protoSignedPreKey.signature = signature

            if let data = try? protoSignedPreKey.serializedData() {
                keys.signedKey = data
            }
        }

        keys.oneTimeKeys = keyBundle.oneTime.compactMap { oneTimeKey in
            var protoOneTimePreKey = Clients_OneTimePreKey()
            protoOneTimePreKey.id = oneTimeKey.id
            protoOneTimePreKey.publicKey = oneTimeKey.publicKey
            return try? protoOneTimePreKey.serializedData()
        }

        keys.action = .set

        let packet = Server_Packet.iqPacket(type: .set, payload: .whisperKeys(keys))

        super.init(iqPacket: packet, transform: { _ in .success(()) }, completion: completion)
    }
}

final public class ProtoWhisperAddOneTimeKeysRequest: ProtoRequest<Void> {

    public init(preKeys: [PreKey], completion: @escaping Completion) {
        var keys = Server_WhisperKeys()
        keys.action = .add
        keys.oneTimeKeys = preKeys.compactMap { oneTimeKey in
            var protoOneTimePreKey = Clients_OneTimePreKey()
            protoOneTimePreKey.id = oneTimeKey.id
            protoOneTimePreKey.publicKey = oneTimeKey.publicKey
            return try? protoOneTimePreKey.serializedData()
        }

        let packet = Server_Packet.iqPacket(type: .set, payload: .whisperKeys(keys))

        super.init(
            iqPacket: packet,
            transform: { (iq) in
                DDLogInfo("whisper uploader response: \(iq)")
                return .success(())
            },
            completion: completion)
    }
}

final public class ProtoWhisperGetBundleRequest: ProtoRequest<WhisperKeyBundle> {

    public init(targetUserId: String, completion: @escaping Completion) {
        var keys = Server_WhisperKeys()
        keys.action = .get
        if let uid = Int64(targetUserId) {
            keys.uid = uid
        }

        let packet = Server_Packet.iqPacket(type: .get, payload: .whisperKeys(keys))

        super.init(
            iqPacket: packet,
            transform: { (iq) in
                ProtoWhisperGetBundleRequest.processResponse(iq: iq)
            },
            completion: completion)
    }

    private static func processResponse(iq: Server_Iq) -> Result<WhisperKeyBundle, Error> {
        let pbKey = iq.whisperKeys
        let protoContainer: Clients_SignedPreKey
        if let container = try? Clients_SignedPreKey(serializedData: pbKey.signedKey) {
            // Binary data
            protoContainer = container
        } else if let decodedData = Data(base64Encoded: pbKey.signedKey, options: .ignoreUnknownCharacters),
            let container = try? Clients_SignedPreKey(serializedData: decodedData) {
            // Legacy Base64 protocol
            protoContainer = container
        } else {
            DDLogError("ProtoWhisperGetBundleRequest/didFinish/error could not deserialize signed key")
            return .failure(ProtoServiceCoreError.deserialization)
        }

        let oneTimeKeys: [PreKey] = pbKey.oneTimeKeys.compactMap { data in
            let protoKey: Clients_OneTimePreKey
            if let key = try? Clients_OneTimePreKey(serializedData: data) {
                // Binary data
                protoKey = key
            } else if let decodedData = Data(base64Encoded: pbKey.signedKey, options: .ignoreUnknownCharacters),
                let key = try? Clients_OneTimePreKey(serializedData: decodedData)
            {
                // Legacy Base64 protocol
                protoKey = key
            } else {
                DDLogError("ProtoWhisperGetBundleRequest/didFinish/error could not deserialize one time key")
                return nil
            }
            return PreKey(id: protoKey.id, privateKey: nil, publicKey: protoKey.publicKey)
        }

        let protoIdentity: Clients_IdentityKey
        if let identity = try? Clients_IdentityKey(serializedData: pbKey.identityKey) {
            protoIdentity = identity
        } else if let decodedData = Data(base64Encoded: pbKey.identityKey, options: .ignoreUnknownCharacters),
                  let identity = try? Clients_IdentityKey(serializedData: decodedData)
        {
            protoIdentity = identity
        } else {
            DDLogError("ProtoWhisperGetBundleRequest/didFinish/error could not deserialize identity key")
            return .failure(ProtoServiceCoreError.deserialization)
        }

        let bundle = WhisperKeyBundle(
            identity: protoIdentity.publicKey,
            signed: PreKey(id: protoContainer.id, privateKey: nil, publicKey: protoContainer.publicKey),
            signature: protoContainer.signature,
            oneTime: oneTimeKeys)

        return .success(bundle)
    }
}

final public class ProtoWhisperGetCountOfOneTimeKeysRequest: ProtoRequest<Int32> {

    public init(completion: @escaping Completion) {
        var keys = Server_WhisperKeys()
        keys.action = .count
        if let uid = Int64(AppContext.shared.userData.userId) {
            keys.uid = uid
        }

        let packet = Server_Packet.iqPacket(type: .get, payload: .whisperKeys(keys))
        super.init(
            iqPacket: packet,
            transform: { (iq) in
                .success(iq.whisperKeys.otpKeyCount)
            },
            completion: completion)
    }
}
