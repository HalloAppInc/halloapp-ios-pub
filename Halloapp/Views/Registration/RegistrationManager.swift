//
//  RegistrationManager.swift
//  HalloApp
//
//  Created by Garrett on 10/23/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Contacts
import Foundation

protocol RegistrationManager: AnyObject {
    var contactsAccessStatus: CNAuthorizationStatus { get }
    var formattedPhoneNumber: String? { get }
    func set(countryCode: String, nationalNumber: String, userName: String)
    func requestVerificationCode(completion: @escaping (Result<TimeInterval, Error>) -> Void)
    func confirmVerificationCode(_ verificationCode: String, completion: @escaping (Result<Void, Error>) -> Void)
    func requestContactsPermissions()
    func didCompleteRegistrationFlow()
}

final class DefaultRegistrationManager: RegistrationManager {

    init(registrationService: RegistrationService = DefaultRegistrationService()) {
        self.registrationService = registrationService
    }

    private let registrationService: RegistrationService

    var contactsAccessStatus: CNAuthorizationStatus {
        return CNContactStore.authorizationStatus(for: .contacts)
    }

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

    /// Completion block includes retry delay
    func requestVerificationCode(completion: @escaping (Result<TimeInterval, Error>) -> Void) {
        let userData = MainAppContext.shared.userData
        let phoneNumber = userData.countryCode.appending(userData.phoneInput)
        registrationService.requestVerificationCode(for: phoneNumber, locale: Locale.current) { result in
            switch result {
            case .success(let response):
                let userData = MainAppContext.shared.userData
                userData.normalizedPhoneNumber = response.normalizedPhoneNumber
                userData.save()
                completion(.success(response.retryDelay))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func confirmVerificationCode(_ verificationCode: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let userData = MainAppContext.shared.userData
        let keyData = MainAppContext.shared.keyData

        guard let noiseKeys = userData.generateNoiseKeysForRegistration(),
              let userKeys = keyData?.generateUserKeys() else
        {
            completion(.failure(VerificationCodeValidationError.keyGenerationError))
            return
        }

        registrationService.validateVerificationCode(
            verificationCode,
            name: userData.name,
            normalizedPhoneNumber: userData.normalizedPhoneNumber,
            noiseKeys: noiseKeys,
            whisperKeys: userKeys.whisperKeys) { result in
            switch result {
            case .success(let credentials):
                userData.update(credentials: credentials)
                keyData?.saveUserKeys(userKeys)
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
