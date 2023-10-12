//
//  PhotoSuggestionsData.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/5/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreData

final class PhotoSuggestionsData: NSObject, Sendable {

    private let persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: AppContext.photoSuggestionsStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let modelURL = Bundle(for: PhotoSuggestionsData.self).url(forResource: "PhotoSuggestions", withExtension: "momd")!
        let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL)
        let container = NSPersistentContainer(name: "PhotoSuggestions", managedObjectModel: managedObjectModel!)
        container.persistentStoreDescriptions = [storeDescription]
        container.loadPersistentStores { (description, error) in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()

    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }

    func reset() {
        do {
            try persistentContainer.persistentStoreCoordinator.destroyPersistentStore(at: AppContext.photoSuggestionsStoreURL, type: .sqlite)
        } catch {
            DDLogError("Failed to reset PhotoSuggestionsData")
        }

        persistentContainer.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        return persistentContainer.newBackgroundContext()
    }

    func performOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        persistentContainer.performBackgroundTask(block)
    }

    func performOnBackgroundContext<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async rethrows -> T {
        try await persistentContainer.performBackgroundTask(block)
    }

    func saveOnBackgroundContext<T>(_ block: @escaping @Sendable (NSManagedObjectContext) throws -> T) async throws -> T {
        try await persistentContainer.performBackgroundTask { context in
            let result = try block(context)

            if context.hasChanges {
                do {
                    try context.save()
                } catch {
                    DDLogError("PhotoSuggestionsData/saveOnBackgroundContext/failed: \(error)")
                    throw error
                }
            }

            return result
        }
    }
}
