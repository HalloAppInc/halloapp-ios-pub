//
//  HalloApp
//
//  Created by Tony Jiang on 7/15/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import Core
import CryptoKit
import CryptoSwift
import Foundation
import Sodium
import XMPPFramework

class KeyData {
    let oneTimePreKeysToUpload: Int32 = 20
    let thresholdToUploadMoreOTPKeys: Int32 = 5
    
    private var userData: UserData
    private var service: HalloService
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var keyStore: KeyStore
    
    init(service: HalloService, userData: UserData, keyStore: KeyStore) {
        self.service = service
        self.userData = userData
        self.keyStore = keyStore
        self.service.keyDelegate = self
        self.cancellableSet.insert(
            self.service.didConnect.sink { [weak self] in
                DDLogInfo("KeyData/onConnect")
                guard let self = self else { return }
                self.keyStore.performSeriallyOnBackgroundContext { (managedObjectContext) in

                    // used for testing purposes
//                    self.keyStore.deleteUserKeyBundles()

                    if self.keyStore.keyBundle(in: managedObjectContext) == nil {
                        DDLogInfo("KeyData/onConnect/noUserKeyBundle")
                        self.uploadWhisperKeyBundle()
                    } else {
                        self.getWhisperCountOfOneTimeKeys()
                    }

                }
            }
        )

    }
    
    private func uploadWhisperKeyBundle() {
        DDLogInfo("KeyData/uploadWhisperKeyBundle")
        let sodium = Sodium()
        guard let identityEdKeyPair = sodium.sign.keyPair() else { return }
        guard let identityKeyPair = sodium.sign.convertToX25519KeyPair(keyPair: identityEdKeyPair) else { return }
        guard let signedPreKeyPair = sodium.box.keyPair() else { return }

        let signedPreKey = PreKey(
            id: 1,
            privateKey: Data(signedPreKeyPair.secretKey),
            publicKey: Data(signedPreKeyPair.publicKey)
        )
        
        guard let signature = sodium.sign.signature(message: signedPreKeyPair.publicKey, secretKey: identityEdKeyPair.secretKey) else { return }
        
        // generate onetime keys
        let generatedOTPKeys = self.generateOneTimePreKeys(initialCounter: 0)
        
        let keyBundle = XMPPWhisperKey(
            identity: Data(identityEdKeyPair.publicKey),
            signed: signedPreKey,
            signature: Data(signature),
            oneTime: generatedOTPKeys.keys
        )

        service.uploadWhisperKeyBundle(keyBundle) { result in
            switch result {
            case .success:
                self.keyStore.performSeriallyOnBackgroundContext { (managedObjectContext) in
                    DDLogDebug("KeyData/uploadWhisperKeyBundle/save/new")
                    let userKeyBundle = NSEntityDescription.insertNewObject(forEntityName: UserKeyBundle.entity().name!, into: managedObjectContext) as! UserKeyBundle
                    userKeyBundle.identityPrivateEdKey = Data(identityEdKeyPair.secretKey)
                    userKeyBundle.identityPublicEdKey = Data(identityEdKeyPair.publicKey)
                    userKeyBundle.identityPrivateKey = Data(identityKeyPair.secretKey)
                    userKeyBundle.identityPublicKey = Data(identityKeyPair.publicKey)
                    userKeyBundle.oneTimePreKeysCounter = generatedOTPKeys.counter
                    
                    let signedKey = NSEntityDescription.insertNewObject(forEntityName: SignedPreKey.entity().name!, into: managedObjectContext) as! SignedPreKey
                    signedKey.id = signedPreKey.id
                    if let privateKey = signedPreKey.privateKey {
                        signedKey.privateKey = privateKey
                    }
                    
                    signedKey.publicKey  = signedPreKey.publicKey
                    signedKey.userKeyBundle = userKeyBundle
                    
                    // Process one time keys
                    for preKey in generatedOTPKeys.keys {
                        DDLogDebug("KeyData/uploadWhisperKeyBundle/save/new/oneTimeKey id: \(preKey.id)")
                        let oneTimeKey = NSEntityDescription.insertNewObject(forEntityName: OneTimePreKey.entity().name!, into: managedObjectContext) as! OneTimePreKey
                        oneTimeKey.id = preKey.id
                        if let privateKey = preKey.privateKey {
                            oneTimeKey.privateKey = privateKey
                        }
                        oneTimeKey.publicKey  = preKey.publicKey
                        oneTimeKey.userKeyBundle = userKeyBundle
                    }
                    self.keyStore.save(managedObjectContext)
                    
                    self.keyStore.deleteAllMessageKeyBundles()
                }
            case .failure(let error):
                DDLogInfo("KeyData/uploadWhisperKeyBundle/save/error \(error)")
            }
        }
    }
    
