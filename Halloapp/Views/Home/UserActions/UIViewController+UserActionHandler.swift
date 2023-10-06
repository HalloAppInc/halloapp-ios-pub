//
//  UIViewController+UserActionHandler.swift
//  HalloApp
//
//  Created by Tanveer on 9/20/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import CoreCommon
import CocoaLumberjackSwift

@MainActor
extension UserActionHandler where Self: UIViewController {

    func handle(_ action: UserAction, for userID: UserID) async throws {
        switch action {
        case .message:
            pushChatViewController(userID)
        case .call(let type):
            startCall(to: userID, type: type)
        case .addFavorite:
            addFavorite(userID: userID)
        case .removeFavorite:
            removeFavorite(userID: userID)
        case .addFriend:
            addFriend(userID: userID)
        case .removeFriend:
            removeFriend(userID: userID)
        case .viewProfile:
            viewProfile(userID: userID)
        case .safetyNumber(let contactData, let bundle):
            verifySafetyNumber(userID: userID, contactData: contactData, bundle: bundle)
        case .commonGroups:
            groupsInCommon(userID: userID)
        case .block:
            try await block(userID: userID)
        case .unblock:
            try await unblock(userID: userID)
        case .report:
            report(userID: userID)
        }
    }

    private func pushChatViewController(_ id: UserID) {
        // slight delay because otherwise the dismissal of the context menu makes the
        // push animation look abrupt
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            let vc = ChatViewControllerNew(for: id)
            self?.navigationController?.pushViewController(vc, animated: true)
        }
    }

    private func startCall(to userID: UserID, type: CallType) {
        MainAppContext.shared.callManager.startCall(to: userID, type: type) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success:
                    DDLogInfo("UserContextMenuHandler/startCall/success")
                case .failure:
                    DDLogInfo("UserContextMenuHandler/startCall/failure")
                    let alert = self.getFailedCallAlert()
                    self.present(alert, animated: true)
                }
            }
        }
    }

    private func addFriend(userID: UserID) {
        Task(priority: .userInitiated) { @MainActor [weak self] in
            do {
                try await MainAppContext.shared.userProfileData.addFriend(userID: userID)
            } catch {
                let alert = UIAlertController(title: Localizations.genericError, message: nil, preferredStyle: .alert)
                self?.present(alert, animated: true)
            }
        }
    }

    private func removeFriend(userID: UserID) {
        Task(priority: .userInitiated) { @MainActor [weak self] in
            do {
                try await MainAppContext.shared.userProfileData.removeFriend(userID: userID)
            } catch {
                let alert = UIAlertController(title: Localizations.genericError, message: nil, preferredStyle: .alert)
                self?.present(alert, animated: true)
            }
        }
    }

    private func addFavorite(userID: UserID) {
        Task(priority: .userInitiated) { @MainActor in
            do {
                try await MainAppContext.shared.mainDataStore.saveSeriallyOnBackgroundContext { context in
                    UserProfile.find(with: userID, in: context)?.isFavorite = true
                }
            } catch {
                return
            }

            let toast = Toast(type: .icon(UIImage(named: "FavoritesOutline")?.withRenderingMode(.alwaysTemplate)),
                              text: Localizations.addedToFavorites)
            toast.show()
        }
    }

    private func removeFavorite(userID: UserID) {
        Task(priority: .userInitiated) { @MainActor in
            do {
                try await MainAppContext.shared.mainDataStore.saveSeriallyOnBackgroundContext { context in
                    UserProfile.find(with: userID, in: context)?.isFavorite = false
                }
            } catch {
                return
            }

            let toast = Toast(type: .icon(UIImage(named: "UnfavoriteOutline")?.withRenderingMode(.alwaysTemplate)),
                              text: Localizations.removedFromFavorites)
            toast.show()
        }
    }

    private func viewProfile(userID: UserID) {
        let vc = UserFeedViewController(userId: userID)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func verifySafetyNumber(userID: UserID, contactData: SafetyNumberData, bundle: UserKeyBundle) {
        let current = SafetyNumberData(userID: MainAppContext.shared.userData.userId, identityKey: bundle.identityPublicKey)
        let name = UserProfile.find(with: userID, in: MainAppContext.shared.mainDataStore.viewContext)?.displayName ?? ""
        let vc = SafetyNumberViewController(currentUser: current,
                                            contact: contactData,
                                            contactName: name,
                                            dismissAction: { [weak self] in
            self?.dismiss(animated: true)
        })

        present(vc.withNavigationController(), animated: true)
    }

    private func groupsInCommon(userID: UserID) {
        let commonGroupsVC = GroupsInCommonViewController(userID: userID)
        let controller = UINavigationController(rootViewController: commonGroupsVC)
        controller.modalPresentationStyle = .fullScreen

        navigationController?.present(controller, animated: true)
    }

    private func block(userID: UserID, showAlert: Bool = true) async throws {
        guard showAlert else {
            return try await MainAppContext.shared.userProfileData.block(userID: userID)
        }

        let profile = UserProfile.find(with: userID, in: MainAppContext.shared.mainDataStore.viewContext)
        let title = Localizations.blockTitle(name: profile?.name ?? "")
        let message = Localizations.blockMessage(username: profile?.name ?? "")

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        try await withCheckedThrowingContinuation { continuation in
            let blockAction = UIAlertAction(title: Localizations.blockButton, style: .destructive) { _ in
                Task(priority: .userInitiated) {
                    do {
                        try await MainAppContext.shared.userProfileData.block(userID: userID)
                        continuation.resume()
                        Toast.show(type: .icon(.init(systemName: "checkmark")), text: Localizations.blockSuccess)
                    } catch {
                        continuation.resume(throwing: error)
                        Toast.show(type: .icon(.init(systemName: "xmark")), text: Localizations.blockFailure)
                    }
                }
            }

            let cancelAction = UIAlertAction(title: Localizations.buttonCancel, style: .cancel) { _ in
                // we throw an error here so that the caller can avoid dismissing content if the user decides against it
                continuation.resume(throwing: CancellationError())
            }

            alert.addAction(blockAction)
            alert.addAction(cancelAction)

            present(alert, animated: true)
        }
    }

    private func unblock(userID: UserID) async throws {
        let profile = UserProfile.find(with: userID, in: MainAppContext.shared.mainDataStore.viewContext)
        let title = Localizations.unblockTitle(name: profile?.name ?? "")
        let message = Localizations.unBlockMessage(username: profile?.name ?? "")

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        try await withCheckedThrowingContinuation { continuation in
            let blockAction = UIAlertAction(title: Localizations.unBlockButton, style: .default) { _ in
                Task(priority: .userInitiated) {
                    do {
                        try await MainAppContext.shared.userProfileData.unblock(userID: userID)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            let cancelAction = UIAlertAction(title: Localizations.buttonCancel, style: .cancel) { _ in
                continuation.resume(throwing: CancellationError())
            }

            alert.addAction(blockAction)
            alert.addAction(cancelAction)

            present(alert, animated: true)
        }
    }

    private func report(userID: UserID) {
        let name = UserProfile.find(with: userID, in: MainAppContext.shared.mainDataStore.viewContext)?.displayName ?? ""
        let title = String(format: Localizations.reportUserTitle, name)
        let message = String(format: Localizations.reportUserMessage, name)
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        let report = {
            MainAppContext.shared.service.report(userID: userID) {
                switch $0 {
                case .success(_):
                    Toast(type: .icon(.init(systemName: "checkmark")), text: String(format: Localizations.reportUserSuccess, name)).show()
                case .failure(_):
                    Toast(type: .icon(.init(systemName: "xmark")), text: String(format: Localizations.reportUserFailure, name)).show()
                }
            }
        }

        alert.addAction(.init(title: Localizations.reportAndBlock, style: .destructive) { _ in
            report()
            Task { [weak self] in
                try await self?.block(userID: userID, showAlert: false)
            }
        })

        alert.addAction(.init(title: Localizations.reportTitle, style: .destructive) { _ in
            report()
        })

        alert.addAction(.init(title: Localizations.buttonCancel, style: .cancel) { _ in })

        present(alert, animated: true)
    }
}

// MARK: - Localization

extension Localizations {

    static func removeFriendTitle(name: String) -> String {
        let format = NSLocalizedString("remove.friend.title",
                                       value: "Remove %@ from Friends",
                                       comment: "Title of an alert that appears when removing a friend.")
        return String(format: format, name)
    }

    static func removeFriendBody(name: String) -> String {
        let format = NSLocalizedString("remove.friend.body",
                                       value: "%@ and you will no longer be able to see each other’s posts.",
                                       comment: "Body of an alert that appears when removing a friend.")
        return String(format: format, name)
    }

    static func blockTitle(name: String) -> String {
        let format = NSLocalizedString("block.title", value: "Block %@", comment: "Title of an alert when blocking a user.")
        return String(format: format, name)
    }

    static func unblockTitle(name: String) -> String {
        let format = NSLocalizedString("unblock.title", value: "Unblock %@", comment: "Title of an alert when unblocking a user")
        return String(format: format, name)
    }

    static var blockSuccess: String {
        NSLocalizedString("block.success",
                          value: "Blocked",
                          comment: "Success message displayed after blocking a user.")
    }

    static var blockFailure: String {
        NSLocalizedString("block.success",
                          value: "Failed to Block",
                          comment: "Failure message displayed after trying to block a user.")
    }

    static var genericError: String {
        NSLocalizedString("generic.error",
                          value: "An Error Occurred",
                          comment: "When displaying a generic error message.")
    }
}
