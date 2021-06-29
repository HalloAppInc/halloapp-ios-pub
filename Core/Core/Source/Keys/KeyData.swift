//
//  KeyData.swift
//  Core
//
//  Created by Tony Jiang on 7/15/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import CoreData
import CryptoKit
import CryptoSwift
import Foundation
import Sodium

enum KeyDataError: Error {
    case identityKeyMismatch
    case identityKeyMissing
}

public class KeyData {
    let oneTimePreKeysToUpload: Int32 = 100
    let thresholdToUploadMoreOTPKeys: Int32 = 5
    var isOneTimePreKeyUploadInProgress = false

    private struct UserDefaultsKey {
        static let identityKeyVerificationDate = "com.halloapp.identity.key.verification.date"
    }

    private var userData: UserData
    private var service: CoreService
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var keyStore: KeyStore
    
    init(service: CoreService, userData: UserData, keyStore: KeyStore) {
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
                    }
                }
            }
        )
    }

    public func generateUserKeys() -> UserKeys? {
        let sodium = Sodium()
        guard let identityEdKeyPair = sodium.sign.keyPair(),
              let identityKeyPair = sodium.sign.convertToX25519KeyPair(keyPair: identityEdKeyPair),
              let signedPreKeyPair = sodium.box.keyPair(),
              let signature = sodium.sign.signature(message: signedPreKeyPair.publicKey, secretKey: identityEdKeyPair.secretKey) else
        {
            return nil
        }

        // Start one time keys from 1 (`0` is indistinguishable from `unset` in our current protocol)
        let minimumOneTimeKeyIndex: Int32 = 1

        return UserKeys(
            identityEd: identityEdKeyPair.keyPairEd(),
            identityX25519: identityKeyPair.keyPairX25519(),
            signed: PreKeyPair(id: 1, keyPair: signedPreKeyPair.keyPairX25519()),
            signature: Data(signature),
            oneTimeKeyPairs: generateOneTimePreKeys(initialCounter: minimumOneTimeKeyIndex))
    }

    public func saveUserKeys(_ userKeys: UserKeys) {

        // We only support storing keys for one user at a time!
        keyStore.deleteUserKeyBundles()

        let maxOneTimeKeyID: Int32 = userKeys.oneTimeKeyPairs.map { $0.id }.max() ?? -1
        keyStore.performSeriallyOnBackgroundContext { (managedObjectContext) in
            DDLogDebug("KeyData/saveUserKeys/new")
            let userKeyBundle = NSEntityDescription.insertNewObject(forEntityName: UserKeyBundle.entity().name!, into: managedObjectContext) as! UserKeyBundle
            userKeyBundle.identityPrivateEdKey = userKeys.identityEd.privateKey
            userKeyBundle.identityPublicEdKey = userKeys.identityEd.publicKey
            userKeyBundle.identityPrivateKey = userKeys.identityX25519.privateKey
            userKeyBundle.identityPublicKey = userKeys.identityX25519.publicKey
            userKeyBundle.oneTimePreKeysCounter = maxOneTimeKeyID + 1

            let signedKey = NSEntityDescription.insertNewObject(forEntityName: SignedPreKey.entity().name!, into: managedObjectContext) as! SignedPreKey
            signedKey.id = userKeys.signed.id
            signedKey.privateKey = userKeys.signed.keyPair.privateKey
            signedKey.publicKey  = userKeys.signed.keyPair.publicKey
            signedKey.userKeyBundle = userKeyBundle

            // Process one time keys
            for preKey in userKeys.oneTimeKeyPairs {
                DDLogDebug("KeyData/saveUserKeys/oneTimeKey id: \(preKey.id)")
                let oneTimeKey = NSEntityDescription.insertNewObject(forEntityName: OneTimePreKey.entity().name!, into: managedObjectContext) as! OneTimePreKey
                oneTimeKey.id = preKey.id
                oneTimeKey.privateKey = preKey.keyPair.privateKey
                oneTimeKey.publicKey  = preKey.keyPair.publicKey
                oneTimeKey.userKeyBundle = userKeyBundle
            }
            self.keyStore.save(managedObjectContext)

            self.keyStore.deleteAllMessageKeyBundles()
        }
    }
    
    private func uploadWhisperKeyBundle() {
        DDLogInfo("KeyData/uploadWhisperKeyBundle")

        guard let userKeys = generateUserKeys() else {
            DDLogError("Keydata/uploadWhisperKeyBundle/error unable to generate user keys")
            return
        }

        service.uploadWhisperKeyBundle(userKeys.whisperKeys) { result in
            switch result {
            case .success:
                self.saveUserKeys(userKeys)
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

        guard let userKeyBundle = keyStore.keyBundle() else {
            DDLogError("KeyStore/uploadMoreOneTimePreKeys/error [noKeysFound]")
            return
        }

        let generatedOTPKeys = self.generateOneTimePreKeys(initialCounter: userKeyBundle.oneTimePreKeysCounter)

        saveOneTimePreKeys(generatedOTPKeys) { saveSuccess in
            guard saveSuccess else {
                DDLogError("KeyStore/uploadMoreOneTimePreKeys/error [saveError]")
                self.isOneTimePreKeyUploadInProgress = false
                return
            }

            self.service.requestAddOneTimeKeys(generatedOTPKeys.map { $0.publicPreKey }) { result in
                self.isOneTimePreKeyUploadInProgress = false
                switch result {
                case .success:
                    DDLogInfo("KeyStore/uploadMoreOneTimePreKeys/complete")
                case .failure(let error):
                    DDLogError("KeyStore/uploadMoreOneTimePreKeys/error \(error)")
                }
            }
        }
    }

    private func saveOneTimePreKeys(_ preKeys: [PreKeyPair<X25519>], completion: ((Bool) -> Void)?) {
        guard let maxKeyID = preKeys.map({ $0.id }).max() else {
            DDLogInfo("KeyData/saveOneTimePreKeys/skipping (empty)")
            completion?(false)
            return
        }

        DDLogInfo("KeyData/saveOneTimePreKeys")
        self.keyStore.performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let userKeyBundle = self.keyStore.keyBundle(in: managedObjectContext) else {
                DDLogInfo("KeyData/saveOneTimePreKeys/noKeysFound")
                completion?(false)
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
                let saveSuccess = self.keyStore.save(managedObjectContext)
                completion?(saveSuccess)
            } else {
                completion?(false)
            }
        }
    }

    // Unused function as of now.
    // We dont request count of otp keys from the server - since server already sends us notifications when we are running low.
    // server team will measure if clients are missing these notifications and we can then revisit and enable this if needed.
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
    
    private func generateOneTimePreKeys(initialCounter: Int32) -> [PreKeyPair<X25519>] {
        DDLogInfo("KeyData/generateOneTimePreKeys")
        let sodium = Sodium()
        let endCounter = initialCounter + self.oneTimePreKeysToUpload
        return (initialCounter ..< endCounter).compactMap {
            guard let oneTimePreKeyPair = sodium.box.keyPair() else { return nil }
            return PreKeyPair(id: $0, keyPair: oneTimePreKeyPair.keyPairX25519())
        }
    }

    private var isVerifyingIdentityKey = false

    private func verifyIdentityKeyIfNecessary() {
        guard !isVerifyingIdentityKey else {
            DDLogInfo("KeyData/verifyIdentityKey/skipping [in progress]")
            return
        }

        let oneDay = TimeInterval(86400)

        if let lastVerificationDate = AppContext.shared.userDefaults.object(forKey: UserDefaultsKey.identityKeyVerificationDate) as? Date,
           lastVerificationDate.advanced(by: oneDay) > Date()
        {
            DDLogInfo("KeyData/verifyIdentityKey/skipping [last verified: \(lastVerificationDate)]")
            return
        }

        guard let savedIdentityKey = keyStore.keyBundle()?.identityPublicEdKey else {
            self.didFailIdentityKeyVerification(with: .identityKeyMissing)
            return
        }

        isVerifyingIdentityKey = true
        service.requestWhisperKeyBundle(userID: userData.userId) { result in
            switch result {
            case .failure(let error):
                DDLogError("KeyData/verifyIdentityKey/error [\(error)]")
            case .success(let bundle):
                if bundle.identity == savedIdentityKey {
                    DDLogError("KeyData/verifyIdentityKey/success")
                    AppContext.shared.userDefaults.setValue(Date(), forKey: UserDefaultsKey.identityKeyVerificationDate)
                } else {
                    DDLogInfo("KeyData/verifyIdentityKey/identityKeyMismatch: saved: \(savedIdentityKey.bytes), received:\(bundle.identity.bytes)")
                    self.didFailIdentityKeyVerification(with: .identityKeyMismatch)
                }
            }
            self.isVerifyingIdentityKey = false
        }
    }

    private func didFailIdentityKeyVerification(with error: KeyDataError) {
        DDLogError("KeyData/didFailIdentityKeyVerification [\(error)]")
        AppContext.shared.errorLogger?.logError(error)
        userData.logout()
    }
}

extension KeyData: ServiceKeyDelegate {
    public func service(_ service: CoreService, didReceiveWhisperMessage message: WhisperMessage) {
        DDLogInfo("KeyData/didReceiveWhisperMessage \(message)")
        switch message {
        case .update(let uid):
            self.keyStore.deleteMessageKeyBundles(for: uid)
        case .count(let otpKeyCountNum):
            self.uploadMoreOTPKeysIfNeeded(currentNum: otpKeyCountNum)
        }
    }

    public func service(_ service: CoreService, didReceiveRerequestWithRerequestCount rerequestCount: Int) {
        if rerequestCount > 2 {
            verifyIdentityKeyIfNecessary()
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
