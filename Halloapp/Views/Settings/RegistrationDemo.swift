//
//  RegistrationDemo.swift
//  HalloApp
//
//  Created by Garrett on 10/27/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Contacts
import Core
import CoreCommon
import Foundation
import SwiftUI


final class DemoRegistrationManager: RegistrationManager {

    init(onboardingNetworkSize: Int, completion: @escaping () -> Void) {
        self.onboardingNetworkSize = onboardingNetworkSize
        self.completion = completion
    }

    var onboardingNetworkSize: Int
    var correctCode = "111111"
    var completion: () -> Void
    var formattedPhoneNumber: String?

    var contactsAccessStatus: CNAuthorizationStatus {
        return CNContactStore.authorizationStatus(for: .contacts)
    }

    func set(countryCode: String, nationalNumber: String, userName: String) {
        formattedPhoneNumber = "+\(countryCode) \(nationalNumber)"
    }

    func requestVerificationCode(byVoice: Bool = false, completion: @escaping (Result<TimeInterval, RegistrationErrorResponse>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(2)) {
            completion(.success(5))
        }
    }

    func confirmVerificationCode(_ verificationCode: String, pushOS: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(2)) {
            if verificationCode == self.correctCode {
                completion(.success(()))
            } else {
                completion(.failure(VerificationCodeValidationError.incorrectCode))
            }
        }

    }

    func requestContactsPermissions() {
        // no-op
    }

    func didCompleteRegistrationFlow() {
        // no-op
    }
    
    public func getGroupName(groupInviteToken: String, completion: @escaping (Result<String?, Error>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(2)) {
            completion(.success((nil)))
        }
    }
}
