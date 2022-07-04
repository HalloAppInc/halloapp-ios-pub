//
//  Whisper.swift
//  Core
//
//  Created by Garrett on 3/2/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CocoaLumberjackSwift
import CryptoSwift
import Foundation
import Sodium

final class Whisper {
    static let audienceHashLength = 6 // audienceHash is 6 bytes.

    static func generateCommentKey(for postID: FeedPostID, using session: HomeOutgoingSession) -> Result<Data, EncryptionError> {
        guard let commentSymmetricRatchet = symmetricRatchet(chainKey: session.senderKey.chainKey.bytes, style: .comment) else {
            DDLogError("Whisper/generateCommentKey/ratchetFailure")
            return .failure(.ratchetFailure)
        }
        // TODO: (murali@): remove this eventually!
        DDLogVerbose("Whisper/generateCommentKey/success/data: \(commentSymmetricRatchet.messageKey)")
        return .success(Data(commentSymmetricRatchet.messageKey))
    }

    /// Encrypt comment using commentKey for home feed
    static func signAndEncrypt(_ unencrypted: Data, using commentKey: CommentKey) -> Result<Data, EncryptionError> {

        // TODO: (murali@): updates logs with first few bytes of the keys only?
        DDLogInfo("Whisper/signAndEncrypt/commentAESKey [\(commentKey.aesKey)...]")
        DDLogInfo("Whisper/signAndEncrypt/commentHMACKey [\(commentKey.hmacKey)...]")

        let sodium = Sodium()
        guard let ivBytes = sodium.randomBytes.buf(length: 16) else {
            DDLogError("Whisper/setupGroupOutgoingSession/randomBytesGenerationFailed")
            return .failure(.aesError)
        }
        let iv = Data(ivBytes)

        // Encrypt PlainText
        guard let encrypted = try? AES(key: commentKey.aesKey, blockMode: CBC(iv: iv.bytes), padding: .pkcs7).encrypt(unencrypted.bytes) else {
            DDLogError("Whisper/signAndEncrypt/aesError")
            return .failure(.aesError)
        }

        // Compute MAC for encryptedData
        guard let HMAC = try? CryptoSwift.HMAC(key: commentKey.hmacKey, variant: .sha256).authenticate([UInt8](encrypted)) else {
            DDLogError("Whisper/signAndEncrypt/hmacError")
            return .failure(.hmacError)
        }

        var data = iv
        data += encrypted
        data += HMAC

        // TODO: (murali@): remove this eventually!
        DDLogVerbose("Whisper/signAndEncrypt/success/data: \(data.bytes)")
        return .success(data)
    }

    /// Sign and encrypt data for group feed
    static func signAndEncrypt(_ unencrypted: Data, session: GroupOutgoingSession) -> Result<(encryptedData: Data, chainKey: Data), EncryptionError> {

        // TODO: (murali@): updates logs with first few bytes of the keys only?
        DDLogInfo("Whisper/signAndEncrypt/currentChainIndex [\(session.currentChainIndex)]")
        DDLogInfo("Whisper/signAndEncrypt/chainKey [\(session.senderKey.chainKey.bytes)...]")
        DDLogInfo("Whisper/signAndEncrypt/privateSignKey [\(session.privateSigningKey.bytes)...]")

        // Sign plainText
        let sodium = Sodium()
        guard let signature = sodium.sign.signature(message: unencrypted.bytes, secretKey: session.privateSigningKey.bytes) else {
            DDLogError("Whisper/signAndEncrypt/signing plainText data failed")
            return .failure(.signing)
        }

        DDLogInfo("Whisper/signAndEncrypt/lengths \(unencrypted.count) + \(signature.count)")
        // Obtain signedPlainText
        var signed = unencrypted.bytes
        signed.append(contentsOf: signature)
        guard let symmetricRatchet = symmetricRatchet(chainKey: session.senderKey.chainKey.bytes, style: .group),
              let messageKey = MessageKeyContents(data: Data(symmetricRatchet.messageKey)) else {
            DDLogError("Whisper/signAndEncrypt/ratchetFailure")
            return .failure(.ratchetFailure)
        }

        // Encrypt signedPlainText
        guard let encrypted = try? AES(key: messageKey.aesKey, blockMode: CBC(iv: messageKey.iv), padding: .pkcs7).encrypt(Array(signed)) else {
            DDLogError("Whisper/signAndEncrypt/aesError")
            return .failure(.aesError)
        }

        // Compute MAC for encryptedData
        guard let HMAC = try? CryptoSwift.HMAC(key: messageKey.hmac, variant: .sha256).authenticate([UInt8](encrypted)) else {
            DDLogError("Whisper/signAndEncrypt/hmacError")
            return .failure(.hmacError)
        }

        var data = Int32(session.currentChainIndex).asBigEndianData
        data += encrypted
        data += HMAC

        // TODO: (murali@): remove this eventually!
        DDLogVerbose("Whisper/signAndEncrypt/success/data: \(data.bytes)")
        return .success((encryptedData: data, chainKey: Data(symmetricRatchet.updatedChainKey)))
    }

    /// Sign and encrypt data for home feed
    static func signAndEncrypt(_ unencrypted: Data, session: HomeOutgoingSession) -> Result<(encryptedData: Data, chainKey: Data), EncryptionError> {

        // TODO: (murali@): updates logs with first few bytes of the keys only?
        DDLogInfo("Whisper/signAndEncrypt/currentChainIndex [\(session.currentChainIndex)]")
        DDLogInfo("Whisper/signAndEncrypt/chainKey [\(session.senderKey.chainKey.bytes)...]")
        DDLogInfo("Whisper/signAndEncrypt/privateSignKey [\(session.privateSigningKey.bytes)...]")

        // Sign plainText
        let sodium = Sodium()
        guard let signature = sodium.sign.signature(message: unencrypted.bytes, secretKey: session.privateSigningKey.bytes) else {
            DDLogError("Whisper/signAndEncrypt/signing plainText data failed")
            return .failure(.signing)
        }

        DDLogInfo("Whisper/signAndEncrypt/lengths \(unencrypted.count) + \(signature.count)")
        // Obtain signedPlainText
        var signed = unencrypted.bytes
        signed.append(contentsOf: signature)
        guard let chainSymmetricRatchet = symmetricRatchet(chainKey: session.senderKey.chainKey.bytes, style: .feed),
              let messageKey = MessageKeyContents(data: Data(chainSymmetricRatchet.messageKey)) else {
            DDLogError("Whisper/signAndEncrypt/ratchetFailure")
            return .failure(.ratchetFailure)
        }

        // Encrypt signedPlainText
        guard let encrypted = try? AES(key: messageKey.aesKey, blockMode: CBC(iv: messageKey.iv), padding: .pkcs7).encrypt(Array(signed)) else {
            DDLogError("Whisper/signAndEncrypt/aesError")
            return .failure(.aesError)
        }

        // Compute MAC for encryptedData
        guard let HMAC = try? CryptoSwift.HMAC(key: messageKey.hmac, variant: .sha256).authenticate([UInt8](encrypted)) else {
            DDLogError("Whisper/signAndEncrypt/hmacError")
            return .failure(.hmacError)
        }

        var data = Int32(session.currentChainIndex).asBigEndianData
        data += encrypted
        data += HMAC

        // TODO: (murali@): remove this eventually!
        DDLogVerbose("Whisper/signAndEncrypt/success/data: \(data.bytes)")
        return .success((encryptedData: data, chainKey: Data(chainSymmetricRatchet.updatedChainKey)))
    }

