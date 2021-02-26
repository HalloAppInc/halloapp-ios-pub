//
//  HalloApp
//
//  Created by Tony Jiang on 7/15/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import CoreData
import CryptoKit
import CryptoSwift
import Foundation
import Sodium

// Add new error cases at the end (the index is used as the error code)
public enum DecryptionError: String, Error {
    case aesError
    case deserialization
    case hmacMismatch
    case invalidMessageKey
    case invalidPayload
    case keyGenerationFailure
    case masterKeyComputation
    case missingMessageKey
    case missingOneTimeKey
    case missingPublicKey
    case missingSignedPreKey
    case missingUserKeys
    case plaintextMismatch
    case ratchetFailure
    case x25519Conversion
}

// Add new error cases at the end (the index is used as the error code)
public enum EncryptionError: String, Error {
    case aesError
    case hmacError
    case missingKeyBundle
    case ratchetFailure
    case serialization
}

open class KeyStore {
    public let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.keys")
    public let userData: UserData
    
    private var bgContext: NSManagedObjectContext
    
    required public init(userData: UserData) {
        self.userData = userData
        self.bgContext = persistentContainer.newBackgroundContext()
    }
    
    // MARK: CoreData stack
    
    private class var persistentStoreURL: URL {
        get {
            return AppContext.keyStoreURL
        }
    }
    
    private func loadPersistentStores(in persistentContainer: NSPersistentContainer) {
        persistentContainer.loadPersistentStores { (description, error) in
            if let error = error {
                DDLogError("Failed to load persistent store: \(error)")
                DDLogError("Deleting persistent store at [\(KeyStore.persistentStoreURL.absoluteString)]")
                try! FileManager.default.removeItem(at: KeyStore.persistentStoreURL)
                fatalError("Unable to load persistent store: \(error)")
            } else {
                DDLogInfo("KeyStore/load-store/completed [\(description)]")
            }
        }
    }
    
