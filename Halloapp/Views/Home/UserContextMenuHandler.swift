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
import CocoaLumberjackSwift

enum UserContextAction {
    case message(UserID)
    case call(UserID, CallType)
    case block(UserID)
    case unblock(UserID)
}

/// For responding to context actions for a specific user.
protocol UserContextMenuHandler {
    func handle(user action: UserContextAction)
}

// MARK: - default implementations for view controllers

extension UserContextMenuHandler where Self: UIViewController {
    func handle(user action: UserContextAction) {
        switch action {
        case .message(let id):
            pushChatViewController(id)
        case .call(let id, let type) where type == .audio:
            startCall(to: id, type: .audio)
        case .call(let id, let type) where type == .video:
            startCall(to: id, type: .video)
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
            let vc = ChatViewController(for: id)
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
    
    private func block(userID: UserID) {
        let privacySettings = MainAppContext.shared.privacySettings
        guard let blockedList = privacySettings.blocked, MainAppContext.shared.userData.userId != userID else {
            return
        }
        
        privacySettings.replaceUserIDs(in: blockedList, with: blockedList.userIds + [userID])
        MainAppContext.shared.didPrivacySettingChange.send(userID)
    }
    
    private func unblock(userID: UserID) {
        let privacySettings = MainAppContext.shared.privacySettings
        guard let blockedList = privacySettings.blocked else { return }
        
        var newBlockList = blockedList.userIds
        newBlockList.removeAll { value in return value == userID}
        privacySettings.replaceUserIDs(in: blockedList, with: newBlockList)
        
        MainAppContext.shared.didPrivacySettingChange.send(userID)
    }
}
