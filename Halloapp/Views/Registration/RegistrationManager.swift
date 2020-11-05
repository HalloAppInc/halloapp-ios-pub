//
//  RegistrationManager.swift
//  HalloApp
//
//  Created by Garrett on 10/23/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Foundation

protocol RegistrationManager: AnyObject {
    var formattedPhoneNumber: String? { get }
    func set(countryCode: String, nationalNumber: String, userName: String)
    func requestVerificationCode(completion: @escaping (Result<Void, Error>) -> Void)
    func confirmVerificationCode(_ verificationCode: String, completion: @escaping (Result<Void, Error>) -> Void)
    func requestContactsPermissions()
    func didCompleteRegistrationFlow()
}

final class DefaultRegistrationManager: RegistrationManager {

    init(verificationCodeService: VerificationCodeService = VerificationCodeServiceSMS()) {
        self.verificationCodeService = verificationCodeService
    }

    private let verificationCodeService: VerificationCodeService

    var formattedPhoneNumber: String? {
        MainAppContext.shared.userData.formattedPhoneNumber
    }

    func set(countryCode: String, nationalNumber: String, userName: String) {
        let userData = MainAppContext.shared.userData
        userData.normalizedPhoneNumber = ""
        userData.countryCode = countryCode
        userData.phoneInput = nationalNumber
        userData.name = userName
        userData.save()
    }

    func requestVerificationCode(completion: @escaping (Result<Void, Error>) -> Void) {
        let userData = MainAppContext.shared.userData
        let phoneNumber = userData.countryCode.appending(userData.phoneInput)
        verificationCodeService.requestVerificationCode(for: phoneNumber) { result in
            switch result {
            case .success(let normalizedPhoneNumber):
                let userData = MainAppContext.shared.userData
                userData.normalizedPhoneNumber = normalizedPhoneNumber
                userData.save()
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func confirmVerificationCode(_ verificationCode: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let userData = MainAppContext.shared.userData

        verificationCodeService.validateVerificationCode(verificationCode, name: userData.name, normalizedPhoneNumber: userData.normalizedPhoneNumber) { result in
            switch result {
            case .success((let userID, let password)):
                let userData = MainAppContext.shared.userData
                userData.userId = userID
                userData.password = password
                userData.save()
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func requestContactsPermissions() {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            DDLogError("RegistrationManager/requestContactsPermission/error app delegate unavailable")
            return
        }
        appDelegate.requestAccessToContactsAndNotifications()
    }

    func didCompleteRegistrationFlow() {
        MainAppContext.shared.userData.tryLogIn()
    }
}
