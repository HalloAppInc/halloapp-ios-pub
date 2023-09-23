//
//  UserActions.swift
//  HalloApp
//
//  Created by Tanveer on 2/25/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit
import Core
import CoreCommon
import CocoaLumberjackSwift

enum UserAction {
    case message(UserID)
    case call(UserID, CallType)
    case addContact(UserID)
    case viewProfile(UserID)
    case addFavorite(UserID)
    case removeFavorite(UserID)
    case safetyNumber(UserID, contactData: SafetyNumberData, bundle: UserKeyBundle)
    case commonGroups(UserID)
    case block(UserID)
    case unblock(UserID)
    case report(UserID)
}

/// For responding to context actions for a specific user.
protocol UserActionHandler {
    func handle(action: UserAction)
}

// MARK: - default implementations for view controllers

extension UserActionHandler where Self: UIViewController {

    func handle(action: UserAction) {
        switch action {
        case .message(let id):
            pushChatViewController(id)
        case .call(let id, let type) where type == .audio:
            startCall(to: id, type: .audio)
        case .call(let id, let type) where type == .video:
            startCall(to: id, type: .video)
        case .addContact(let id):
            addToContacts(userID: id)
        case .addFavorite(let id):
            addFavorite(userID: id)
        case .removeFavorite(let id):
            removeFavorite(userID: id)
        case .viewProfile(let id):
            viewProfile(userID: id)
        case .safetyNumber(let id, let contactData, let bundle):
            verifySafetyNumber(userID: id, contactData: contactData, bundle: bundle)
        case .commonGroups(let id):
            groupsInCommon(userID: id)
        case .block(let id):
            block(userID: id)
        case .unblock(let id):
            unblock(userID: id)
        case .report(let id):
            report(userID: id)
        default:
            break
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
    
    private func addToContacts(userID: UserID) {
        MainAppContext.shared.contactStore.addUserToAddressBook(userID: userID, presentingVC: self)
    }

    private func addFavorite(userID: UserID) {
        MainAppContext.shared.privacySettings.addFavorite(userID)

        let name = MainAppContext.shared.contactStore.firstName(for: userID, in: MainAppContext.shared.contactStore.viewContext)
        let toast = Toast(type: .icon(UIImage(named: "FavoritesOutline")?.withRenderingMode(.alwaysTemplate)),
                          text: String(format: Localizations.addedToFavorites, name))

        toast.show()
    }

    private func removeFavorite(userID: UserID) {
        MainAppContext.shared.privacySettings.removeFavorite(userID)

        let name = MainAppContext.shared.contactStore.firstName(for: userID, in: MainAppContext.shared.contactStore.viewContext)
        let toast = Toast(type: .icon(UIImage(named: "UnfavoriteOutline")?.withRenderingMode(.alwaysTemplate)),
                          text: String(format: Localizations.removedFromFavorites, name))

        toast.show()
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
    
    private func block(userID: UserID, showAlert: Bool = true) {
        guard showAlert else {
            return MainAppContext.shared.privacySettings.block(userID: userID)
        }

        let name = UserProfile.find(with: userID, in: MainAppContext.shared.mainDataStore.viewContext)?.displayName ?? ""
        let blockMessage = Localizations.blockMessage(username: name)
        let alert = UIAlertController(title: nil, message: blockMessage, preferredStyle: .actionSheet)
        let blockButon = UIAlertAction(title: Localizations.blockButton, style: .destructive) { _ in
            MainAppContext.shared.privacySettings.block(userID: userID)
        }
        
        let cancelButton = UIAlertAction(title: Localizations.buttonCancel, style: .cancel)
        alert.addAction(blockButon)
        alert.addAction(cancelButton)
        
        present(alert, animated: true)
    }
    
    private func unblock(userID: UserID) {
        let name = UserProfile.find(with: userID, in: MainAppContext.shared.mainDataStore.viewContext)?.displayName ?? ""
        let unblockMessage = Localizations.unBlockMessage(username: name)
        let alert = UIAlertController(title: nil, message: unblockMessage, preferredStyle: .actionSheet)
        let unblockButton = UIAlertAction(title: Localizations.unBlockButton, style: .default) { _ in
            MainAppContext.shared.privacySettings.unblock(userID: userID)
        }
        
        let cancelButton = UIAlertAction(title: Localizations.buttonCancel, style: .cancel)
        alert.addAction(unblockButton)
        alert.addAction(cancelButton)
        
        present(alert, animated: true)
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
            self.block(userID: userID, showAlert: false)
        })

        alert.addAction(.init(title: Localizations.reportTitle, style: .destructive) { _ in
            report()
        })

        alert.addAction(.init(title: Localizations.buttonCancel, style: .cancel) { _ in })

        present(alert, animated: true)
    }
}

// MARK: - creating menus

extension HAMenu {

