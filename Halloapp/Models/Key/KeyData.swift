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
    private var xmppController: XMPPControllerMain
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var keyStore: KeyStore
    
    init(xmppController: XMPPControllerMain, userData: UserData, keyStore: KeyStore) {
        self.xmppController = xmppController
        self.userData = userData
        self.keyStore = keyStore
        self.xmppController.keyDelegate = self
        self.cancellableSet.insert(
            self.xmppController.didConnect.sink { [weak self] in
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

        let request = XMPPWhisperUploadRequest(keyBundle: keyBundle) { (error) in
            if error == nil {
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
            } else {
                DDLogInfo("KeyData/uploadWhisperKeyBundle/save/error")
            }
        }
        self.xmppController.enqueue(request: request)
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
            
            let request = XMPPWhisperAddOneTimeKeysRequest(whisperKeyBundle: whisperKeyBundle) { (error) in
                if error == nil {
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
                } else {
                    DDLogInfo("KeyData/uploadMoreOneTimePreKeys/save/error")
                }
            }
            self.xmppController.enqueue(request: request)
        }
    }

    public func getWhisperCountOfOneTimeKeys() {
        DDLogInfo("keyData/getWhisperCountOfOneTimeKeys")
        let request = XMPPWhisperGetCountOfOneTimeKeysRequest() { (response, error) in
            if error == nil {
                guard let whisperKeys = response?.element(forName: "whisper_keys") else { return }

                //gotcha: there's no type although server doc say there is a type of normal
                guard let otpKeyCount = whisperKeys.element(forName: "otp_key_count") else { return }
                let otpKeyCountNum = otpKeyCount.stringValueAsInt()
                self.uploadMoreOTPKeysIfNeeded(currentNum: otpKeyCountNum)
            } else {
            }
        }
        self.xmppController.enqueue(request: request)
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
    public func wrapMessage(for userId: String, unencrypted: Data, completion: @escaping (Data?, Data?, Int32) -> Void) {
        DDLogInfo("KeyData/wrapMessage")
        var keyBundle: KeyBundle? = nil
        let group = DispatchGroup()
        group.enter()
        
        self.keyStore.performSeriallyOnBackgroundContext { (managedObjectContext) in
            if let savedMessageKeyBundle = self.keyStore.messageKeyBundle(for: userId) {
                
                keyBundle = KeyBundle(userId: savedMessageKeyBundle.userId,
                                      inboundIdentityPublicEdKey: savedMessageKeyBundle.inboundIdentityPublicEdKey!,
                                      
                                      inboundEphemeralPublicKey: savedMessageKeyBundle.inboundEphemeralPublicKey,
                                      inboundEphemeralKeyId: savedMessageKeyBundle.inboundEphemeralKeyId,
                                      inboundChainKey: savedMessageKeyBundle.inboundChainKey,
                                      inboundPreviousChainLength: savedMessageKeyBundle.inboundPreviousChainLength,
                                      inboundChainIndex: savedMessageKeyBundle.inboundChainIndex,
    
                                      rootKey: savedMessageKeyBundle.rootKey,
                                      
                                      outboundEphemeralPrivateKey: savedMessageKeyBundle.outboundEphemeralPrivateKey,
                                      outboundEphemeralPublicKey: savedMessageKeyBundle.outboundEphemeralPublicKey,
                                      outboundEphemeralKeyId: savedMessageKeyBundle.outboundEphemeralKeyId,
                                      outboundChainKey: savedMessageKeyBundle.outboundChainKey,
                                      outboundPreviousChainLength: savedMessageKeyBundle.outboundPreviousChainLength,
                                      outboundChainIndex: savedMessageKeyBundle.outboundChainIndex,
                                      
                                      outboundIdentityPublicEdKey: savedMessageKeyBundle.outboundIdentityPublicEdKey,
                                      outboundOneTimePreKeyId: savedMessageKeyBundle.outboundOneTimePreKeyId)
                
                group.leave()
                
            } else {
                let request = XMPPWhisperGetBundleRequest(targetUserId: userId) { (response, error) in
                    if error == nil {
                        if let response = response {
                            if let keys = XMPPWhisperKey(itemElement: response) {
                                keyBundle = self.keyStore.initiateSessionSetup(for: userId, with: keys)
                            }
                        }
                    } else {
                        DDLogInfo("KeyData/wrapMessage/error")
                    }
                    group.leave()
                }
                self.xmppController.enqueue(request: request)
            }
        }
        
        group.notify(queue: self.keyStore.backgroundProcessingQueue) {
            var encryptedData: Data? = nil
            if let keyBundle = keyBundle {
                encryptedData = self.keyStore.encryptMessage(for: userId, unencrypted: unencrypted, keyBundle: keyBundle)
                var identityKey: Data? = nil, oneTimeKey: Int32 = 0
                if let outboundIdentityKey = keyBundle.outboundIdentityPublicEdKey {
                    identityKey = outboundIdentityKey
                    oneTimeKey = keyBundle.outboundOneTimePreKeyId
                }
                completion(encryptedData, identityKey, oneTimeKey)
            }
        }
    }
    
    public func unwrapMessage(for userId: String, from entry: XMLElement) -> Data? {
        
        guard let enc = entry.element(forName: "enc") else { return nil }
        guard enc.stringValue != nil else { return nil }
        
        var keyBundle: KeyBundle? = nil
        var isNewReceiveSession = false
        
        if let messageKeyBundle = self.keyStore.messageKeyBundle(for: userId) {
            
            keyBundle = KeyBundle(userId: messageKeyBundle.userId,
                                  inboundIdentityPublicEdKey: messageKeyBundle.inboundIdentityPublicEdKey!,
                                  
                                  inboundEphemeralPublicKey: messageKeyBundle.inboundEphemeralPublicKey,
                                  inboundEphemeralKeyId: messageKeyBundle.inboundEphemeralKeyId,
                                  inboundChainKey: messageKeyBundle.inboundChainKey,
                                  inboundPreviousChainLength: messageKeyBundle.inboundPreviousChainLength,
                                  inboundChainIndex: messageKeyBundle.inboundChainIndex,
                                  
                                  rootKey: messageKeyBundle.rootKey,
                                  
                                  outboundEphemeralPrivateKey: messageKeyBundle.outboundEphemeralPrivateKey,
                                  outboundEphemeralPublicKey: messageKeyBundle.outboundEphemeralPublicKey,
                                  outboundEphemeralKeyId: messageKeyBundle.outboundEphemeralKeyId,
                                  outboundChainKey: messageKeyBundle.outboundChainKey,
                                  outboundPreviousChainLength: messageKeyBundle.outboundPreviousChainLength,
                                  outboundChainIndex: messageKeyBundle.outboundChainIndex)
        } else {
            keyBundle = self.keyStore.receiveSessionSetup(for: userId, from: entry)
            isNewReceiveSession = true
        }
        
        if let keyBundle = keyBundle {
            return self.keyStore.decryptMessage(for: userId, from: entry, keyBundle: keyBundle, isNewReceiveSession: isNewReceiveSession)
        }
        
        return nil
    }
    
}

extension KeyData: XMPPControllerKeyDelegate {
    public func xmppController(_ xmppController: XMPPController, didReceiveWhisperMessage item: XMLElement) {
        DDLogInfo("KeyData/didReceiveWhisperMessage \(item)")
        guard let whisperType = item.attributeStringValue(forName: "type") else { return }

        if whisperType == "update" {
            DDLogInfo("KeyData/didReceiveWhisperMessage/type \(whisperType)")
            guard let uid = item.attributeStringValue(forName: "uid") else { return }
            self.keyStore.deleteMessageKeyBundles(for: uid)
        } else if whisperType == "normal" {
            DDLogInfo("KeyData/didReceiveWhisperMessage/type \(whisperType)")
            guard let otpKeyCount = item.element(forName: "otp_key_count") else { return }
            let otpKeyCountNum = otpKeyCount.stringValueAsInt()
            self.uploadMoreOTPKeysIfNeeded(currentNum: otpKeyCountNum)
        }
    }
}
