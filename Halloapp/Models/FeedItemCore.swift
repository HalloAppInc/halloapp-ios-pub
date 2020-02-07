//
//  FeedDataCore.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/3/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import SwiftUI
import Combine
import CoreData

class FeedItemCore {

    func getAll() -> [FeedDataItem] {
        
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FeedCore")
        fetchRequest.fetchOffset = 0
        fetchRequest.fetchLimit = 100 // 125 have some lag 
        
        fetchRequest.sortDescriptors = [NSSortDescriptor.init(key: "timestamp", ascending: false)]
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            
            var feedArr: [FeedDataItem] = []
            
            for data in result as! [NSManagedObject] {
                
                let item = FeedDataItem(
                    itemId: data.value(forKey: "itemId") as! String,
                    username: data.value(forKey: "username") as! String,
                    imageUrl: data.value(forKey: "imageUrl") as! String,
                    userImageUrl: data.value(forKey: "userImageUrl") as! String,
                    text: (data.value(forKey: "text") as? String) ?? "",
                    unreadComments: (data.value(forKey: "unreadComments") as? Int) ?? 0,
                    timestamp: data.value(forKey: "timestamp") as! Double
                )
                
//                if let imageData = data.value(forKey: "imageBlob") as? Data {
//                    if let imageData2 = UIImage(data: imageData) {
//                        item.image = imageData2
//                    }
//                }
                
                
                feedArr.append(item)

            }
            
//            completion(feedArr)
//            self.pushAllItems(items: feedArr)
            
            return feedArr
            
        } catch  {
            print("failed")
        }
        
        print("returning with empty array 2")
        return []
    }
    
    func create(item: FeedDataItem) {

        let managedContext = CoreDataManager.sharedManager.bgContext

        managedContext.perform {
        
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FeedCore")
            fetchRequest.predicate = NSPredicate(format: "itemId == %@", item.itemId)
            
            do {
                let result = try managedContext.fetch(fetchRequest)
                
                if (result.count > 0) {
                    return
                }
                
                let userEntity = NSEntityDescription.entity(forEntityName: "FeedCore", in: managedContext)!
                
                let obj = NSManagedObject(entity: userEntity, insertInto: managedContext)
                obj.setValue(item.itemId, forKeyPath: "itemId")
                obj.setValue(item.username, forKeyPath: "username")
                obj.setValue(item.userImageUrl, forKeyPath: "userImageUrl")
                obj.setValue(item.imageUrl, forKeyPath: "imageUrl")
                obj.setValue(item.timestamp, forKeyPath: "timestamp")
                obj.setValue(item.text, forKeyPath: "text")
                obj.setValue(item.unreadComments, forKeyPath: "unreadComments")
                
                do {
                    try managedContext.save()
                } catch let error as NSError {
                    print("could not save. \(error), \(error.userInfo)")
                }
                
            } catch  {
                print("failed")
            }

        }
    }
    
    func isPresent(itemId: String) -> Bool {
        
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FeedCore")
        
        fetchRequest.predicate = NSPredicate(format: "itemId == %@", itemId)
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            
            if (result.count > 0) {

                return true
            } else {

                return false
            }
            
        } catch  {
            print("failed")
        }
        
        return false
    }
    
    func update(item: FeedDataItem) {
        
        let managedContext = CoreDataManager.sharedManager.bgContext
        
        managedContext.perform {

            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FeedCore")
            fetchRequest.predicate = NSPredicate(format: "itemId == %@", item.itemId)
            
            do {
                let result = try managedContext.fetch(fetchRequest)
                
                if (result.count == 0) {
                    return
                }
                
                let objectUpdate = result[0] as! NSManagedObject
                objectUpdate.setValue(item.unreadComments, forKey: "unreadComments")
                
                do {
                    try managedContext.save()
                } catch {
                    print(error)
                }
            
                do {
                    try managedContext.save()
                } catch {
                    print(error)
                }
                
            } catch  {
                print("failed")
            }
        }
    }

    func delete(itemId: String) {
        
        let managedContext = CoreDataManager.sharedManager.bgContext

        managedContext.perform {
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FeedCore")
            
            fetchRequest.predicate = NSPredicate(format: "itemId == %@", itemId)
            
            do {
                let result = try managedContext.fetch(fetchRequest)

                if (result.count == 0) {
                    return
                }
                
                let objectToDelete = result[0] as! NSManagedObject
                managedContext.delete(objectToDelete)
                
                do {
                    try managedContext.save()
                } catch {
                    print(error)
                }
                
            } catch  {
                print("failed")
            }
        }
    }

}