    public private(set) var persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: KeyStore.persistentStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let modelURL = Bundle(for: KeyStore.self).url(forResource: "Keys", withExtension: "momd")!
        let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL)
        let container = NSPersistentContainer(name: "Keys", managedObjectModel: managedObjectModel!)
        container.persistentStoreDescriptions = [storeDescription]
        container.loadPersistentStores { (description, error) in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        return container
    }()
    
    private func loadPersistentContainer() {
        let container = self.persistentContainer
        DDLogDebug("KeyStore/loadPersistentStore Loaded [\(container)]")
    }
    
    public func performSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        backgroundProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            self.bgContext.performAndWait { block(self.bgContext) }
        }
    }
        
    public var viewContext: NSManagedObjectContext {
        get {
            self.persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
            return self.persistentContainer.viewContext
        }
    }
    
    public func save(_ managedObjectContext: NSManagedObjectContext) {
        DDLogVerbose("KeyStore/will-save")
        do {
            try managedObjectContext.save()
            DDLogVerbose("KeyStore/did-save")
        } catch {
            DDLogError("KeyStore/save-error error=[\(error)]")
        }
    }
    
    // MARK: Fetching

    public func keyBundles(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext? = nil) -> [UserKeyBundle] {
        let managedObjectContext = managedObjectContext ?? self.viewContext
        let fetchRequest: NSFetchRequest<UserKeyBundle> = UserKeyBundle.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let keyBundles = try managedObjectContext.fetch(fetchRequest)
            return keyBundles
        }
        catch {
            DDLogError("KeyStore/fetchUserKeyBundle/error  [\(error)]")
            fatalError("Failed to fetch key bundle")
        }
    }
    
    public func keyBundle(in managedObjectContext: NSManagedObjectContext? = nil) -> UserKeyBundle? {
        DDLogDebug("KeyStore/fetchUserKeyBundle")
        return self.keyBundles(in: managedObjectContext).first
    }
 
    public func messageKeyBundles(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext? = nil) -> [MessageKeyBundle] {
        let managedObjectContext = managedObjectContext ?? self.viewContext
        let fetchRequest: NSFetchRequest<MessageKeyBundle> = MessageKeyBundle.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false
        
        do {
            let keyBundles = try managedObjectContext.fetch(fetchRequest)
            return keyBundles
        }
        catch {
            DDLogError("KeyStore/fetch-keyBundle/error  [\(error)]")
            fatalError("Failed to fetch key bundle")
        }
    }
    
    public func messageKeyBundle(for userId: UserID, in managedObjectContext: NSManagedObjectContext? = nil) -> MessageKeyBundle? {
        return self.messageKeyBundles(predicate: NSPredicate(format: "userId == %@", userId), in: managedObjectContext).first
    }
    
    public func messageKey(for userId: UserID, eId: Int32, iId: Int32, in managedObjectContext: NSManagedObjectContext? = nil) -> Data? {
        guard let messageKeyBundle = self.messageKeyBundle(for: userId, in: managedObjectContext) else { return nil }
        guard let messageKeys = messageKeyBundle.messageKeys else { return nil }
        for messageKey in messageKeys {
            if messageKey.ephemeralKeyId == eId && messageKey.chainIndex == iId {
                return messageKey.key
            }
        }
        
        return nil
    }
   
    // MARK: Updating

    struct MessageKeyData {
        var ephemeralKeyID: Int32
        var chainIndex: Int32
        var data: Data
    }

    private func addMessageKeys(_ keys: [MessageKeyData], for userID: UserID) {
        guard !keys.isEmpty else {
            DDLogInfo("KeyStore/addMessageKeys/\(userID)/skipping (no keys)")
            return
        }

        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let messageKeyBundle = self.messageKeyBundle(for: userID, in: managedObjectContext) else {
                DDLogError("KeyStore/addMessageKeys/\(userID)/error bundle not found")
                return
            }

            let ephemeralKeyIDs = keys.map { $0.ephemeralKeyID }
            let chainIndices = keys.map { $0.chainIndex }
            if let eID = ephemeralKeyIDs.first, let maxChainIndex = chainIndices.max(), Set(ephemeralKeyIDs).count == 1 {
                DDLogInfo("KeyStore/addMessageKeys/\(userID)/adding \(keys.count) keys [eID=\(eID)] [maxChainIndex=\(maxChainIndex)]")
            } else {
                DDLogInfo("KeyStore/addMessageKeys/\(userID)/adding \(keys.count) keys to \(ephemeralKeyIDs.count) eIDs")
            }

            for keyData in keys {
                let messageKey = NSEntityDescription.insertNewObject(forEntityName: MessageKey.entity().name!, into: managedObjectContext) as! MessageKey
                messageKey.ephemeralKeyId = keyData.ephemeralKeyID
                messageKey.chainIndex = keyData.chainIndex
                messageKey.messageKeyBundle = messageKeyBundle
            }

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    // MARK: Deleting
   
    public func deleteUserKeyBundles() {
        DDLogInfo("KeyStore/deleteUserKeyBundles")
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let fetchRequest = NSFetchRequest<UserKeyBundle>(entityName: UserKeyBundle.entity().name!)
            do {
                let userKeyBundles = try managedObjectContext.fetch(fetchRequest)
                DDLogInfo("KeyStore/deleteUserKeyBundles/begin count=[\(userKeyBundles.count)]")
                userKeyBundles.forEach {
  
                    $0.signedPreKeys.forEach { (signedPreKey) in
                        managedObjectContext.delete(signedPreKey)
                    }
                    $0.oneTimePreKeys?.forEach { (oneTimePreKey) in
                        managedObjectContext.delete(oneTimePreKey)
                    }
                    managedObjectContext.delete($0)
                }
                DDLogInfo("KeyStore/deleteUserKeyBundles/finished")
            }
            catch {
                DDLogError("KeyStore/deleteUserKeyBundles/error  [\(error)]")
                return
            }
            self.save(managedObjectContext)
        }
    }

    /// Note: must be called on background processing queue!
    private func deleteUserOneTimePreKey(oneTimeKeyId: Int) {
        DDLogInfo("KeyStore/deleteUserOneTimePreKey/id/\(oneTimeKeyId)")
        bgContext.performAndWait {
            let fetchRequest = NSFetchRequest<UserKeyBundle>(entityName: UserKeyBundle.entity().name!)
            do {
                let userKeyBundles = try bgContext.fetch(fetchRequest)
                userKeyBundles.forEach {
                    guard let oneTimePreKeys = $0.oneTimePreKeys else {
                        DDLogInfo("KeyStore/deleteUserOneTimePreKey/no oneTimePreKeys found")
                        return
                    }
                    for oneTimeKey in oneTimePreKeys {
                        if oneTimeKey.id == oneTimeKeyId {
                            DDLogInfo("KeyStore/deleteUserOneTimePreKey/delete/id/\(oneTimeKeyId)")
                            bgContext.delete(oneTimeKey)
                            break
                        }
                    }
                }
                DDLogInfo("KeyStore/deleteUserOneTimePreKey/finished")
            }
            catch {
                DDLogError("KeyStore/deleteUserOneTimePreKey/error  [\(error)]")
                return
            }
            if self.bgContext.hasChanges {
                self.save(bgContext)
            }
        }
    }
    
    public func deleteMessageKeyBundles(for userId: UserID) {
        DDLogInfo("KeyStore/deleteMessageKeyBundles/forUser: \(userId)")
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let fetchRequest = NSFetchRequest<MessageKeyBundle>(entityName: MessageKeyBundle.entity().name!)
            fetchRequest.predicate = NSPredicate(format: "userId = %@", userId)
            do {
                let messageKeyBundles = try managedObjectContext.fetch(fetchRequest)
                DDLogInfo("KeyStore/deleteMessageKeyBundles count=[\(messageKeyBundles.count)]")
                messageKeyBundles.forEach {
                    $0.messageKeys?.forEach { (msgKey) in
                        managedObjectContext.delete(msgKey)
                    }
                    managedObjectContext.delete($0)
                }
            }
            catch {
                DDLogError("KeyStore/deleteMessageKeyBundles/error  [\(error)]")
                return
            }
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    public func deleteMessageKey(for userId: UserID, eId: Int32, iId: Int32) {
        DDLogInfo("KeyStore/deleteMessageKey")
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let fetchRequest = NSFetchRequest<MessageKeyBundle>(entityName: MessageKeyBundle.entity().name!)
            fetchRequest.predicate = NSPredicate(format: "userId = %@", userId)
            do {
                let messageKeyBundles = try managedObjectContext.fetch(fetchRequest)
                DDLogInfo("KeyStore/deleteMessageKey count=[\(messageKeyBundles.count)]")
                messageKeyBundles.forEach {
                    $0.messageKeys?.forEach { (msgKey) in
                        if msgKey.ephemeralKeyId == eId && msgKey.chainIndex == iId {
                            managedObjectContext.delete(msgKey)
                        }
                    }
                    managedObjectContext.delete($0)
                }
            }
            catch {
                DDLogError("KeyStore/deleteMessageKey/error  [\(error)]")
                return
            }
            self.save(managedObjectContext)
        }
    }

    // whenever a new keybundle is uploaded, all current message bundles should be deleted
    public func deleteAllMessageKeyBundles() {
        DDLogInfo("KeyStore/deleteAllMessageKeyBundles")
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let fetchRequest = NSFetchRequest<MessageKeyBundle>(entityName: MessageKeyBundle.entity().name!)
            do {
                let messageKeyBundles = try managedObjectContext.fetch(fetchRequest)
                DDLogInfo("KeyStore/deleteAllMessageKeyBundles count=[\(messageKeyBundles.count)]")
                messageKeyBundles.forEach {
                    $0.messageKeys?.forEach { (msgKey) in
                        managedObjectContext.delete(msgKey)
                    }
                    managedObjectContext.delete($0)
                }
            }
            catch {
                DDLogError("KeyStore/deleteAllMessageKeyBundles/error  [\(error)]")
                return
            }
            self.save(managedObjectContext)
        }
    }
    
}