    typealias UserActionCallback = @MainActor @Sendable (UserAction) async -> Void

    struct UserMenuOptions: OptionSet {
        let rawValue: Int

        static let message = UserMenuOptions(rawValue: 1 << 0)
        static let voiceCall = UserMenuOptions(rawValue: 1 << 1)
        static let videoCall = UserMenuOptions(rawValue: 1 << 2)
        static let viewProfile = UserMenuOptions(rawValue: 1 << 3)
        static let addContact = UserMenuOptions(rawValue: 1 << 4)
        static let favorite = UserMenuOptions(rawValue: 1 << 5)
        static let safetyNumber = UserMenuOptions(rawValue: 1 << 6)
        static let commonGroups = UserMenuOptions(rawValue: 1 << 7)
        static let block = UserMenuOptions(rawValue: 1 << 8)
        static let report = UserMenuOptions(rawValue: 1 << 9)

        static let all: UserMenuOptions = [.firstGroup, .secondGroup, .thirdGroup]
        fileprivate static let firstGroup: UserMenuOptions = [.message, .voiceCall, .videoCall]
        fileprivate static let secondGroup: UserMenuOptions = [.viewProfile, .addContact, .favorite, .safetyNumber, .commonGroups]
        fileprivate static let thirdGroup: UserMenuOptions = [.block, .report]

        fileprivate static var ordered: [UserMenuOptions] {
            [
                .message, .voiceCall, .videoCall,
                .viewProfile, .addContact, .favorite, .safetyNumber, .commonGroups,
                .block, .report
            ]
        }
    }

    /// - Returns: A menu for a specific user.
    static func menu(for userID: UserID, options: UserMenuOptions = .all, handler: @escaping UserActionCallback) -> HAMenu {
        guard userID != MainAppContext.shared.userData.userId else {
            return HAMenu { }.displayInline()
        }

        return HAMenu.lazy {
            buildMenu(userID: userID, desiredOptions: options, handler: handler)
        }
        .displayInline()
    }

    private static func buildMenu(userID: UserID, desiredOptions: UserMenuOptions, handler: @escaping UserActionCallback) -> [HAMenuItem] {
        let inAddressBook = MainAppContext.shared.contactStore.isContactInAddressBook(userId: userID, in: MainAppContext.shared.contactStore.viewContext)
        var currentGroup = UserMenuOptions.firstGroup
        var currentButtonGroup = [HAMenuButton]()
        var menuItems = [HAMenuItem]()

        func finalizeCurrentGroup() {
            let menu = HAMenu {
                for button in currentButtonGroup { button }
            }
            .displayInline()

            menuItems.append(.menu(menu))
            currentButtonGroup = []
        }

        for option in UserMenuOptions.ordered where desiredOptions.contains(option) {
            guard let button = button(for: option, userID: userID, inAddressBook: inAddressBook, handler: handler) else {
                continue
            }

            if currentGroup.contains(option) {
                currentButtonGroup.append(button)
                continue
            }

            // button is part of a different group; finalize the previous group and start a new one
            finalizeCurrentGroup()

            if let nextGroup = [UserMenuOptions.firstGroup, UserMenuOptions.secondGroup, UserMenuOptions.thirdGroup].first(where: { $0.contains(option) }) {
                currentGroup = nextGroup
                currentButtonGroup.append(button)
            } else {
                DDLogError("UserMenuHandler/buildMenu/unknown group for option \(option)")
                break
            }
        }

        finalizeCurrentGroup()
        return menuItems
    }