    /// Encrypt 1-1 message
    static func encrypt(_ unencrypted: Data, keyBundle: KeyBundle) -> Result<(encryptedData: Data, chainKey: Data), EncryptionError> {

        DDLogInfo("Whisper/encrypt/outboundChainIndex [\(keyBundle.outboundChainIndex)]")
        DDLogInfo("Whisper/encrypt/chain [\(keyBundle.outboundChainKey.bytes.prefix(4))...]")
        DDLogInfo("Whisper/encrypt/outboundEphemeralKeyId [\(keyBundle.outboundEphemeralKeyId)]")
        DDLogInfo("Whisper/encrypt/outboundEphemeralPublicKeyBytes [\(keyBundle.outboundEphemeralPublicKey.bytes.prefix(4))...]")
        DDLogInfo("Whisper/encrypt/outboundPreviousChainLength [\(keyBundle.outboundPreviousChainLength)]")

        guard let symmetricRatchet = symmetricRatchet(chainKey: keyBundle.outboundChainKey.bytes),
              let messageKey = MessageKeyContents(data: Data(symmetricRatchet.messageKey)) else
        {
            return .failure(.ratchetFailure)
        }
        DDLogInfo("Whisper/encrypt/message [\(messageKey.data.bytes.prefix(4))...]")
        DDLogInfo("Whisper/encrypt/new-chain [\(symmetricRatchet.updatedChainKey.prefix(4))...]")

        guard let encrypted = try? AES(key: messageKey.aesKey, blockMode: CBC(iv: messageKey.iv), padding: .pkcs7).encrypt(Array(unencrypted)) else {
            return .failure(.aesError)
        }

        guard let HMAC = try? CryptoSwift.HMAC(key: messageKey.hmac, variant: .sha256).authenticate([UInt8](encrypted)) else {
            return .failure(.hmacError)
        }

        var data = keyBundle.outboundEphemeralPublicKey
        data += keyBundle.outboundEphemeralKeyId.asBigEndianData
        data += keyBundle.outboundPreviousChainLength.asBigEndianData
        data += keyBundle.outboundChainIndex.asBigEndianData
        data += encrypted
        data += HMAC

        return .success((encryptedData: data, chainKey: Data(symmetricRatchet.updatedChainKey)))
    }

    /// Decrypt 1-1 message
    static func decrypt(_ payload: EncryptedPayload, keyBundle: KeyBundle, messageKeys: MessageKeyMap) -> Result<(data: Data, keyBundle: KeyBundle, messageKeys: MessageKeyMap), DecryptionFailure> {

        var updatedKeyBundle: KeyBundle
        var updatedMessageKeys: MessageKeyMap

        switch Whisper.ratchetKeyBundle(keyBundle, for: payload) {
        case .failure(let error):
            return .failure(.init(error, ephemeralKey: payload.ephemeralPublicKey))
        case .success((let keyBundle, let newKeys)):
            updatedKeyBundle = keyBundle
            updatedMessageKeys = messageKeys.merging(newKeys) { (_, new) in new }
        }

        let keyLocator = MessageKeyLocator(ephemeralKeyID: payload.ephemeralKeyID, chainIndex: payload.chainIndex)
        guard let messageKeyData = updatedMessageKeys[keyLocator],
              let messageKey = MessageKeyContents(data: messageKeyData) else
        {
            return .failure(.init(.missingMessageKey, ephemeralKey: payload.ephemeralPublicKey))
        }

        DDLogInfo("Whisper/decrypt/message-key [\(messageKey.data.bytes.prefix(4))...]")
        updatedMessageKeys[keyLocator] = nil

        do {
            let calculatedHMAC = try CryptoSwift
                .HMAC(key: messageKey.hmac, variant: .sha256)
                .authenticate(payload.encryptedMessage.bytes)

            guard payload.hmac.bytes == calculatedHMAC else {
                return .failure(.init(.hmacMismatch, ephemeralKey: payload.ephemeralPublicKey))
            }

            let aes = try AES(key: messageKey.aesKey, blockMode: CBC(iv: messageKey.iv), padding: .pkcs7)
            let decrypted = try aes.decrypt(payload.encryptedMessage.bytes)
            let data = Data(decrypted)

            return .success((data: data, keyBundle: updatedKeyBundle, messageKeys: updatedMessageKeys))
        } catch {
            return .failure(.init(.aesError, ephemeralKey: payload.ephemeralPublicKey))
        }
    }