extension KeyStore {
    
    public func initiateSessionSetup(for targetUserId: UserID, with targetUserWhisperKeys: WhisperKeyBundle) -> KeyBundle? {
        DDLogInfo("KeyStore/initiateSessionSetup \(targetUserId)")
        
        guard let myKeys = self.keyBundle() else {
            DDLogInfo("KeyStore/initiateSessionSetup/missingMyKeyBundle")
            return nil
        }
        
        let sodium = Sodium()
        
        // generate new key pair
        guard let newKeyPair = sodium.box.keyPair() else {
            DDLogInfo("KeyStore/initiateSessionSetup/keyPairGenerationFailed")
            return nil
        }
        
        let outboundIdentityPrivateKey = myKeys.identityPrivateKey                              // I_initiator
        
        let outboundEphemeralPublicKey = Data(newKeyPair.publicKey)
        let outboundEphemeralPrivateKey = Data(newKeyPair.secretKey)                            // E_initiator
        
        let inboundIdentityPublicEdKey = targetUserWhisperKeys.identity

        guard let inboundIdentityPublicKeyUInt8 = sodium.sign.convertToX25519PublicKey(publicKey: [UInt8](inboundIdentityPublicEdKey)) else {
            DDLogInfo("KeyStore/initiateSessionSetup/x25519conversionFailed")
            return nil
        }

        let inboundIdentityPublicKey = Data(inboundIdentityPublicKeyUInt8)                      // I_recipient

        let targetUserSigned = targetUserWhisperKeys.signedPreKey
        let inboundSignedPrePublicKey = targetUserSigned.key.publicKey                              // S_recipient
        let signature = targetUserSigned.signature
        
        guard sodium.sign.verify(message: [UInt8](inboundSignedPrePublicKey), publicKey: [UInt8](inboundIdentityPublicEdKey), signature: [UInt8](signature)) else {
            DDLogInfo("KeyStore/initiateSessionSetup/invalidSignature")
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
            DDLogDebug("KeyStore/initiateSessionSetup/invalidMasterKey")
            return nil
        }
        
        let rootKey = masterKey.rootKey
        let outboundChainKey = masterKey.firstChainKey
        let inboundChainKey = masterKey.secondChainKey
        
        // attributes for initiating sessions
        let outboundIdentityPublicEdKey = myKeys.identityPublicEdKey
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
                                  outboundOneTimePreKeyId: outboundOneTimePreKeyId)
        saveKeyBundle(keyBundle)

