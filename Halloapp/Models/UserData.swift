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



final class UserData: ObservableObject {

    @Published var phone = "14088922686"
    @Published var status = ""
    @Published var highlight = false

    @Published var hostName = "d.halloapp.dev"
    // @Published var userJIDString = "14154121848@s.halloapp.net/iphone"
    @Published var userJIDString = "14088922686@s.halloapp.net/iphone"
    @Published var password = "11111111"
    
    private var subCancellable: AnyCancellable!
    private var validCharSet = CharacterSet(charactersIn: "1234567890+.-_ ")

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
            return true
        }
    }
    
    init() {
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
}
