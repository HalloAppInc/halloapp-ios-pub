//
//  ChatDataLegacy.swift
//  HalloApp
//
//  Created by Garrett on 4/3/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreData

final class ChatDataLegacy {

    public init(persistentStoreURL: URL) {
        self.persistentStoreURL = persistentStoreURL
    }

    func fetchGroups() -> [ChatGroupLegacy] {
        let request = NSFetchRequest<ChatGroupLegacy>(entityName: "ChatGroup")
        do {
            return try persistentContainer.viewContext.fetch(request)
        } catch {
            return []
        }
    }

    func fetchMessages() -> [ChatMessageLegacy] {
        let request = NSFetchRequest<ChatMessageLegacy>(entityName: "ChatMessage")
        do {
            return try persistentContainer.viewContext.fetch(request)
        } catch {
            return []
        }
    }

    func fetchThreads() -> [ChatThreadLegacy] {
        let request = NSFetchRequest<ChatThreadLegacy>(entityName: "ChatThread")
        do {
            return try persistentContainer.viewContext.fetch(request)
        } catch {
            return []
        }
    }

    func fetchEvents() -> [ChatEventLegacy] {
        let request = NSFetchRequest<ChatEventLegacy>(entityName: "ChatEvent")
        do {
            return try persistentContainer.viewContext.fetch(request)
        } catch {
            return []
        }
    }

    func destroyStore() {
        DDLogInfo("ChatDataLegacy/destroy/start")

        // Delete SQlite database.
        let coordinator = self.persistentContainer.persistentStoreCoordinator
        do {
            let stores = coordinator.persistentStores
            stores.forEach { (store) in
                do {
                    try coordinator.remove(store)
                    DDLogError("ChatDataLegacy/destroy/remove-store/finised [\(store)]")
                }
                catch {
                    DDLogError("ChatDataLegacy/destroy/remove-store/error [\(error)]")
                }
            }

            try coordinator.destroyPersistentStore(at: persistentStoreURL, ofType: NSSQLiteStoreType, options: nil)
            DDLogInfo("ChatDataLegacy/destroy/delete-store/complete")
        }
        catch {
            DDLogError("ChatDataLegacy/destroy/delete-store/error [\(error)]")
        }

        do {
            try FileManager.default.removeItem(at: persistentStoreURL)
            DDLogInfo("ChatDataLegacy/deletePersistentStores: Deleted chat data")
        } catch {
            DDLogError("ChatDataLegacy/deletePersistentStores: Error deleting chat data: \(error)")
        }

        DDLogInfo("ChatDataLegacy/destroy/finished")
    }

    private let persistentStoreURL: URL

    private lazy var persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: persistentStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let container = NSPersistentContainer(name: "Chat")
        container.persistentStoreDescriptions = [ storeDescription ]
        container.loadPersistentStores(completionHandler: { (description, error) in
            if let error = error {
                DDLogError("Failed to load persistent store: \(error)")
                fatalError("Unable to load persistent store: \(error)")
            } else {
                DDLogInfo("ChatData/load-store/completed [\(description)]")
            }
        })
        return container
    }()
}
