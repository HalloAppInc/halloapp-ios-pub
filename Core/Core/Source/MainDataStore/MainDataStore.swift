//
//  MainDataStore.swift
//  Core
//
//  Created by Murali Balusu on 12/13/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift
import Combine
import CoreData

// MARK: Types

open class MainDataStore {

    public let userData: UserData

    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.mainDataStore")

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

    public var viewContext: NSManagedObjectContext
    private var bgContext: NSManagedObjectContext? = nil

    required public init(userData: UserData) {
        self.userData = userData
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
        viewContext = persistentContainer.viewContext
    }

    public func performSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        backgroundProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            self.initBgContext()
            guard let bgContext = self.bgContext else { return }
            bgContext.performAndWait { block(bgContext) }
        }
    }

    public func performSeriallyOnBackgroundContextAndWait(_ block: (NSManagedObjectContext) -> Void) {
        backgroundProcessingQueue.sync { [weak self] in
            guard let self = self else { return }
            self.initBgContext()
            guard let bgContext = self.bgContext else { return }
            bgContext.performAndWait { block(bgContext) }
        }
    }

    private func initBgContext() {
        if bgContext == nil {
            bgContext = persistentContainer.newBackgroundContext()
            bgContext?.automaticallyMergesChangesFromParent = true
        }
    }

    public final func save(_ managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("MainDataStore/will-save")
        do {
            managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            try managedObjectContext.save()
            DDLogInfo("MainDataStore/did-save")
        } catch {
            DDLogError("MainDataStore/save-error error=[\(error)]")
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

            let call = Call(context: managedObjectContext)
            call.callID = callID
            call.peerUserID = peerUserID
            call.type = type
            call.direction = direction
            call.timestamp = timestamp
            call.answered = false
            call.durationMs = 0.0
            call.endReason = .unknown

            managedObjectContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
            self.save(managedObjectContext)
            DispatchQueue.main.async {
                completion?(call)
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
        let managedObjectContext = managedObjectContext
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
        let managedObjectContext = managedObjectContext
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
        let managedObjectContext = managedObjectContext
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
            DDLogError("FeedData/fetchAndUpdateRetryCount/error  [\(error)]")
            fatalError("Failed to fetchAndUpdateRetryCount.")
        }
    }

}
