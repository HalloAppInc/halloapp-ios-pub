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

//    public var hostName = "s-test.halloapp.net"
    public var hostName = "s.halloapp.net"

    var didLogOff = PassthroughSubject<Void, Never>()
        
    @Published var isRegistered = false
    @Published var isLoggedIn = false
    
    public var compressionQuality: Float = 0.4
    
    @Published var userId: UserID = ""
    @Published var name = ""

    @Published var phone = ""
    @Published var password = "11111111"
    
    // TODO: UserData and Login View logic should be separated as each have/would get more complex
    
    @Published var countryCode = "1"
    @Published var phoneInput = ""
    @Published var status: String = ""
    @Published var highlight = false
    @Published var highlightCountryCode = false

    // TODO: Eventually we might want to allow alphanumerical phone numbers (ie. 1-408-GAS-DROP)
    private var charsForDisplay = CharacterSet(charactersIn: "1234567890+.-_() ") // allow more chars to display for UX
    private var charsForSubmission = CharacterSet(charactersIn: "1234567890") // strip everything except for numbers
        
    let userCore = UserCore()
    private var cancellableSet: Set<AnyCancellable> = []

    init() {

//        let locale = Locale.current
//        print("country: \(locale.regionCode)")
//        print(locale.localizedString(forRegionCode: locale.regionCode!))
//        print(Utils().getCountryFromCode("1"))
        
        (self.countryCode,
        self.phoneInput,
        self.userId,
        self.password,
        self.name,
        self.phone,
        self.isLoggedIn) = userCore.get()

        self.cancellableSet.insert(self.$name.sink { val in

            if (val.count > 30) {
                self.status = "Name must be less than 30 characters"
                DispatchQueue.main.async {
                    self.name = String(val.prefix(30))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                    self.status = ""
                }
            }
            
        })
        
        self.cancellableSet.insert(self.$phoneInput.sink { val in

            if (val.rangeOfCharacter(from: self.charsForDisplay.inverted) != nil) {
        
                self.status = "Please enter only numbers"

                DispatchQueue.main.async {
                    self.phoneInput = String(self.phoneInput.unicodeScalars.filter {
                        return self.charsForDisplay.contains($0)
                    })
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                    self.status = ""
                }
            }
            
            if (val.count > 25) {
                self.status = "Phone must be less than 25 numbers"

                DispatchQueue.main.async {
                    self.phoneInput = String(val.prefix(25))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                    self.status = ""
                }
                
            }
            
        })
        
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
        
        self.didLogOff.send()
            
        self.countryCode = "1"
        self.phone = ""
        self.isRegistered = false
        
        self.isLoggedIn = false
    }
    
    func switchToNetwork() {
        if self.hostName == "s.halloapp.net" {
            self.hostName = "s-test.halloapp.net"
        } else {
            self.hostName = "s.halloapp.net"
        }
    }
    
    func save() {
        DispatchQueue.global(qos: .default).async {
            self.userCore.update(countryCode: self.countryCode,
                                 phoneInput: self.phoneInput,
                                 userId: self.userId,
                                 password: self.password,
                                 name: self.name,
                                 phone: self.phone,
                                 isLoggedIn: self.isLoggedIn)
        }
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

    func validate() -> Bool {
        self.name = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
  
        if (self.name == "") {
            self.status = "Please enter a name"
            return false
        } else if (self.countryCode == "" || (Int(self.countryCode) ?? 0) < 1) {
            self.status = "Please enter a country code"
            self.highlightCountryCode = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
              self.status = ""
              self.highlightCountryCode = false
            }
            return false
        } else if (self.countryCode.count > 5) {
            self.status = "Country Code is too long"
            self.highlightCountryCode = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
              self.status = ""
              self.highlightCountryCode = false
            }
            return false
        } else if (self.phoneInput == "") {
            self.status = "Please enter a phone number"
            self.highlight = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                self.status = ""
                self.highlight = false
            }
            return false
        } else if (self.phoneInput.count < 5) {
            self.status = "Please enter valid phone number"
            self.highlight = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                self.status = ""
                self.highlight = false
            }
            return false
        } else {
            
            let strippedPhoneInput = String(self.phoneInput.unicodeScalars.filter {
                return self.charsForSubmission.contains($0)
            })
            self.phone = "\(self.countryCode)\(strippedPhoneInput)"
            
            if (self.userCore.isPresent()) {
     
                self.save()

            } else {
                DispatchQueue.global(qos: .default).async {
                    self.userCore.create(countryCode: self.countryCode,
                                         phoneInput: self.phoneInput,
                                         userId: self.userId,
                                         password: self.password,
                                         name: self.name,
                                         phone: self.phone,
                                         isLoggedIn: self.isLoggedIn)
                }
            }
            
            self.register()

            return true
        }
    }
    
    func register() {

        guard let url = URL(string: "https://api.halloapp.net/api/registration/request_sms") else { return }
        
        guard let data = try? JSONSerialization.data(withJSONObject: ["phone": self.phone]) else {
            DDLogError("reg/request-sms/json-error")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data

        let task = URLSession.shared.dataTask(with: request) { (data, urlResponse, error) in
            guard error == nil else {
                DDLogError("reg/request-sms/error [\(error!)]")
                return
            }
            guard let data = data else {
                DDLogError("reg/request-sms/error Data is empty.")
                return
            }
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                DDLogError("reg/request-sms/error Invalid response. [\(String(describing: urlResponse))]")
                return
            }
            guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DDLogError("reg/request-sms/error Invalid response. [\(String(bytes: data, encoding: .utf8) ?? "")]")
                return
            }
            DDLogInfo("reg/request-sms/http-response \(httpResponse.statusCode) \(response)")

            if httpResponse.statusCode == 200 {
                if response["phone"] != nil {
                    DispatchQueue.main.async {
                        self.isRegistered = true
                    }
                }
            } else {
                if let responseError = response["error"] as? String {
                    if responseError == "sms_fail" {
                        DispatchQueue.main.async {
                            self.status = "Error sending SMS"
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.status = "Error trying to register"
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                        self.status = ""
                    }
                }
            }
        }
        task.resume()
    }
    
}