    /// Decrypt data from group feed
    static func decrypt(_ payload: EncryptedGroupPayload, senderState: IncomingSenderState) -> Result<(data: Data, senderState: IncomingSenderState), DecryptionError> {

        // TODO: add logs with keys used for decryption?
        var updatedSenderState: IncomingSenderState

        switch ratchetSenderState(senderState, to: payload.chainIndex, style: .group) {
        case .failure(let error):
            DDLogError("Whisper/decryptGroup/ratchetSenderState/error \(error)")
            return .failure(error)
        case .success(let senderState):
            DDLogInfo("Whisper/decryptGroup/ratchetSenderState/success")
            updatedSenderState = senderState
        }

        guard let messageKeyData = updatedSenderState.unusedMessageKeys[payload.chainIndex],
              let messageKey = MessageKeyContents(data: messageKeyData) else
        {
            DDLogError("Whisper/decryptGroup/error missingMessageKey")
            return .failure(.missingMessageKey)
        }
        updatedSenderState.unusedMessageKeys[payload.chainIndex] = nil
        let signatureKey = updatedSenderState.senderKey.publicSignatureKey

        // TODO: (murali@): change these logs to only log prefix of these keys.
        DDLogInfo("Whisper/decryptGroup/messageKey [\(messageKey.data.bytes)...]")
        DDLogInfo("Whisper/decryptGroup/publicSignKey [\(signatureKey.bytes)...]")

        let calculatedHMAC: Array<UInt8>
        do {
            // Calculate HMAC
            calculatedHMAC = try CryptoSwift
                .HMAC(key: messageKey.hmac, variant: .sha256)
                .authenticate(payload.encryptedSignedMessage.bytes)
        } catch {
            DDLogError("Whisper/decryptGroup/error hmacMismatch")
            return .failure(.hmacMismatch)
        }

        // Verify HMAC
        guard payload.hmac.bytes == calculatedHMAC else {
            DDLogError("Whisper/decryptGroup/error hmacMismatch")
            return .failure(.hmacMismatch)
        }

        do {
            // Decrypt data
            let aes = try AES(key: messageKey.aesKey, blockMode: CBC(iv: messageKey.iv), padding: .pkcs7)
            let decrypted = try aes.decrypt(payload.encryptedSignedMessage.bytes)

            // Obtain signedPayload
            guard let signedPayload = SignedPayload(data: Data(decrypted)) else {
                DDLogError("Whisper/decryptGroup/error invalidPayload")
                return .failure(.invalidPayload)
            }

            // Verify signature
            let sodium = Sodium()
            if sodium.sign.verify(message: signedPayload.payload.bytes, publicKey: signatureKey.bytes, signature: signedPayload.signature.bytes) {
                let data = signedPayload.payload
                DDLogInfo("Whisper/decryptGroup/success")
                return .success((data: data, senderState: updatedSenderState))
            } else {
                DDLogError("Whisper/decryptGroup/error signatureMisMatch")
                return .failure(.signatureMisMatch)
            }

        } catch {
            DDLogError("Whisper/decryptGroup/error aesError")
            return .failure(.aesError)
        }
    }

    /// Decrypt data from home feed
    static func decryptHome(_ payload: EncryptedGroupPayload, senderState: IncomingSenderState) -> Result<(data: Data, senderState: IncomingSenderState), DecryptionError> {

        // TODO: add logs with keys used for decryption?
        var updatedSenderState: IncomingSenderState

        switch ratchetSenderState(senderState, to: payload.chainIndex, style: .feed) {
        case .failure(let error):
            DDLogError("Whisper/decryptGroup/ratchetSenderState/error \(error)")
            return .failure(error)
        case .success(let senderState):
            DDLogInfo("Whisper/decryptGroup/ratchetSenderState/success")
            updatedSenderState = senderState
        }

        guard let messageKeyData = updatedSenderState.unusedMessageKeys[payload.chainIndex],
              let messageKey = MessageKeyContents(data: messageKeyData) else
        {
            DDLogError("Whisper/decryptGroup/error missingMessageKey")
            return .failure(.missingMessageKey)
        }
        updatedSenderState.unusedMessageKeys[payload.chainIndex] = nil
        let signatureKey = updatedSenderState.senderKey.publicSignatureKey

        // TODO: (murali@): change these logs to only log prefix of these keys.
        DDLogInfo("Whisper/decryptGroup/messageKey [\(messageKey.data.bytes)...]")
        DDLogInfo("Whisper/decryptGroup/publicSignKey [\(signatureKey.bytes)...]")

        let calculatedHMAC: Array<UInt8>
        do {
            // Calculate HMAC
            calculatedHMAC = try CryptoSwift
                .HMAC(key: messageKey.hmac, variant: .sha256)
                .authenticate(payload.encryptedSignedMessage.bytes)
        } catch {
            DDLogError("Whisper/decryptGroup/error hmacMismatch")
            return .failure(.hmacMismatch)
        }

        // Verify HMAC
        guard payload.hmac.bytes == calculatedHMAC else {
            DDLogError("Whisper/decryptGroup/error hmacMismatch")
            return .failure(.hmacMismatch)
        }

        do {
            // Decrypt data
            let aes = try AES(key: messageKey.aesKey, blockMode: CBC(iv: messageKey.iv), padding: .pkcs7)
            let decrypted = try aes.decrypt(payload.encryptedSignedMessage.bytes)

            // Obtain signedPayload
            guard let signedPayload = SignedPayload(data: Data(decrypted)) else {
                DDLogError("Whisper/decryptGroup/error invalidPayload")
                return .failure(.invalidPayload)
            }

            // Verify signature
            let sodium = Sodium()
            if sodium.sign.verify(message: signedPayload.payload.bytes, publicKey: signatureKey.bytes, signature: signedPayload.signature.bytes) {
                let data = signedPayload.payload
                DDLogInfo("Whisper/decryptGroup/success")
                return .success((data: data, senderState: updatedSenderState))
            } else {
                DDLogError("Whisper/decryptGroup/error signatureMisMatch")
                return .failure(.signatureMisMatch)
            }

        } catch {
            DDLogError("Whisper/decryptGroup/error aesError")
            return .failure(.aesError)
        }
    }

    /// Decrypt comment using commentKey for home feed
    static func decrypt(_ payload: CommentEncryptedPayload, using commentKey: CommentKey) -> Result<Data, DecryptionError> {

        // TODO: (murali@): change these logs to only log prefix of these keys.
        DDLogInfo("Whisper/decrypt/commentAESKey [\(commentKey.aesKey)...]")
        DDLogInfo("Whisper/decrypt/commentHMACKey [\(commentKey.hmacKey)...]")

        let calculatedHMAC: Array<UInt8>
        do {
            // Calculate HMAC
            calculatedHMAC = try CryptoSwift
                .HMAC(key: commentKey.hmacKey, variant: .sha256)
                .authenticate(payload.encrypted.bytes)
        } catch {
            DDLogError("Whisper/decryptGroup/error hmacMismatch")
            return .failure(.hmacMismatch)
        }

        // Verify HMAC
        guard payload.hmac.bytes == calculatedHMAC else {
            DDLogError("Whisper/decryptGroup/error hmacMismatch")
            return .failure(.hmacMismatch)
        }

        do {
            // Decrypt data
            let aes = try AES(key: commentKey.aesKey, blockMode: CBC(iv: payload.iv.bytes), padding: .pkcs7)
            let decrypted = try aes.decrypt(payload.encrypted.bytes)

            return .success(Data(decrypted))

        } catch {
            DDLogError("Whisper/decryptGroup/error aesError")
            return .failure(.aesError)
        }
    }

