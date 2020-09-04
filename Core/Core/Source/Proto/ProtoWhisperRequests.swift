//
//  ProtoWhisperRequests.swift
//  Core
//
//  Created by Garrett on 8/30/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjack
import Foundation

final public class ProtoWhisperUploadRequest : ProtoRequest {
    let completion: ServiceRequestCompletion<Void>

    public init(keyBundle: XMPPWhisperKey, completion: @escaping ServiceRequestCompletion<Void>) {
        self.completion = completion

        var keys = PBwhisper_keys()

        // todo: error if following conditionals fail?

        if let identity = keyBundle.identity {
            var protoIdentityKey = Proto_IdentityKey()
            protoIdentityKey.publicKey = identity

            if let data = try? protoIdentityKey.serializedData() {
                keys.identityKey = data
            }
        }

        if let signed = keyBundle.signed, let signature = keyBundle.signature {
            var protoSignedPreKey = Proto_SignedPreKey()
            protoSignedPreKey.id = signed.id
            protoSignedPreKey.publicKey = signed.publicKey
            protoSignedPreKey.signature = signature

            if let data = try? protoSignedPreKey.serializedData() {
                keys.signedKey = data
            }
        }

        keys.oneTimeKeys = keyBundle.oneTime.compactMap { oneTimeKey in
            var protoOneTimePreKey = Proto_OneTimePreKey()
            protoOneTimePreKey.id = oneTimeKey.id
            protoOneTimePreKey.publicKey = oneTimeKey.publicKey
            return try? protoOneTimePreKey.serializedData()
        }

        let packet = PBpacket.iqPacket(type: .set, payload: .whisperKeys(keys))

        super.init(packet: packet, id: packet.iq.id)
    }

    public override func didFinish(with response: PBpacket) {
        completion(.success(()))
    }

    public override func didFail(with error: Error) {
        completion(.failure(error))
    }
}

final public class ProtoWhisperAddOneTimeKeysRequest : ProtoRequest {

    let completion: ServiceRequestCompletion<Void>

    public init(whisperKeyBundle: XMPPWhisperKey, completion: @escaping ServiceRequestCompletion<Void>) {
        self.completion = completion

        var keys = PBwhisper_keys()
        keys.action = .add
        keys.oneTimeKeys = whisperKeyBundle.oneTime.compactMap { oneTimeKey in
            var protoOneTimePreKey = Proto_OneTimePreKey()
            protoOneTimePreKey.id = oneTimeKey.id
            protoOneTimePreKey.publicKey = oneTimeKey.publicKey
            return try? protoOneTimePreKey.serializedData()
        }

        let packet = PBpacket.iqPacket(type: .set, payload: .whisperKeys(keys))

        super.init(packet: packet, id: packet.iq.id)
    }

    public override func didFinish(with response: PBpacket) {
        DDLogInfo("whisper uploader response: \(response)")
        self.completion(.success(()))
    }

    public override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

final public class ProtoWhisperGetBundleRequest: ProtoRequest {
    let completion: ServiceRequestCompletion<WhisperKeyBundle>

    public init(targetUserId: String, completion: @escaping ServiceRequestCompletion<WhisperKeyBundle>) {
        self.completion = completion
        
        var keys = PBwhisper_keys()
        keys.action = .get
        if let uid = Int64(targetUserId) {
            keys.uid = uid
        }

        let packet = PBpacket.iqPacket(type: .get, payload: .whisperKeys(keys))

        super.init(packet: packet, id: packet.iq.id)
    }

    public override func didFinish(with response: PBpacket) {
        let pbKey = response.iq.payload.whisperKeys
        guard let protoContainer = try? Proto_SignedPreKey(serializedData: pbKey.signedKey) else {
            DDLogError("ProtoWhisperGetBundleRequest/didFinish/error could not deserialize signed key")
            completion(.failure(ProtoServiceCoreError.deserialization))
            return
        }

        let oneTimeKeys: [PreKey] = pbKey.oneTimeKeys.compactMap { data in
            guard let protoKey = try? Proto_OneTimePreKey(serializedData: data) else {
                DDLogError("ProtoWhisperGetBundleRequest/didFinish/error could not deserialize one time key")
                return nil
            }
            return PreKey(id: protoKey.id, privateKey: nil, publicKey: protoKey.publicKey)
        }

        let bundle = WhisperKeyBundle(
            identity: pbKey.identityKey,
            signed: PreKey(id: protoContainer.id, privateKey: nil, publicKey: protoContainer.publicKey),
            signature: protoContainer.signature,
            oneTime: oneTimeKeys)

        self.completion(.success(bundle))
    }

    public override func didFail(with error: Error) {
        DDLogError("ProtoWhisperGetBundleRequest/didFail/error \(error)")
        self.completion(.failure(error))
    }
}


public class ProtoWhisperGetCountOfOneTimeKeysRequest : ProtoRequest {
    let completion: ServiceRequestCompletion<Int32>

    public init(completion: @escaping ServiceRequestCompletion<Int32>) {
        self.completion = completion

        var keys = PBwhisper_keys()
        keys.action = .count
        if let uid = Int64(AppContext.shared.userData.userId) {
            keys.uid = uid
        }

        let packet = PBpacket.iqPacket(type: .get, payload: .whisperKeys(keys))

        super.init(packet: packet, id: packet.iq.id)
    }

    public override func didFinish(with response: PBpacket) {
        completion(.success(response.iq.payload.whisperKeys.otpKeyCount))
    }

    public override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}
