//
//  Verification.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/26/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Foundation
import SwiftUI

final class Verification: ObservableObject {

    @Published var code = ""
    @Published var status = ""
    @Published var highlight = false
    
    private var subCancellable: AnyCancellable!
    private var validCharSet = CharacterSet(charactersIn: "1234567890-")
    
    init() {
        
        subCancellable = $code.sink { val in
            
            if (val.rangeOfCharacter(from: self.validCharSet.inverted) != nil) {
                self.status = "Please enter only numbers"
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    self.status = ""
                }
                DispatchQueue.main.async {
                    self.code = String(self.code.unicodeScalars.filter {
                        self.validCharSet.contains($0)
                    })
                }
            }
            

            if (val.count > 6) {
                DispatchQueue.main.async {
                    self.code = String(val.prefix(6))
                }
            }
            
        }
    }

    func show(status: String, highlightInputField: Bool = false) {
        self.status = status
        if highlightInputField {
            self.highlight = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.status = ""
            if highlightInputField {
                self.highlight = false
            }
        }
    }
    
    func verify(userData: UserData) {
    
        if (!self.validate()) {
            return
        }
        
        let endpoint = "https://api.halloapp.net/api/registration/register"
        
        guard let url = URL(string: endpoint) else {
            return
        }
        
        DDLogInfo("Validating code. url:[\(url)]")
        
        var json = [String:Any]()
        
        json["name"] = userData.name
        json["phone"] = userData.phone
        json["code"] = self.code
        
        DDLogInfo("\(json)")
    
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = data
            
            let session = URLSession.shared
            
            let task = session.dataTask(with: request) { (data, response, error) in
                
                if error != nil {
                    DDLogError("Error validating code. [\(error!)]")
                    DispatchQueue.main.async {
                        self.show(status: "Error validating code. Please try again.")
                    }
                    return
                }

                if let data = data {
                    DDLogInfo("Got code validation response: \(String(data: data, encoding: .utf8) ?? "<invalid>")")

                    do {
                        let object = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
                        DDLogInfo("Decoded response [\(object)]")
                        
                        if let httpResponse = response as? HTTPURLResponse {
                            DDLogInfo("reg/verify-sms/http-response \(httpResponse.statusCode)")
                            
                            if httpResponse.statusCode == 200 {
                            
                                DispatchQueue.main.async {
                                    if let userId = object["uid"] as? String {
                                        if let password = object["password"] as? String {
                                            
                                            let userData = AppContext.shared.userData
                                            userData.userId = userId
                                            userData.password = password
                                            userData.logIn()
                                            userData.save()

                                            self.code = ""
                                        }
                                    }
                                }
                                
                            } else {

                                DispatchQueue.main.async {
                                    if let error = object["error"] as? String {
                                        
                                        DDLogInfo("reg/verify-sms/error \(error)")
                                        
                                        if error == "wrong_sms_code" {
                                            self.show(status: "Incorrect verification code")
                                            self.code = ""
                                        } else {
                                            self.show(status: "Error")
                                            self.code = ""
                                        }

                                    }
                                }
                                
                            }
                            
                        }

                    } catch {
                        DDLogError("Failed to parse response. [\(error)]")
                    }
                }
            }
            task.resume()
            
            
        } catch {
            DDLogError("reg/verify-sms/data \(error)")
        }
        
    }
    
    func verifyPreBuild29(userData: UserData) {
    
        if (!self.validate()) {
            return
        }
        
        let session = URLSession.shared
        let url = URL(string: "https://\(userData.hostName)/cgi-bin/register.sh?user=\(userData.phone)&code=\(self.code)")!

        DDLogInfo("Validating code. url:[\(url)]")
        
        let task = session.dataTask(with: url) { (data, response, error) in
            if error != nil {
                DDLogError("Error validating code. [\(error!)]")
                DispatchQueue.main.async {
                    self.show(status: "Error validating code. Please try again.")
                }
                return
            }

            if let data = data {
                DDLogInfo("Got code validation response: \(String(data: data, encoding: .utf8) ?? "<invalid>")")

                do {
                    let object = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
                    DDLogInfo("Decoded response [\(object)]")
                    DispatchQueue.main.async {
                        if let password = object["pass"] as? String {
                            let userData = AppContext.shared.userData
                            userData.password = password
                            userData.logIn()
                            userData.save()

                            self.code = ""
                        } else {
                            self.show(status: "Incorrect verification code")
                            self.code = ""
                        }
                    }
                } catch {
                    DDLogError("Failed to parse response. [\(error)]")
                }
            }
        }
        task.resume()
    }
    
    func validate() -> Bool {
        if (self.code == "") {
            self.show(status: "Please enter a verification code", highlightInputField: true)
            return false
        } else if (self.code.count < 6) {
            self.show(status: "Please enter a valid verification code", highlightInputField: true)
            return false
        }
        return true
    }

    deinit {
        subCancellable.cancel()
    }
}
