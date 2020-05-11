//
//  UserData.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/20/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import CoreData
import Foundation
import SwiftUI

final class UserData: ObservableObject {

//    public var hostName = "s-test.halloapp.net"
    public var hostName = "s.halloapp.net"

    var didLogOff = PassthroughSubject<Void, Never>()

    /**
     Value is derived from presence of saved userId/password pair.
     */
    @Published var isLoggedIn = false
    
    public var compressionQuality: Float = 0.4

    // Entered by user.
    var countryCode = "1"
    var phoneInput = ""
    var name = ""

    // Provided by the server.
    var normalizedPhoneNumber: String = ""
    var userId: UserID = ""
    var password = "11111111"

    var formattedPhoneNumber: String {
        get {
            var phoneNumberStr = normalizedPhoneNumber
            if phoneNumberStr.isEmpty {
                phoneNumberStr = countryCode.appending(phoneInput)
            }
            phoneNumberStr = "+\(phoneNumberStr)"
            if let phoneNumber = try? AppContext.shared.phoneNumberFormatter.parse(phoneNumberStr) {
                phoneNumberStr = AppContext.shared.phoneNumberFormatter.format(phoneNumber, toType: .international)
            }
            return phoneNumberStr
        }
    }

    init() {
        if let user = UserCore.fetch() {
            self.countryCode = user.countryCode ?? "1"
            self.phoneInput = user.phoneInput ?? ""
            self.normalizedPhoneNumber = user.phone ?? ""
            self.userId = user.userId ?? ""
            self.password = user.password ?? ""
            self.name = user.name ?? ""
        }
        if !self.userId.isEmpty && !self.password.isEmpty {
            self.isLoggedIn = true
        }
    }
    
    func tryLogIn() {
        if !userId.isEmpty && !password.isEmpty {
            self.isLoggedIn = true

            ///TODO: redo this using Combine
            AppContext.shared.xmppController.allowedToConnect = self.isLoggedIn
            AppContext.shared.contactStore.enableContactSync()
        }
    }
    
    func logout() {
        self.didLogOff.send()

        self.countryCode = "1"
        self.phoneInput = ""
        self.normalizedPhoneNumber = ""
        self.userId = ""
        self.password = ""
        self.name = ""
        self.save()

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
        UserCore.save(countryCode: self.countryCode, phoneInput: self.phoneInput, normalizedPhoneNumber: self.normalizedPhoneNumber,
                      userId: self.userId, password: self.password, name: self.name)
    }

}
