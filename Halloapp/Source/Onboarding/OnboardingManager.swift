//
//  OnboardingManager.swift
//  HalloApp
//
//  Created by Tanveer on 8/25/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import CoreCommon
import Core
import Combine
import Contacts

protocol OnboardingManager {
    var hasContactsPermission: Bool { get }
    var contactsSyncProgress: AsyncStream<Double> { get }

    func requestContactsPermission() async -> Bool
    func fellowContactIDs() -> [UserID]
    func didCompleteOnboardingFlow()
}

// MARK: - DefaultOnboardingManager implementation

final class DefaultOnboardingManager: OnboardingManager {

    var hasContactsPermission: Bool {
        ContactStore.contactsAccessAuthorized
    }

    func requestContactsPermission() async -> Bool {
        guard ContactStore.contactsAccessRequestNecessary else {
            MainAppContext.shared.contactStore.reloadContactsIfNecessary()
            return ContactStore.contactsAccessAuthorized
        }

        let isAuthorized = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false

        MainAppContext.shared.contactStore.contactsAccessRequestCompleted.send(isAuthorized)
        MainAppContext.shared.contactStore.reloadContactsIfNecessary()

        return isAuthorized
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

    func fellowContactIDs() -> [UserID] {
        let request = ABContact.fetchRequest()
        request.predicate = NSPredicate(format: "userId != nil")
        request.fetchLimit = 5

        let contacts = (try? MainAppContext.shared.contactStore.viewContext.fetch(request)) ?? []
        return contacts.compactMap { $0.userId }
    }

    func didCompleteOnboardingFlow() {
        NotificationCenter.default.post(name: Self.didCompleteOnboarding, object: nil)
    }
}

extension DefaultOnboardingManager {
    /// Posted when the onboarding process has been completed and the user should be allowed
    /// into the main app.
    static let didCompleteOnboarding = Notification.Name("didCompleteOnboarding")
}

// MARK: - DemoOnboardingManager implementation

final class DemoOnboardingManager: OnboardingManager {

    let networkSize: Int
    var completion: () -> Void

    var hasContactsPermission: Bool {
        false
    }

    func requestContactsPermission() async -> Bool {
        true
    }

    init(networkSize: Int, completion: @escaping () -> Void) {
        self.networkSize = networkSize
        self.completion = completion
    }

    var contactsSyncProgress: AsyncStream<Double> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            Task {
                try? await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)
                continuation.yield(0.5)
                try? await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)
                continuation.yield(1)
                try? await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)

                continuation.finish()
            }
        }
    }

    func fellowContactIDs() -> [UserID] {
        guard networkSize > 0 else {
            return []
        }

        let request = ABContact.fetchRequest()
        request.predicate = NSPredicate(format: "userId != nil")
        request.fetchLimit = networkSize < 5 ? networkSize : 5

        let contacts = (try? MainAppContext.shared.contactStore.viewContext.fetch(request)) ?? []
        return contacts.compactMap { $0.userId }
    }

    func didCompleteOnboardingFlow() {
        completion()
    }
}