    private static func button(for option: UserMenuOptions, userID: UserID, inAddressBook: Bool, handler: @escaping UserActionCallback) -> HAMenuButton? {
        switch option {
        case .message:
            return messageButton(userID, handler: handler)
        case .voiceCall where inAddressBook:
            return callButton(userID, callType: .audio, handler: handler)
        case .videoCall where inAddressBook:
            return callButton(userID, callType: .video, handler: handler)

        case .viewProfile:
            return profileButton(userID, handler: handler)
        case .addContact where !inAddressBook:
            return addContactButton(userID, handler: handler)
        case .favorite where inAddressBook:
            return favoriteButton(userID, handler: handler)
        case .safetyNumber:
            return safetyNumberButton(userID, handler: handler)
        case .commonGroups:
            return commonGroupsButton(userID, handler: handler)

        case .block:
            return blockButton(userID, handler: handler)
        case .report:
            return reportButton(userID, handler: handler)

        default:
            return nil
        }
    }

    private static func messageButton(_ userID: UserID, handler: @escaping UserActionCallback) -> HAMenuButton {
        HAMenuButton(title: Localizations.contextMenuMessageUser, image: .init(systemName: "message")) {
            await handler(.message(userID))
        }
    }

    private static func callButton(_ userID: UserID, callType: CallType, handler: @escaping UserActionCallback) -> HAMenuButton {
        let title = callType == .video ? Localizations.contextMenuVideoCall : Localizations.contextMenuAudioCall
        let image = callType == .video ? UIImage(systemName: "video") : UIImage(systemName: "phone")

        return HAMenuButton(title: title, image: image) {
            await handler(.call(userID, callType))
        }
    }

    private static func profileButton(_ userID: UserID, handler: @escaping UserActionCallback) -> HAMenuButton {
        HAMenuButton(title: Localizations.viewProfile, image: UIImage(systemName: "info.circle")) {
            await handler(.viewProfile(userID))
        }
    }

    private static func addContactButton(_ userID: UserID, handler: @escaping UserActionCallback) -> HAMenuButton? {
        guard MainAppContext.shared.contactStore.pushNumber(userID) != nil else {
            return nil
        }

        return HAMenuButton(title: Localizations.addToContactBook, image: UIImage(systemName: "person.badge.plus")) {
            await handler(.addContact(userID))
        }
    }

    /// - note: Assumes that `userID` is in the user's address book.
    private static func favoriteButton(_ userID: UserID, handler: @escaping UserActionCallback) -> HAMenuButton? {
        guard !MainAppContext.shared.privacySettings.isBlocked(userID) else {
            return nil
        }

        // either is already a favorite or is eligible for being one
        let isFavorite = MainAppContext.shared.privacySettings.isFavorite(userID)
        let title = isFavorite ? Localizations.removeFromFavorites : Localizations.addToFavorites
        let image = isFavorite ? UIImage(named: "UnfavoriteOutline") : UIImage(named: "FavoritesOutline")
        let action: UserAction = isFavorite ? .removeFavorite(userID) : .addFavorite(userID)

        return HAMenuButton(title: title, image: image?.withRenderingMode(.alwaysTemplate)) {
            await handler(action)
        }
    }

