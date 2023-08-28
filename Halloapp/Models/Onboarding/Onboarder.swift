//
//  Onboarder.swift
//  HalloApp
//
//  Created by Tanveer on 8/16/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit

protocol OnboardingModel {
    var name: String? { get }
    var username: String? { get }

    var hasContactsPermission: Bool { get }
    var contactsSyncProgress: AsyncStream<Double> { get }

    func set(countryCode: String, nationalNumber: String)
    func set(name: String)
    func set(username: String) async throws

    func requestVerificationCode(byVoice: Bool) async throws -> TimeInterval
    func confirmVerificationCode(_ verificationCode: String, pushOS: String?) async throws

    func requestContactsPermission() async -> Bool
}

protocol Onboarder: OnboardingModel {
    associatedtype Step

    func next() -> Step?
    func nextViewController() -> UIViewController?
    func viewController(for step: Step) -> UIViewController

    func didCompleteOnboarding()
    static var doesRequireOnboarding: Bool { get }
}

extension Onboarder {

    func nextViewController() -> UIViewController? {
        guard let next = next() else {
            didCompleteOnboarding()
            return nil
        }

        return viewController(for: next)
    }
}
