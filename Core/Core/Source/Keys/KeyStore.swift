//
//  HalloApp
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

// Delegate to notify changes to current in-memory sessions.
public protocol KeyStoreDelegate: AnyObject {
    func keyStoreContextChanged()
}

open class KeyStore {
    public let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.keys")
    public let userData: UserData
    public let appTarget: AppTarget
    
    private var bgContext: NSManagedObjectContext
    public weak var delegate: KeyStoreDelegate?
    
    required public init(userData: UserData, appTarget: AppTarget, userDefaults: UserDefaults) {
        self.userData = userData
        // Before fetching the latest context for this target.
        // Let us update their last history timestamp: this will be useful when pruning old transactions later.
        userDefaults.updateLastHistoryTransactionTimestamp(for: appTarget, to: Date())
        self.bgContext = persistentContainer.newBackgroundContext()
        // Set the context name and transaction author name.
        // This is used later to filter out transactions made by own context.
        self.bgContext.name = appTarget.rawValue + "-context"
        self.bgContext.transactionAuthor = appTarget.rawValue
        self.appTarget = appTarget
        // Add observer to notify us when persistentStore records changes.
        // These notifications are triggered for all cross process writes to the store.
        NotificationCenter.default.addObserver(self, selector: #selector(processStoreRemoteChanges), name: .NSPersistentStoreRemoteChange, object: persistentContainer.persistentStoreCoordinator)
    }

    // Process persistent history to merge changes from other coordinators.
    @objc private func processStoreRemoteChanges(_ notification: Notification) {
        processPersistentHistory()
    }
    // Merge Persistent history and clear merged transactions.
    @objc private func processPersistentHistory() {
        performSeriallyOnBackgroundContext({ managedObjectContext in
            do {
                // Merges latest transactions from other contexts into the current target context.
                let merger = PersistentHistoryMerger(backgroundContext: managedObjectContext, currentTarget: self.appTarget)
                let historyMerged = try merger.merge()
                // Prunes transactions that have been merged into all possible contexts: MainApp, NotificationExtension, ShareExtension
                let cleaner = PersistentHistoryCleaner(context: managedObjectContext, targets: AppTarget.allCases)
                try cleaner.clean()

                if historyMerged {
                    // Call delegate only if there were actual transactions that were merged
                    self.delegate?.keyStoreContextChanged()
                }
            } catch {
                DDLogError("KeyStore/PersistentHistoryTracking failed with error: \(error)")
            }
        })
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
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSPersistentHistoryTrackingKey)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
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

    @discardableResult
    public func save(_ managedObjectContext: NSManagedObjectContext) -> Bool {
        DDLogVerbose("KeyStore/will-save")
        do {
            managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            try managedObjectContext.save()
            DDLogVerbose("KeyStore/did-save")
            return true
        } catch {
            DDLogError("KeyStore/save-error error=[\(error)]")
            return false
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
        let bundles = messageKeyBundles(predicate: NSPredicate(format: "userId == %@", userId), in: managedObjectContext)
        if bundles.count > 1 {
            DDLogError("KeyStore/messageKeyBundle/error multiple-bundles-for-user [\(bundles.count)]")
        }
        return bundles.first
    }

    public func groupSessionKeyBundle(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext? = nil) -> GroupSessionKeyBundle? {
        let managedObjectContext = managedObjectContext ?? self.viewContext
        let fetchRequest: NSFetchRequest<GroupSessionKeyBundle> = GroupSessionKeyBundle.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let keyBundles = try managedObjectContext.fetch(fetchRequest)
            if keyBundles.count > 1 {
                DDLogError("KeyStore/groupKeyBundle/error multiple-bundles-for-group [\(keyBundles.count)]")
                keyBundles[1...].forEach { managedObjectContext.delete($0) }
            }
            return keyBundles.first
        }
        catch {
            DDLogError("KeyStore/fetch-groupKeyBundles/error  [\(error)]")
            fatalError("Failed to fetch key bundle")
        }
    }

    public func groupSessionKeyBundle(for groupID: GroupID, in managedObjectContext: NSManagedObjectContext? = nil) -> GroupSessionKeyBundle? {
        return groupSessionKeyBundle(predicate: NSPredicate(format: "groupId == %@", groupID), in: managedObjectContext)
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

    func deleteUserOneTimePreKey(oneTimeKeyId: Int) {
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
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
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

    // MARK: Saving

    public func saveMessageKeys(_ keys: MessageKeyMap, for userID: UserID) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let messageKeyBundle = self.messageKeyBundle(for: userID, in: managedObjectContext) else {
                DDLogError("KeyStore/saveMessageKeys/\(userID)/error bundle not found")
                return
            }

            var keysToAdd = keys
            var keysDeleted = 0

            for oldKey in messageKeyBundle.messageKeys ?? [] {
                if let newData = keysToAdd[oldKey.locator], newData == oldKey.key {
                    keysToAdd[oldKey.locator] = nil
                } else {
                    managedObjectContext.delete(oldKey)
                    keysDeleted += 1
                }
            }

            for (locator, keyData) in keysToAdd {
                let messageKey = NSEntityDescription.insertNewObject(forEntityName: MessageKey.entity().name!, into: managedObjectContext) as! MessageKey
                messageKey.ephemeralKeyId = locator.ephemeralKeyID
                messageKey.chainIndex = locator.chainIndex
                messageKey.key = keyData
                messageKey.messageKeyBundle = messageKeyBundle
            }

            DDLogInfo("KeyStore/saveMessageKeys/\(userID)/complete [\(keysToAdd.count) added] [\(keysDeleted) deleted]")

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }

    public func saveKeyBundle(_ keyBundle: KeyBundle) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in

            let messageKeyBundles = self.messageKeyBundles(predicate: NSPredicate(format: "userId == %@", keyBundle.userId), in: managedObjectContext)

            // TODO: We should enforce one bundle per user with a uniqueness constraint.
            if messageKeyBundles.count > 1 {
                DDLogInfo("KeyStore/saveKeyBundle/\(keyBundle.userId)/deleting-duplicates [found \(messageKeyBundles.count)]")
                messageKeyBundles[1...].forEach { managedObjectContext.delete($0) }
            }

            let messageKeyBundle = messageKeyBundles.first ?? NSEntityDescription.insertNewObject(forEntityName: MessageKeyBundle.entity().name!, into: managedObjectContext) as! MessageKeyBundle

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

            messageKeyBundle.teardownKey = keyBundle.teardownKey

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
}

extension KeyStore {

    // MARK: GroupKeys Saving

    public func saveGroupSessionKeyBundle(groupID: GroupID, state: GroupSessionState, groupKeyBundle: GroupKeyBundle) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in

            let groupSessionKeyBundle: GroupSessionKeyBundle = self.groupSessionKeyBundle(for: groupID, in: managedObjectContext) ?? NSEntityDescription.insertNewObject(forEntityName: GroupSessionKeyBundle.entity().name!, into: managedObjectContext) as! GroupSessionKeyBundle

            // It is not great and feels dangerous that we delete everything and re-add them everytime.
            // TODO: murali@: there must be a better way for sure.
            groupSessionKeyBundle.senderStates?.forEach{ senderState in
                senderState.messageKeys?.forEach{ messageKey in managedObjectContext.delete(messageKey) }
                managedObjectContext.delete(senderState)
            }

            let outgoingSession = groupKeyBundle.outgoingSession
            var senderStates = Set<SenderStateBundle>()
            for (userID, senderState) in groupKeyBundle.incomingSession?.senderStates ?? [:] {
                let memberSenderState = NSEntityDescription.insertNewObject(forEntityName: SenderStateBundle.entity().name!, into: managedObjectContext) as! SenderStateBundle
                memberSenderState.userId = userID
                memberSenderState.chainKey = senderState.senderKey.chainKey
                memberSenderState.publicSignatureKey = senderState.senderKey.publicSignatureKey
                memberSenderState.currentChainIndex = Int32(senderState.currentChainIndex)
                var messageKeys = Set<GroupMessageKey>()
                for (chainIndex, messageKey) in senderState.unusedMessageKeys {
                    let groupMessageKey = NSEntityDescription.insertNewObject(forEntityName: GroupMessageKey.entity().name!, into: managedObjectContext) as! GroupMessageKey
                    groupMessageKey.messageKey = messageKey
                    groupMessageKey.chainIndex = chainIndex
                    groupMessageKey.senderStateBundle = memberSenderState
                    messageKeys.insert(groupMessageKey)
                }
                memberSenderState.messageKeys = messageKeys.isEmpty ? nil : messageKeys
                memberSenderState.groupSessionKeyBundle = groupSessionKeyBundle
                senderStates.insert(memberSenderState)
            }

            // Try and insert own senderState if available.
            if outgoingSession != nil,
               let chainKey = outgoingSession?.senderKey.chainKey,
               let signKey = outgoingSession?.senderKey.publicSignatureKey,
               let chainIndex = outgoingSession?.currentChainIndex {
                let memberSenderState = NSEntityDescription.insertNewObject(forEntityName: SenderStateBundle.entity().name!, into: managedObjectContext) as! SenderStateBundle
                memberSenderState.userId = AppContext.shared.userData.userId
                memberSenderState.chainKey = chainKey
                memberSenderState.publicSignatureKey = signKey
                memberSenderState.currentChainIndex = Int32(chainIndex)
                memberSenderState.messageKeys = nil
                memberSenderState.groupSessionKeyBundle = groupSessionKeyBundle
                senderStates.insert(memberSenderState)
            }

            groupSessionKeyBundle.groupId = groupID
            groupSessionKeyBundle.state = state
            groupSessionKeyBundle.pendingUserIds = groupKeyBundle.pendingUids
            groupSessionKeyBundle.audienceHash = outgoingSession?.audienceHash
            groupSessionKeyBundle.privateSignatureKey = outgoingSession?.privateSigningKey
            groupSessionKeyBundle.senderStates = senderStates.isEmpty ? nil : senderStates

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
}

public struct MessageKeyLocator: Hashable, Equatable {
    var ephemeralKeyID: Int32
    var chainIndex: Int32
}

public typealias MessageKeyMap = [MessageKeyLocator: Data]

public struct KeyBundle {
    public var userId: String
    public var inboundIdentityPublicEdKey: Data
    
    public var inboundEphemeralPublicKey: Data?
    public var inboundEphemeralKeyId: Int32
    public var inboundChainKey: Data
    public var inboundPreviousChainLength: Int32
    public var inboundChainIndex: Int32
    
    public var rootKey: Data
    
    public var outboundEphemeralPrivateKey: Data
    public var outboundEphemeralPublicKey: Data
    public var outboundEphemeralKeyId: Int32
    public var outboundChainKey: Data
    public var outboundPreviousChainLength: Int32
    public var outboundChainIndex: Int32
    
    public var outboundIdentityPublicEdKey: Data?
    public var outboundOneTimePreKeyId: Int32

    public var teardownKey: Data?
    
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
        outboundOneTimePreKeyId: Int32 = 0,

        teardownKey: Data? = nil
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

        self.teardownKey = teardownKey
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