    static func setupGroupOutgoingSession(for groupId: GroupID, memberKeys: [UserID : Data]) -> GroupOutgoingSession? {
        DDLogInfo("Whisper/setupGroupOutgoingSession/groupId: \(groupId), memberCount: \(memberKeys.count)")

        // Compute audienceHash
        guard let audienceHash = computeAudienceHash(memberKeys: memberKeys) else {
            DDLogError("Whisper/setupGroupOutgoingSession/groupId: \(groupId), audienceHash is nil")
            return nil
        }

        // Generate signingKeyPair
        let sodium = Sodium()
        guard let signKeyPair = sodium.sign.keyPair() else {
            DDLogError("Whisper/setupGroupOutgoingSession/keyPairGenerationFailed")
            return nil
        }

        // Generate random bytes for chainKey
        guard let chainKey = sodium.randomBytes.buf(length: 32) else {
            DDLogError("Whisper/setupGroupOutgoingSession/randomBytesGenerationFailed")
            return nil
        }

        // setup outgoingSession
        let senderKey = SenderKey(chainKey: Data(chainKey),
                                  publicSignatureKey: Data(signKeyPair.publicKey))
        let outgoingSession = GroupOutgoingSession(audienceHash: audienceHash,
                                                   senderKey: senderKey,
                                                   currentChainIndex: 0,
                                                   privateSigningKey: Data(signKeyPair.secretKey))
        DDLogInfo("Whisper/setupGroupOutgoingSession/success, audienceHash: \(audienceHash.toHexString())")
        return outgoingSession
    }

    static func computeAudienceHash(memberKeys: [UserID : Data]) -> Data? {
        if memberKeys.isEmpty {
            DDLogError("Whisper/computeAudienceHash/memberKeys is empty")
            return nil
        }

        // Start with empty data array.
        // TODO: murali@: name this constant somewhere or compute it.
        var xorOfKeys = Data(count: 32)
        for (userID, memberKeySerialized) in memberKeys {
            DDLogInfo("Whisper/computeAudienceHash/member - \(userID)")
            do {
                let memberIdentityKey = try Server_IdentityKey(serializedData: memberKeySerialized)
                let memberKey = memberIdentityKey.publicKey
                xorOfKeys = xorOfKeys ^ memberKey
            } catch {
                DDLogError("Whisper/computeAudienceHash/memberKeySerialized is invalid, userID: \(userID)")
                return nil
            }
        }

        // audienceHash is the first 6 bytes of sha256 value.
        let audienceHash = Data(CryptoSwift.Hash.sha256(xorOfKeys.bytes)).prefix(audienceHashLength)
        DDLogInfo("Whisper/computeAudienceHash/success, audienceHash: \(audienceHash.toHexString())")
        return audienceHash
    }

    static func initiateSessionSetup(
        for targetUserId: UserID,
        with targetUserWhisperKeys: WhisperKeyBundle,
        userKeys: UserKeyBundle,
        teardownKey: Data? = nil) -> KeyBundle?
    {
        DDLogInfo("WhisperSession/initiateSessionSetup \(targetUserId)")

        let sodium = Sodium()

        guard let newKeyPair = sodium.box.keyPair() else {
            DDLogInfo("WhisperSession/initiateSessionSetup/keyPairGenerationFailed")
            return nil
        }

        let outboundIdentityPrivateKey = userKeys.identityPrivateKey                              // I_initiator

        let outboundEphemeralPublicKey = Data(newKeyPair.publicKey)
        let outboundEphemeralPrivateKey = Data(newKeyPair.secretKey)                            // E_initiator

        let inboundIdentityPublicEdKey = targetUserWhisperKeys.identity

        guard let inboundIdentityPublicKeyUInt8 = sodium.sign.convertToX25519PublicKey(publicKey: [UInt8](inboundIdentityPublicEdKey)) else {
            DDLogInfo("WhisperSession/initiateSessionSetup/x25519conversionFailed")
            return nil
        }

        let inboundIdentityPublicKey = Data(inboundIdentityPublicKeyUInt8)                      // I_recipient

        let targetUserSigned = targetUserWhisperKeys.signedPreKey
        let inboundSignedPrePublicKey = targetUserSigned.key.publicKey                              // S_recipient
        let signature = targetUserSigned.signature

        guard sodium.sign.verify(message: [UInt8](inboundSignedPrePublicKey), publicKey: [UInt8](inboundIdentityPublicEdKey), signature: [UInt8](signature)) else {
            DDLogInfo("WhisperSession/initiateSessionSetup/invalidSignature")
            return nil
        }

        var inboundOneTimeKey: PreKey? = nil
        var inboundOneTimePrePublicKey: Data? = nil                                             // O_recipient

        if let whisperOneTimeKey = targetUserWhisperKeys.oneTime.first {
            inboundOneTimeKey = whisperOneTimeKey
            inboundOneTimePrePublicKey = whisperOneTimeKey.publicKey
        }

        guard let masterKey = computeMasterKey(isInitiator: true,
                                               initiatorIdentityKey: outboundIdentityPrivateKey,
                                               initiatorEphemeralKey: outboundEphemeralPrivateKey,
                                               recipientIdentityKey: inboundIdentityPublicKey,
                                               recipientSignedPreKey: inboundSignedPrePublicKey,
                                               recipientOneTimePreKey: inboundOneTimePrePublicKey) else
        {
            DDLogDebug("WhisperSession/initiateSessionSetup/invalidMasterKey")
            return nil
        }

        let rootKey = masterKey.rootKey
        let outboundChainKey = masterKey.firstChainKey
        let inboundChainKey = masterKey.secondChainKey

        // attributes for initiating sessions
        let outboundIdentityPublicEdKey = userKeys.identityPublicEdKey
        var outboundOneTimePreKeyId: Int32 = -1

        if let oneTimePreKey = inboundOneTimeKey {
            outboundOneTimePreKeyId = oneTimePreKey.id
        }

        let keyBundle = KeyBundle(userId: targetUserId,
                                  inboundIdentityPublicEdKey: inboundIdentityPublicEdKey,

                                  inboundEphemeralPublicKey: nil,
                                  inboundEphemeralKeyId: -1,
                                  inboundChainKey: Data(inboundChainKey),
                                  inboundPreviousChainLength: 0,
                                  inboundChainIndex: 0,

                                  rootKey: Data(rootKey),

                                  outboundEphemeralPrivateKey: outboundEphemeralPrivateKey,
                                  outboundEphemeralPublicKey: outboundEphemeralPublicKey,
                                  outboundEphemeralKeyId: 0,
                                  outboundChainKey: Data(outboundChainKey),
                                  outboundPreviousChainLength: 0,
                                  outboundChainIndex: 0,

                                  outboundIdentityPublicEdKey: outboundIdentityPublicEdKey,
                                  outboundOneTimePreKeyId: outboundOneTimePreKeyId,

                                  teardownKey: teardownKey)

        return keyBundle
    }

