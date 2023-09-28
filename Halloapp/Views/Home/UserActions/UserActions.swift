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
    case message
    case call(type: CallType)
    case addFriend
    case removeFriend
    case viewProfile
    case addFavorite
    case removeFavorite
    case safetyNumber(contactData: SafetyNumberData, bundle: UserKeyBundle)
    case commonGroups
    case block
    case unblock
    case report
}

/// For responding to context actions for a specific user.
protocol UserActionHandler {
    func handle(_ action: UserAction, for userID: UserID) async throws
}

// MARK: - creating menus

extension HAMenu {

    typealias UserActionCallback = @MainActor @Sendable (UserAction, UserID) async -> Void

    struct UserMenuOptions: OptionSet {
        let rawValue: Int

        static let message = UserMenuOptions(rawValue: 1 << 0)
        static let voiceCall = UserMenuOptions(rawValue: 1 << 1)
        static let videoCall = UserMenuOptions(rawValue: 1 << 2)
        static let viewProfile = UserMenuOptions(rawValue: 1 << 3)
        static let updateFriendship = UserMenuOptions(rawValue: 1 << 4)
        static let favorite = UserMenuOptions(rawValue: 1 << 5)
        static let safetyNumber = UserMenuOptions(rawValue: 1 << 6)
        static let commonGroups = UserMenuOptions(rawValue: 1 << 7)
        static let block = UserMenuOptions(rawValue: 1 << 8)
        static let report = UserMenuOptions(rawValue: 1 << 9)

        static let all: UserMenuOptions = [.firstGroup, .secondGroup, .thirdGroup]
        fileprivate static let firstGroup: UserMenuOptions = [.message, .voiceCall, .videoCall]
        fileprivate static let secondGroup: UserMenuOptions = [.viewProfile, .updateFriendship, .favorite, .safetyNumber, .commonGroups]
        fileprivate static let thirdGroup: UserMenuOptions = [.block, .report]

        fileprivate static var ordered: [UserMenuOptions] {
            [
                .message, .voiceCall, .videoCall,
                .viewProfile, .updateFriendship, .favorite, .safetyNumber, .commonGroups,
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
        let profile = UserProfile.findOrCreate(with: userID, in: MainAppContext.shared.mainDataStore.viewContext)
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
            guard let button = button(for: option, profile: profile, handler: handler) else {
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

    private static func button(for option: UserMenuOptions, profile: UserProfile, handler: @escaping UserActionCallback) -> HAMenuButton? {
        let id = profile.id

        switch (option, profile.friendshipStatus) {
        case (.message, .friends):
            return messageButton(id, handler: handler)
        case (.voiceCall, .friends):
            return callButton(id, callType: .audio, handler: handler)
        case (.videoCall, .friends):
            return callButton(id, callType: .video, handler: handler)

        case (.viewProfile, _):
            return profileButton(id, handler: handler)

        case (.updateFriendship, .none) where !profile.isBlocked:
            return addFriendButton(id, handler: handler)
        case (.updateFriendship, .friends) where !profile.isBlocked:
            return removeFriendButton(id, handler: handler)

        case (.favorite, .friends):
            return favoriteButton(id, isFavorite: profile.isFavorite, handler: handler)

        case (.commonGroups, _):
            return commonGroupsButton(id, handler: handler)

        case (.block, _):
            return blockButton(id, handler: handler)
        case (.report, _):
            return reportButton(id, handler: handler)

        default:
            return nil
        }
    }

    private static func messageButton(_ userID: UserID, handler: @escaping UserActionCallback) -> HAMenuButton {
        HAMenuButton(title: Localizations.contextMenuMessageUser, image: .init(systemName: "message")) {
            await handler(.message, userID)
        }
    }

    private static func callButton(_ userID: UserID, callType: CallType, handler: @escaping UserActionCallback) -> HAMenuButton {
        let title = callType == .video ? Localizations.contextMenuVideoCall : Localizations.contextMenuAudioCall
        let image = callType == .video ? UIImage(systemName: "video") : UIImage(systemName: "phone")

        return HAMenuButton(title: title, image: image) {
            await handler(.call(type: callType), userID)
        }
    }

    private static func profileButton(_ userID: UserID, handler: @escaping UserActionCallback) -> HAMenuButton {
        HAMenuButton(title: Localizations.viewProfile, image: UIImage(systemName: "info.circle")) {
            await handler(.viewProfile, userID)
        }
    }

    private static func addFriendButton(_ userID: UserID, handler: @escaping UserActionCallback) -> HAMenuButton {
        HAMenuButton(title: Localizations.addFriend, image: UIImage(systemName: "person.crop.circle.badge.plus")) {
            await handler(.addFriend, userID)
        }
    }

    private static func removeFriendButton(_ userID: UserID, handler: @escaping UserActionCallback) -> HAMenuButton {
        HAMenuButton(title: Localizations.removeFriend, image: UIImage(systemName: "person.crop.circle.badge.minus")) {
            await handler(.removeFriend, userID)
        }
    }

    /// - note: Assumes that `userID` is in the user's address book.
    private static func favoriteButton(_ userID: UserID, isFavorite: Bool, handler: @escaping UserActionCallback) -> HAMenuButton? {
        let title: String
        let image: UIImage?
        let action: UserAction

        if isFavorite {
            title = Localizations.removeFromFavorites
            image = UIImage(named: "UnfavoriteOutline")
            action = .removeFavorite
        } else {
            title = Localizations.addToFavorites
            image = UIImage(named: "FavoritesOutline")
            action = .addFavorite
        }

        return HAMenuButton(title: title, image: image?.withRenderingMode(.alwaysTemplate)) {
            await handler(action, userID)
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
            await handler(.safetyNumber(contactData: data, bundle: keys), userID)
        }
    }

    private static func commonGroupsButton(_ userID: UserID, handler: @escaping UserActionCallback) -> HAMenuButton {
        HAMenuButton(title: Localizations.groupsInCommonButtonLabel, image: UIImage(named: "TabBarGroups")?.withRenderingMode(.alwaysTemplate)) {
            await handler(.commonGroups, userID)
        }
    }

    private static func blockButton(_ userID: UserID, handler: @escaping UserActionCallback) -> HAMenuButton {
        if !MainAppContext.shared.privacySettings.isBlocked(userID) {
            return HAMenuButton(title: Localizations.userOptionBlock, image: .init(systemName: "nosign")) {
                await handler(.block, userID)
            }
            .destructive()
        } else {
            return HAMenuButton(title: Localizations.userOptionUnblock, image: .init(systemName: "nosign")) {
                await handler(.unblock, userID)
            }
        }
    }

    private static func reportButton(_ userID: UserID, handler: @escaping UserActionCallback) -> HAMenuButton {
        HAMenuButton(title: Localizations.reportUser, image: UIImage(systemName: "flag")) {
            await handler(.report, userID)
        }
        .destructive()
    }
}

// MARK: - Localization

extension Localizations {

    static var addFriend: String {
        NSLocalizedString("add.friend",
                          value: "Add Friend",
                          comment: "Title of a button to send a friend request.")
    }

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
                   value: "Added to Favorites",
                 comment: "Confirmation when a user was successfully added to favorites.")
    }

    static var removedFromFavorites: String {
        NSLocalizedString("removed.user.from.favorites",
                   value: "Removed from Favorites",
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
