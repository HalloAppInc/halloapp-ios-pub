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
