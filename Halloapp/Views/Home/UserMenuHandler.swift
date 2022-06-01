//
//  UserContextMenuHandler.swift
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

enum UserMenuAction {
    case message(UserID)
    case call(UserID, CallType)
    case addContact(UserID)
    case safetyNumber(UserID, contactData: SafetyNumberData, bundle: UserKeyBundle)
    case commonGroups(UserID)
    case block(UserID)
    case unblock(UserID)
}

/// For responding to context actions for a specific user.
protocol UserMenuHandler {
    func handle(action: UserMenuAction)
}

// MARK: - default implementations for view controllers

extension UserMenuHandler where Self: UIViewController {
    func handle(action: UserMenuAction) {
        switch action {
        case .message(let id):
            pushChatViewController(id)
        case .call(let id, let type) where type == .audio:
            startCall(to: id, type: .audio)
        case .call(let id, let type) where type == .video:
            startCall(to: id, type: .video)
        case .addContact(let id):
            addToContacts(userID: id)
        case .safetyNumber(let id, let contactData, let bundle):
            verifySafetyNumber(userID: id, contactData: contactData, bundle: bundle)
        case .commonGroups(let id):
            groupsInCommon(userID: id)
        case .block(let id):
            block(userID: id)
        case .unblock(let id):
            unblock(userID: id)
        default:
            break
        }
    }
    
