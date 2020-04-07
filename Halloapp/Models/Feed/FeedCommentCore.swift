//
//  FeedCommentCore.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/3/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import CoreData

class FeedCommentCore {

    class func items(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil) -> [FeedComment] {
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<FeedComments>(entityName: FeedComments.entity().name!)
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        do {
            let results = try managedContext.fetch(fetchRequest)
            return results.map{ FeedComment($0) }
        } catch  {
            DDLogError("Failed to fetch comments. [\(error)]")
        }

        return []
    }

    class func getAll() -> [FeedComment] {
        return FeedCommentCore.items(sortDescriptors: [ NSSortDescriptor(keyPath: \FeedComments.timestamp, ascending: false) ])
    }

    class func comment(withIdentifier identifier: String) -> FeedComment? {
        return FeedCommentCore.items(predicate: NSPredicate(format: "commentId == %@", identifier)).first
    }

    class func create(item: FeedComment) {
        let managedContext = CoreDataManager.sharedManager.bgContext
        managedContext.perform {
            let fetchRequest = NSFetchRequest<FeedComments>(entityName: "FeedComments")
            fetchRequest.predicate = NSPredicate(format: "commentId == %@", item.id)
            do {
                let result = try managedContext.fetch(fetchRequest)
                guard result.isEmpty else { return }

                let comment = NSEntityDescription.insertNewObject(forEntityName: "FeedComments", into: managedContext) as! FeedComments
                comment.commentId = item.id
                comment.parentCommentId = item.parentCommentId
                comment.feedItemId = item.feedItemId
                comment.username = item.username
                comment.timestamp = item.timestamp.timeIntervalSince1970
                comment.text = item.text

                do {
                    try managedContext.save()
                } catch {
                    DDLogError("Failed to save new comment. [\(error)]")
                }
            } catch  {
                DDLogError("Failed to fetch comments. [\(error)]")
            }
        }
    }
}
