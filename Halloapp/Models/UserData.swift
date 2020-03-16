//
//  UserData.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/20/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import MessageUI
import Foundation
import SwiftUI
import Combine

import CoreData

final class UserData: ObservableObject {

    private let logsQueue = DispatchQueue(label: "com.halloapp.logs.serial", qos: DispatchQoS.default)
    
    var didLogOff = PassthroughSubject<Void, Never>()
    
    var didResyncContacts = PassthroughSubject<Void, Never>()
    
    @Published var countryCode = "1"
    
    @Published var phoneInput = ""
    
    @Published var phone = ""
    @Published var isLoggedIn = false

    public var haveContactsSub = false
    public var haveFeedSub = false
    
    @Published var status: String = ""
    @Published var highlight = false
    
    @Published var highlightCountryCode = false

    @Published var hostName = "s.halloapp.net"
//    @Published var hostName = "s-test.halloapp.net"
    
//  @Published var userJIDString = "14088922686@s.halloapp.net/iphone"
    
    @Published var password = "11111111"
    
    @Published var isRegistered = false
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var subCancellable: AnyCancellable!
    private var validCharSet = CharacterSet(charactersIn: "1234567890+.-_ ")
    
    public var logging = ""
    
    public var loggingTimestamp = Int(Date().timeIntervalSince1970)
    
    public var compressionQuality: Float = 0.4
    
    let userCore = UserCore()
    let miscCore = MiscCore()
    
    init() {

//        let locale = Locale.current
//        print("country: \(locale.regionCode)")
//        print(locale.localizedString(forRegionCode: locale.regionCode!))
        
//        print(Utils().getCountryFromCode("1"))
        
        (self.countryCode,
        self.phoneInput,
        self.password,
        self.phone,
        self.isLoggedIn,
        self.haveContactsSub,
        self.haveFeedSub) = userCore.get()
        
        self.initLogging()

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

    
    func initLogging() {
        
        if (!miscCore.isPresent()) {
            miscCore.create(logs: "")
        }
        
        self.logging = miscCore.get()
        
        /* clean up logs every 3 days */
        let current = Int(Date().timeIntervalSince1970)
        let threedays = 60*60*24*3
        let diff = current - self.loggingTimestamp
                        
        if (diff > threedays) {
            self.loggingTimestamp = Int(Date().timeIntervalSince1970)
            self.logging = ""
            self.miscCore.update(logs: "")
        }
    }
    
    func log(_ str: String) {
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMdd'T'HH:mmssZ"
        let time = formatter.string(from: Date())
        
        var log = "\(time) \(str)"
        print(log)
        log += "\r\n"
        self.logging += log
        
        self.logsQueue.async {
            self.miscCore.update(logs: self.logging)
        }
    }
    
    func devLog(_ str: String) {
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMdd'T'HH:mmssZ"
        let time = formatter.string(from: Date())
        
        var log = "\(time) \(str)"
        
        log += "\r\n"
        self.logging += log
        
        self.logsQueue.async {
            self.miscCore.update(logs: self.logging)
        }
    }
    
    func save() {
        DispatchQueue.global(qos: .default).async {
            self.userCore.update(countryCode: self.countryCode,
                                 phoneInput: self.phoneInput,
                                 password: self.password,
                                 phone: self.phone,
                                 isLoggedIn: self.isLoggedIn,
                                 haveContactsSub: self.haveContactsSub,
                                 haveFeedSub: self.haveFeedSub)
        }
    }
    
    deinit {
        subCancellable.cancel()
    }
    
    func setHaveContactsSub(value: Bool) {
        self.haveContactsSub = value
        self.save()
    }
    
    func setHaveFeedSub(value: Bool) {
        self.haveFeedSub = value
        self.save()
    }
        
    func resyncContacts() {
//        deleteAllData(entityName: "ContactsCore")
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
        deleteAllData(entityName: "ContactsCore")
        deleteAllData(entityName: "FeedCore")
        deleteAllData(entityName: "FeedComments")
        deleteAllData(entityName: "CContactsAvatar")
        deleteAllData(entityName: "CFeedImage")
        deleteAllData(entityName: "CPending")
        
        self.didLogOff.send()
            
        self.countryCode = "1"
        self.phone = ""
        self.isRegistered = false
        
        self.haveContactsSub = false
        self.haveFeedSub = false
        
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
                                         isLoggedIn: self.isLoggedIn,
                                         haveContactsSub: self.haveContactsSub,
                                         haveFeedSub: self.haveFeedSub)
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
                    print("user: \(res.user)")
                    print("result: \(res.result)")
                    
                    DispatchQueue.main.async {
                    
                        self.isRegistered = true
                        
                    }
                    
                } catch let error {
                   print(error)
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
                print("Deleting \(entityName)")
            } catch {
                print("Delete error for \(entityName) error :", error)
            }
        }
        
    }
}