    private func pushChatViewController(_ id: UserID) {
        // slight delay because otherwise the dismissal of the context menu makes the
        // push animation look abrupt
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            if AppContext.shared.userDefaults.bool(forKey: "enableNewChat") {
                let vc = ChatViewControllerNew(for: id)
                self?.navigationController?.pushViewController(vc, animated: true)
            } else {
                let vc = ChatViewController(for: id)
                self?.navigationController?.pushViewController(vc, animated: true)
            }
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
    
    private func verifySafetyNumber(userID: UserID, contactData: SafetyNumberData, bundle: UserKeyBundle) {
        let current = SafetyNumberData(userID: MainAppContext.shared.userData.userId, identityKey: bundle.identityPublicKey)
        let vc = SafetyNumberViewController(currentUser: current,
                                                contact: contactData,
                                            contactName: MainAppContext.shared.contactStore.fullName(for: userID),
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
    
    private func block(userID: UserID) {
        let blockMessage = Localizations.blockMessage(username: MainAppContext.shared.contactStore.fullName(for: userID))
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
        let unblockMessage = Localizations.unBlockMessage(username: MainAppContext.shared.contactStore.fullName(for: userID))
        let alert = UIAlertController(title: nil, message: unblockMessage, preferredStyle: .actionSheet)
        let unblockButton = UIAlertAction(title: Localizations.unBlockButton, style: .default) { _ in
            MainAppContext.shared.privacySettings.unblock(userID: userID)
        }
        
        let cancelButton = UIAlertAction(title: Localizations.buttonCancel, style: .cancel)
        alert.addAction(unblockButton)
        alert.addAction(cancelButton)
        
        present(alert, animated: true)
    }
}

// MARK: - creating menus

extension UIMenu {
    struct UserMenuOptions: OptionSet {
        let rawValue: Int
        /// `.message` and `.call` actions.
        static let contactActions = UserMenuOptions(rawValue: 1 << 0)
        /// `.addContact`, `.safetyNumber`, and `.commonGroups` actions.
        static let utilityActions = UserMenuOptions(rawValue: 1 << 1)
        /// `.block` / `.unblock` actions.
        static let blockAction = UserMenuOptions(rawValue: 1 << 2)
        static let all: UserMenuOptions = [contactActions, utilityActions, blockAction]
    }
    
    /**
     Create a menu for a specific user.
     
     - Returns: `nil` if `userID` is equal to the user's own id.
     */
    static func menu(for userID: UserID, options: UserMenuOptions = .all, handler: @escaping (UserMenuAction) -> Void) -> UIMenu? {
        guard userID != MainAppContext.shared.userData.userId else {
            return nil
        }
        
        var items = [UIMenuElement]()
        
        if options.contains(.contactActions), let contactMenu = contactMenu(for: userID, handler: handler) {
            items.append(contactMenu)
        }
        
        if options.contains(.utilityActions) {
            items.append(utilityMenu(for: userID, handler: handler))
        }
        
        if options.contains(.blockAction) {
            items.append(blockMenu(for: userID, handler: handler))
        }
        
        return UIMenu(title: "", options: .displayInline, children: items)
    }
    
    /**
     Get the first part of the menu that includes `.message` and `.call` cases.
     
     - Returns: `nil` if `userID` isn't in the contact store.
     */
    private static func contactMenu(for userID: UserID, handler: @escaping (UserMenuAction) -> Void) -> UIMenu? {
        guard let _ = MainAppContext.shared.contactStore.contact(withUserId: userID) else {
            return nil
        }
        
        var items = [UIMenuElement]()
        items.append(UIAction(title: Localizations.contextMenuMessageUser, image: .init(systemName: "message")) { _ in
            handler(.message(userID))
        })
        
        items.append(UIAction(title: Localizations.contextMenuAudioCall, image: .init(systemName: "phone")) { _ in
            handler(.call(userID, .audio))
        })
        
        if ServerProperties.isVideoCallsEnabled {
            items.append(UIAction(title: Localizations.contextMenuVideoCall, image: .init(systemName: "video")) { _ in
                handler(.call(userID, .video))
            })
        }
        
        return UIMenu(title: "", options: .displayInline, children: items)
    }
    
    /**
     Get the second part of the menu that includes `.addContact`, `.safetyNumber`, and `.commonGroups`.
     */
    private static func utilityMenu(for userID: UserID, handler: @escaping (UserMenuAction) -> Void) -> UIMenu {
        var items = [UIMenuElement]()
        let shouldAllowContactsAdd = !MainAppContext.shared.contactStore.isContactInAddressBook(userId: userID) &&
                                      MainAppContext.shared.contactStore.pushNumber(userID) != nil
        
        // add to contacts
        if shouldAllowContactsAdd {
            items.append(UIAction(title: Localizations.addToContactBook,
                                  image: UIImage(systemName: "person.badge.plus")) { _ in
                handler(.addContact(userID))
            })
        }
        
        // verify safety number
        let context = MainAppContext.shared
        if let keys = context.keyStore.keyBundle(),
           let bundle = context.keyStore.messageKeyBundle(for: userID)?.keyBundle,
           let data = SafetyNumberData(keyBundle: bundle) {
            
            items.append(UIAction(title: Localizations.safetyNumberTitle, image: UIImage(systemName: "number")) { _ in
                handler(.safetyNumber(userID, contactData: data, bundle: keys))
            })
        }
        
        // groups in common
        items.append(UIAction(title: Localizations.groupsInCommonButtonLabel,
                              image: UIImage(named: "TabBarGroups")?.withTintColor(.label, renderingMode: .alwaysOriginal)) { _ in
            handler(.commonGroups(userID))
        })
        
        return UIMenu(title: "", options: .displayInline, children: items)
    }
    
    /**
     Get the last part of the menu that includes either `.block` or `.unblock`.
     */
    private static func blockMenu(for userID: UserID, handler: @escaping (UserMenuAction) -> Void) -> UIMenu {
        let isBlocked = MainAppContext.shared.privacySettings.blocked.userIds.contains(userID)
        
        var block: UIAction!
        if !isBlocked {
            block = UIAction(title: Localizations.userOptionBlock, image: .init(systemName: "nosign"), attributes: .destructive) { _ in
                handler(.block(userID))
            }
        } else {
            block = UIAction(title: Localizations.userOptionUnblock, image: .init(systemName: "nosign")) { _ in
                handler(.unblock(userID))
            }
        }
        
        return UIMenu(title: "", options: .displayInline, children: [block])
    }
}
