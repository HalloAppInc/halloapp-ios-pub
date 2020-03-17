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

    func getAll() -> [FeedComment] {
        
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FeedComments")
        fetchRequest.sortDescriptors = [NSSortDescriptor.init(key: "timestamp", ascending: false)]
        do {
            let result = try managedContext.fetch(fetchRequest)
            
            
            var commentArr: [FeedComment] = []
            
            for data in result as! [NSManagedObject] {
                
                let item = FeedComment( id: data.value(forKey: "commentId") as! String,
                                        feedItemId: data.value(forKey: "feedItemId") as! String,
                                        parentCommentId: data.value(forKey: "parentCommentId") as! String,
                                        username: data.value(forKey: "username") as! String,
                                        userImageUrl: data.value(forKey: "userImageUrl") as! String,
                                        text: data.value(forKey: "text") as! String,
                                        timestamp: data.value(forKey: "timestamp") as! Double)
                
                commentArr.append(item)
   
            }
            
            return commentArr
            
        } catch  {
            DDLogError("failed")
        }
        
        return []
    }
    
    func get(feedItemId: String) -> [FeedComment] {
     
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
         
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FeedComments")

        let p1 = NSPredicate(format: "feedItemId = %@", feedItemId)
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [p1])

        fetchRequest.sortDescriptors = [NSSortDescriptor.init(key: "timestamp", ascending: false)]

        do {
            
            let result = try managedContext.fetch(fetchRequest)

            var commentArr: [FeedComment] = []

            for data in result as! [NSManagedObject] {
             
                let item = FeedComment( id: data.value(forKey: "commentId") as! String,
                                        feedItemId: data.value(forKey: "feedItemId") as! String,
                                        parentCommentId: data.value(forKey: "parentCommentId") as! String,
                                        username: data.value(forKey: "username") as! String,
                                        userImageUrl: data.value(forKey: "userImageUrl") as! String,
                                        text: data.value(forKey: "text") as! String,
                                        timestamp: data.value(forKey: "timestamp") as! Double)

                commentArr.append(item)

            }
         
            return commentArr
         
        } catch  {
            DDLogError("failed")
        }
     
        return []
    }
    
    func create(item: FeedComment) {
        
        let managedContext = CoreDataManager.sharedManager.bgContext
        
        managedContext.perform {

            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FeedComments")
            fetchRequest.predicate = NSPredicate(format: "commentId == %@", item.id)
            
            do {

                let result = try managedContext.fetch(fetchRequest)
                
                if (result.count > 0) {
                    return
                }
                
                let userEntity = NSEntityDescription.entity(forEntityName: "FeedComments", in: managedContext)!
                let obj = NSManagedObject(entity: userEntity, insertInto: managedContext)
                obj.setValue(item.id, forKeyPath: "commentId")
                obj.setValue(item.username, forKeyPath: "username")
                obj.setValue(item.userImageUrl, forKeyPath: "userImageUrl")
                obj.setValue(item.feedItemId, forKeyPath: "feedItemId")
                obj.setValue(item.parentCommentId, forKeyPath: "parentCommentId")
                obj.setValue(item.timestamp, forKeyPath: "timestamp")
                obj.setValue(item.text, forKeyPath: "text")
                
                do {
                    try managedContext.save()
                } catch let error as NSError {
                    DDLogError("could not save. \(error), \(error.userInfo)")
                }
                
            } catch  {
                DDLogError("failed")
            }
            
        }
    }
    
}
