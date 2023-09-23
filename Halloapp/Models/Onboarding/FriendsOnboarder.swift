//
//  FriendsOnboarder.swift
//  HalloApp
//
//  Created by Tanveer on 9/6/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon
import CocoaLumberjackSwift

extension FriendsOnboarder {

    enum Step {
        case explain, usernameEntry, friends
    }

    static var doesRequireOnboarding: Bool {
        MainAppContext.shared.userData.username.isEmpty
    }
}

class FriendsOnboarder: Onboarder {

    private var current: Step?
    private let completion: (() -> Void)?

    init(_ completion: (() -> Void)? = nil) {
        self.completion = completion
    }

    var name: String? {
        MainAppContext.shared.userData.name
    }

    var username: String? {
        MainAppContext.shared.userData.username
    }

    func set(name: String) {
        let userData = AppContextCommon.shared.userData

        userData.name = name
        userData.save(using: userData.viewContext)

        AppContextCommon.shared.coreServiceCommon.updateUsername(name)
    }

    func set(username: String) async throws {
        try await MainAppContext.shared.userData.set(username: username)
    }

    func next() -> Step? {
        let next: Step?

        switch current {
        case .none:
            next = .explain
        case .explain:
            fallthrough
        case _ where username?.isEmpty ?? true:
            next = .usernameEntry
        case .usernameEntry:
            next = .friends
        case .friends:
            next = nil
        }

        DDLogInfo("FriendsOnboarder/next/current [\(String(describing: current))] next [\(String(describing: next))]")
        current = next ?? current

        return next
    }

    func viewController(for step: Step) -> UIViewController {
        switch step {
        case .explain:
            return FriendMigrationInfoViewController(onboarder: self)
        case .usernameEntry:
            return UsernameInputViewController(onboarder: self)
        case .friends:
            return OnboardingFriendsViewController(onboarder: self)
        }
    }

    func didCompleteOnboarding() {
        completion?()
    }
}