        return keyBundle
    }

    private func ephemeralPublicKey(in encryptedPayload: Data) -> Data? {
        guard encryptedPayload.count >= 32 else { return nil }
        return encryptedPayload[0...31]
    }

    /// Note: must be called on background processing queue!
    private func receiveSessionSetup(for userId: UserID, from encryptedPayload: Data, publicKey inboundIdentityPublicEdKey: Data, oneTimeKeyID: Int?) -> Result<KeyBundle, DecryptionError> {
        DDLogInfo("KeyStore/receiveSessionSetup \(userId)")
        let sodium = Sodium()

        let inboundOneTimePreKeyId = oneTimeKeyID ?? -1
        
        guard let x25519Key = sodium.sign.convertToX25519PublicKey(publicKey: [UInt8](inboundIdentityPublicEdKey)) else {
            DDLogError("KeyStore/receiveSessionSetup/error X25519 conversion error")
            DDLogInfo("Inbound Key: \(inboundIdentityPublicEdKey)")
            return .failure(.x25519Conversion)
        }
        let I_initiator = Data(x25519Key)
        
        let inboundEphemeralPublicKey = encryptedPayload[0...31]
        let inboundEphemeralKeyId = encryptedPayload[32...35]
        
        //TODO: could remove these, need to test
        let inboundPreviousChainLength = encryptedPayload[36...39]
        let inboundChainIndex = encryptedPayload[40...43]
        
        let inboundEphemeralKeyIdInt = Int32(bigEndian: inboundEphemeralKeyId.withUnsafeBytes { $0.load(as: Int32.self) })
        let inboundPreviousChainLengthInt = Int32(bigEndian: inboundPreviousChainLength.withUnsafeBytes { $0.load(as: Int32.self) })
        let inboundChainIndexInt = Int32(bigEndian: inboundChainIndex.withUnsafeBytes { $0.load(as: Int32.self) })
        
        guard let userKeyBundle = self.keyBundle() else { return .failure(.missingUserKeys) }
        let signedPreKeys = userKeyBundle.signedPreKeys
        guard let signedPreKey = signedPreKeys.first(where: {$0.id == 1}) else { return .failure(.missingSignedPreKey) }
        
        var O_recipient: Data? = nil
        
        if inboundOneTimePreKeyId >= 0 {
            guard let oneTimePreKeys = userKeyBundle.oneTimePreKeys else {
                return .failure(.missingOneTimeKey)
            }
            guard let oneTimePreKey = oneTimePreKeys.first(where: {$0.id == inboundOneTimePreKeyId}) else {
                DDLogError("KeyStore/receiveSessionSetup/missingOneTimeKey [\(inboundOneTimePreKeyId)]")
                return .failure(.missingOneTimeKey)
            }
            O_recipient = oneTimePreKey.privateKey
        }
        
        let E_initiator = inboundEphemeralPublicKey
        let S_recipient = signedPreKey.privateKey
        let I_recipient = userKeyBundle.identityPrivateKey
        
        guard let masterKey = computeMasterKey(isInitiator: false,
                                               initiatorIdentityKey: I_initiator,
                                               initiatorEphemeralKey: E_initiator,
                                               recipientIdentityKey: I_recipient,
                                               recipientSignedPreKey: S_recipient,
                                               recipientOneTimePreKey: O_recipient) else
        {
            DDLogError("KeyStore/receiveSessionSetup/invalidMasterKey")
            return .failure(.masterKeyComputation)
        }
        
        var rootKey = masterKey.rootKey
        let inboundChainKey = masterKey.firstChainKey
        var outboundChainKey = masterKey.secondChainKey
        
        // generate new Ephemeral key and update root + outboundChainKey
        guard let outboundEphemeralKeyPair = sodium.box.keyPair() else { return .failure(.keyGenerationFailure) }
        let outboundEphemeralPrivateKey = Data(outboundEphemeralKeyPair.secretKey)
        let outboundEphemeralPublicKey = Data(outboundEphemeralKeyPair.publicKey)
        
        guard let outboundAsymmetricRachet = self.asymmetricRachet(privateKey: Data(outboundEphemeralKeyPair.secretKey), publicKey: Data(inboundEphemeralPublicKey), rootKey: rootKey) else {
            return .failure(.ratchetFailure)
        }
        rootKey = outboundAsymmetricRachet.updatedRootKey
        outboundChainKey = outboundAsymmetricRachet.updatedChainKey
        
        if inboundOneTimePreKeyId >= 0 {
            // delete the prekey once used
            self.deleteUserOneTimePreKey(oneTimeKeyId: inboundOneTimePreKeyId)
        }

        let keyBundle = KeyBundle(userId: userId,
                                  inboundIdentityPublicEdKey: inboundIdentityPublicEdKey,
                                  
                                  inboundEphemeralPublicKey: Data(inboundEphemeralPublicKey),
                                  inboundEphemeralKeyId: Int32(inboundEphemeralKeyIdInt),
                                  inboundChainKey: Data(inboundChainKey),
                                  inboundPreviousChainLength: Int32(inboundPreviousChainLengthInt),
                                  inboundChainIndex: Int32(inboundChainIndexInt),
                                  
                                  rootKey: Data(rootKey),
                                  
                                  outboundEphemeralPrivateKey: outboundEphemeralPrivateKey,
                                  outboundEphemeralPublicKey: outboundEphemeralPublicKey,
                                  outboundEphemeralKeyId: 1,
                                  outboundChainKey: Data(outboundChainKey),
                                  outboundPreviousChainLength: 0,
                                  outboundChainIndex: 0)
        saveKeyBundle(keyBundle)

        return .success(keyBundle)
    }

    private func saveKeyBundle(_ keyBundle: KeyBundle) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let messageKeyBundle = NSEntityDescription.insertNewObject(forEntityName: MessageKeyBundle.entity().name!, into: managedObjectContext) as! MessageKeyBundle
            messageKeyBundle.userId = keyBundle.userId
            messageKeyBundle.inboundIdentityPublicEdKey = keyBundle.inboundIdentityPublicEdKey

            messageKeyBundle.inboundEphemeralPublicKey = keyBundle.inboundEphemeralPublicKey
            messageKeyBundle.inboundEphemeralKeyId = keyBundle.inboundEphemeralKeyId
            messageKeyBundle.inboundChainKey = keyBundle.inboundChainKey
            messageKeyBundle.inboundPreviousChainLength = keyBundle.inboundPreviousChainLength
            messageKeyBundle.inboundChainIndex = keyBundle.inboundChainIndex

            messageKeyBundle.rootKey = keyBundle.rootKey

            messageKeyBundle.outboundEphemeralPrivateKey = keyBundle.outboundEphemeralPrivateKey
            messageKeyBundle.outboundEphemeralPublicKey = keyBundle.outboundEphemeralPublicKey
            messageKeyBundle.outboundEphemeralKeyId = keyBundle.outboundEphemeralKeyId
            messageKeyBundle.outboundChainKey = keyBundle.outboundChainKey
            messageKeyBundle.outboundPreviousChainLength = keyBundle.outboundPreviousChainLength
            messageKeyBundle.outboundChainIndex = keyBundle.outboundChainIndex

            messageKeyBundle.outboundIdentityPublicEdKey = keyBundle.outboundIdentityPublicEdKey
            messageKeyBundle.outboundOneTimePreKeyId = keyBundle.outboundOneTimePreKeyId

            self.save(managedObjectContext)
        }
    }

    /// Note: must be called on background processing queue!
    private func encryptMessage(for userId: String, unencrypted: Data, keyBundle: KeyBundle) -> Result<Data, EncryptionError> {
        DDLogInfo("KeyStore/encryptMessage/for \(userId)")
        
        // get outbound data
        let outboundEphemeralPublicKey          = keyBundle.outboundEphemeralPublicKey
        let outboundEphemeralKeyId: Int32       = keyBundle.outboundEphemeralKeyId      // shouldn't be any changes
        var outboundChainKey                    = [UInt8](keyBundle.outboundChainKey)
        let outboundPreviousChainLength: Int32  = keyBundle.outboundPreviousChainLength // shouldn't be any changes
        let outboundChainIndex: Int32           = keyBundle.outboundChainIndex
        
        let outboundEphemeralKeyIdData          = withUnsafeBytes(of: outboundEphemeralKeyId.bigEndian) { Data($0) }
        let outboundPreviousChainLengthData     = withUnsafeBytes(of: outboundPreviousChainLength.bigEndian) { Data($0) }
        let outboundChainIndexData              = withUnsafeBytes(of: outboundChainIndex.bigEndian) { Data($0) }
        
        var messageKey: [UInt8] = []
        
        guard let symmetricRachet = self.symmetricRachet(chainKey: outboundChainKey) else { return .failure(.ratchetFailure) }
        messageKey = symmetricRachet.messageKey
        outboundChainKey = symmetricRachet.updatedChainKey
        
        let AESKey = Array(messageKey[0...31])
        let HMACKey = Array(messageKey[32...63])
        let IV = Array(messageKey[64...79])

        guard let encrypted = try? AES(key: AESKey, blockMode: CBC(iv: IV), padding: .pkcs7).encrypt(Array(unencrypted)) else {
            return .failure(.aesError)
        }

        guard let HMAC = try? CryptoSwift.HMAC(key: HMACKey, variant: .sha256).authenticate([UInt8](encrypted)) else {
            return .failure(.hmacError)
        }

        var data = outboundEphemeralPublicKey
        data += outboundEphemeralKeyIdData
        data += outboundPreviousChainLengthData
        data += outboundChainIndexData
        data += encrypted
        data += HMAC

        DDLogDebug("KeyStore/encryptMessage/outboundEphemeralKey:            \([UInt8](outboundEphemeralPublicKey))")
        DDLogDebug("KeyStore/encryptMessage/outboundEphemeralKeyIdData:      \([UInt8](outboundEphemeralKeyIdData))")
        DDLogDebug("KeyStore/encryptMessage/outboundPreviousChainLengthData: \([UInt8](outboundPreviousChainLengthData))")
        DDLogDebug("KeyStore/encryptMessage/outboundChainIndexData:          \([UInt8](outboundChainIndexData))")

        bgContext.performAndWait {
            if let messageKeyBundle = self.messageKeyBundle(for: userId, in: bgContext) {
                messageKeyBundle.outboundChainKey = Data(outboundChainKey)
                messageKeyBundle.outboundChainIndex = outboundChainIndex + 1
            }
            self.save(bgContext)
        }

        return .success(data)
    }

    public func decryptMessage(for userId: String, encryptedPayload: Data, keyBundle: KeyBundle, isNewReceiveSession: Bool) -> Result<Data, DecryptionError> {

        // 44 byte header + 32 byte HMAC
        guard encryptedPayload.count >= 76 else {
            DDLogError("KeyStore/decryptMessage/error encryptedPayload too small [\(encryptedPayload.count)]")
            return .failure(.invalidPayload)
        }

        let inboundEphemeralPublicKey = encryptedPayload[0...31]
        let inboundEphemeralKeyId = encryptedPayload[32...35]
        let inboundPreviousChainLength = encryptedPayload[36...39]
        let inboundChainIndex = encryptedPayload[40...43]
        
        let inboundEphemeralKeyIdInt = Int32(bigEndian: inboundEphemeralKeyId.withUnsafeBytes { $0.load(as: Int32.self) })
        let inboundPreviousChainLengthInt = Int32(bigEndian: inboundPreviousChainLength.withUnsafeBytes { $0.load(as: Int32.self) })
        let inboundChainIndexInt = Int32(bigEndian: inboundChainIndex.withUnsafeBytes { $0.load(as: Int32.self) })
        
        let encryptedPayloadWithoutHeader = encryptedPayload.dropFirst(44)
        let inboundHMAC = encryptedPayloadWithoutHeader.suffix(32)
        let encryptedMessage = encryptedPayloadWithoutHeader.dropLast(32)
        
        DDLogDebug("KeyStore/decryptMessage/user/\(userId)/inboundEphemeralPublicKey:   \([UInt8](inboundEphemeralPublicKey))")
        DDLogDebug("KeyStore/decryptMessage/user/\(userId)/inboundEphemeralKeyId:       \([UInt8](inboundEphemeralKeyId))")
        DDLogDebug("KeyStore/decryptMessage/user/\(userId)/previousChainLengthInt:      \([UInt8](inboundPreviousChainLength))")
        DDLogDebug("KeyStore/decryptMessage/user/\(userId)/inboundChainIndexInt:        \([UInt8](inboundChainIndex))")
        
        var rootKey = [UInt8](keyBundle.rootKey)
        var inboundChainKey = [UInt8](keyBundle.inboundChainKey)
        
        let savedInboundEphemeralKeyId = keyBundle.inboundEphemeralKeyId
        var savedInboundChainIndex = keyBundle.inboundChainIndex
//        let savedInboundPreviousChainLength = keyBundle.inboundPreviousChainLength

        DDLogInfo("KeyStore/decryptMessage/user/\(userId)/savedInboundEphemeralKeyId \(savedInboundEphemeralKeyId)")

        // only for saving
        var outboundChainKey = [UInt8](keyBundle.outboundChainKey)
        var outboundEphemeralPrivateKey = keyBundle.outboundEphemeralPrivateKey
        var outboundEphemeralPublicKey = keyBundle.outboundEphemeralPublicKey
        var outboundEphemeralKeyId = keyBundle.outboundEphemeralKeyId
        
        var outboundIdentityPublicEdKey = keyBundle.outboundIdentityPublicEdKey
        var outboundOneTimePreKeyId = keyBundle.outboundOneTimePreKeyId
        var outboundPreviousChainLength = keyBundle.outboundPreviousChainLength
        var outboundChainIndex = keyBundle.outboundChainIndex
        
        /*TODO: Begin section needs refactoring */
        var messageKey: [UInt8] = []
        var isOutOfOrderMessage = false
        
        if ((savedInboundEphemeralKeyId != -1) && ((savedInboundEphemeralKeyId - 1) == inboundEphemeralKeyIdInt)) {
            isOutOfOrderMessage = true
            guard let msgKey = self.messageKey(for: userId, eId: inboundEphemeralKeyIdInt, iId: inboundChainIndexInt) else {
                DDLogInfo("KeyStore/decryptMessage/isOutOfOrderMessage/priorEphemeralKeyId/can't find messageKey")
                return .failure(.missingMessageKey)
            }
            messageKey = [UInt8](msgKey)
            self.deleteMessageKey(for: userId, eId: inboundEphemeralKeyIdInt, iId: inboundChainIndexInt)
        }
        if ((savedInboundEphemeralKeyId == inboundEphemeralKeyIdInt) && (savedInboundChainIndex > inboundChainIndexInt )) {
            isOutOfOrderMessage = true
            guard let msgKey = self.messageKey(for: userId, eId: inboundEphemeralKeyIdInt, iId: inboundChainIndexInt) else {
                DDLogInfo("KeyStore/decryptMessage/isOutOfOrderMessage/priorChainIndex/can't find messageKey")
                return .failure(.missingMessageKey)
            }
            messageKey = [UInt8](msgKey)
            self.deleteMessageKey(for: userId, eId: inboundEphemeralKeyIdInt, iId: inboundChainIndexInt)
        }
        
        
        if !isOutOfOrderMessage {
            if isNewReceiveSession {
                DDLogInfo("KeyStore/decryptMessage/newReceiveSessionSetup")
                savedInboundChainIndex = -1
            } else if ((savedInboundEphemeralKeyId == -1) || (savedInboundEphemeralKeyId < inboundEphemeralKeyIdInt)) {
                DDLogInfo("KeyStore/decryptMessage/newEphermeralKey")
                let sodium = Sodium()
                
                let inboundPreviousChainIndex = inboundPreviousChainLengthInt - 1
                if savedInboundChainIndex < inboundPreviousChainIndex {
                    DDLogInfo("KeyStore/decryptMessage/newEphermeralKey/catchup")
                    var catchupChainIndex = savedInboundChainIndex
                    var newKeys = [MessageKeyData]()
                    
                    while catchupChainIndex < inboundPreviousChainIndex {
                        DDLogInfo("KeyStore/decryptMessage/newEphermeralKey/catchup/index \(catchupChainIndex)")
                        guard let symmetricRachet = self.symmetricRachet(chainKey: inboundChainKey) else { return .failure(.ratchetFailure) }
                        messageKey = symmetricRachet.messageKey
                        inboundChainKey = symmetricRachet.updatedChainKey
                        
                        let newKey = MessageKeyData(
                            ephemeralKeyID: savedInboundEphemeralKeyId,
                            chainIndex: catchupChainIndex,
                            data: Data(messageKey))
                        newKeys.append(newKey)

                        catchupChainIndex += 1
                    }
                    addMessageKeys(newKeys, for: userId)
                }
                
                guard let inboundAsymmetricRachet = self.asymmetricRachet(privateKey: keyBundle.outboundEphemeralPrivateKey, publicKey: Data(inboundEphemeralPublicKey), rootKey: rootKey) else { return .failure(.ratchetFailure) }
                rootKey = inboundAsymmetricRachet.updatedRootKey
                inboundChainKey = inboundAsymmetricRachet.updatedChainKey
                
                savedInboundChainIndex = -1
                
                // generate new key pair and update outbound key
                guard let newOutboundEphemeralKeyPair = sodium.box.keyPair() else { return .failure(.keyGenerationFailure) }
                outboundEphemeralPrivateKey = Data(newOutboundEphemeralKeyPair.secretKey)
                outboundEphemeralPublicKey = Data(newOutboundEphemeralKeyPair.publicKey)
                outboundEphemeralKeyId += 1
                
                guard let outboundAsymmetricRachet = self.asymmetricRachet(privateKey: outboundEphemeralPrivateKey, publicKey: Data(inboundEphemeralPublicKey), rootKey: rootKey) else { return .failure(.ratchetFailure) }
                rootKey = outboundAsymmetricRachet.updatedRootKey
                outboundChainKey = outboundAsymmetricRachet.updatedChainKey
                
                outboundPreviousChainLength = outboundChainIndex // save previousChainLength before updating index
                outboundChainIndex = 0
                
                // once a message is received, there's no need to send these anymore
                outboundIdentityPublicEdKey = nil
                outboundOneTimePreKeyId = -1
            }

            var newKeys = [MessageKeyData]()

            DDLogInfo("KeyStore/decryptMessage/symmetricRachet/begin [\(savedInboundChainIndex)]")
            while savedInboundChainIndex < inboundChainIndexInt {
                guard let symmetricRachet = self.symmetricRachet(chainKey: inboundChainKey) else {
                    DDLogError("KeyStore/decryptMessage/symmetricRachet/error [\(savedInboundChainIndex)]")
                    return .failure(.ratchetFailure)
                }
                messageKey = symmetricRachet.messageKey
                inboundChainKey = symmetricRachet.updatedChainKey
                
                savedInboundChainIndex += 1
                
                if savedInboundChainIndex != inboundChainIndexInt {
                    let newKey = MessageKeyData(
                        ephemeralKeyID: inboundEphemeralKeyIdInt,
                        chainIndex: savedInboundChainIndex,
                        data: Data(messageKey))
                    newKeys.append(newKey)
                }
            }
            DDLogInfo("KeyStore/decryptMessage/symmetricRachet/finished [\(savedInboundChainIndex)]")
            addMessageKeys(newKeys, for: userId)
        }
        
        /*TODO: End section needs refactoring */

        guard !messageKey.isEmpty else {
            DDLogError("KeyStore/decryptMessage/missingMessageKey [no ratchet?]")
            return .failure(.missingMessageKey)
        }

        // 32 byte AES + 32 byte HMAC + 16 byte IV
        guard messageKey.count >= 80 else {
            DDLogError("KeyStore/decryptMessage/invalidMessageKey [\(messageKey.count) bytes]")
            return .failure(.invalidMessageKey)
        }
        
        let AESKey = Array(messageKey[0...31])
        let HMACKey = Array(messageKey[32...63])
        let IV = Array(messageKey[64...79])
        let calculatedHMAC = try! CryptoSwift.HMAC(key: HMACKey, variant: .sha256).authenticate([UInt8](encryptedMessage))
        
        guard [UInt8](inboundHMAC) == calculatedHMAC else {
            DDLogError("KeyStore/decryptMessage/hmacMismatch")
            DDLogInfo("Computed HMAC: \(calculatedHMAC)")
            DDLogInfo(" Inbound HMAC: \([UInt8](inboundHMAC))")
            DDLogInfo("  Message Key: \(messageKey)")
            return .failure(.hmacMismatch)
        }
        
        do {
            let decrypted = try AES(key: AESKey, blockMode: CBC(iv: IV), padding: .pkcs7).decrypt(Array(encryptedMessage))
            let data = Data(decrypted)
            
            self.performSeriallyOnBackgroundContext { (managedObjectContext) in
                if let messageKeyBundle = self.messageKeyBundle(for: userId, in: managedObjectContext) {
                    DDLogInfo("KeyStore/decryptMessage/user/\(userId)/updating key bundle")
                    messageKeyBundle.inboundEphemeralPublicKey = Data(inboundEphemeralPublicKey)
                    messageKeyBundle.inboundEphemeralKeyId = Int32(inboundEphemeralKeyIdInt)
                    messageKeyBundle.inboundChainKey = Data(inboundChainKey)
                    messageKeyBundle.inboundPreviousChainLength = Int32(inboundPreviousChainLengthInt)
                    messageKeyBundle.inboundChainIndex = Int32(inboundChainIndexInt)
                    
                    messageKeyBundle.rootKey = Data(rootKey)
                    
                    messageKeyBundle.outboundEphemeralPrivateKey = outboundEphemeralPrivateKey
                    messageKeyBundle.outboundEphemeralPublicKey = outboundEphemeralPublicKey
                    messageKeyBundle.outboundEphemeralKeyId = outboundEphemeralKeyId
                    messageKeyBundle.outboundChainKey = Data(outboundChainKey)
                    messageKeyBundle.outboundPreviousChainLength = outboundPreviousChainLength
                    messageKeyBundle.outboundChainIndex = outboundChainIndex
                    
                    messageKeyBundle.outboundIdentityPublicEdKey = outboundIdentityPublicEdKey
                    messageKeyBundle.outboundOneTimePreKeyId = outboundOneTimePreKeyId
                } else {
                    DDLogError("KeyStore/decryptMessage/user/\(userId)/error no key bundle to update")
                }
                self.save(managedObjectContext)
            }
            return .success(data)
        } catch {
            DDLogError("KeyStore/decryptMessage/error \(error)")
            return .failure(.aesError)
        }
    }

    
    /**
     Public and Private Keys are reversed when computing the master key for a recipient session
     Initiator:
     ECDH(I_initiator, S_recipient) + ECDH(E_initiator, I_recipient) + ECDH(E_initiator, S_recipient) + [ECDH(E_initiator, O_recipient)]
     Recipient:
     ECDH(S_recipient, I_initiator) + ECDH(I_recipient, E_initiator) + ECDH(S_recipient, E_initiator) + [ECDH(O_recipient, E_initiator)]
     */
    private func computeMasterKey(isInitiator: Bool,
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
            DDLogInfo("KeyStore/computeMasterKey/HKDF/invalidExpandedKey")
            return nil
        }
        
        let rootKey = Array(expandedKeyBytes[0...31])
        let firstChainKey = Array(expandedKeyBytes[32...63])
        let secondChainKey = Array(expandedKeyBytes[64...95])
        
        return (rootKey, firstChainKey, secondChainKey)
    }
    
    private func symmetricRachet(chainKey: [UInt8]) -> (messageKey: [UInt8], updatedChainKey: [UInt8])? {
        let infoOne: Array<UInt8> = [0x01]
        let infoTwo: Array<UInt8> = [0x02]
        guard let messageKey = try? HKDF(password: chainKey, info: infoOne, keyLength: 80, variant: .sha256).calculate() else { return nil }
        guard let updatedChainKey = try? HKDF(password: chainKey, info: infoTwo, keyLength: 32, variant: .sha256).calculate() else { return nil }
        return (messageKey, updatedChainKey)
    }
    
    private func asymmetricRachet(privateKey: Data, publicKey: Data, rootKey: [UInt8]) -> (updatedRootKey: [UInt8], updatedChainKey: [UInt8])? {
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


public struct KeyBundle {
    public let userId: String
    public let inboundIdentityPublicEdKey: Data
    
    public let inboundEphemeralPublicKey: Data?
    public let inboundEphemeralKeyId: Int32
    public let inboundChainKey: Data
    public let inboundPreviousChainLength: Int32
    public let inboundChainIndex: Int32
    
    public let rootKey: Data
    
    public let outboundEphemeralPrivateKey: Data
    public let outboundEphemeralPublicKey: Data
    public let outboundEphemeralKeyId: Int32
    public let outboundChainKey: Data
    public let outboundPreviousChainLength: Int32
    public let outboundChainIndex: Int32
    
    public let outboundIdentityPublicEdKey: Data?
    public let outboundOneTimePreKeyId: Int32
    
    public init(
        userId: String,
        inboundIdentityPublicEdKey: Data,
        
        inboundEphemeralPublicKey: Data? = nil,
        inboundEphemeralKeyId: Int32,
        inboundChainKey: Data,
        inboundPreviousChainLength: Int32,
        inboundChainIndex: Int32,
        
        rootKey: Data,
        
        outboundEphemeralPrivateKey: Data,
        outboundEphemeralPublicKey: Data,
        outboundEphemeralKeyId: Int32,
        outboundChainKey: Data,
        outboundPreviousChainLength: Int32,
        outboundChainIndex: Int32,
        
        outboundIdentityPublicEdKey: Data? = nil,
        outboundOneTimePreKeyId: Int32 = 0
    ) {
        self.userId = userId
        self.inboundIdentityPublicEdKey = inboundIdentityPublicEdKey
        
        self.inboundEphemeralPublicKey = inboundEphemeralPublicKey
        self.inboundEphemeralKeyId = inboundEphemeralKeyId
        self.inboundChainKey = inboundChainKey
        self.inboundPreviousChainLength = inboundPreviousChainLength
        self.inboundChainIndex = inboundChainIndex
        
        self.rootKey = rootKey
        
        self.outboundEphemeralPrivateKey = outboundEphemeralPrivateKey
        self.outboundEphemeralPublicKey = outboundEphemeralPublicKey
        self.outboundEphemeralKeyId = outboundEphemeralKeyId
        self.outboundChainKey = outboundChainKey
        self.outboundPreviousChainLength = outboundPreviousChainLength
        self.outboundChainIndex = outboundChainIndex

        self.outboundIdentityPublicEdKey = outboundIdentityPublicEdKey
        self.outboundOneTimePreKeyId = outboundOneTimePreKeyId
    }
}

public extension MessageKeyBundle {
    var keyBundle: KeyBundle? {
        guard let inboundIdentityPublicEdKey = inboundIdentityPublicEdKey else {
            DDLogInfo("MessageKeyBundle/keyBundle missing inboundIdentityPublicEdKey")
            return nil
        }
        return KeyBundle(
            userId: userId,
            inboundIdentityPublicEdKey: inboundIdentityPublicEdKey,

            inboundEphemeralPublicKey: inboundEphemeralPublicKey,
            inboundEphemeralKeyId: inboundEphemeralKeyId,
            inboundChainKey: inboundChainKey,
            inboundPreviousChainLength: inboundPreviousChainLength,
            inboundChainIndex: inboundChainIndex,

            rootKey: rootKey,

            outboundEphemeralPrivateKey: outboundEphemeralPrivateKey,
            outboundEphemeralPublicKey: outboundEphemeralPublicKey,
            outboundEphemeralKeyId: outboundEphemeralKeyId,
            outboundChainKey: outboundChainKey,
            outboundPreviousChainLength: outboundPreviousChainLength,
            outboundChainIndex: outboundChainIndex,

            outboundIdentityPublicEdKey: outboundIdentityPublicEdKey,
            outboundOneTimePreKeyId: outboundOneTimePreKeyId)
    }
}

extension KeyStore {
    public func encryptOperation(for userID: UserID, with service: CoreService) -> EncryptOperation {
        return { data, completion in
            self.wrapMessage(for: userID, with: service, unencrypted: data, completion: completion)
        }
    }

    public func wrapMessage(for userId: String, with service: CoreService, unencrypted: Data, completion: @escaping (Result<EncryptedData, EncryptionError>) -> Void) {
        DDLogInfo("KeyStore/wrapMessage/user/\(userId)")
        var keyBundle: KeyBundle? = nil
        let group = DispatchGroup()
        group.enter()

        performSeriallyOnBackgroundContext { (managedObjectContext) in
            if let savedKeyBundle = self.messageKeyBundle(for: userId, in: managedObjectContext)?.keyBundle {
                keyBundle = savedKeyBundle
                group.leave()
            } else {
                service.requestWhisperKeyBundle(userID: userId) { result in
                    switch result {
                    case .success(let keys):
                        DDLogError("KeyStore/wrapMessage/user/\(userId)/requestWhisperKeys/success")
                        keyBundle = self.initiateSessionSetup(for: userId, with: keys)
                    case .failure(let error):
                        DDLogError("KeyStore/wrapMessage/user/\(userId)/requestWhisperKeys/error \(error)")
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: backgroundProcessingQueue) {
            guard let keyBundle = keyBundle else {
                completion(.failure(.missingKeyBundle))
                return
            }
            switch self.encryptMessage(for: userId, unencrypted: unencrypted, keyBundle: keyBundle) {
            case .success(let encryptedData):
                var identityKey: Data? = nil, oneTimeKey: Int32 = 0
                if let outboundIdentityKey = keyBundle.outboundIdentityPublicEdKey {
                    identityKey = outboundIdentityKey
                    oneTimeKey = keyBundle.outboundOneTimePreKeyId
                }
                completion(.success((encryptedData, identityKey, oneTimeKey)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Decrypts on background serial queue and dispatches completion handler onto main queue.
    public func decryptPayload(for userId: String, encryptedPayload: Data, publicKey: Data?, oneTimeKeyID: Int?, completion: @escaping (Result<Data, DecryptionError>) -> Void) {

        performSeriallyOnBackgroundContext { managedObjectContext in
            var keyBundle: KeyBundle
            var isNewReceiveSession: Bool

            if let savedKeyBundle = self.messageKeyBundle(for: userId, in: managedObjectContext)?.keyBundle,
               savedKeyBundle.inboundEphemeralPublicKey == nil || savedKeyBundle.inboundEphemeralPublicKey == self.ephemeralPublicKey(in: encryptedPayload)
            {
                DDLogInfo("KeyData/decryptPayload/user/\(userId)/found key bundle with matching ephemeral key")
                keyBundle = savedKeyBundle
                isNewReceiveSession = false
            } else {
                guard let publicKey = publicKey else {
                    DDLogError("KeyData/decryptPayload/user/\(userId)/error missing public key")
                    DispatchQueue.main.async {
                        completion(.failure(.missingPublicKey))
                    }
                    return
                }
                let setup = self.receiveSessionSetup(for: userId, from: encryptedPayload, publicKey: publicKey, oneTimeKeyID: oneTimeKeyID)
                switch setup {
                case .success(let newKeyBundle):
                    DDLogInfo("KeyData/decryptPayload/user/\(userId)/receiveSessionSetup/success")
                    keyBundle = newKeyBundle
                    isNewReceiveSession = true
                case .failure(let error):
                    DDLogError("KeyData/decryptPayload/user/\(userId)/receiveSessionSetup/error \(error)")
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                    return
                }
            }

            let result = self.decryptMessage(for: userId, encryptedPayload: encryptedPayload, keyBundle: keyBundle, isNewReceiveSession: isNewReceiveSession)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

}