    static func receiveSessionSetup(
        userID: UserID,
        inboundIdentityPublicEdKey: Data,
        inboundEphemeralPublicKey: Data,
        inboundEphemeralKeyID: Int,
        oneTimeKeyID: Int?,
        previousChainLength: Int,
        userKeys: UserKeyBundle) -> Result<KeyBundle, DecryptionError>
    {
        DDLogInfo("WhisperSession/receiveSessionSetup \(userID)")

        let sodium = Sodium()

        guard let x25519Key = sodium.sign.convertToX25519PublicKey(publicKey: [UInt8](inboundIdentityPublicEdKey)) else {
            DDLogError("WhisperSession/receiveSessionSetup/error X25519 conversion error")
            DDLogInfo("Inbound Key: \(inboundIdentityPublicEdKey.bytes.prefix(4))...")
            return .failure(.x25519Conversion)
        }

        guard let signedPreKey = userKeys.signedPreKeys.first(where: {$0.id == 1}) else {
            return .failure(.missingSignedPreKey)
        }

        let I_initiator = Data(x25519Key)
        let E_initiator = inboundEphemeralPublicKey
        let I_recipient = userKeys.identityPrivateKey
        let S_recipient = signedPreKey.privateKey
        let O_recipient: Data?

        // oneTimeKeyID's start from 1 always.
        // If the ID is zero or negative - then we leave the oneTimeKey out of master secret computation.
        if let oneTimeKeyID = oneTimeKeyID, oneTimeKeyID > 0 {
            guard let oneTimePreKeys = userKeys.oneTimePreKeys else {
                return .failure(.missingOneTimeKey)
            }
            guard let oneTimePreKey = oneTimePreKeys.first(where: {$0.id == oneTimeKeyID}) else {
                DDLogError("WhisperSession/receiveSessionSetup/missingOneTimeKey [\(oneTimeKeyID)]")
                return .failure(.missingOneTimeKey)
            }
            O_recipient = oneTimePreKey.privateKey
        } else {
            O_recipient = nil
        }

        guard let masterKey = computeMasterKey(isInitiator: false,
                                               initiatorIdentityKey: I_initiator,
                                               initiatorEphemeralKey: E_initiator,
                                               recipientIdentityKey: I_recipient,
                                               recipientSignedPreKey: S_recipient,
                                               recipientOneTimePreKey: O_recipient) else
        {
            DDLogError("WhisperSession/receiveSessionSetup/invalidMasterKey")
            return .failure(.masterKeyComputation)
        }

        var rootKey = masterKey.rootKey
        let inboundChainKey = masterKey.firstChainKey
        var outboundChainKey = masterKey.secondChainKey

        // generate new Ephemeral key and update root + outboundChainKey
        guard let outboundEphemeralKeyPair = sodium.box.keyPair() else {
            return .failure(.keyGenerationFailure)
        }

        let outboundEphemeralPrivateKey = Data(outboundEphemeralKeyPair.secretKey)
        let outboundEphemeralPublicKey = Data(outboundEphemeralKeyPair.publicKey)

        guard let outboundAsymmetricRachet = asymmetricRatchet(
                privateKey: Data(outboundEphemeralKeyPair.secretKey),
                publicKey: inboundEphemeralPublicKey,
                rootKey: rootKey) else
        {
            return .failure(.ratchetFailure)
        }
        rootKey = outboundAsymmetricRachet.updatedRootKey
        outboundChainKey = outboundAsymmetricRachet.updatedChainKey

        let keyBundle = KeyBundle(userId: userID,
                                  inboundIdentityPublicEdKey: inboundIdentityPublicEdKey,

                                  inboundEphemeralPublicKey: inboundEphemeralPublicKey,
                                  inboundEphemeralKeyId: Int32(inboundEphemeralKeyID),
                                  inboundChainKey: Data(inboundChainKey),
                                  inboundPreviousChainLength: Int32(previousChainLength),
                                  inboundChainIndex: -1, // start new sessions at -1 (not incoming chainIndex) so we ratchet properly for out of order messages

                                  rootKey: Data(rootKey),

                                  outboundEphemeralPrivateKey: outboundEphemeralPrivateKey,
                                  outboundEphemeralPublicKey: outboundEphemeralPublicKey,
                                  outboundEphemeralKeyId: 0,
                                  outboundChainKey: Data(outboundChainKey),
                                  outboundPreviousChainLength: 0,
                                  outboundChainIndex: 0)
        return .success(keyBundle)
    }

