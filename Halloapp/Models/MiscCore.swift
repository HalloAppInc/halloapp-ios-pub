//
//  MiscCore.swift
//  Halloapp
//
//  Created by Tony Jiang on 3/11/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CoreData

class MiscCore {

    func get() -> (String) {
                        
        var resultStr: String = ""
                        
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CMisc")
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            
            for data in result as! [NSManagedObject] {

                if let logs = data.value(forKey: "logs") as! String? {
                    resultStr = logs
                }
                
            }
            
        } catch  {
            print("failed")
        }
                        
        return resultStr
    }
    
    func create(logs: String) {
        let managedContext = CoreDataManager.sharedManager.bgContext

        managedContext.perform {
        
            let userEntity = NSEntityDescription.entity(forEntityName: "CMisc", in: managedContext)!
            
            let user = NSManagedObject(entity: userEntity, insertInto: managedContext)
            user.setValue(logs, forKeyPath: "logs")
            
            do {
                try managedContext.save()
            } catch let error as NSError {
                print("could not save. \(error), \(error.userInfo)")
            }
        }
    }
    
    func update(logs: String) {
        
        let managedContext = CoreDataManager.sharedManager.bgContext

        managedContext.perform {
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CMisc")
            
            do {
                let result = try managedContext.fetch(fetchRequest)
                
                if (result.count == 0) {
                    return
                }
                
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CMisc")
                
                do {
                    let result = try managedContext.fetch(fetchRequest)

                    let objectUpdate = result[0] as! NSManagedObject
                    objectUpdate.setValue(logs, forKey: "logs")
                    
                    do {
                        try managedContext.save()
                    } catch {
                        print(error)
                    }
                    
                } catch  {
                    print("failed")
                }
                
                
            } catch  {
                print("failed")
            }
            
        }
        
    }
    
    
    func isPresent() -> Bool {
        
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CMisc")
        
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
    
    
}
