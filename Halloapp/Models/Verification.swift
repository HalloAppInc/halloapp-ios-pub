//
//  Verification.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/26/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

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
    
    func verify(userData: UserData) {
    
        if (!self.validate()) {
            return
        }
        
        let session = URLSession.shared
        let url = URL(string: "https://\(userData.hostName)/cgi-bin/register.sh?user=\(userData.phone)&code=\(self.code)")!

        print("url: \(url)")
        
        let task = session.dataTask(with: url, completionHandler: { data, response, error in

            
            struct registerRes: Codable {
                let user: String?
                let pass: String?
                let result: String?
                
            }
            
            if let data = data {
                
                print("verify data resonse: \(data)")
                
                do {
                    let res = try JSONDecoder().decode(registerRes.self, from: data)
                    

                    DispatchQueue.main.async {
                    
                        if let password = res.pass {
                            
                            userData.password = password
                            userData.setIsLoggedIn(value: true)
                            userData.save()

                            self.code = ""
                        } else {

                            self.status = "Incorrect verification code"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                                self.status = ""
                            }
                            
                        }
                        

                    }
                    
                } catch let error {
                   print(error)
                }
             }

        })
        task.resume()
        return
    }
    
    func validate() -> Bool {

        if (self.code == "") {
            self.status = "Please enter a verification code"
            self.highlight = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self.status = ""
                self.highlight = false
            }
            return false
        } else if (self.code.count < 6) {
            self.status = "Please enter a valid verification code"
            self.highlight = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self.status = ""
                self.highlight = false
            }
            return false
        } else {
            
            return true
        }
    }
    
    


    deinit {
        subCancellable.cancel()
    }
    
}
