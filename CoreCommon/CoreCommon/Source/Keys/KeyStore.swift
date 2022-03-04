//
//  HalloApp
//
//  Created by Tony Jiang on 7/15/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
import CocoaLumberjackSwift
import Combine
import CoreData
import Foundation

// Delegate to notify changes to current in-memory sessions.
public protocol KeyStoreDelegate: AnyObject {
    func keyStoreContextChanged()
}

open class KeyStore {
    public let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.keys")
    public let userData: UserData
    public let appTarget: AppTarget

    private let bgQueueKey = DispatchSpecificKey<String>()
    private let bgQueueValue = "com.halloapp.keys"
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
        backgroundProcessingQueue.setSpecific(key: bgQueueKey, value: bgQueueValue)
    }

    // Process persistent history to merge changes from other coordinators.
    @objc private func processStoreRemoteChanges(_ notification: Notification) {
        DDLogInfo("KeyStore/processStoreRemoteChanges/notification: \(notification)")
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

                self.save(managedObjectContext)
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
            return AppContextCommon.keyStoreURL
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

    public func performOnBackgroundContextAndWait(_ block: (NSManagedObjectContext) -> Void) {
        if DispatchQueue.getSpecific(key: bgQueueKey) as String? == bgQueueValue {
            bgContext.performAndWait { block(bgContext) }
        } else {
            backgroundProcessingQueue.sync { [weak self] in
                guard let self = self else { return }
                self.bgContext.performAndWait { block(self.bgContext) }
            }
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

    // This function expects to run synchronously.
    // So it should either run on the backgroundProcessingQueue with its own context (or)
    // it should run on the mainQueue with viewContext (or)
    // If the context is nil: then it runs synchronously on the backgroundQueue with its own context.
    // This way: we avoid crashes when context argument is nil.
    public func keyBundle(in managedObjectContext: NSManagedObjectContext? = nil) -> UserKeyBundle? {
        DDLogDebug("KeyStore/fetchUserKeyBundle")
        if let managedObjectContext = managedObjectContext {
            return keyBundles(in: managedObjectContext).first
        } else {
            var userKeyBundle: UserKeyBundle? = nil
            performOnBackgroundContextAndWait { context in
                userKeyBundle = keyBundles(in: context).first
            }
            return userKeyBundle
        }
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
        var bundles: [MessageKeyBundle] = []
        let predicate = NSPredicate(format: "userId == %@", userId)
        if let managedObjectContext = managedObjectContext {
            bundles = messageKeyBundles(predicate: predicate, in: managedObjectContext)
        } else {
            performOnBackgroundContextAndWait { context in
                bundles = messageKeyBundles(predicate: predicate, in: context)
            }
        }
        if bundles.count > 1 {
            DDLogError("KeyStore/messageKeyBundle/error multiple-bundles-for-user [\(bundles.count)]")
        }
        return bundles.first
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
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }

    public func deleteMessageKeyBundles(for userId: UserID) {
        DDLogInfo("KeyStore/deleteMessageKeyBundles/forUser: \(userId)")
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let fetchRequest = NSFetchRequest<MessageKeyBundle>(entityName: MessageKeyBundle.entity().name!)
            fetchRequest.predicate = NSPredicate(format: "userId == %@", userId)
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

public struct MessageKeyLocator: Hashable, Equatable {
    public var ephemeralKeyID: Int32
    public var chainIndex: Int32
    public init(ephemeralKeyID: Int32, chainIndex: Int32) {
        self.ephemeralKeyID = ephemeralKeyID
        self.chainIndex = chainIndex
    }
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