//
//  RegistrationManager.swift
//  Core
//
//  Created by Garrett on 10/23/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Contacts
import Foundation

public protocol RegistrationManager: AnyObject {
    var contactsAccessStatus: CNAuthorizationStatus { get }
    var formattedPhoneNumber: String? { get }
    func set(countryCode: String, nationalNumber: String, userName: String)
    func requestVerificationCode(byVoice: Bool, completion: @escaping (Result<TimeInterval, Error>) -> Void)
    func confirmVerificationCode(_ verificationCode: String, completion: @escaping (Result<Void, Error>) -> Void)
//    func requestContactsPermissions()
    func didCompleteRegistrationFlow()
}

public final class DefaultRegistrationManager: RegistrationManager {

    public init(registrationService: RegistrationService = DefaultRegistrationService()) {
        self.registrationService = registrationService
    }

    private let registrationService: RegistrationService

    public var contactsAccessStatus: CNAuthorizationStatus {
        return CNContactStore.authorizationStatus(for: .contacts)
    }

    public var formattedPhoneNumber: String? {
        AppContext.shared.userData.formattedPhoneNumber
    }

    public func set(countryCode: String, nationalNumber: String, userName: String) {
        let userData = AppContext.shared.userData
        userData.normalizedPhoneNumber = ""
        userData.countryCode = countryCode
        userData.phoneInput = nationalNumber
        userData.name = userName
        userData.save()
    }

    /// Completion block includes retry delay
    public func requestVerificationCode(byVoice: Bool, completion: @escaping (Result<TimeInterval, Error>) -> Void) {
        let userData = AppContext.shared.userData
        let phoneNumber = userData.countryCode.appending(userData.phoneInput)
        let groupInviteToken = userData.groupInviteToken
        registrationService.requestVerificationCode(for: phoneNumber, byVoice: byVoice, groupInviteToken: groupInviteToken, locale: Locale.current) { result in
            switch result {
            case .success(let response):
                let userData = AppContext.shared.userData
                userData.normalizedPhoneNumber = response.normalizedPhoneNumber
                userData.save()
                completion(.success(response.retryDelay))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    public func confirmVerificationCode(_ verificationCode: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let userData = AppContext.shared.userData
        let keyData = AppContext.shared.keyData

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

    public func didCompleteRegistrationFlow() {
        AppContext.shared.userData.tryLogIn()
    }
}
