//
//  PendingCore.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import CoreData

class PendingCore {

    func getAll() -> [PendingMedia] {
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<CPending>(entityName: "CPending")
        do {
            let results = try managedContext.fetch(fetchRequest)
            return results.compactMap{ PendingMedia($0) }
        } catch  {
            DDLogError("Failed to fetch temp media. [\(error)]")
            return []
        }
    }

    func create(item: PendingMedia) {
        let managedContext = CoreDataManager.sharedManager.bgContext
        managedContext.perform {
            guard let imageData = item.image?.jpegData(compressionQuality: 1.0) else { return }
            guard item.url != nil else { return }

            let fetchRequest = NSFetchRequest<CPending>(entityName: "CPending")
            fetchRequest.predicate = NSPredicate(format: "type == %@ && url == %@", item.type.rawValue, item.url!.absoluteString)
            do {
                let result = try managedContext.fetch(fetchRequest)
                guard result.isEmpty else { return }

                let pending = NSEntityDescription.insertNewObject(forEntityName: "CPending", into: managedContext) as! CPending
                pending.type = item.type.rawValue
                pending.url = item.url!.absoluteString
                pending.blob = imageData

                do {
                    try managedContext.save()
                } catch let error as NSError {
                    DDLogError("Failed to save new temp media. [\(error)]")
                }
            } catch  {
                DDLogError("Failed to fetch temp media. [\(error)]")
            }
        }
    }
    
    func delete(url: URL) {
        let managedContext = CoreDataManager.sharedManager.bgContext
        managedContext.perform {
            // TODO: switch to NSBatchDeleteRequest
            let fetchRequest = NSFetchRequest<CPending>(entityName: "CPending")
            fetchRequest.predicate = NSPredicate(format: "url == %@", url.absoluteString)
            do {
                let results = try managedContext.fetch(fetchRequest)
                guard !results.isEmpty else { return }

                for item in results {
                    managedContext.delete(item)
                }
                do {
                    try managedContext.save()
                } catch {
                    DDLogError("Failed to delete temp media. [\(error)]")
                }
            } catch  {
                DDLogError("Failed to fetch temp media. [\(error)]")
            }
        }
    }
}
