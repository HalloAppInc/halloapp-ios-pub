//
//  RegistrationOnboarder.swift
//  HalloApp
//
//  Created by Tanveer on 8/16/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import Combine
import Contacts
import Core
import CoreCommon
import CocoaLumberjackSwift

extension RegistrationOnboarder {

    enum Step {
        case login, nameEntry, permissions, addFriends
    }

    /// This value is set to `false` whenever a `RegistrationOnboarder` is initialized.
    @UserDefault(key: "hasCompletedRegistrationOnboarding", defaultValue: true)
    private static var hasCompletedRegistrationOnboarding: Bool

    static var doesRequireOnboarding: Bool {
        !hasCompletedRegistrationOnboarding
    }
}

final class RegistrationOnboarder: Onboarder {

    private var current: Step

    private let registrationService: RegistrationService
    private var userDefinedCountryCode: String?

    private lazy var hashcashSolver: HashcashSolver = {
        HashcashSolver { [weak self] completion in
            guard let self else {
                return completion(.failure(NSError(domain: "Registration internal error", code: 1, userInfo: nil)))
            }

            self.registrationService.requestHashcashChallenge(countryCode: self.userDefinedCountryCode,
                                                              completion: completion)
        }
    }()

    init(registrationService: RegistrationService) {
        self.registrationService = registrationService
        self.current = .login

        // Precompute first hashcash
        hashcashSolver.solveNext()

        Self.hasCompletedRegistrationOnboarding = false
    }

    func next() -> Step? {
        let context = MainAppContext.shared
        let nextStep: Step?

        switch current {
        case _ where !context.userData.isLoggedIn:
            nextStep = .login
        case _ where context.userData.name.isEmpty || context.userData.username.isEmpty:
            nextStep = .nameEntry

        case _ where ContactStore.contactsAccessRequestNecessary:
            nextStep = .permissions
        case _ where ContactStore.contactsAccessAuthorized && !context.contactStore.isInitialSyncCompleted:
            nextStep = .permissions

        case .permissions:
            nextStep = nil //.addFriends
        default:
            nextStep = nil
        }

        DDLogInfo("RegistrationOnboarder/next-step/current [\(current)] next [\(nextStep ?? current)]")

        current = nextStep ?? current
        return nextStep
    }

    func viewController(for step: Step) -> UIViewController {
        let viewController: UIViewController

        switch step {
        case .login:
            viewController = PhoneNumberEntryViewController(onboarder: self)
        case .nameEntry:
            viewController = UsernameInputViewController(onboarder: self)
        case .permissions:
            viewController = PermissionsViewController(onboarder: self)
        case .addFriends:
            viewController = PhoneNumberEntryViewController(onboarder: self)
        }

        return viewController
    }

    func didCompleteOnboarding() {
        DDLogInfo("RegistrationOnboarder/didCompleteOnboarding")

        Self.hasCompletedRegistrationOnboarding = true
        NotificationCenter.default.post(name: .didCompleteRegistrationOnboarding, object: nil)
    }
}

// MARK: - OnboardingModel methods

extension RegistrationOnboarder {

    var name: String? {
        let name = MainAppContext.shared.userData.name
        return name.isEmpty ? nil : name
    }

    var username: String? {
        let username = MainAppContext.shared.userData.username
        return username.isEmpty ? nil : username
    }

    var hasContactsPermission: Bool {
        ContactStore.contactsAccessAuthorized
    }

    var contactsSyncProgress: AsyncStream<Double> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let finished = MainAppContext.shared.syncManager.$isSyncInProgress
            let progress = MainAppContext.shared.syncManager.syncProgress
                .prepend(0)
                .eraseToAnyPublisher()

