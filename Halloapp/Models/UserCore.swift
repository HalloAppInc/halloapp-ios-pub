//
//  UserCore.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/4/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import CoreData

fileprivate class CoreDataManager {

    static let shared = CoreDataManager()

    lazy var persistentContainer: NSPersistentContainer = {
        /*
         The persistent container for the application. This implementation
         creates and returns a container, having loaded the store for the
         application to it. This property is optional since there are legitimate
         error conditions that could cause the creation of the store to fail.
        */
        let container = NSPersistentContainer(name: "Halloapp")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()

}

class UserCore {

    static func fetch() -> User? {
        return fetch(using: CoreDataManager.shared.persistentContainer.viewContext)
    }

    static func fetch(using managedObjectContext: NSManagedObjectContext) -> User? {
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let result = try managedObjectContext.fetch(fetchRequest)
            return result.first
        } catch  {
            DDLogError("usercore/fetch/error [\(error)]")
            fatalError()
        }
    }

    static func save(countryCode: String, phoneInput: String, normalizedPhoneNumber: String,
                     userId: String, password: String, name: String) {
        let managedObjectContext = CoreDataManager.shared.persistentContainer.viewContext
        var user = self.fetch(using: managedObjectContext)
        if user == nil {
            user = NSEntityDescription.insertNewObject(forEntityName: User.entity().name!, into: managedObjectContext) as? User
        }
        user?.countryCode = countryCode
        user?.phoneInput = phoneInput
        user?.phone = normalizedPhoneNumber
        user?.userId = userId
        user?.password = password
        user?.name = name
        do {
            try managedObjectContext.save()
        } catch let error as NSError {
            DDLogError("usercore/save/error [\(error)]")
            fatalError()
        }
    }
    
}
