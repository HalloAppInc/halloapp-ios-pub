//
//  MainDataStore.swift
//  Core
//
//  Created by Murali Balusu on 12/13/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation
import CoreCommon
import CocoaLumberjackSwift
import Combine
import CoreData

// MARK: Types

open class MainDataStore {

    public let userData: UserData

    private let userDefaults: UserDefaults
    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.mainDataStore")
    private let bgQueueKey = DispatchSpecificKey<String>()
    private let bgQueueValue = "com.halloapp.mainDataStore"
    public let appTarget: AppTarget

    public let willClearStore = PassthroughSubject<Void, Never>()
    public let didClearStore = PassthroughSubject<Void, Never>()

    // MARK: CoreData stack

    public class var persistentStoreURL: URL {
        get {
            return AppContext.mainStoreURL
        }
    }

    public private(set) var persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: MainDataStore.persistentStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSPersistentHistoryTrackingKey)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let modelURL = Bundle(for: MainDataStore.self).url(forResource: "MainDataStore", withExtension: "momd")!
        let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL)
        let container = NSPersistentContainer(name: "MainDataStore", managedObjectModel: managedObjectModel!)
        container.persistentStoreDescriptions = [storeDescription]
        container.loadPersistentStores { (description, error) in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        return container
    }()

    public var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    required public init(userData: UserData, appTarget: AppTarget, userDefaults: UserDefaults) {
        self.userData = userData
        self.userDefaults = userDefaults
        self.appTarget = appTarget

        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true

        // Before fetching the latest context for this target.
        // Let us update their last history timestamp: this will be useful when pruning old transactions later.
        userDefaults.updateLastHistoryTransactionTimestamp(for: appTarget, dataStore: .mainDataStore, to: Date())

        // Add observer to notify us when persistentStore records changes.
        // These notifications are triggered for all cross process writes to the store.
        NotificationCenter.default.addObserver(self, selector: #selector(processStoreRemoteChanges), name: .NSPersistentStoreRemoteChange, object: persistentContainer.persistentStoreCoordinator)

        backgroundProcessingQueue.setSpecific(key: bgQueueKey, value: bgQueueValue)
    }

    // Process persistent history to merge changes from other coordinators.
    @objc private func processStoreRemoteChanges(_ notification: Notification) {
        DDLogInfo("MainDataStore/processStoreRemoteChanges/notification: \(notification)")
        processPersistentHistory()
    }
    // Merge Persistent history and clear merged transactions.
    @objc private func processPersistentHistory() {
        performSeriallyOnBackgroundContext({ managedObjectContext in
            do {
                // Merges latest transactions from other contexts into the current target context.
                let merger = PersistentHistoryMerger(backgroundContext: managedObjectContext,
                                                     viewContext: self.viewContext,
                                                     dataStore: .mainDataStore,
                                                     userDefaults: self.userDefaults,
                                                     currentTarget: self.appTarget)
                let historyMerged = try merger.merge()
                // Prunes transactions that have been merged into all possible contexts: MainApp, NotificationExtension, ShareExtension
                let cleaner = PersistentHistoryCleaner(context: managedObjectContext,
                                                       targets: AppTarget.allCases,
                                                       dataStore: .mainDataStore,
                                                       userDefaults: self.userDefaults)
                try cleaner.clean()

                if managedObjectContext.hasChanges {
                    self.save(managedObjectContext)
                }

                if historyMerged {
                    DDLogInfo("MainDataStore/processPersistentHistory/historyMerged: \(historyMerged)")
                }
            } catch {
                DDLogError("MainDataStore/processPersistentHistory failed with error: \(error)")
            }
        })
    }

    private func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Set the context name and transaction author name.
        // This is used later to filter out transactions made by own context.
        context.name = appTarget.rawValue + "-context"
        context.transactionAuthor = appTarget.rawValue

        return context
    }

    public func performSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        backgroundProcessingQueue.async { [weak self] in
            guard let self = self else { return }

            let context = self.newBackgroundContext()
            context.performAndWait {
                block(context)
            }
        }
    }

    public func performOnBackgroundContextAndWait(_ block: (NSManagedObjectContext) -> Void) {
        if DispatchQueue.getSpecific(key: bgQueueKey) as String? == bgQueueValue {
            let context = self.newBackgroundContext()
            context.performAndWait { block(context) }
        } else {
            backgroundProcessingQueue.sync { [weak self] in
                guard let self = self else { return }
                let context = self.newBackgroundContext()
                context.performAndWait { block(context) }
            }
        }
    }

    public final func save(_ managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("MainDataStore/will-save")
        do {
            try managedObjectContext.save()
            DDLogInfo("MainDataStore/did-save")
        } catch {
            DDLogError("MainDataStore/save-error error=[\(error)]")
        }
    }

    public final func saveSeriallyOnBackgroundContextAndWait(_ block: (NSManagedObjectContext) -> Void) throws {
        var errorOnSave: Error?

        backgroundProcessingQueue.sync {
            let context = self.newBackgroundContext()

            context.performAndWait {
                block(context)

                do {
                    try context.save()
                    DDLogInfo("MainDataStore/saveSeriallyOnBackgroundContextAndWait - Success")
                } catch {
                    DDLogError("MainDataStore/saveSeriallyOnBackgroundContextAndWait - Error [\(error)]")
                    errorOnSave = error
                }
            }
        }

        if let errorOnSave = errorOnSave {
            throw errorOnSave
        }
    }

    public final func saveSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void, completion: ((Result<Void, Error>) -> Void)? = nil) {
        backgroundProcessingQueue.async { [weak self] in
            guard let self = self else { return }

            let context = self.newBackgroundContext()
            context.performAndWait {
                block(context)

                do {
                    try context.save()
                    DDLogInfo("MainDataStore/saveSeriallyOnBackgroundContext - Success")
                    completion?(.success(()))
                } catch {
                    DDLogError("MainDataStore/saveSeriallyOnBackgroundContext - Error [\(error)]")
                    completion?(.failure(error))
                }
            }
        }
    }

    // MARK: Metadata
    /**
     - returns:
     Metadata associated with main data store.
     */
    public var databaseMetadata: [String: Any]? {
        get {
            var result: [String: Any] = [:]
            self.persistentContainer.persistentStoreCoordinator.performAndWait {
                do {
                    try result = NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: MainDataStore.persistentStoreURL)
                }
                catch {
                    DDLogError("MainDataStore/metadata/read error=[\(error)]")
                }
            }
            return result
        }
    }

    // MARK: Calls
    // TODO: We dont store end-call reason for each call, we can add this later.

    public func saveCall(callID: CallID, peerUserID: UserID, type: CallType, direction: CallDirection, timestamp: Date, completion: ((Call) -> Void)? = nil) {
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }
            DDLogInfo("MainDataStore/saveCall/callID: \(callID)")

            let newCall: Call
            if let existingCall = self.call(with: callID, in: managedObjectContext) {
                newCall = existingCall
            } else {
                newCall = Call(context: managedObjectContext)
                newCall.callID = callID
                newCall.peerUserID = peerUserID
                newCall.type = type
                newCall.direction = direction
                newCall.timestamp = timestamp
                newCall.answered = false
                newCall.durationMs = 0.0
                newCall.endReason = .unknown
            }

            managedObjectContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
            self.save(managedObjectContext)
            DispatchQueue.main.async {
                completion?(newCall)
            }
        }
    }

    public func saveMissedCall(callID: CallID, peerUserID: UserID, type: CallType, timestamp: Date, completion: ((Call) -> Void)? = nil) {
        saveCall(callID: callID, peerUserID: peerUserID, type: type, direction: .incoming, timestamp: timestamp, completion: completion)
    }

    public func updateCall(with callID: CallID, block: @escaping (Call) -> Void) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            DDLogInfo("MainDataStore/updateCall/callID: \(callID)")

            guard let call = self.call(with: callID, in: managedObjectContext) else {
                DDLogVerbose("ChatData/updateCall - missing")
                return
            }

            DDLogInfo("ChatData/updateCall: [\(callID)]")
            block(call)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }

    public func call(with callID: CallID, in managedObjectContext: NSManagedObjectContext) -> Call? {
        let fetchRequest: NSFetchRequest<Call> = Call.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "callID == %@", callID)
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let calls = try managedObjectContext.fetch(fetchRequest)
            return calls.first
        } catch {
            DDLogError("MainDataStore/fetch-call/error  [\(error)]")
            fatalError("Failed to fetch call")
        }
    }

    public func deleteCalls(with peerUserID: UserID) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            DDLogInfo("MainDataStore/deleteCalls/peerUserID: \(peerUserID)")

            let fetchRequest: NSFetchRequest<Call> = Call.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "peerUserID == %@", peerUserID)

            do {
                let calls = try managedObjectContext.fetch(fetchRequest)
                calls.forEach {
                    managedObjectContext.delete($0)
                }
                self.save(managedObjectContext)
            } catch {
                DDLogError("MainDataStore/deleteCalls/error  [\(error)]/peerUserID: \(peerUserID)")
                fatalError("Failed to delete call history: \(peerUserID)")
            }
        }
    }

    public func saveGroupHistoryInfo(id: String, groupID: GroupID, payload: Data) {
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }
            DDLogInfo("MainDataStore/saveGroupHistoryInfo/id: \(id)")
            let groupHistoryInfo = GroupHistoryInfo(context: managedObjectContext)
            groupHistoryInfo.id = id
            groupHistoryInfo.groupId = groupID
            groupHistoryInfo.payload = payload

            managedObjectContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
            self.save(managedObjectContext)
        }
    }

    public func groupHistoryInfo(for id: String, in managedObjectContext: NSManagedObjectContext) -> GroupHistoryInfo? {
        let fetchRequest: NSFetchRequest<GroupHistoryInfo> = GroupHistoryInfo.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let groupHistoryInfos = try managedObjectContext.fetch(fetchRequest)
            return groupHistoryInfos.first
        } catch {
            DDLogError("MainDataStore/fetch-groupHistoryInfo/error  [\(error)]")
            fatalError("Failed to fetch groupHistoryInfo")
        }
    }

    public func fetchContentResendInfo(for contentID: String, userID: UserID, in managedObjectContext: NSManagedObjectContext) -> ContentResendInfo {
        let fetchRequest: NSFetchRequest<ContentResendInfo> = ContentResendInfo.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "contentID == %@ AND userID == %@", contentID, userID)
        fetchRequest.returnsObjectsAsFaults = false
        do {
            if let result = try managedObjectContext.fetch(fetchRequest).first {
                return result
            } else {
                let result = ContentResendInfo(context: managedObjectContext)
                result.contentID = contentID
                result.userID = userID
                result.retryCount = 0
                return result
            }
        } catch {
            DDLogError("MainDataStore/fetchAndUpdateRetryCount/error  [\(error)]")
            fatalError("Failed to fetchAndUpdateRetryCount.")
        }
    }

    // MARK: CommonMedia

    public func commonMediaObject(forObjectId objectId: NSManagedObjectID) throws -> CommonMedia? {
        return try persistentContainer.viewContext.existingObject(with: objectId) as? CommonMedia
    }

    public func commonMediaItems(predicate: NSPredicate? = nil, in managedObjectContext: NSManagedObjectContext) -> [CommonMedia] {
        let fetchRequest: NSFetchRequest<CommonMedia> = CommonMedia.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let commonMediaItems = try managedObjectContext.fetch(fetchRequest)
            return commonMediaItems
        } catch {
            DDLogError("MainDataStore/fetch-commonMediaItems/error  [\(error)]")
            fatalError("Failed to fetch commonMediaItems.")
        }
    }

    // MARK: Groups
    public func groups(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext) -> [Group] {
        let fetchRequest: NSFetchRequest<Group> = Group.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let groups = try managedObjectContext.fetch(fetchRequest)
            return groups
        } catch {
            DDLogError("MainDataStore/fetch-groups/error  [\(error)]")
            fatalError("Failed to fetch chat groups")
        }
    }

    public func chatThread(id: String, in managedObjectContext: NSManagedObjectContext) -> CommonThread? {
        return commonThreads(predicate: NSPredicate(format: "userID == %@", id), in: managedObjectContext).first
    }

    public func commonThreads(predicate: NSPredicate, in context: NSManagedObjectContext) -> [CommonThread] {
        let request = CommonThread.fetchRequest()
        request.predicate = predicate
        do {
            return try context.fetch(request)
        } catch {
            DDLogError("MainDataStore/fetch-chatThreads/error  [\(error)]")
        }
        return []
    }

    public func chatThreads(in context: NSManagedObjectContext) -> [CommonThread] {
        let request = CommonThread.fetchRequest()
        request.predicate = NSPredicate(format: "groupID == nil")
        do {
            return try context.fetch(request)
        } catch {
            DDLogError("MainDataStore/fetch-groupThreads/error  [\(error)]")
        }
        return []
    }

    public func groupThreads(in context: NSManagedObjectContext) -> [CommonThread] {
        let request = CommonThread.fetchRequest()
        request.predicate = NSPredicate(format: "groupID != nil")
        do {
            return try context.fetch(request)
        } catch {
            DDLogError("MainDataStore/fetch-groupThreads/error  [\(error)]")
        }
        return []
    }

    public func groupThread(for id: GroupID, in context: NSManagedObjectContext) -> CommonThread? {
        let request = CommonThread.fetchRequest()
        request.predicate = NSPredicate(format: "groupID == %@", id)
        do {
            return try context.fetch(request).first
        } catch {
            DDLogError("MainDataStore/fetch-groupThread/error  [\(error)]")
        }
        return nil
    }

    public func deleteAllEntities() {

        DispatchQueue.main.async {
            self.willClearStore.send()
        }

        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }

            let model = self.persistentContainer.managedObjectModel
            let entities = model.entities

            /* nb: batchdelete will not auto delete entities with a cascade delete rule for core data relationships but
               can result in not deleting an entity if there's a deny delete rule in place */
            for entity in entities {
                guard let entityName = entity.name else { continue }
                DDLogDebug("MainDataStore/deleteAllEntities/clear/\(entityName)")

                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                batchDeleteRequest.resultType = .resultTypeObjectIDs
                do {
                    let result = try managedObjectContext.execute(batchDeleteRequest) as? NSBatchDeleteResult
                    guard let objectIDs = result?.result as? [NSManagedObjectID] else { continue }
                    let changes = [NSDeletedObjectsKey: objectIDs]
                    DDLogDebug("MainDataStore/deleteAllEntities/clear/\(entityName)/num: \(objectIDs.count)")

                    // update main context manually as batchdelete does not notify other contexts
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.viewContext])

                } catch {
                    DDLogError("MainDataStore/deleteAllEntities/clear/\(entityName)/error \(error)")
                }
            }

            DispatchQueue.main.async {
                self.didClearStore.send()
            }
        }

    }

}