    private static func safetyNumberButton(_ userID: UserID, handler: @escaping UserActionCallback) -> HAMenuButton? {
        let context = MainAppContext.shared
        guard
            let keys = context.keyStore.keyBundle(in: context.keyStore.viewContext),
            let bundle = context.keyStore.messageKeyBundle(for: userID, in: context.keyStore.viewContext)?.keyBundle,
            let data = SafetyNumberData(keyBundle: bundle)
        else {
            return nil
        }

        return HAMenuButton(title: Localizations.safetyNumberTitle, image: UIImage(systemName: "number")) {
            await handler(.safetyNumber(userID, contactData: data, bundle: keys))
        }
    }

    private static func commonGroupsButton(_ userID: UserID, handler: @escaping UserActionCallback) -> HAMenuButton {
        HAMenuButton(title: Localizations.groupsInCommonButtonLabel, image: UIImage(named: "TabBarGroups")?.withRenderingMode(.alwaysTemplate)) {
            await handler(.commonGroups(userID))
        }
    }

    private static func blockButton(_ userID: UserID, handler: @escaping UserActionCallback) -> HAMenuButton {
        if !MainAppContext.shared.privacySettings.isBlocked(userID) {
            return HAMenuButton(title: Localizations.userOptionBlock, image: .init(systemName: "nosign")) {
                await handler(.block(userID))
            }
            .destructive()
        } else {
            return HAMenuButton(title: Localizations.userOptionUnblock, image: .init(systemName: "nosign")) {
                await handler(.unblock(userID))
            }
        }
    }

    private static func reportButton(_ userID: UserID, handler: @escaping UserActionCallback) -> HAMenuButton {
        HAMenuButton(title: Localizations.reportUser, image: UIImage(systemName: "flag")) {
            await handler(.report(userID))
        }
        .destructive()
    }
}

// MARK: - Localization

extension Localizations {

    static var viewProfile: String {
        NSLocalizedString("view.profile",
                   value: "View Profile",
                 comment: "Title of a button that navigates to a user's profile.")
    }

    static var addToFavorites: String {
        NSLocalizedString("add.to.favorites.title",
                   value: "Add to Favorites",
                 comment: "Text for the action of adding a contact to the user's favorites list (title case).")
    }

    static var removeFromFavorites: String {
        NSLocalizedString("remove.from.favorites.title",
                   value: "Remove from Favorites",
                 comment: "Text for the action of removing a contact from the user's favorites list (title case).")
    }

    static var addedToFavorites: String {
        NSLocalizedString("added.user.to.favorites",
                   value: "Added %@ to favorites",
                 comment: "Confirmation when a user was successfully added to favorites.")
    }

    static var removedFromFavorites: String {
        NSLocalizedString("removed.user.from.favorites",
                   value: "Removed %@ from favorites",
                 comment: "Confirmation when a user was successfully removed from favorites.")
    }

    static var reportUser: String {
        NSLocalizedString("report.user",
                   value: "Report User",
                 comment: "Title of a button that reports a user.")
    }

    static var reportUserMessage: String {
        NSLocalizedString("report.user.message",
                   value: "Are you sure want to report %@?",
                 comment: "Message confirming if the user wants to report someone.")
    }

    static var reportUserTitle: String {
        NSLocalizedString("report.user.title",
                   value: "Report %@",
                 comment: "Title of the dialog that appears when reporting a user.")
    }

    static var reportTitle: String {
        NSLocalizedString("report.title",
                   value: "Report",
                 comment: "Title of the report button.")
    }

    static var reportAndBlock: String {
        NSLocalizedString("report.and.block",
                   value: "Report and Block",
                 comment: "Title of the button that both reports and blocks a user.")
    }

    static var reportUserSuccess: String {
        NSLocalizedString("report.user.success",
                   value: "Reported %@",
                 comment: "Message that's displayed after successfully reporting a user.")
    }

    static var reportUserFailure: String {
        NSLocalizedString("report.user.failure",
                    value: "Failed to Report %@",
                  comment: "Message that's displayed when reporting a user failed.")
    }
}
