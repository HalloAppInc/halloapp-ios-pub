//
//  HalloApp
//
//  Created by Tony Jiang on 7/15/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import CryptoKit
import CryptoSwift
import Foundation
import Sodium
import XMPPFramework

open class KeyStore {
    public let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.keys")
    public let userData: UserData
    
    required public init(userData: UserData) {
        self.userData = userData
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
    
    public private(set) lazy var persistentContainer: NSPersistentContainer = {
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
        self.backgroundProcessingQueue.async {
            let managedObjectContext = self.persistentContainer.newBackgroundContext()
            managedObjectContext.performAndWait { block(managedObjectContext) }
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
    
    public func addMessageKey(for userId: UserID, eId: Int32, iId: Int32, messageKey: Data) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            if let messageKeyBundle = self.messageKeyBundle(for: userId, in: managedObjectContext) {
            
                let messageKey = NSEntityDescription.insertNewObject(forEntityName: MessageKey.entity().name!, into: managedObjectContext) as! MessageKey
                messageKey.ephemeralKeyId = eId
                messageKey.chainIndex = iId
                messageKey.messageKeyBundle = messageKeyBundle
                
                if managedObjectContext.hasChanges {
                    self.save(managedObjectContext)
                }
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
    
    public func deleteUserOneTimePreKey(oneTimeKeyId: Int) {
        DDLogInfo("KeyStore/deleteUserOneTimePreKey/id/\(oneTimeKeyId)")
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let fetchRequest = NSFetchRequest<UserKeyBundle>(entityName: UserKeyBundle.entity().name!)
            do {
                let userKeyBundles = try managedObjectContext.fetch(fetchRequest)
                userKeyBundles.forEach {
                    guard let oneTimePreKeys = $0.oneTimePreKeys else {
                        DDLogInfo("KeyStore/deleteUserOneTimePreKey/no oneTimePreKeys found")
                        return
                    }
                    for oneTimeKey in oneTimePreKeys {
                        if oneTimeKey.id == oneTimeKeyId {
                            DDLogInfo("KeyStore/deleteUserOneTimePreKey/delete/id/\(oneTimeKeyId)")
                            managedObjectContext.delete(oneTimeKey)
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
            self.save(managedObjectContext)
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
            self.save(managedObjectContext)
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
    
    public func initiateSessionSetup(for targetUserId: UserID, with targetUserWhisperKeys: XMPPWhisperKey) -> KeyBundle? {
        DDLogInfo("KeyStore/initiateSessionSetup \(targetUserId)")
        
        guard let myKeys = self.keyBundle() else {
            DDLogInfo("KeyStore/initiateSessionSetup/missingMyKeyBundle")
            return nil
        }
        
        let sodium = Sodium()
        
        // generate new key pair
        guard let newKeyPair = sodium.box.keyPair() else { return nil }
        
        let outboundIdentityPrivateKey = myKeys.identityPrivateKey                              // I_initiator
        
        let outboundEphemeralPublicKey = Data(newKeyPair.publicKey)
        let outboundEphemeralPrivateKey = Data(newKeyPair.secretKey)                            // E_initiator
        
        guard let inboundIdentityPublicEdKey = targetUserWhisperKeys.identity else { return nil }
        guard let inboundIdentityPublicKeyUInt8 = sodium.sign.convertToX25519PublicKey(publicKey: [UInt8](inboundIdentityPublicEdKey)) else { return nil }
        
        let inboundIdentityPublicKey = Data(inboundIdentityPublicKeyUInt8)                      // I_recipient
        
        guard let targetUserSigned = targetUserWhisperKeys.signed else { return nil }
        
        let inboundSignedPrePublicKey = targetUserSigned.publicKey                              // S_recipient
        
        guard let signature = targetUserWhisperKeys.signature else {
            DDLogInfo("KeyStore/initiateSessionSetup/missingSignature")
            return nil
        }
        
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
                                               recipientOneTimePreKey: inboundOneTimePrePublicKey) else {
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
        
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let messageKeyBundle = NSEntityDescription.insertNewObject(forEntityName: MessageKeyBundle.entity().name!, into: managedObjectContext) as! MessageKeyBundle
            
            messageKeyBundle.userId = targetUserId
            messageKeyBundle.inboundIdentityPublicEdKey = inboundIdentityPublicEdKey
            
            messageKeyBundle.inboundEphemeralPublicKey = nil
            messageKeyBundle.inboundEphemeralKeyId = -1
            messageKeyBundle.inboundChainKey = Data(inboundChainKey)
            messageKeyBundle.inboundPreviousChainLength = 0
            messageKeyBundle.inboundChainIndex = 0
            
            messageKeyBundle.rootKey = Data(rootKey)
            
            messageKeyBundle.outboundEphemeralPrivateKey = outboundEphemeralPrivateKey
            messageKeyBundle.outboundEphemeralPublicKey = outboundEphemeralPublicKey
            messageKeyBundle.outboundEphemeralKeyId = 1
            messageKeyBundle.outboundChainKey = Data(outboundChainKey)
            messageKeyBundle.outboundPreviousChainLength = 0
            messageKeyBundle.outboundChainIndex = 0
            
            messageKeyBundle.outboundIdentityPublicEdKey = Data(outboundIdentityPublicEdKey)
            messageKeyBundle.outboundOneTimePreKeyId = Int32(outboundOneTimePreKeyId)
            
            self.save(managedObjectContext)
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
        
        return keyBundle
    }
    
    public func receiveSessionSetup(for userId: UserID, from entry: XMLElement) -> KeyBundle? {
        DDLogInfo("KeyStore/receiveSessionSetup \(userId)")
        let sodium = Sodium()
        
        guard let enc = entry.element(forName: "enc") else { return nil }
        guard let encStringValue = enc.stringValue else { return nil }
        
        var inboundOneTimePreKeyId: Int = -1
        
        guard let inboundIdentityPublicEdKeyBase64 = enc.attributeStringValue(forName: "identity_key") else {
            DDLogInfo("KeyStore/receiveSessionSetup/user/\(userId)/invalidIdentitykey")
            return nil
        }
        
        guard let inboundIdentityPublicEdKey = Data(base64Encoded: inboundIdentityPublicEdKeyBase64) else { return nil }
        
        guard let x25519Key = sodium.sign.convertToX25519PublicKey(publicKey: [UInt8](inboundIdentityPublicEdKey)) else { return nil }
        let I_initiator = Data(x25519Key)
        
        if let inboundOneTimePreKeyIdStr = enc.attributeStringValue(forName: "one_time_pre_key_id") {
            inboundOneTimePreKeyId = Int(inboundOneTimePreKeyIdStr) ??  -1
        }
        
        guard let encryptedPayload = Data(base64Encoded: encStringValue, options: .ignoreUnknownCharacters) else { return nil }
        
        let inboundEphemeralPublicKey = encryptedPayload[0...31]
        let inboundEphemeralKeyId = encryptedPayload[32...35]
        
        //TODO: could remove these, need to test
        let inboundPreviousChainLength = encryptedPayload[36...39]
        let inboundChainIndex = encryptedPayload[40...43]
        
        let inboundEphemeralKeyIdInt = Int32(bigEndian: inboundEphemeralKeyId.withUnsafeBytes { $0.load(as: Int32.self) })
        let inboundPreviousChainLengthInt = Int32(bigEndian: inboundPreviousChainLength.withUnsafeBytes { $0.load(as: Int32.self) })
        let inboundChainIndexInt = Int32(bigEndian: inboundChainIndex.withUnsafeBytes { $0.load(as: Int32.self) })
        
        guard let userKeyBundle = self.keyBundle() else { return nil }
        let signedPreKeys = userKeyBundle.signedPreKeys
        guard let signedPreKey = signedPreKeys.first(where: {$0.id == 1}) else { return nil }
        
        var O_recipient: Data? = nil
        
        if inboundOneTimePreKeyId >= 0 {
            guard let oneTimePreKeys = userKeyBundle.oneTimePreKeys else { return nil }
            guard let oneTimePreKey = oneTimePreKeys.first(where: {$0.id == inboundOneTimePreKeyId}) else { return nil }
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
                                               recipientOneTimePreKey: O_recipient) else {
                                                DDLogDebug("KeyStore/receiveSessionSetup/invalidMasterKey")
                                                return nil
        }
        
        var rootKey = masterKey.rootKey
        let inboundChainKey = masterKey.firstChainKey
        var outboundChainKey = masterKey.secondChainKey
        
        // generate new Ephemeral key and update root + outboundChainKey
        guard let outboundEphemeralKeyPair = sodium.box.keyPair() else { return nil }
        let outboundEphemeralPrivateKey = Data(outboundEphemeralKeyPair.secretKey)
        let outboundEphemeralPublicKey = Data(outboundEphemeralKeyPair.publicKey)
        
        guard let outboundAsymmetricRachet = self.asymmetricRachet(privateKey: Data(outboundEphemeralKeyPair.secretKey), publicKey: Data(inboundEphemeralPublicKey), rootKey: rootKey) else { return nil }
        rootKey = outboundAsymmetricRachet.updatedRootKey
        outboundChainKey = outboundAsymmetricRachet.updatedChainKey
        
        if inboundOneTimePreKeyId >= 0 {
            // delete the prekey once used
            self.deleteUserOneTimePreKey(oneTimeKeyId: inboundOneTimePreKeyId)
        }
        
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            
            let messageKeyBundle = NSEntityDescription.insertNewObject(forEntityName: MessageKeyBundle.entity().name!, into: managedObjectContext) as! MessageKeyBundle
            messageKeyBundle.userId = userId
            messageKeyBundle.inboundIdentityPublicEdKey = inboundIdentityPublicEdKey
            
            messageKeyBundle.inboundEphemeralPublicKey = Data(inboundEphemeralPublicKey)
            messageKeyBundle.inboundEphemeralKeyId = Int32(inboundEphemeralKeyIdInt)
            messageKeyBundle.inboundChainKey = Data(inboundChainKey)
            messageKeyBundle.inboundPreviousChainLength = Int32(inboundPreviousChainLengthInt)
            messageKeyBundle.inboundChainIndex = Int32(inboundChainIndexInt)
            
            messageKeyBundle.rootKey = Data(rootKey)
            
            messageKeyBundle.outboundEphemeralPrivateKey = outboundEphemeralPrivateKey
            messageKeyBundle.outboundEphemeralPublicKey = outboundEphemeralPublicKey
            messageKeyBundle.outboundEphemeralKeyId = 1
            messageKeyBundle.outboundChainKey = Data(outboundChainKey)
            messageKeyBundle.outboundPreviousChainLength = 0
            messageKeyBundle.outboundChainIndex = 0
            
            self.save(managedObjectContext)
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
        
        return keyBundle
    }
    
    public func encryptMessage(for userId: String, unencrypted: Data, keyBundle: KeyBundle) -> Data? {
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
        
        guard let symmetricRachet = self.symmetricRachet(chainKey: outboundChainKey) else { return nil }
        messageKey = symmetricRachet.messageKey
        outboundChainKey = symmetricRachet.updatedChainKey
        
        let AESKey = Array(messageKey[0...31])
        let HMACKey = Array(messageKey[32...63])
        let IV = Array(messageKey[64...79])
        
        do {
            let encrypted = try AES(key: AESKey, blockMode: CBC(iv: IV), padding: .pkcs7).encrypt(Array(unencrypted))
            let HMAC = try! CryptoSwift.HMAC(key: HMACKey, variant: .sha256).authenticate([UInt8](encrypted))
            
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
            
            self.performSeriallyOnBackgroundContext { (managedObjectContext) in
                if let messageKeyBundle = self.messageKeyBundle(for: userId, in: managedObjectContext) {
                    messageKeyBundle.outboundChainKey = Data(outboundChainKey)
                    messageKeyBundle.outboundChainIndex = outboundChainIndex + 1
                }
                self.save(managedObjectContext)
            }
            
            return data
        } catch {
            DDLogError("KeyStore/encryptMessage/error \(error)")
        }
        return nil
    }
    
    public func decryptMessage(for userId: String, from entry: XMLElement, keyBundle: KeyBundle, isNewReceiveSession: Bool) -> Data? {
        DDLogInfo("KeyStore/decryptMessage/for/\(userId)")
        
        guard let enc = entry.element(forName: "enc") else { return nil }
        guard let encStringValue = enc.stringValue else { return nil }
        guard let encryptedPayload = Data(base64Encoded: encStringValue, options: .ignoreUnknownCharacters) else { return nil }
        
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
        
        DDLogDebug("KeyStore/decryptMessage/inboundEphemeralPublicKey:   \([UInt8](inboundEphemeralPublicKey))")
        DDLogDebug("KeyStore/decryptMessage/inboundEphemeralKeyId:       \([UInt8](inboundEphemeralKeyId))")
        DDLogDebug("KeyStore/decryptMessage/previousChainLengthInt:      \([UInt8](inboundPreviousChainLength))")
        DDLogDebug("KeyStore/decryptMessage/inboundChainIndexInt:        \([UInt8](inboundChainIndex))")
        
        var rootKey = [UInt8](keyBundle.rootKey)
        var inboundChainKey = [UInt8](keyBundle.inboundChainKey)
        
        let savedInboundEphemeralKeyId = keyBundle.inboundEphemeralKeyId
        var savedInboundChainIndex = keyBundle.inboundChainIndex
//        let savedInboundPreviousChainLength = keyBundle.inboundPreviousChainLength
        
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
                return nil
            }
            messageKey = [UInt8](msgKey)
            self.deleteMessageKey(for: userId, eId: inboundEphemeralKeyIdInt, iId: inboundChainIndexInt)
        }
        if ((savedInboundEphemeralKeyId == inboundEphemeralKeyIdInt) && (savedInboundChainIndex > inboundChainIndexInt )) {
            isOutOfOrderMessage = true
            guard let msgKey = self.messageKey(for: userId, eId: inboundEphemeralKeyIdInt, iId: inboundChainIndexInt) else {
                DDLogInfo("KeyStore/decryptMessage/isOutOfOrderMessage/priorChainIndex/can't find messageKey")
                return nil
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
                    
                    while catchupChainIndex < inboundPreviousChainIndex {
                        DDLogInfo("KeyStore/decryptMessage/newEphermeralKey/catchup/index \(catchupChainIndex)")
                        guard let symmetricRachet = self.symmetricRachet(chainKey: inboundChainKey) else { return nil }
                        messageKey = symmetricRachet.messageKey
                        inboundChainKey = symmetricRachet.updatedChainKey
                        
                        let msgKey = Data(messageKey)
                        self.addMessageKey(for: userId, eId: savedInboundEphemeralKeyId, iId: catchupChainIndex, messageKey: msgKey)
                        
                        catchupChainIndex += 1
                    }
                }
                
                guard let inboundAsymmetricRachet = self.asymmetricRachet(privateKey: keyBundle.outboundEphemeralPrivateKey, publicKey: Data(inboundEphemeralPublicKey), rootKey: rootKey) else { return nil }
                rootKey = inboundAsymmetricRachet.updatedRootKey
                inboundChainKey = inboundAsymmetricRachet.updatedChainKey
                
                savedInboundChainIndex = -1
                
                // generate new key pair and update outbound key
                guard let newOutboundEphemeralKeyPair = sodium.box.keyPair() else { return nil }
                outboundEphemeralPrivateKey = Data(newOutboundEphemeralKeyPair.secretKey)
                outboundEphemeralPublicKey = Data(newOutboundEphemeralKeyPair.publicKey)
                outboundEphemeralKeyId += 1
                
                guard let outboundAsymmetricRachet = self.asymmetricRachet(privateKey: outboundEphemeralPrivateKey, publicKey: Data(inboundEphemeralPublicKey), rootKey: rootKey) else { return nil }
                rootKey = outboundAsymmetricRachet.updatedRootKey
                outboundChainKey = outboundAsymmetricRachet.updatedChainKey
                
                outboundPreviousChainLength = outboundChainIndex // save previousChainLength before updating index
                outboundChainIndex = 0
                
                // once a message is received, there's no need to send these anymore
                outboundIdentityPublicEdKey = nil
                outboundOneTimePreKeyId = -1
            }
            
            while savedInboundChainIndex < inboundChainIndexInt {
                DDLogInfo("KeyStore/decryptMessage/symmetricRachet/currentChainIndex \(savedInboundChainIndex)")
                guard let symmetricRachet = self.symmetricRachet(chainKey: inboundChainKey) else { return nil }
                messageKey = symmetricRachet.messageKey
                inboundChainKey = symmetricRachet.updatedChainKey
                
                savedInboundChainIndex += 1
                
                if savedInboundChainIndex != inboundChainIndexInt {
                    let msgKey = Data(messageKey)
                    self.addMessageKey(for: userId, eId: inboundEphemeralKeyIdInt, iId: savedInboundChainIndex, messageKey: msgKey)
                }
            }
        }
        
        /*TODO: End section needs refactoring */
        
        guard !messageKey.isEmpty else {
            DDLogInfo("KeyStore/decryptMessage/invalidMessageKey")
            return nil
        }
        
        let AESKey = Array(messageKey[0...31])
        let HMACKey = Array(messageKey[32...63])
        let IV = Array(messageKey[64...79])
        let calculatedHMAC = try! CryptoSwift.HMAC(key: HMACKey, variant: .sha256).authenticate([UInt8](encryptedMessage))
        
        guard [UInt8](inboundHMAC) == calculatedHMAC else {
            DDLogInfo("KeyStore/decryptMessage/hmacMismatch")
            return nil
        }
        
        do {
            let decrypted = try AES(key: AESKey, blockMode: CBC(iv: IV), padding: .pkcs7).decrypt(Array(encryptedMessage))
            let data = Data(decrypted)
            
            self.performSeriallyOnBackgroundContext { (managedObjectContext) in
                if let messageKeyBundle = self.messageKeyBundle(for: userId, in: managedObjectContext) {
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
                }
                self.save(managedObjectContext)
            }
            return data
        } catch {
            DDLogError("KeyStore/decryptMessage/error \(error)")
        }
        return nil
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
