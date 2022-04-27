//
//  FeedDataLegacy.swift
//  HalloApp
//
//  Created by Garrett on 3/26/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreData

final class FeedDataLegacy {

    public init(persistentStoreURL: URL) {
        self.persistentStoreURL = persistentStoreURL
    }

    func fetchPosts() -> [FeedPostLegacy] {
        let request = NSFetchRequest<FeedPostLegacy>(entityName: "FeedPost")
        do {
            return try persistentContainer.viewContext.fetch(request)
        } catch {
            return []
        }
    }

    func fetchNotifications() -> [FeedNotification] {
        let request = NSFetchRequest<FeedNotification>(entityName: "FeedNotification")
        do {
            return try persistentContainer.viewContext.fetch(request)
        } catch {
            return []
        }
    }

    private let persistentStoreURL: URL

    private func loadPersistentContainer() {
        let container = self.persistentContainer
        DDLogDebug("FeedDataLegacy/loadPersistentStore Loaded [\(container)]")
    }

    private lazy var persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: persistentStoreURL)
        storeDescription.shouldMigrateStoreAutomatically = true
        storeDescription.shouldInferMappingModelAutomatically = true
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let container = NSPersistentContainer(name: "Feed")
        container.persistentStoreDescriptions = [storeDescription]
        self.loadPersistentStores(in: container)
        return container
    }()

    private func loadPersistentStores(in persistentContainer: NSPersistentContainer) {
        persistentContainer.loadPersistentStores { (description, error) in
            if let error = error {
                DDLogError("Failed to load persistent store: \(error)")
                fatalError("Unable to load persistent store: \(error)")
            } else {
                DDLogInfo("FeedDataLegacy/load-store/completed [\(description)]")
            }
        }
    }

    func destroyStore() {
        DDLogInfo("FeedDataLegacy/destroy/start")

        // Delete SQlite database.
        let coordinator = self.persistentContainer.persistentStoreCoordinator
        do {
            let stores = coordinator.persistentStores
            stores.forEach { (store) in
                do {
                    try coordinator.remove(store)
                    DDLogError("FeedDataLegacy/destroy/remove-store/finised [\(store)]")
                }
                catch {
                    DDLogError("FeedDataLegacy/destroy/remove-store/error [\(error)]")
                }
            }

            try coordinator.destroyPersistentStore(at: persistentStoreURL, ofType: NSSQLiteStoreType, options: nil)
            DDLogInfo("FeedDataLegacy/destroy/delete-store/complete")
        }
        catch {
            DDLogError("FeedDataLegacy/destroy/delete-store/error [\(error)]")
        }

        do {
            try FileManager.default.removeItem(at: persistentStoreURL)
            DDLogInfo("FeedDataLegacy/deletePersistentStores: Deleted feed data")
        } catch {
            DDLogError("FeedDataLegacy/deletePersistentStores: Error deleting feed data: \(error)")
        }


        DDLogInfo("FeedDataLegacy/destroy/finished")
    }
}
