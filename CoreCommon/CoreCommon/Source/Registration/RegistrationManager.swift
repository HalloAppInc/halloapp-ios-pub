//
//  RegistrationManager.swift
//  Core
//
//  Created by Garrett on 10/23/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Contacts
import Foundation

public protocol RegistrationManager: AnyObject {
    var contactsAccessStatus: CNAuthorizationStatus { get }
    var formattedPhoneNumber: String? { get }
    func set(countryCode: String, nationalNumber: String, userName: String)
    func requestVerificationCode(byVoice: Bool, completion: @escaping (Result<TimeInterval, RegistrationErrorResponse>) -> Void)
    func confirmVerificationCode(_ verificationCode: String, pushOS: String?, completion: @escaping (Result<Void, Error>) -> Void)
    func didCompleteRegistrationFlow()
    func getGroupName(groupInviteToken: String, completion: @escaping (Result<String?, Error>) -> Void)

    func requestVerificationCode(byVoice: Bool) async -> Result<TimeInterval, RegistrationErrorResponse>
    func confirmVerificationCode(_ verificationCode: String, pushOS: String?) async -> Result<Void, Error>
}

extension RegistrationManager {
    // TODO: remove callback-based API when the old registration flow is replaced
    public func requestVerificationCode(byVoice: Bool) async -> Result<TimeInterval, RegistrationErrorResponse> {
        await withCheckedContinuation { continuation in
            requestVerificationCode(byVoice: byVoice) { result in
                continuation.resume(returning: result)
            }
        }
    }

    public func confirmVerificationCode(_ verificationCode: String, pushOS: String?) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            confirmVerificationCode(verificationCode, pushOS: pushOS) { result in
                continuation.resume(returning: result)
            }
        }
    }
}

enum RegistrationManagerError: Error {
    case internalError
}

public final class DefaultRegistrationManager: RegistrationManager {

    public init(registrationService: RegistrationService) {
        self.registrationService = registrationService

        // Precompute first hashcash
        hashcashSolver.solveNext()
    }

    private let registrationService: RegistrationService

    // Explicitly track country code provided by user for use in hashcash request
    // (UserData provides a default country code that we don't want to fall back to).
    private var userDefinedCountryCode: String?

    private lazy var hashcashSolver: HashcashSolver = {
        return HashcashSolver() { [weak self] completion in
            guard let self = self else {
                completion(.failure(RegistrationManagerError.internalError))
                return
            }
            self.registrationService.requestHashcashChallenge(
                countryCode: self.userDefinedCountryCode,
                completion: completion)
        }
    }()

    public var contactsAccessStatus: CNAuthorizationStatus {
        return CNContactStore.authorizationStatus(for: .contacts)
    }

    public var formattedPhoneNumber: String? {
        AppContextCommon.shared.userData.formattedPhoneNumber
    }

    public func set(countryCode: String, nationalNumber: String, userName: String) {
        userDefinedCountryCode = countryCode
        let userData = AppContextCommon.shared.userData
        userData.countryCode = countryCode
        userData.phoneInput = nationalNumber
        userData.normalizedPhoneNumber = countryCode.appending(nationalNumber)
        userData.name = userName
        userData.save(using: userData.viewContext)
    }

    /// Completion block includes retry delay. May need to wait for hashcash solution to be computed before issuing request.
    public func requestVerificationCode(byVoice: Bool, completion: @escaping (Result<TimeInterval, RegistrationErrorResponse>) -> Void) {
        hashcashSolver.solveNext() { [weak self] result in
            guard let self = self else {
                completion(.failure(RegistrationErrorResponse(error: VerificationCodeRequestError.requestCreationError)))
                return
            }
            switch result {
            case .success(let hashcash):
                self.requestVerificationCode(byVoice: byVoice, hashcash: hashcash, completion: completion)
            case .failure(let error):
                completion(.failure(RegistrationErrorResponse(error: error)))
            }
        }
    }

    public func confirmVerificationCode(_ verificationCode: String, pushOS: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        let userData = AppContextCommon.shared.userData
        let keyData = AppContextCommon.shared.keyData

        guard let noiseKeys = NoiseKeys(),
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
            groupInviteToken: userData.groupInviteToken,
            pushOS: pushOS,
            pushToken: UserDefaults.standard.string(forKey: "apnsPushToken"),
            whisperKeys: userKeys.whisperKeys) { result in
            switch result {
            case .success(let credentials):
                userData.performSeriallyOnBackgroundContext { managedObjectContext in
                    userData.update(credentials: credentials, in: managedObjectContext)

                    keyData?.saveUserKeys(userKeys)
                    DispatchQueue.main.async {
                        completion(.success(()))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    public func didCompleteRegistrationFlow() {
        AppContextCommon.shared.userData.tryLogIn()
    }
    
    public func getGroupName(groupInviteToken: String, completion: @escaping (Result<String?, Error>) -> Void) {
        registrationService.getGroupName(groupInviteToken: groupInviteToken) { result in
            switch result {
            case .success(let groupName):
                completion(.success((groupName)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func requestVerificationCode(byVoice: Bool, hashcash: HashcashSolution?, completion: @escaping (Result<TimeInterval, RegistrationErrorResponse>) -> Void) {
        let userData = AppContextCommon.shared.userData
        let phoneNumber = userData.countryCode.appending(userData.phoneInput)
        let groupInviteToken = userData.groupInviteToken
        registrationService.requestVerificationCode(for: phoneNumber, byVoice: byVoice, hashcash: hashcash, groupInviteToken: groupInviteToken, locale: Locale.current) { result in
            switch result {
            case .success(let response):
                let userData = AppContextCommon.shared.userData

                userData.performSeriallyOnBackgroundContext { managedObjectContext in
                    userData.normalizedPhoneNumber = response.normalizedPhoneNumber
                    userData.save(using: managedObjectContext)
                    DispatchQueue.main.async {
                        completion(.success(response.retryDelay))
                    }
                }
            case .failure(let errorResponse):
                completion(.failure(errorResponse))
            }
        }
    }

}
