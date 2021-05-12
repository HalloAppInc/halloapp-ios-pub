//
//  Whisper.swift
//  Core
//
//  Created by Garrett on 3/2/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjack
import CryptoSwift
import Foundation
import Sodium

final class Whisper {

    static func encrypt(_ unencrypted: Data, keyBundle: KeyBundle) -> Result<(encryptedData: Data, chainKey: Data), EncryptionError> {

        DDLogInfo("Whisper/encrypt/outboundChainIndex [\(keyBundle.outboundChainIndex)]")
        DDLogInfo("Whisper/encrypt/chain [\(keyBundle.outboundChainKey.bytes)]")
        DDLogInfo("Whisper/encrypt/outboundEphemeralKeyId [\(keyBundle.outboundEphemeralKeyId)]")
        DDLogInfo("Whisper/encrypt/outboundEphemeralPublicKeyBytes [\(keyBundle.outboundEphemeralPublicKey.bytes)]")
        DDLogInfo("Whisper/encrypt/outboundPreviousChainLength [\(keyBundle.outboundPreviousChainLength)]")

        guard let symmetricRatchet = symmetricRatchet(chainKey: keyBundle.outboundChainKey.bytes),
              let messageKey = MessageKeyContents(data: Data(symmetricRatchet.messageKey)) else
        {
            return .failure(.ratchetFailure)
        }
        DDLogInfo("Whisper/encrypt/message [\(messageKey.data.bytes)]")
        DDLogInfo("Whisper/encrypt/new-chain [\(symmetricRatchet.updatedChainKey)]")

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

        DDLogInfo("Whisper/decrypt/message-key [\(messageKey.data.bytes)]")
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
                                  outboundEphemeralKeyId: 1,
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
            DDLogInfo("Inbound Key: \(inboundIdentityPublicEdKey)")
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

        if let oneTimeKeyID = oneTimeKeyID, oneTimeKeyID >= 0 {
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
                                  outboundEphemeralKeyId: 1,
                                  outboundChainKey: Data(outboundChainKey),
                                  outboundPreviousChainLength: 0,
                                  outboundChainIndex: 0)
        return .success(keyBundle)
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
            DDLogInfo("WhisperSession/ratchetKeyBundle/newEphemeralKey/skipping [ephemeral keys match]")
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

        DDLogDebug("ecdhA:  \([UInt8](ecdhA))")
        DDLogDebug("ecdhB:  \([UInt8](ecdhB))")
        DDLogDebug("ecdhC:  \([UInt8](ecdhC))")

        if let recipientOneTimePreKey = recipientOneTimePreKey {

            let ecdhDPrivateKey = isInitiator ? initiatorEphemeralKey  : recipientOneTimePreKey
            let ecdhDPublicKey  = isInitiator ? recipientOneTimePreKey  : initiatorEphemeralKey

            guard let ecdhD = sodium.keyAgreement.sharedSecret(secretKey: ecdhDPrivateKey, publicKey: ecdhDPublicKey) else {
                DDLogInfo("ecdhD:  \([UInt8](ecdhA))")
                return nil
            }
            DDLogDebug("ecdhD:  \([UInt8](ecdhD))")
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

    private static func symmetricRatchet(chainKey: [UInt8]) -> (messageKey: [UInt8], updatedChainKey: [UInt8])? {
        let infoOne: Array<UInt8> = [0x01]
        let infoTwo: Array<UInt8> = [0x02]
        guard let messageKey = try? HKDF(password: chainKey, info: infoOne, keyLength: 80, variant: .sha256).calculate() else { return nil }
        guard let updatedChainKey = try? HKDF(password: chainKey, info: infoTwo, keyLength: 32, variant: .sha256).calculate() else { return nil }
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
