//
//  ContactCore.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/3/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import SwiftUI
import Combine
import CoreData

class ContactCore {

    func getAll() -> [NormContact] {
    
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ContactsCore")
        
        fetchRequest.sortDescriptors = [NSSortDescriptor.init(key: "name", ascending: false)]
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            
            var contactsArr: [NormContact] = []
            
            for data in result as! [NSManagedObject] {
                var item = NormContact(
                    phone: data.value(forKey: "phone") as! String,
                    name: data.value(forKey: "name") as! String,
                    
                    isConnected: data.value(forKey: "isConnected") as! Bool,
                    timeLastChecked: data.value(forKey: "timeLastChecked") as! Double
                )
                
                if let normPhone = data.value(forKey: "normPhone") as? String {
                    item.normPhone = normPhone
                }
                
                if let isWhiteListed = data.value(forKey: "isWhiteListed") as? Bool {
                    item.isWhiteListed = isWhiteListed
                }

                if let isNormalized = data.value(forKey: "isNormalized") as? Bool {
                    item.isNormalized = isNormalized
                }
                
                contactsArr.append(item)

            }
            
//            self.pushAllItems(items: contactsArr)
            
            return contactsArr
            
        } catch  {
            print("failed")
            return []
            
        }
    }
    
    // not in use?
    func get(phone: String) -> Bool {
        
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
         
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ContactsCore")
         
        fetchRequest.predicate = NSPredicate(format: "phone == %@", phone)
         
        do {
            let result = try managedContext.fetch(fetchRequest)

            for data in result as! [NSManagedObject] {
                var item = NormContact(
                    phone: data.value(forKey: "phone") as! String,
                    name: data.value(forKey: "name") as! String,

                    isConnected: data.value(forKey: "isConnected") as! Bool,
                    timeLastChecked: data.value(forKey: "timeLastChecked") as! Double
                )

                if let normPhone = data.value(forKey: "normPhone") as? String {
                    item.normPhone = normPhone
                }

                if let isWhiteListed = data.value(forKey: "isWhiteListed") as? Bool {
                    item.isWhiteListed = isWhiteListed
                }

                if let isNormalized = data.value(forKey: "isNormalized") as? Bool {
                    item.isNormalized = isNormalized
                }
             
            }
         
        } catch  {
            print("failed")
        }
         
        return false
     }
    
    func isPresent(phone: String) -> Bool {
        
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ContactsCore")
        
        fetchRequest.predicate = NSPredicate(format: "phone == %@", phone)
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            
            if (result.count > 0) {
                return true
            } else {

                return false
            }
            
        } catch  {
            print("failed")
            return false
        }
        
    }
    
    func create(item: NormContact) {
        
        let managedContext = CoreDataManager.sharedManager.bgContext
        
        managedContext.perform {
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ContactsCore")
            
            fetchRequest.predicate = NSPredicate(format: "phone == %@", item.phone)
            
            do {
                let result = try managedContext.fetch(fetchRequest)
                
                if (result.count > 0) {
                    return
                }
   
                let userEntity = NSEntityDescription.entity(forEntityName: "ContactsCore", in: managedContext)!
                
                let obj = NSManagedObject(entity: userEntity, insertInto: managedContext)
                
                obj.setValue(item.phone, forKeyPath: "phone")
                obj.setValue(item.normPhone, forKeyPath: "normPhone")
                
                obj.setValue(item.name, forKeyPath: "name")
                
                obj.setValue(item.isConnected, forKeyPath: "isConnected")
                obj.setValue(item.isWhiteListed, forKeyPath: "isWhiteListed")
                obj.setValue(item.isNormalized, forKeyPath: "isNormalized")
                
                obj.setValue(item.timeLastChecked, forKeyPath: "timeLastChecked")
                
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
    
    func update(item: NormContact) {
        
        let managedContext = CoreDataManager.sharedManager.bgContext
        
        managedContext.perform {

            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ContactsCore")
            
            fetchRequest.predicate = NSPredicate(format: "phone == %@", item.phone)
            
            do {
                let result = try managedContext.fetch(fetchRequest)

                if (result.count == 0) {
                    return
                }
                
                let objectUpdate = result[0] as! NSManagedObject
                objectUpdate.setValue(item.phone, forKey: "phone")
                objectUpdate.setValue(item.normPhone, forKey: "normPhone")
                objectUpdate.setValue(item.name, forKey: "name")
                
                objectUpdate.setValue(item.isConnected, forKey: "isConnected")
                objectUpdate.setValue(item.isWhiteListed, forKey: "isWhiteListed")
                objectUpdate.setValue(item.isNormalized, forKey: "isNormalized")
                objectUpdate.setValue(item.timeLastChecked, forKey: "timeLastChecked")
                
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
    
    func delete(item: NormContact) {
        
        let managedContext = CoreDataManager.sharedManager.bgContext

        managedContext.perform {
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ContactsCore")
            
            fetchRequest.predicate = NSPredicate(format: "phone == %@", item.phone)
            
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