            let cancellable = Publishers.CombineLatest(progress, finished)
                .sink { progress, isFinished in
                    if MainAppContext.shared.contactStore.isInitialSyncCompleted {
                        continuation.finish()
                    }

                    continuation.yield(progress)
                }

            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func set(countryCode: String, nationalNumber: String) {
        let userData = AppContextCommon.shared.userData
        let normalizedNumber = countryCode.appending(nationalNumber)

        userDefinedCountryCode = countryCode
        userData.countryCode = countryCode
        userData.phoneInput = nationalNumber
        userData.normalizedPhoneNumber = normalizedNumber

        userData.save(using: userData.viewContext)
    }

    func set(name: String) {
        let userData = AppContextCommon.shared.userData

        userData.name = name
        userData.save(using: userData.viewContext)

        AppContextCommon.shared.coreServiceCommon.updateUsername(name)
    }

    func set(username: String) async throws {
        try await AppContext.shared.userData.set(username: username)
    }

    func requestVerificationCode(byVoice: Bool) async throws -> TimeInterval {
        let solveHashcash = Task {
            try await withCheckedThrowingContinuation { continuation in
                hashcashSolver.solveNext { result in
                    continuation.resume(with: result)
                }
            }
        }

        switch await solveHashcash.result {
        case .success(let hashcash):
            return try await requestVerificationCode(byVoice: byVoice, hashcash: hashcash)
        case .failure(let error):
            throw RegistrationErrorResponse(error: error)
        }
    }

    func confirmVerificationCode(_ verificationCode: String, pushOS: String?) async throws {
        let userData = AppContextCommon.shared.userData
        let keyData = AppContextCommon.shared.keyData

        guard let noiseKeys = NoiseKeys(),
              let userKeys = keyData?.generateUserKeys() else {
            throw VerificationCodeValidationError.keyGenerationError
        }

        try await withCheckedThrowingContinuation { continuation in
            registrationService.validateVerificationCode(verificationCode,
                                                         name: "",
                                                         normalizedPhoneNumber: userData.normalizedPhoneNumber,
                                                         noiseKeys: noiseKeys,
                                                         groupInviteToken: userData.groupInviteToken,
                                                         pushOS: pushOS,
                                                         pushToken: UserDefaults.standard.string(forKey: "apnsPushToken"),
                                                         whisperKeys: userKeys.whisperKeys) { result in
                switch result {
                case .success(let credentials):
                    userData.performSeriallyOnBackgroundContext { context in
                        userData.update(credentials: credentials, in: context)
                        keyData?.saveUserKeys(userKeys)

                        AppContextCommon.shared.userData.tryLogIn()
                        continuation.resume()
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func requestVerificationCode(byVoice: Bool, hashcash: HashcashSolution) async throws -> TimeInterval {
        let userData = AppContextCommon.shared.userData
        let phoneNumber = userData.countryCode.appending(userData.phoneInput)
        let groupInviteToken = userData.groupInviteToken

        return try await withCheckedThrowingContinuation { continuation in
            registrationService.requestVerificationCode(for: phoneNumber,
                                                        byVoice: byVoice,
                                                        hashcash: hashcash,
                                                        groupInviteToken: groupInviteToken,
                                                        locale: Locale.current) { result in
                switch result {
                case .success(let response):
                    userData.performSeriallyOnBackgroundContext { context in
                        userData.normalizedPhoneNumber = response.normalizedPhoneNumber
                        userData.save(using: context)

                        continuation.resume(returning: response.retryDelay)
                    }
                case .failure(let errorResponse):
                    continuation.resume(throwing: errorResponse)
                }
            }
        }
    }

    func requestContactsPermission() async -> Bool {
        let context = MainAppContext.shared
        defer { context.contactStore.reloadContactsIfNecessary() }

        guard ContactStore.contactsAccessRequestNecessary else {
            return ContactStore.contactsAccessAuthorized
        }

        let isAuthorized = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
        context.contactStore.contactsAccessRequestCompleted.send(isAuthorized)

        return isAuthorized
    }
}

// MARK: - Notification.Name extension

extension Notification.Name {
    /// Posted when the onboarding process has been completed and the user should be allowed into the main app.
    static let didCompleteRegistrationOnboarding = Notification.Name("didCompleteRegistrationOnboarding")
}