    private static func ratchetSenderState(_ senderState: IncomingSenderState, to chainIndex: Int32, style: RatchetStyle) -> Result<IncomingSenderState, DecryptionError> {
        var newSenderState = senderState
        DDLogInfo("Whisper/ratchetSenderState/begin/startIndex: \(newSenderState.currentChainIndex), endIndex: \(chainIndex)")

        let ratchetDiff = Int(chainIndex) + 1 - newSenderState.currentChainIndex
        if ratchetDiff > 100 {
            DDLogError("Whisper/ratchetSenderState/group/error/very large difference: \(ratchetDiff)")
            return .failure(.ratchetFailure)
        }

        // ratchet one more than the chainIndex - so that we take the messageKey and store it inside the state.
        while newSenderState.currentChainIndex < chainIndex + 1 {
            guard let symmetricRatchet = Self.symmetricRatchet(chainKey: newSenderState.senderKey.chainKey.bytes, style: style) else {
                DDLogError("Whisper/ratchetSenderState/group/error - ratchet failure, chainkey: \(newSenderState.senderKey.chainKey.bytes)")
                return .failure(.ratchetFailure)
            }
            newSenderState.unusedMessageKeys[Int32(newSenderState.currentChainIndex)] = Data(symmetricRatchet.messageKey)
            newSenderState.senderKey.chainKey = Data(symmetricRatchet.updatedChainKey)
            newSenderState.currentChainIndex += 1
        }
        DDLogInfo("Whisper/ratchetSenderState/end/finalIndex: \(newSenderState.currentChainIndex), unusedMessageKeysCount: \(newSenderState.unusedMessageKeys.count)")

        return .success(newSenderState)
    }

    private static func ratchetKeyBundle(_ keyBundle: KeyBundle, for payload: EncryptedPayload) -> Result<(KeyBundle, MessageKeyMap), DecryptionError> {

        guard keyBundle.phase == .keyAgreement ||
                keyBundle.inboundEphemeralKeyId < payload.ephemeralKeyID ||
                keyBundle.inboundChainIndex <= payload.chainIndex else
        {
            // No need to ratchet for out-of-order message
            DDLogInfo("WhisperSession/ratchetKeyBundle/skipping [out-of-order]")
            return .success((keyBundle, MessageKeyMap()))
        }

        var newKeyBundle = keyBundle
        var newKeys = MessageKeyMap()

        if keyBundle.phase == .conversation && keyBundle.inboundEphemeralKeyId == payload.ephemeralKeyID - 1 {

            // Generate skipped message keys from previous ephemeral key

            let catchupIndex = payload.previousChainLength - 1
            var currentIndex = keyBundle.inboundChainIndex + 1

            DDLogInfo("WhisperSession/ratchetKeyBundle/catchup/begin [\(currentIndex)]")
            while currentIndex < payload.previousChainLength {
                guard let (msgKey, chainKey) = symmetricRatchet(chainKey: newKeyBundle.inboundChainKey.bytes) else {
                    DDLogError("WhisperSession/ratchetKeyBundle/catchup/error ratchet failure [\(currentIndex)]")
                    break
                }

                newKeyBundle.inboundChainKey = Data(chainKey)
                newKeyBundle.inboundChainIndex = currentIndex

                let locator = MessageKeyLocator(ephemeralKeyID: keyBundle.inboundEphemeralKeyId, chainIndex: currentIndex)
                newKeys[locator] = Data(msgKey)

                if currentIndex == catchupIndex {
                    DDLogInfo("WhisperSession/ratchetKeyBundle/catchup/finished [\(catchupIndex)]")
                }
                currentIndex += 1
            }
        }

        if keyBundle.inboundEphemeralPublicKey == payload.ephemeralPublicKey {
            if keyBundle.inboundEphemeralKeyId != payload.ephemeralKeyID {
                // We have the right key but need to update the ID to match sender's state
                DDLogInfo("WhisperSession/ratchetKeyBundle/newEphemeralKey/match [new key id] [\(keyBundle.inboundEphemeralKeyId)]->[\(payload.ephemeralKeyID)]")
                newKeyBundle.inboundEphemeralKeyId = payload.ephemeralKeyID
            } else {
                DDLogInfo("WhisperSession/ratchetKeyBundle/newEphemeralKey/match [skipping]")
            }
        } else {
            DDLogInfo("WhisperSession/ratchetKeyBundle/newEphemeralKey/updating")

            // Move inbound chain values to new ephemeral key

            guard let inboundAsymmetricRachet = asymmetricRatchet(
                    privateKey: keyBundle.outboundEphemeralPrivateKey,
                    publicKey: payload.ephemeralPublicKey,
                    rootKey: keyBundle.rootKey.bytes) else
            {
                return .failure(.ratchetFailure)
            }
            newKeyBundle.inboundEphemeralPublicKey = payload.ephemeralPublicKey
            newKeyBundle.inboundEphemeralKeyId = payload.ephemeralKeyID
            newKeyBundle.inboundChainIndex = -1
            newKeyBundle.inboundChainKey = Data(inboundAsymmetricRachet.updatedChainKey)
            newKeyBundle.rootKey = Data(inboundAsymmetricRachet.updatedRootKey)

            // Move outbound chain values to new ephemeral key

            guard let newOutboundEphemeralKeyPair = Sodium().box.keyPair() else
            {
                return .failure(.keyGenerationFailure)
            }
            newKeyBundle.outboundEphemeralPrivateKey = Data(newOutboundEphemeralKeyPair.secretKey)
            newKeyBundle.outboundEphemeralPublicKey = Data(newOutboundEphemeralKeyPair.publicKey)
            newKeyBundle.outboundEphemeralKeyId += 1

            guard let outboundAsymmetricRachet = asymmetricRatchet(
                    privateKey: newKeyBundle.outboundEphemeralPrivateKey,
                    publicKey: payload.ephemeralPublicKey,
                    rootKey: newKeyBundle.rootKey.bytes) else
            {
                return .failure(.ratchetFailure)
            }
            newKeyBundle.rootKey = Data(outboundAsymmetricRachet.updatedRootKey)
            newKeyBundle.outboundChainKey = Data(outboundAsymmetricRachet.updatedChainKey)

            newKeyBundle.outboundPreviousChainLength = keyBundle.outboundChainIndex
            newKeyBundle.outboundChainIndex = 0
        }

        var currentIndex = newKeyBundle.inboundChainIndex + 1
        DDLogInfo("WhisperSession/ratchetKeyBundle/symmetricRatchet/begin [\(currentIndex)]")
        while currentIndex <= payload.chainIndex {

            // Generate message keys for current ephemeral key

            guard let (msgKey, chainKey) = symmetricRatchet(chainKey: newKeyBundle.inboundChainKey.bytes) else {
                DDLogError("WhisperSession/ratchetKeyBundle/symmetricRatchet/error [\(currentIndex)]")
                return .failure(.ratchetFailure)
            }

            newKeyBundle.inboundChainKey = Data(chainKey)
            newKeyBundle.inboundChainIndex = currentIndex

            let locator = MessageKeyLocator(ephemeralKeyID: payload.ephemeralKeyID, chainIndex: currentIndex)
            newKeys[locator] = Data(msgKey)

            currentIndex += 1
        }
        DDLogInfo("WhisperSession/ratchetKeyBundle/symmetricRatchet/finished [\(payload.chainIndex)]")

        // Clear outbound setup values now that we've decrypted a message successfully

        newKeyBundle.outboundIdentityPublicEdKey = nil
        newKeyBundle.outboundOneTimePreKeyId = -1

        return .success((newKeyBundle, newKeys))
    }

