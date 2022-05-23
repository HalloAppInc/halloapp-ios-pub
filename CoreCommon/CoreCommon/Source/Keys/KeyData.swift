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
    public let userDefaultsKeyForOneTimePreKeys = "serverRequestedOneTimeKeys"

    private struct UserDefaultsKey {
        static let identityKeyVerificationDate = "com.halloapp.identity.key.verification.date"
    }

    private var userData: UserData
    private var service: CoreServiceCommon
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var keyStore: KeyStore
    
    init(service: CoreServiceCommon, userData: UserData, keyStore: KeyStore) {
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
                        DDLogError("KeyData/onConnect/noUserKeyBundle")
                        AppContextCommon.shared.errorLogger?.logError(KeyDataError.identityKeyMissing)

                        userData.performSeriallyOnBackgroundContext { userManagedObjectContext in
                            userData.logout(using: userManagedObjectContext)
                        }
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
    
    public func uploadMoreOneTimePreKeys() {
        guard !isOneTimePreKeyUploadInProgress else {
            DDLogInfo("KeyData/uploadMoreOneTimePreKeys/skipping (already in progress)")
            return
        }

        DDLogInfo("KeyStore/uploadMoreOneTimePreKeys")
        isOneTimePreKeyUploadInProgress = true
        UserDefaults.shared.set(true, forKey: userDefaultsKeyForOneTimePreKeys)

        keyStore.performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }
            guard let userKeyBundle = self.keyStore.keyBundle(in: managedObjectContext) else {
                DDLogError("KeyStore/uploadMoreOneTimePreKeys/error [noKeysFound]")
                return
            }

            let generatedOTPKeys = self.generateOneTimePreKeys(initialCounter: userKeyBundle.oneTimePreKeysCounter)

            self.saveOneTimePreKeys(generatedOTPKeys) { saveSuccess in
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
                        UserDefaults.shared.set(false, forKey: self.userDefaultsKeyForOneTimePreKeys)
                    case .failure(let error):
                        DDLogError("KeyStore/uploadMoreOneTimePreKeys/error \(error)")
                    }
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

        if let lastVerificationDate = AppContextCommon.shared.userDefaults.object(forKey: UserDefaultsKey.identityKeyVerificationDate) as? Date,
           lastVerificationDate.advanced(by: oneDay) > Date()
        {
            DDLogInfo("KeyData/verifyIdentityKey/skipping [last verified: \(lastVerificationDate)]")
            return
        }

        keyStore.performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }
            guard let savedIdentityKey = self.keyStore.keyBundle(in: managedObjectContext)?.identityPublicEdKey else {
                self.didFailIdentityKeyVerification(with: .identityKeyMissing)
                return
            }

            self.isVerifyingIdentityKey = true
            self.service.requestWhisperKeyBundle(userID: self.userData.userId) { result in
                switch result {
                case .failure(let error):
                    DDLogError("KeyData/verifyIdentityKey/error [\(error)]")
                case .success(let bundle):
                    if bundle.identity == savedIdentityKey {
                        DDLogError("KeyData/verifyIdentityKey/success")
                        AppContextCommon.shared.userDefaults.setValue(Date(), forKey: UserDefaultsKey.identityKeyVerificationDate)
                    } else {
                        DDLogInfo("KeyData/verifyIdentityKey/identityKeyMismatch: saved: \(savedIdentityKey.bytes), received:\(bundle.identity.bytes)")
                        self.didFailIdentityKeyVerification(with: .identityKeyMismatch)
                    }
                }
                self.isVerifyingIdentityKey = false
            }
        }
    }

    private func didFailIdentityKeyVerification(with error: KeyDataError) {
        DDLogError("KeyData/didFailIdentityKeyVerification [\(error)]")
        AppContextCommon.shared.errorLogger?.logError(error)

        userData.performSeriallyOnBackgroundContext { managedObjectContext in
            self.userData.logout(using: managedObjectContext)
        }
    }
}

extension KeyData: ServiceKeyDelegate {
    public func service(_ service: CoreServiceCommon, didReceiveWhisperMessage message: WhisperMessage) {
        DDLogInfo("KeyData/didReceiveWhisperMessage \(message)")
        switch message {
        case .update(let uid, let identityKey):
            // We might have already processed this update using the notification extension.
            // Use the identity-key to deduplicate these messages.
            // Server sends these messages only on re-registration (which basically means a new identity key).
            self.keyStore.performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
                guard let self = self else { return }
                if let keyBundle = self.keyStore.messageKeyBundle(for: uid, in: managedObjectContext) {
                    if keyBundle.inboundIdentityPublicEdKey != identityKey {
                        DDLogInfo("KeyData/didReceiveWhisperMessage \(message)/new identity key/clear old key bundle.")
                        self.keyStore.deleteMessageKeyBundles(for: uid)
                    } else {
                        DDLogInfo("KeyData/didReceiveWhisperMessage \(message)/skip - already on the latest identity key.")
                    }
                }
            }
        case .count(let otpKeyCountNum):
            self.uploadMoreOTPKeysIfNeeded(currentNum: otpKeyCountNum)
        }
        // Nothing special to do for group e2e keys here.
        // We wait for them to resend their own senderState and we then discard what we have.
    }

    public func service(_ service: CoreServiceCommon, didReceiveRerequestWithRerequestCount rerequestCount: Int) {
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
