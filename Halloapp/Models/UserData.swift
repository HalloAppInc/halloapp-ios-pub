//
//  UserData.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/20/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

import CoreData

final class UserData: ObservableObject {

    @Published var phone = ""
    @Published var isLoggedIn = false
    
    public var haveContactsSub = false
    public var haveFeedSub = false
    
    @Published var isOffline = true
    
    @Published var status = ""
    @Published var highlight = false

    @Published var hostName = "d.halloapp.dev"
//  @Published var userJIDString = "14154121848@s.halloapp.net/iphone"
//  @Published var userJIDString = "14088922686@s.halloapp.net/iphone"
    
    @Published var password = "11111111"
    
    @Published var isRegistered = false
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var subCancellable: AnyCancellable!
    private var validCharSet = CharacterSet(charactersIn: "1234567890+.-_ ")
    
    var xmppRegister: XMPPRegister?

    init() {

        self.getData()
        
        subCancellable = $phone.sink { val in
            
            if (val.rangeOfCharacter(from: self.validCharSet.inverted) != nil) {
                self.status = "Please enter only numbers"
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    self.status = ""
                }
                DispatchQueue.main.async {
                    self.phone = String(self.phone.unicodeScalars.filter {
                        self.validCharSet.contains($0)
                    })
                }
            }
            
            if (val.count > 25) {
                self.status = "Phone must be less than 25 numbers"
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    self.status = ""
                }
                DispatchQueue.main.async {
                    self.phone = String(val.prefix(25))
                }
            }
            
        }
    }

    deinit {
        subCancellable.cancel()
    }
    
    func setIsOffline(value: Bool) {
        self.isOffline = value
    }
    
    func setIsLoggedIn(value: Bool) {
        self.isLoggedIn = value
        self.saveData()
    }
    
    func setHaveContactsSub(value: Bool) {
        self.haveContactsSub = value
        self.saveData()
    }
    
    func setHaveFeedSub(value: Bool) {
        self.haveFeedSub = value
        self.saveData()
    }
    
    func logout() {
        deleteAllData(entityName: "User")
        deleteAllData(entityName: "ContactsCore")
        deleteAllData(entityName: "FeedCore")
        
        
        /* wipe in memory data */
        self.phone = ""
        self.isRegistered = false
        
        self.haveContactsSub = false
        self.haveFeedSub = false
        
        self.isLoggedIn = false
    }
    
    func validate() -> Bool {
  
        if (self.phone == "") {
            self.status = "Please enter a phone number"
            self.highlight = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self.status = ""
                self.highlight = false
            }
            return false
        } else if (self.phone.count < 5) {
            self.status = "Please enter valid phone number"
            self.highlight = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self.status = ""
                self.highlight = false
            }
            return false
        } else {
            if (self.isDataPresent()) {
                self.saveData()
            } else {
                self.createData()
            }
            self.register()
            return true
        }
    }
    
    func register() {
        
        do {
            
            try self.xmppRegister = XMPPRegister(phone: self.phone, password: self.password)
            
            if (self.xmppRegister != nil) {
            
                self.xmppRegister!.xmppStream.addDelegate(self, delegateQueue: DispatchQueue.main)
                
                self.cancellableSet.insert(
                 
                    self.xmppRegister!.didConnect.sink(receiveValue: { value in

                        print(value)
                        
                        if (value == "exists") {
                            self.isRegistered = true
                        } else if (value == "success") {
                            self.isRegistered = true
                        } else if (value == "too quick") {
                            self.status = "Error, please try again in 10 minutes"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                                self.status = ""
                            }
                            self.isRegistered = false
                        } else if (value == "error") {
                            self.status = "Could not login, please try again later"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                                self.status = ""
                            }
                            self.isRegistered = false
                        }
                        
                        self.xmppRegister!.xmppStream.disconnect()

                    })

                )
            }
            
        } catch {
            print("error connecting to xmpp register server")
        }
        

        
        
    }
    
    
    func createData() {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        let managedContext = appDelegate.persistentContainer.viewContext
        
        let userEntity = NSEntityDescription.entity(forEntityName: "User", in: managedContext)!
        
        let user = NSManagedObject(entity: userEntity, insertInto: managedContext)
        user.setValue(self.phone, forKeyPath: "phone")
        user.setValue(self.isLoggedIn, forKeyPath: "isLoggedIn")
        user.setValue(self.haveContactsSub, forKeyPath: "haveContactsSub")
        user.setValue(self.haveFeedSub, forKeyPath: "haveFeedSub")
        
        do {
            try managedContext.save()
        } catch let error as NSError {
            print("could not save. \(error), \(error.userInfo)")
        }
    }
    

    func saveData() {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        
        let managedContext = appDelegate.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "User")
        
        do {
            let result = try managedContext.fetch(fetchRequest)

            let objectUpdate = result[0] as! NSManagedObject
            objectUpdate.setValue(self.phone, forKey: "phone")
            objectUpdate.setValue(self.isLoggedIn, forKey: "isLoggedIn")
            objectUpdate.setValue(self.haveContactsSub, forKey: "haveContactsSub")
            objectUpdate.setValue(self.haveFeedSub, forKey: "haveFeedSub")
            do {
                try managedContext.save()
            } catch {
                print(error)
            }
            
        } catch  {
            print("failed")
        }
    }
    
    func deleteAllData(entityName: String) {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        
        let managedContext = appDelegate.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

        do {
            try managedContext.execute(batchDeleteRequest)
            print("Deleting \(entityName)")
        } catch {
            print("Delete error for \(entityName) error :", error)
        }
        
    }
    
    func getData() {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        
        let managedContext = appDelegate.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "User")
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            
            for data in result as! [NSManagedObject] {
                self.phone = data.value(forKey: "phone") as! String

//                print(data.value(forKey: "haveFeedSub") as! Bool?)
                if let isLoggedIn = data.value(forKey: "isLoggedIn") as! Bool? {
                    self.isLoggedIn = isLoggedIn
                } else {
                    self.isLoggedIn = false
                }

                if let haveContactsSub = data.value(forKey: "haveContactsSub") as! Bool? {
                    self.haveContactsSub = haveContactsSub
                } else {
                    self.haveContactsSub = false
                }
                
                if let haveFeedSub = data.value(forKey: "haveFeedSub") as! Bool? {
                    self.haveFeedSub = haveFeedSub
                } else {
                    self.haveFeedSub = false
                }
                
            }
            
        } catch  {
            print("failed")
        }
    }
    
    func isDataPresent() -> Bool {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return false
        }
        
        let managedContext = appDelegate.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "User")
        
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
