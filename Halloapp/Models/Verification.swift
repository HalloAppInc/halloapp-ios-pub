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

            self.code = ""
            return true
        }
    }
    
    
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

    deinit {
        subCancellable.cancel()
    }
    
}