    private func uploadMoreOneTimePreKeys() {
        DDLogInfo("KeyStore/uploadMoreOneTimePreKeys")
        self.keyStore.performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let userKeyBundle = self.keyStore.keyBundle(in: managedObjectContext) else {
                DDLogInfo("KeyStore/uploadMoreOneTimePreKeys/noKeysFound")
                return
            }
            
            let generatedOTPKeys = self.generateOneTimePreKeys(initialCounter: userKeyBundle.oneTimePreKeysCounter)
            
            let whisperKeyBundle = XMPPWhisperKey(
                oneTime: generatedOTPKeys.keys
            )

            self.service.requestAddOneTimeKeys(whisperKeyBundle) { result in
                switch result {
                case .success:
                    DDLogDebug("KeyData/uploadMoreOneTimePreKeys/save")
                    userKeyBundle.oneTimePreKeysCounter = generatedOTPKeys.counter

                    // Process one time keys
                    for preKey in whisperKeyBundle.oneTime {
                        DDLogDebug("KeyData/uploadMoreOneTimePreKeys/save/new/oneTimeKey id: \(preKey.id) \(preKey.publicKey.base64EncodedString())")
                        let oneTimeKey = NSEntityDescription.insertNewObject(forEntityName: OneTimePreKey.entity().name!, into: managedObjectContext) as! OneTimePreKey
                        oneTimeKey.id = preKey.id
                        if let privateKey = preKey.privateKey {
                            oneTimeKey.privateKey = privateKey
                        }
                        oneTimeKey.publicKey  = preKey.publicKey
                        oneTimeKey.userKeyBundle = userKeyBundle
                    }
                    self.keyStore.save(managedObjectContext)
                case .failure(let error):
                    DDLogInfo("KeyData/uploadMoreOneTimePreKeys/save/error \(error)")
                }
            }
        }
    }

    public func getWhisperCountOfOneTimeKeys() {
        DDLogInfo("keyData/getWhisperCountOfOneTimeKeys")
        service.requestCountOfOneTimeKeys() { result in
            switch result {
            case .success(let otpKeyCountNum):
                self.uploadMoreOTPKeysIfNeeded(currentNum: otpKeyCountNum)
            case .failure(let error):
                DDLogError("KeyData/getWhisperCountOfOneTimeKeys/error \(error)")
            }
        }
    }
    
    func uploadMoreOTPKeysIfNeeded(currentNum: Int32) {
        DDLogInfo("KeyData/uploadMoreOTPKeysIfNeeded/serverNumOTPKey: \(currentNum)")
        if currentNum < self.thresholdToUploadMoreOTPKeys {
            self.uploadMoreOneTimePreKeys()
        }
    }
    
    private func generateOneTimePreKeys(initialCounter: Int32) -> (keys: [PreKey], counter: Int32) {
        DDLogInfo("KeyData/generateOneTimePreKeys")
        let sodium = Sodium()
        var oneTimePreKeys: [PreKey] = []
        var currentCounter: Int32 = initialCounter
        let endCounter = currentCounter + self.oneTimePreKeysToUpload
        while currentCounter < endCounter {
            guard let oneTimePreKeyPair = sodium.box.keyPair() else { continue }
            let preKey = PreKey(
                id: currentCounter,
                privateKey: Data(oneTimePreKeyPair.secretKey),
                publicKey: Data(oneTimePreKeyPair.publicKey)
            )
            oneTimePreKeys.append(preKey)
            currentCounter += 1
        }
        return (oneTimePreKeys, currentCounter)
    }
    
}

extension KeyData {
    public func encryptOperation(for userID: UserID) -> EncryptOperation {
        return { data, completion in
            self.wrapMessage(for: userID, unencrypted: data, completion: completion)
        }
    }

