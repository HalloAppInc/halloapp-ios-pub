//
//  HalloApp
//
//  Created by Tony Jiang on 7/15/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import CryptoKit
import CryptoSwift
import Foundation
import Sodium

class KeyData {
    let oneTimePreKeysToUpload: Int32 = 20
    let thresholdToUploadMoreOTPKeys: Int32 = 5
    var isOneTimePreKeyUploadInProgress = false
    
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

    private func generateUserKeys() -> UserKeys? {
        let sodium = Sodium()
        guard let identityEdKeyPair = sodium.sign.keyPair(),
              let identityKeyPair = sodium.sign.convertToX25519KeyPair(keyPair: identityEdKeyPair),
              let signedPreKeyPair = sodium.box.keyPair(),
              let signature = sodium.sign.signature(message: signedPreKeyPair.publicKey, secretKey: identityEdKeyPair.secretKey) else
        {
            return nil
        }

        return UserKeys(
            identityEd: identityEdKeyPair.keyPairEd(),
            identityX25519: identityKeyPair.keyPairX25519(),
            signed: PreKeyPair(id: 1, keyPair: signedPreKeyPair.keyPairX25519()),
            signature: Data(signature))
    }
    
    private func uploadWhisperKeyBundle() {
        DDLogInfo("KeyData/uploadWhisperKeyBundle")

        guard let userKeys = generateUserKeys() else {
            DDLogError("Keydata/uploadWhisperKeyBundle/error unable to generate user keys")
            return
        }
        let generatedOTPKeys = self.generateOneTimePreKeys(initialCounter: 0)
        
        let keyBundle = WhisperKeyBundle(
            identity: userKeys.identityEd.publicKey,
            signed: userKeys.signed.publicPreKey,
            signature: userKeys.signature,
            oneTime: generatedOTPKeys.keys.map { $0.publicPreKey }
        )

        service.uploadWhisperKeyBundle(keyBundle) { result in
            switch result {
            case .success:
                self.keyStore.performSeriallyOnBackgroundContext { (managedObjectContext) in
                    DDLogDebug("KeyData/uploadWhisperKeyBundle/save/new")
                    let userKeyBundle = NSEntityDescription.insertNewObject(forEntityName: UserKeyBundle.entity().name!, into: managedObjectContext) as! UserKeyBundle
                    userKeyBundle.identityPrivateEdKey = userKeys.identityEd.privateKey
                    userKeyBundle.identityPublicEdKey = userKeys.identityEd.publicKey
                    userKeyBundle.identityPrivateKey = userKeys.identityX25519.privateKey
                    userKeyBundle.identityPublicKey = userKeys.identityX25519.publicKey
                    userKeyBundle.oneTimePreKeysCounter = generatedOTPKeys.counter
                    
                    let signedKey = NSEntityDescription.insertNewObject(forEntityName: SignedPreKey.entity().name!, into: managedObjectContext) as! SignedPreKey
                    signedKey.id = userKeys.signed.id
                    signedKey.privateKey = userKeys.signed.keyPair.privateKey
                    signedKey.publicKey  = userKeys.signed.keyPair.publicKey
                    signedKey.userKeyBundle = userKeyBundle
                    
                    // Process one time keys
                    for preKey in generatedOTPKeys.keys {
                        DDLogDebug("KeyData/uploadWhisperKeyBundle/save/new/oneTimeKey id: \(preKey.id)")
                        let oneTimeKey = NSEntityDescription.insertNewObject(forEntityName: OneTimePreKey.entity().name!, into: managedObjectContext) as! OneTimePreKey
                        oneTimeKey.id = preKey.id
                        oneTimeKey.privateKey = preKey.keyPair.privateKey
                        oneTimeKey.publicKey  = preKey.keyPair.publicKey
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
        guard !isOneTimePreKeyUploadInProgress else {
            DDLogInfo("KeyData/uploadMoreOneTimePreKeys/skipping (already in progress)")
            return
        }

        DDLogInfo("KeyStore/uploadMoreOneTimePreKeys")
        isOneTimePreKeyUploadInProgress = true
        self.keyStore.performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let userKeyBundle = self.keyStore.keyBundle(in: managedObjectContext) else {
                DDLogInfo("KeyStore/uploadMoreOneTimePreKeys/noKeysFound")
                return
            }
            
            let generatedOTPKeys = self.generateOneTimePreKeys(initialCounter: userKeyBundle.oneTimePreKeysCounter)

            self.service.requestAddOneTimeKeys(generatedOTPKeys.keys.map { $0.publicPreKey }) { result in
                switch result {
                case .success:
                    self.saveOneTimePreKeys(generatedOTPKeys.keys) {
                        self.isOneTimePreKeyUploadInProgress = false
                    }
                case .failure(let error):
                    DDLogError("KeyStore/uploadMoreOneTimePreKeys/error \(error)")
                    self.isOneTimePreKeyUploadInProgress = false
                }
            }
        }
    }

    private func saveOneTimePreKeys(_ preKeys: [PreKeyPair<X25519>], completion: (() -> Void)?) {
        guard let maxKeyID = preKeys.map({ $0.id }).max() else {
            DDLogInfo("KeyData/saveOneTimePreKeys/skipping (empty)")
            completion?()
            return
        }

        DDLogInfo("KeyData/saveOneTimePreKeys")
        self.keyStore.performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let userKeyBundle = self.keyStore.keyBundle(in: managedObjectContext) else {
                DDLogInfo("KeyData/saveOneTimePreKeys/noKeysFound")
                completion?()
                return
            }

            for preKey in preKeys {
                guard preKey.id >= userKeyBundle.oneTimePreKeysCounter else {
                    DDLogError("KeyData/saveOneTimePreKeys/invalid key [id=\(preKey.id)] [counter=\(userKeyBundle.oneTimePreKeysCounter)]")
                    continue
                }
                DDLogDebug("KeyData/saveOneTimePreKeys/oneTimeKey id: \(preKey.id) \(preKey.keyPair.publicKey.base64EncodedString())")
                let oneTimeKey = NSEntityDescription.insertNewObject(forEntityName: OneTimePreKey.entity().name!, into: managedObjectContext) as! OneTimePreKey
                oneTimeKey.id = preKey.id
                oneTimeKey.privateKey = preKey.keyPair.privateKey
                oneTimeKey.publicKey  = preKey.keyPair.publicKey
                oneTimeKey.userKeyBundle = userKeyBundle
            }

            userKeyBundle.oneTimePreKeysCounter = maxKeyID + 1

            if managedObjectContext.hasChanges {
                self.keyStore.save(managedObjectContext)
                completion?()
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
    
    private func generateOneTimePreKeys(initialCounter: Int32) -> (keys: [PreKeyPair<X25519>], counter: Int32) {
        DDLogInfo("KeyData/generateOneTimePreKeys")
        let sodium = Sodium()
        var oneTimePreKeys: [PreKeyPair<X25519>] = []
        var currentCounter: Int32 = initialCounter
        let endCounter = currentCounter + self.oneTimePreKeysToUpload
        while currentCounter < endCounter {
            guard let oneTimePreKeyPair = sodium.box.keyPair() else { continue }
            let preKey = PreKeyPair(id: currentCounter, keyPair: oneTimePreKeyPair.keyPairX25519())
            oneTimePreKeys.append(preKey)
            currentCounter += 1
        }
        return (oneTimePreKeys, currentCounter)
    }
    
}

extension KeyData: HalloKeyDelegate {
    public func halloService(_ halloService: HalloService, didReceiveWhisperMessage message: WhisperMessage) {
        DDLogInfo("KeyData/didReceiveWhisperMessage \(message)")
        switch message {
        case .update(let uid):
            self.keyStore.deleteMessageKeyBundles(for: uid)
        case .count(let otpKeyCountNum):
            self.uploadMoreOTPKeysIfNeeded(currentNum: otpKeyCountNum)
        }
    }
}

extension Sign.KeyPair {
    func keyPairEd() -> TypedKeyPair<Ed> {
        return TypedKeyPair<Ed>(privateKey: Data(secretKey), publicKey: Data(publicKey))
    }
}

extension Box.KeyPair {
    func keyPairX25519() -> TypedKeyPair<X25519> {
        return TypedKeyPair<X25519>(privateKey: Data(secretKey), publicKey: Data(publicKey))
    }
}
