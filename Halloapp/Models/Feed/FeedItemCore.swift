//
//  FeedDataCore.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/3/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import CoreData

class FeedItemCore {

    class func items(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil) -> [FeedDataItem] {
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<FeedCore>(entityName: FeedCore.entity().name!)
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        do {
            let results = try managedContext.fetch(fetchRequest)
            return results.map{ FeedDataItem($0) }
        } catch  {
            DDLogError("Failed to fetch feed posts. [\(error)]")
        }

        return []
    }

    class func getAll() -> [FeedDataItem] {
        return FeedItemCore.items(sortDescriptors: [ NSSortDescriptor(keyPath: \FeedCore.timestamp, ascending: false) ])
    }

    class func items<T: CVarArg>(withIdentifiers identifiers: T) -> [FeedDataItem] {
        return FeedItemCore.items(predicate: NSPredicate(format: "itemId in %@", identifiers))
    }
    
    class func create(item: FeedDataItem) {
        let managedContext = CoreDataManager.sharedManager.bgContext
        managedContext.perform {
            let fetchRequest = NSFetchRequest<FeedCore>(entityName: "FeedCore")
            fetchRequest.predicate = NSPredicate(format: "itemId == %@", item.itemId)
            do {
                let result = try managedContext.fetch(fetchRequest)
                guard result.isEmpty else { return }

                let feedPost = NSEntityDescription.insertNewObject(forEntityName: "FeedCore", into: managedContext) as! FeedCore
                feedPost.itemId = item.itemId
                feedPost.username = item.username
                feedPost.text = item.text
                feedPost.unreadComments = Int16(item.unreadComments)
                feedPost.mediaHeight = Int16(item.mediaHeight ?? 0)
                feedPost.timestamp = item.timestamp.timeIntervalSince1970

                do {
                    try managedContext.save()
                } catch {
                    DDLogError("Failed to save new feed post. [\(error)]")
                }
            } catch  {
                DDLogError("Failed to fetch feed posts. [\(error)]")
            }
        }
    }
    
    class func isPresent(itemId: String) -> Bool {
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<FeedCore>(entityName: "FeedCore")
        fetchRequest.predicate = NSPredicate(format: "itemId == %@", itemId)
        do {
            let results = try managedContext.fetch(fetchRequest)
            return !results.isEmpty
        } catch {
            DDLogError("Failed to fetch feed posts. [\(error)]")
        }
        return false
    }

    class func update(item: FeedDataItem) {
        let managedContext = CoreDataManager.sharedManager.bgContext
        managedContext.perform {
            let fetchRequest = NSFetchRequest<FeedCore>(entityName: "FeedCore")
            fetchRequest.predicate = NSPredicate(format: "itemId == %@", item.itemId)
            do {
                let results = try managedContext.fetch(fetchRequest)
                guard !results.isEmpty else { return }

                let feedItem = results.first!
                feedItem.unreadComments = Int16(item.unreadComments)

                do {
                    try managedContext.save()
                } catch {
                    DDLogError("Failed to update feed post. [\(error)]")
                }
            } catch  {
                DDLogError("Failed to fetch feed posts. [\(error)]")
            }
        }
    }

    class func delete(itemId: String) {
        let managedContext = CoreDataManager.sharedManager.bgContext
        managedContext.perform {
            let fetchRequest = NSFetchRequest<FeedCore>(entityName: "FeedCore")
            fetchRequest.predicate = NSPredicate(format: "itemId == %@", itemId)
            do {
                let results = try managedContext.fetch(fetchRequest)
                guard !results.isEmpty else { return }

                for item in results {
                    managedContext.delete(item)
                }
                do {
                    try managedContext.save()
                } catch {
                    DDLogError("Failed to delete feed posts. [\(error)]")
                }
            } catch {
                DDLogError("Failed to fetch feed posts. [\(error)]")
            }
        }
    }
}
