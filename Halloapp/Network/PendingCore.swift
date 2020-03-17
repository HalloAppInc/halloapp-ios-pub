//
//  PendingCore.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import CoreData
import Foundation
import SwiftUI

class PendingCore {

    func getAll() -> [FeedMedia] {
        
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CPending")
        
//        fetchRequest.sortDescriptors = [NSSortDescriptor.init(key: "order", ascending: false)]
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            
            var arr: [FeedMedia] = []
            
            for data in result as! [NSManagedObject] {
                let item = FeedMedia(
                    type: data.value(forKey: "type") as! String,
                    url: data.value(forKey: "url") as! String
                )
                
                if let blob = data.value(forKey: "blob") as? Data {
                    if let image = UIImage(data: blob) {
                        item.image = image
                    }
                }
                
                arr.append(item)

            }
            
            return arr
            
        } catch  {
            DDLogError("failed")
            return []
        }
    }

    func create(item: FeedMedia) {
        
        let managedContext = CoreDataManager.sharedManager.bgContext
        
        managedContext.perform {
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CPending")

            fetchRequest.predicate = NSPredicate(format: "type == %@ && url == %@", item.type, item.url)
            
            do {
                
                let result = try managedContext.fetch(fetchRequest)
                
                if result.count > 0 {
                    return
                }
            
                let userEntity = NSEntityDescription.entity(forEntityName: "CPending", in: managedContext)!
                
                let obj = NSManagedObject(entity: userEntity, insertInto: managedContext)
                obj.setValue(item.type, forKeyPath: "type")
                obj.setValue(item.url, forKeyPath: "url")
                
                let image = item.image.jpegData(compressionQuality: 1.0)
                
                if image == nil {
                    return
                }
                
                if image != nil {
                    obj.setValue(image, forKeyPath: "blob")
                }
                
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
    
    
    func delete(url: String) {
        
        let managedContext = CoreDataManager.sharedManager.bgContext

        managedContext.perform {
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CPending")
            
            fetchRequest.predicate = NSPredicate(format: "url == %@", url)
            
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
                    DDLogError("\(error)")
                }
                
            } catch  {
                DDLogError("failed")
            }
        }
        
    }
    
}



