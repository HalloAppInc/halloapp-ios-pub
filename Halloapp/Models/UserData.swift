//
//  UserData.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/20/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Foundation
import Combine
import MessageUI
import SwiftUI

import CoreData

final class UserData: ObservableObject {

    var didLogOff = PassthroughSubject<Void, Never>()
    
    var didResyncContacts = PassthroughSubject<Void, Never>()
    
    @Published var countryCode = "1"
    
    @Published var phoneInput = ""
    
    @Published var phone = ""
    @Published var isLoggedIn = false
    
    @Published var status: String = ""
    @Published var highlight = false
    
    @Published var highlightCountryCode = false

    public var hostName = "s.halloapp.net"
//    @Published var hostName = "s-test.halloapp.net"
    
//  @Published var userJIDString = "14088922686@s.halloapp.net/iphone"
    
    @Published var password = "11111111"
    
    @Published var isRegistered = false
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var subCancellable: AnyCancellable!
    private var validCharSet = CharacterSet(charactersIn: "1234567890+.-_ ")
    
    public var compressionQuality: Float = 0.4
    
    let userCore = UserCore()

    init() {

//        let locale = Locale.current
//        print("country: \(locale.regionCode)")
//        print(locale.localizedString(forRegionCode: locale.regionCode!))
        
//        print(Utils().getCountryFromCode("1"))
        
        (self.countryCode,
        self.phoneInput,
        self.password,
        self.phone,
        self.isLoggedIn) = userCore.get()

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
    
    func save() {
        DispatchQueue.global(qos: .default).async {
            self.userCore.update(countryCode: self.countryCode,
                                 phoneInput: self.phoneInput,
                                 password: self.password,
                                 phone: self.phone,
                                 isLoggedIn: self.isLoggedIn)
        }
    }
    
    deinit {
        subCancellable.cancel()
    }
    
    func switchToNetwork() {
        if self.hostName == "s.halloapp.net" {
            self.hostName = "s-test.halloapp.net"
        } else {
            self.hostName = "s.halloapp.net"
        }
        
//        self.didResyncContacts.send()
    }
    
    func resyncContacts() {
//        self.didResyncContacts.send()
    }

    func logIn() {
        self.isLoggedIn = true
        self.save()

        ///TODO: redo this using Combine
        AppContext.shared.xmppController.allowedToConnect = self.isLoggedIn
        AppContext.shared.contactStore.enableContactSync()
    }
    
    func logout() {
        deleteAllData(entityName: "User")
        deleteAllData(entityName: "FeedCore")
        deleteAllData(entityName: "FeedComments")
        deleteAllData(entityName: "CContactsAvatar")
        deleteAllData(entityName: "CFeedImage")
        deleteAllData(entityName: "CPending")
        
        self.didLogOff.send()
            
        self.countryCode = "1"
        self.phone = ""
        self.isRegistered = false
        
        self.isLoggedIn = false
    }
    
    func validate() -> Bool {
  
        if (self.countryCode == "" || (Int(self.countryCode) ?? 0) < 1) {
            self.status = "Please enter a country code"
            self.highlightCountryCode = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
              self.status = ""
              self.highlightCountryCode = false
            }
            return false
        } else if (self.countryCode.count > 5) {
            self.status = "Country Code is too long"
            self.highlightCountryCode = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
              self.status = ""
              self.highlightCountryCode = false
            }
            return false
        } else if (self.phoneInput == "") {
            self.status = "Please enter a phone number"
            self.highlight = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self.status = ""
                self.highlight = false
            }
            return false
        } else if (self.phoneInput.count < 5) {
            self.status = "Please enter valid phone number"
            self.highlight = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self.status = ""
                self.highlight = false
            }
            return false
        } else {
            
            self.phone = "\(self.countryCode)\(self.phoneInput)"
            
            if (self.userCore.isPresent()) {
     
                self.save()

            } else {
                DispatchQueue.global(qos: .default).async {
                    self.userCore.create(countryCode: self.countryCode,
                                         phoneInput: self.phoneInput,
                                         password: self.password,
                                         phone: self.phone,
                                         isLoggedIn: self.isLoggedIn)
                }
            }
            self.register()
            return true
        }
    }
    
    func register() {
    
        let session = URLSession.shared
        let url = URL(string: "https://\(self.hostName)/cgi-bin/request.sh?user=\(self.phone)")!

        let task = session.dataTask(with: url, completionHandler: { data, response, error in

            
            struct registerRes: Codable {
                let user: String
                let result: String
                
            }
            
            if let data = data {
                do {
                    let res = try JSONDecoder().decode(registerRes.self, from: data)
                    DDLogInfo("user: \(res.user)")
                    DDLogInfo("result: \(res.result)")
                    
                    DispatchQueue.main.async {
                    
                        self.isRegistered = true
                        
                    }
                    
                } catch let error {
                   DDLogError("\(error)")
                }
             }

        })
        task.resume()
        
    }

    func deleteAllData(entityName: String) {
        
        let managedContext = CoreDataManager.sharedManager.bgContext

        managedContext.perform {
        
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

            do {
                try managedContext.execute(batchDeleteRequest)
                DDLogInfo("Deleting \(entityName)")
            } catch {
                DDLogError("Delete error for \(entityName) error :\(error)")
            }
        }
        
    }
}
