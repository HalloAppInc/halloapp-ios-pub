//
//  NotificationStore.swift
//  Core
//
//  Created by Murali Balusu on 11/17/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift
import Combine
import CoreData

// Delegate to notify changes to current in-memory sessions.
public protocol NotificationStoreDelegate: AnyObject {
    func notificationStoreContextChanged()
}

open class NotificationStore {
    public let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.notificationStore")
    public let appTarget: AppTarget
    private let bgQueueKey = DispatchSpecificKey<String>()
    private let bgQueueValue = "com.halloapp.notificationStore"
    private var bgContext: NSManagedObjectContext
    public weak var delegate: NotificationStoreDelegate?

    required public init(appTarget: AppTarget, userDefaults: UserDefaults) {
        // Before fetching the latest context for this target.
        // Let us update their last history timestamp: this will be useful when pruning old transactions later.
        userDefaults.updateLastHistoryTransactionTimestamp(for: appTarget, to: Date())
        self.bgContext = persistentContainer.newBackgroundContext()
        // Set the context name and transaction author name.
        // This is used later to filter out transactions made by own context.
        self.bgContext.name = appTarget.rawValue + "-notificationStoreContext"
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
                    self.delegate?.notificationStoreContextChanged()
                }
            } catch {
                DDLogError("KeyStore/PersistentHistoryTracking failed with error: \(error)")
            }
        })
    }

    // MARK: CoreData stack

    private class var persistentStoreURL: URL {
        get {
            return AppContext.notificationStoreURL
        }
    }

    private func loadPersistentStores(in persistentContainer: NSPersistentContainer) {
        persistentContainer.loadPersistentStores { (description, error) in
            if let error = error {
                DDLogError("Deleting persistent store at [\(NotificationStore.persistentStoreURL.absoluteString)]")
                fatalError("Unable to load persistent store: \(error)")
            } else {
                DDLogInfo("KeyStore/load-store/completed [\(description)]")
            }
        }
    }

    public private(set) var persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: NotificationStore.persistentStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSPersistentHistoryTrackingKey)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let modelURL = Bundle(for: NotificationStore.self).url(forResource: "PushNotifications", withExtension: "momd")!
        let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL)
        let container = NSPersistentContainer(name: "PushNotifications", managedObjectModel: managedObjectModel!)
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
    private func save(_ managedObjectContext: NSManagedObjectContext) -> Bool {
        DDLogVerbose("NotificationStore/will-save")
        do {
            managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            try managedObjectContext.save()
            DDLogVerbose("NotificationStore/did-save")
            return true
        } catch {
            DDLogError("NotificationStore/save-error error=[\(error)]")
            return false
        }
    }

    private func notificationStatus(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext) -> NotificationStatus? {
        let managedObjectContext = managedObjectContext
        let fetchRequest: NSFetchRequest<NotificationStatus> = NotificationStatus.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let statuses = try managedObjectContext.fetch(fetchRequest)
            return statuses.first
        }
        catch {
            DDLogError("KeyStore/fetchUserKeyBundle/error  [\(error)]")
            fatalError("Failed to fetch key bundle")
        }
    }

    public func save(id contentId: String, type contentTypeRaw: String) {
        self.performSeriallyOnBackgroundContext { managedObjectContext in
            DDLogInfo("NotificationStore/save/contentId: \(contentId)/contentTypeRaw: \(contentTypeRaw)")
            let notificationStatus = NotificationStatus(context: managedObjectContext)
            notificationStatus.contentId = contentId
            notificationStatus.contentTypeRaw = contentTypeRaw
            notificationStatus.timestamp = Date()
            self.save(managedObjectContext)
        }
    }

    public func runIfNotificationWasNotPresented(for contentId: String, completion: @escaping () -> Void) {
        self.isPushPresented(for: contentId) { result in
            if !result {
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    public func isPushPresented(for contentId: String, completion: @escaping (Bool) -> Void) {
        self.performSeriallyOnBackgroundContext { managedObjectContext in
            if self.notificationStatus(predicate: NSPredicate(format: "contentId == %@", contentId), in: managedObjectContext) != nil {
                DDLogInfo("NotificationStore/isPushPresented/contentId: \(contentId)/true")
                completion(true)
            } else {
                DDLogInfo("NotificationStore/isPushPresented/contentId: \(contentId)/false")
                completion(false)
            }
        }
    }
}

