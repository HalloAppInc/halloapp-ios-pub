//
//  UserCore.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/4/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import CoreData

class UserCore {

    func get() -> ( String,
                    String,
                    String,
                    String,
                    String,
                    Bool) {
                        
        var countryCode: String = "1"
        var phoneInput: String = ""
        var userId: String = ""
        var password: String = ""
        var phone: String = ""
        var isLoggedIn: Bool = false
                        
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "User")
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            
            for data in result as! [NSManagedObject] {

                if let countryCodeData = data.value(forKey: "countryCode") as! String? {
                    countryCode = countryCodeData
                }
                
                if let phoneInputData = data.value(forKey: "phoneInput") as! String? {
                    phoneInput = phoneInputData
                }
                
                userId = data.value(forKey: "userId") as! String
                phone = data.value(forKey: "phone") as! String
                
                if let passwordData = data.value(forKey: "password") as! String? {
                    password = passwordData
                }
                    
                if let isLoggedInData = data.value(forKey: "isLoggedIn") as! Bool? {
                    isLoggedIn = isLoggedInData
                } else {
                    isLoggedIn = false
                }

            }
            
        } catch  {
            DDLogError("usercore/get failed")
        }
                        
        return (countryCode, phoneInput, userId, password, phone, isLoggedIn)
    }
    
    func create(countryCode: String,
                phoneInput: String,
                userId: String,
                password: String,
                phone: String,
                isLoggedIn: Bool) {
        let managedContext = CoreDataManager.sharedManager.bgContext

        managedContext.perform {
        
            let userEntity = NSEntityDescription.entity(forEntityName: "User", in: managedContext)!
            
            let user = NSManagedObject(entity: userEntity, insertInto: managedContext)
            user.setValue(countryCode, forKeyPath: "countryCode")
            user.setValue(phoneInput, forKeyPath: "phoneInput")
            user.setValue(phone, forKeyPath: "phone")
            user.setValue(userId, forKeyPath: "userId")
            user.setValue(password, forKeyPath: "password")
            user.setValue(isLoggedIn, forKeyPath: "isLoggedIn")
            
            do {
                try managedContext.save()
            } catch let error as NSError {
                DDLogError("usercore/create \(error), \(error.userInfo)")
            }
        }
    }
    
    func update(countryCode: String,
                phoneInput: String,
                userId: String,
                password: String,
                phone: String,
                isLoggedIn: Bool) {
        
        let managedContext = CoreDataManager.sharedManager.bgContext

        managedContext.perform {
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "User")
            
            do {
                let result = try managedContext.fetch(fetchRequest)
                
                if (result.count == 0) {
                    return
                }
                
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "User")
                
                do {
                    let result = try managedContext.fetch(fetchRequest)

                    let objectUpdate = result[0] as! NSManagedObject
                    objectUpdate.setValue(countryCode, forKey: "countryCode")
                    objectUpdate.setValue(phoneInput, forKey: "phoneInput")
                    objectUpdate.setValue(userId, forKey: "userId")
                    objectUpdate.setValue(password, forKey: "password")
                    objectUpdate.setValue(phone, forKey: "phone")
                    objectUpdate.setValue(isLoggedIn, forKey: "isLoggedIn")
                    
                    do {
                        try managedContext.save()
                    } catch {
                        DDLogError("usercore/update \(error)")
                    }
                } catch  {
                    DDLogError("usercore/update failed")
                }
            } catch  {
                DDLogError("usercore/update failed")
            }
        }
    }
    
    
    func isPresent() -> Bool {
        
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "User")
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            
            if (result.count > 0) {
                return true
            } else {
                return false
            }
        } catch  {
            DDLogError("failed")
        }
        
        return false
    }
    
}
