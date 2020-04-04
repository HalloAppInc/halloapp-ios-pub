//
//  FeedMediaCore.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import CoreData

class FeedMediaCore {

    func get(feedItemId: String) -> [FeedMedia] {
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<CFeedImage>(entityName: "CFeedImage")
        fetchRequest.predicate = NSPredicate(format: "feedItemId = %@", feedItemId)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \CFeedImage.order, ascending: true) ]
        do {
            let results = try managedContext.fetch(fetchRequest)
            return results.compactMap{ FeedMedia($0) }
        } catch  {
            DDLogError("Failed to fetch media. [\(error)]")
            return []
        }
    }

    func create(item: FeedMedia) {
        let managedContext = CoreDataManager.sharedManager.bgContext
        managedContext.perform {
            let fetchRequest = NSFetchRequest<CFeedImage>(entityName: "CFeedImage")
            fetchRequest.predicate = NSPredicate(format: "feedItemId == %@ AND url == %@", item.feedItemId, item.url.absoluteString)
            do {
                let result = try managedContext.fetch(fetchRequest)
                guard result.isEmpty else { return }

                let media = NSEntityDescription.insertNewObject(forEntityName: "CFeedImage", into: managedContext) as! CFeedImage
                media.feedItemId = item.feedItemId
                media.type = item.type.rawValue
                media.order = Int16(item.order)
                media.url = item.url.absoluteString
                media.width = Int16(item.size.width)
                media.height = Int16(item.size.height)
                media.key = item.key
                media.sha256hash = item.sha256hash
                media.numTries = Int16(item.numTries)

                do {
                    try managedContext.save()
                } catch {
                    DDLogError("Failed to save new media. [\(error)]")
                }
            } catch  {
                DDLogError("Failed to fetch media. [\(error)]")
            }
        }
    }
        
    func updateBlob(feedItemId: String, url: URL, data: Data) {
        let managedContext = CoreDataManager.sharedManager.bgContext
        managedContext.perform {
            let fetchRequest = NSFetchRequest<CFeedImage>(entityName: "CFeedImage")
            fetchRequest.predicate = NSPredicate(format: "feedItemId == %@ AND url == %@", feedItemId, url.absoluteString)
            do {
                let result = try managedContext.fetch(fetchRequest)
                guard !result.isEmpty else { return }

                let media = result.first!
                media.blob = data
                do {
                    try managedContext.save()
                } catch {
                    DDLogError("Failed to update media. [\(error)]")
                }
            } catch  {
                DDLogError("Failed to fetch media. [\(error)]")
            }
        }
    }
    
    func updateImage(feedItemId: String, url: URL, thumb: UIImage, orig: UIImage) {
        let managedContext = CoreDataManager.sharedManager.bgContext
        managedContext.perform {
            guard let thumbData = thumb.jpegData(compressionQuality: 1.0) else {
                DDLogError("Failed to generate JPEG data for thumbnail. [\(feedItemId)]:[\(url)]")
                return
            }
            guard let origData = orig.jpegData(compressionQuality: 1.0) else {
                DDLogError("Failed to generate JPEG data for fullsize image. [\(feedItemId)]:[\(url)]")
                return
            }

            let fetchRequest = NSFetchRequest<CFeedImage>(entityName: "CFeedImage")
            fetchRequest.predicate = NSPredicate(format: "feedItemId == %@ AND url == %@", feedItemId, url.absoluteString)
            do {
                let result = try managedContext.fetch(fetchRequest)
                guard !result.isEmpty else { return }

                let media = result.first!
                media.smallBlob = thumbData
                media.blob = origData
                do {
                    try managedContext.save()
                } catch {
                    DDLogError("Failed to update media. [\(error)]")
                }
            } catch  {
                DDLogError("Failed to fetch media. [\(error)]")
            }
        }
    }
    
    func updateNumTries(feedItemId: String, url: URL, numTries: Int) {
        let managedContext = CoreDataManager.sharedManager.bgContext
        managedContext.perform {
            let fetchRequest = NSFetchRequest<CFeedImage>(entityName: "CFeedImage")
            fetchRequest.predicate = NSPredicate(format: "feedItemId == %@ AND url == %@", feedItemId, url.absoluteString)
            do {
                let result = try managedContext.fetch(fetchRequest)
                guard !result.isEmpty else { return }

                let media = result.first!
                media.numTries = Int16(numTries)
                do {
                    try managedContext.save()
                } catch {
                    DDLogError("Failed to update media. [\(error)]")
                }
            } catch  {
                DDLogError("Failed to fetch media. [\(error)]")
            }
        }
    }
    
    func delete(feedItemId: String, url: URL) {
        let managedContext = CoreDataManager.sharedManager.bgContext
        managedContext.perform {
            let fetchRequest = NSFetchRequest<CFeedImage>(entityName: "CFeedImage")
            fetchRequest.predicate = NSPredicate(format: "feedItemId == %@ AND url == %@", feedItemId, url.absoluteString)
            do {
                // TODO: Use NSBatchDeleteRequest
                let result = try managedContext.fetch(fetchRequest)
                guard !result.isEmpty else { return }

                for item in result {
                    managedContext.delete(item)
                }

                do {
                    try managedContext.save()
                } catch {
                    DDLogError("Failed to delete media. [\(error)]")
                }
            } catch  {
                DDLogError("Failed to fetch media. [\(error)]")
            }
        }
    }
}