    /**
     Public and Private Keys are reversed when computing the master key for a recipient session
     Initiator:
     ECDH(I_initiator, S_recipient) + ECDH(E_initiator, I_recipient) + ECDH(E_initiator, S_recipient) + [ECDH(E_initiator, O_recipient)]
     Recipient:
     ECDH(S_recipient, I_initiator) + ECDH(I_recipient, E_initiator) + ECDH(S_recipient, E_initiator) + [ECDH(O_recipient, E_initiator)]
     */
    private static func computeMasterKey(isInitiator: Bool,
                                  initiatorIdentityKey: Data,
                                  initiatorEphemeralKey: Data,
                                  recipientIdentityKey: Data,
                                  recipientSignedPreKey: Data,
                                  recipientOneTimePreKey: Data?) -> (rootKey: [UInt8], firstChainKey: [UInt8], secondChainKey: [UInt8])? {
        let sodium = Sodium()

        let ecdhAPrivateKey = isInitiator ? initiatorIdentityKey  : recipientSignedPreKey
        let ecdhAPublicKey  = isInitiator ? recipientSignedPreKey : initiatorIdentityKey

        let ecdhBPrivateKey = isInitiator ? initiatorEphemeralKey : recipientIdentityKey
        let ecdhBPublicKey  = isInitiator ? recipientIdentityKey  : initiatorEphemeralKey

        let ecdhCPrivateKey = isInitiator ? initiatorEphemeralKey  : recipientSignedPreKey
        let ecdhCPublicKey  = isInitiator ? recipientSignedPreKey  : initiatorEphemeralKey

        guard let ecdhA = sodium.keyAgreement.sharedSecret(secretKey: ecdhAPrivateKey, publicKey: ecdhAPublicKey) else { return nil }
        guard let ecdhB = sodium.keyAgreement.sharedSecret(secretKey: ecdhBPrivateKey, publicKey: ecdhBPublicKey) else { return nil }
        guard let ecdhC = sodium.keyAgreement.sharedSecret(secretKey: ecdhCPrivateKey, publicKey: ecdhCPublicKey) else { return nil }

        var masterKey = ecdhA
        masterKey += ecdhB
        masterKey += ecdhC

        DDLogDebug("ecdhA:  \([UInt8](ecdhA).prefix(4))...")
        DDLogDebug("ecdhB:  \([UInt8](ecdhB).prefix(4))...")
        DDLogDebug("ecdhC:  \([UInt8](ecdhC).prefix(4))...")

        if let recipientOneTimePreKey = recipientOneTimePreKey {

            let ecdhDPrivateKey = isInitiator ? initiatorEphemeralKey  : recipientOneTimePreKey
            let ecdhDPublicKey  = isInitiator ? recipientOneTimePreKey  : initiatorEphemeralKey

            guard let ecdhD = sodium.keyAgreement.sharedSecret(secretKey: ecdhDPrivateKey, publicKey: ecdhDPublicKey) else {
                DDLogInfo("ecdhD:  \([UInt8](ecdhA).prefix(4))...")
                return nil
            }
            DDLogDebug("ecdhD:  \([UInt8](ecdhD).prefix(4))...")
            masterKey += ecdhD
        }

        let str:String = "HalloApp"
        let strToUInt8:[UInt8] = [UInt8](str.utf8)

        let expandedKeyRaw = try? HKDF(password: masterKey.bytes, info: strToUInt8, keyLength: 96, variant: .sha256).calculate()

        guard let expandedKeyBytes = expandedKeyRaw else {
            DDLogInfo("WhisperSession/computeMasterKey/HKDF/invalidExpandedKey")
            return nil
        }

        let rootKey = Array(expandedKeyBytes[0...31])
        let firstChainKey = Array(expandedKeyBytes[32...63])
        let secondChainKey = Array(expandedKeyBytes[64...95])

        return (rootKey, firstChainKey, secondChainKey)
    }

    // MARK: Ratcheting

    private enum RatchetStyle {
        case oneToOne
        case group
        case feed
        case comment
    }

    private static func symmetricRatchet(chainKey: [UInt8], style: RatchetStyle = .oneToOne) -> (messageKey: [UInt8], updatedChainKey: [UInt8])? {
        let messageInfo, chainInfo: Array<UInt8>
        let messageKeyLength: Int
        switch style {
        case .oneToOne:
            messageInfo = [0x01]
            chainInfo = [0x02]
            messageKeyLength = 80
        case .group:
            messageInfo = [0x03]
            chainInfo = [0x04]
            messageKeyLength = 80
        case .feed:
            messageInfo = [0x05]
            chainInfo = [0x06]
            messageKeyLength = 80
        case .comment:
            messageInfo = [0x07]
            chainInfo = [0x08]
            messageKeyLength = 64
        }
        guard let messageKey = try? HKDF(password: chainKey, info: messageInfo, keyLength: messageKeyLength, variant: .sha256).calculate() else {
            return nil
        }
        guard let updatedChainKey = try? HKDF(password: chainKey, info: chainInfo, keyLength: 32, variant: .sha256).calculate() else {
            return nil
        }
        return (messageKey, updatedChainKey)
    }

    private static func asymmetricRatchet(privateKey: Data, publicKey: Data, rootKey: [UInt8]) -> (updatedRootKey: [UInt8], updatedChainKey: [UInt8])? {
        let sodium = Sodium()
        let str:String = "HalloApp"
        let strToUInt8:[UInt8] = [UInt8](str.utf8)
        guard let ecdh = sodium.keyAgreement.sharedSecret(secretKey: privateKey, publicKey: publicKey) else { return nil }

        guard let hkdf = try? HKDF(password: ecdh.bytes, salt: [UInt8](rootKey), info: strToUInt8, keyLength: 64, variant: .sha256).calculate() else { return nil }
        let updatedRootKey = Array(hkdf[0...31])
        let updatedChainKey = Array(hkdf[32...63])

        return (updatedRootKey, updatedChainKey)
    }