    public func wrapMessage(for userId: String, unencrypted: Data, completion: @escaping (EncryptedData) -> Void) {
        DDLogInfo("KeyData/wrapMessage")
        var keyBundle: KeyBundle? = nil
        let group = DispatchGroup()
        group.enter()

        self.keyStore.performSeriallyOnBackgroundContext { (managedObjectContext) in
            if let savedKeyBundle = self.keyStore.messageKeyBundle(for: userId)?.keyBundle {

                keyBundle = savedKeyBundle

                group.leave()

            } else {
                self.service.requestWhisperKeyBundle(userID: userId) { result in
                    switch result {
                    case .success(let keys):
                        keyBundle = self.keyStore.initiateSessionSetup(for: userId, with: keys)
                    case .failure(let error):
                        DDLogInfo("KeyData/wrapMessage/error \(error)")
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: self.keyStore.backgroundProcessingQueue) {
            var encryptedData: Data? = nil, identityKey: Data? = nil, oneTimeKey: Int32 = 0
            if let keyBundle = keyBundle {
                encryptedData = self.keyStore.encryptMessage(for: userId, unencrypted: unencrypted, keyBundle: keyBundle)
                if let outboundIdentityKey = keyBundle.outboundIdentityPublicEdKey {
                    identityKey = outboundIdentityKey
                    oneTimeKey = keyBundle.outboundOneTimePreKeyId
                }
            }
            completion((encryptedData, identityKey, oneTimeKey))
        }
    }

    public func unwrapMessage(for userId: String, from entry: XMLElement) -> Data? {
        DDLogInfo("KeyData/unwrapMessage/for/\(userId)")

        guard let enc = entry.element(forName: "enc") else {
            DDLogDebug("KeyData/unwrapMessage/no enc")
            return nil
        }
        guard let encStringValue = enc.stringValue, !encStringValue.isEmpty else {
            DDLogDebug("KeyData/unwrapMessage/empty enc")
            return nil
        }
        guard let encryptedPayload = Data(base64Encoded: encStringValue, options: .ignoreUnknownCharacters) else {
            DDLogError("KeyData/unwrapMessage/error base64 decoding failed")
            return nil
        }

        let oneTimeKeyID: Int? = {
            guard let inboundOneTimePreKeyIdStr = enc.attributeStringValue(forName: "one_time_pre_key_id") else {
                return nil
            }
            return Int(inboundOneTimePreKeyIdStr)
        }()

        let publicKey: Data? = {
            guard let inboundIdentityPublicEdKeyBase64 = enc.attributeStringValue(forName: "identity_key") else {
                return nil
            }
            return Data(base64Encoded: inboundIdentityPublicEdKeyBase64)
        }()

        return decryptPayload(for: userId, encryptedPayload: encryptedPayload, publicKey: publicKey, oneTimeKeyID: oneTimeKeyID)
    }

    public func decryptPayload(for userId: String, encryptedPayload: Data, publicKey: Data?, oneTimeKeyID: Int?) -> Data? {

        var keyBundle: KeyBundle
        var isNewReceiveSession: Bool

        if let savedKeyBundle = self.keyStore.messageKeyBundle(for: userId)?.keyBundle {
            keyBundle = savedKeyBundle
            isNewReceiveSession = false
        } else {
            guard let publicKey = publicKey else {
                DDLogError("KeyData/decryptPayload/error missing public key")
                return nil
            }
            guard let newKeyBundle = keyStore.receiveSessionSetup(for: userId, from: encryptedPayload, publicKey: publicKey, oneTimeKeyID: oneTimeKeyID) else {
                DDLogError("KeyData/decryptPayload/error receiveSessionSetup failed")
                return nil
            }
            keyBundle = newKeyBundle
            isNewReceiveSession = true
        }

        return keyStore.decryptMessage(for: userId, encryptedPayload: encryptedPayload, keyBundle: keyBundle, isNewReceiveSession: isNewReceiveSession)
    }

}

extension KeyData: HalloKeyDelegate {
    public func halloService(_ halloService: HalloService, didReceiveWhisperMessage message: WhisperMessage) {
        DDLogInfo("KeyData/didReceiveWhisperMessage \(message)")
        switch message {
        case .update(let uid):
            self.keyStore.deleteMessageKeyBundles(for: uid)
        case .normal(let otpKeyCountNum):
            self.uploadMoreOTPKeysIfNeeded(currentNum: otpKeyCountNum)
        }
    }
}