    static func setupHomeOutgoingSession(for type: HomeSessionType) -> HomeOutgoingSession? {
        DDLogInfo("Whisper/setupHomeOutgoingSession/type: \(type)")

        // Generate signingKeyPair
        let sodium = Sodium()
        guard let signKeyPair = sodium.sign.keyPair() else {
            DDLogError("Whisper/setupGroupOutgoingSession/keyPairGenerationFailed")
            return nil
        }

        // Generate random bytes for chainKey
        guard let chainKey = sodium.randomBytes.buf(length: 32) else {
            DDLogError("Whisper/setupGroupOutgoingSession/randomBytesGenerationFailed")
            return nil
        }

        // setup outgoingSession
        let senderKey = SenderKey(chainKey: Data(chainKey),
                                  publicSignatureKey: Data(signKeyPair.publicKey))
        let outgoingSession = HomeOutgoingSession(senderKey: senderKey, currentChainIndex: 0, privateSigningKey: Data(signKeyPair.secretKey))
        DDLogInfo("Whisper/setupGroupOutgoingSession/success")
        return outgoingSession
    }
}

struct MessageKeyContents {
    var aesKey: [UInt8]
    var hmac: [UInt8]
    var iv: [UInt8]

    init?(data: Data) {
        // 32 byte AES + 32 byte HMAC + 16 byte IV
        guard data.count >= 80 else {
            DDLogError("Whisper/invalidMessageKey [\(data.count) bytes]")
            return nil
        }

        self.aesKey = data[0...31].bytes
        self.hmac = data[32...63].bytes
        self.iv = data[64...79].bytes
    }

    var data: Data {
        return Data(aesKey + hmac + iv)
    }
}


struct EncryptedGroupPayload {
    var chainIndex: Int32
    var hmac: Data
    var encryptedSignedMessage: Data

    init?(data: Data) {
        // 4 byte chain index + 32 byte HMAC
        guard data.count >= 36 else {
            DDLogError("Whisper/encryptedGroupPayload/error too small [\(data.count)]")
            return nil
        }

        self.chainIndex = Int32(bigEndian: data[0...4].withUnsafeBytes { $0.load(as: Int32.self) })

        let encryptedPayloadWithoutHeader = data.dropFirst(4)
        self.hmac = encryptedPayloadWithoutHeader.suffix(32)
        self.encryptedSignedMessage = encryptedPayloadWithoutHeader.dropLast(32)
    }
}


struct SignedPayload {
    var payload: Data
    var signature: Data

    init?(data: Data) {
        // payload + signatureLength
        let signatureLength = 64 // 64 bytes signature
        guard data.count > signatureLength else {
            DDLogError("Whisper/SignedPayload/error too small [\(data.count)]")
            return nil
        }

        self.signature = data.suffix(signatureLength)
        self.payload = data.dropLast(signatureLength)
    }
}

struct CommentEncryptedPayload {
    var iv: Data
    var encrypted: Data
    var hmac: Data

    init?(data: Data) {
        // iv (16) + payload + signature (32) Length
        let minimumLength = 48
        guard data.count > minimumLength else {
            DDLogError("Whisper/CommentEncryptedPayload/error too small [\(data.count)]")
            return nil
        }

        self.iv = data.prefix(16)
        self.hmac = data.suffix(32)
        self.encrypted = data.dropLast(32).dropFirst(16)
    }
}

public struct CommentKey {
    var aesKey: [UInt8]
    var hmacKey: [UInt8]
    var rawData: Data

    init?(data: Data) {
        // 32 byte AES + 32 byte HMAC key
        guard data.count >= 64 else {
            DDLogError("Whisper/invalidCommentKey [\(data.count) bytes]")
            return nil
        }

        self.aesKey = data[0...31].bytes
        self.hmacKey = data[32...63].bytes
        self.rawData = data
    }
}

struct EncryptedPayload {
    var ephemeralPublicKey: Data
    var ephemeralKeyID: Int32
    var previousChainLength: Int32
    var chainIndex: Int32
    var hmac: Data
    var encryptedMessage: Data

    init?(data: Data) {
        // 44 byte header + 32 byte HMAC
        guard data.count >= 76 else {
            DDLogError("Whisper/error encryptedPayload too small [\(data.count)]")
            return nil
        }

        self.ephemeralPublicKey = data[0...31]
        self.ephemeralKeyID = Int32(bigEndian: data[32...35].withUnsafeBytes { $0.load(as: Int32.self) })
        self.previousChainLength = Int32(bigEndian: data[36...39].withUnsafeBytes { $0.load(as: Int32.self) })
        self.chainIndex = Int32(bigEndian: data[40...43].withUnsafeBytes { $0.load(as: Int32.self) })

        let encryptedPayloadWithoutHeader = data.dropFirst(44)
        self.hmac = encryptedPayloadWithoutHeader.suffix(32)
        self.encryptedMessage = encryptedPayloadWithoutHeader.dropLast(32)
    }
}

extension KeyBundle {
    enum Phase {
        case keyAgreement
        case conversation
    }
    var phase: Phase {
        (inboundEphemeralPublicKey?.isEmpty ?? true) ? .keyAgreement : .conversation
    }
}

private extension Int32 {
    var asBigEndianData: Data {
        withUnsafeBytes(of: bigEndian) { Data($0) }
    }
}


extension Data {
    // Extension to compute bitwise or of two data arrays.
    // TODO: murali@: clean this up to return nil if arrays dont match.
    static func ^ (left: Data, right: Data) -> Data {
        var result: Data = Data()
        var smaller: Data, bigger: Data
        if left.count <= right.count {
            smaller = left
            bigger = right
        } else {
            smaller = right
            bigger = left
        }

        let bs:[UInt8] = Array(smaller)
        let bb:[UInt8] = Array (bigger)
        var br = [UInt8] ()
        for i in 0..<bs.count {
            br.append(bs[i] ^ bb[i])
        }
        for j in bs.count..<bb.count {
            br.append(bb[j])
        }
        result = Data(br)
        return result
    }
}
