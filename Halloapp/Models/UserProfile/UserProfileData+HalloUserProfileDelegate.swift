//
//  UserProfileData+HalloUserProfileDelegate.swift
//  HalloApp
//
//  Created by Tanveer on 8/8/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import CocoaLumberjackSwift

extension UserProfileData: HalloUserProfileDelegate {

    func halloService(_ halloService: HalloService, didReceiveProfileUpdate profileUpdate: Server_HalloappProfileUpdate, ack: (() -> Void)?) {
        let serverProfile = profileUpdate.profile
        let userID = String(serverProfile.uid)
        DDLogInfo("UserProfileData/didReceiveProfileUpdate/\(userID)/\(profileUpdate.type)")

        let updateNotifications = {
            switch profileUpdate.type {
            case .friendNotice, .incomingFriendRequest:
                await self.presentFriendshipNotification(from: userID, name: serverProfile.name, updateType: profileUpdate.type)
            case .normal, .deleteNotice:
                if serverProfile.status.userProfileFriendshipStatus != .friends {
                    // remove pending friendship notifications, if any
                    await self.removeFriendshipNotification(from: userID)
                }
            case .UNRECOGNIZED:
                DDLogError("UserProfileData/unrecognized update type")
            }
        }

        mainDataStore.saveSeriallyOnBackgroundContext { context in
            let profile = UserProfile.findOrCreate(with: userID, in: context)
            let currentFriendshipStatus = profile.friendshipStatus
            profile.update(with: serverProfile)

            if case .friends = currentFriendshipStatus, currentFriendshipStatus != profile.friendshipStatus {
                // no longer friends, remove content
                UserProfile.removeContent(for: userID, in: context, options: .unfriended)
            }

        } completion: { result in
            switch result {
            case .success:
                ack?()
                Task { await updateNotifications() }
            case .failure(let error):
                DDLogError("UserProfileData/failed to update profile \(String(describing: error))")
            }
        }
    }

    func halloServiceDidReceiveFriendListSyncRequest(_ halloService: HalloService, ack: (() -> Void)?) {
        DDLogInfo("UserProfileData/didReceiveFriendListSyncRequest")
        Task {
            await syncFriendships()
        }
    }

    // Notifications

    @MainActor
    private func presentFriendshipNotification(from userID: UserID, name: String, updateType: Server_HalloappProfileUpdate.TypeEnum) {
        guard UIApplication.shared.applicationState != .active,
              let metadata = NotificationMetadata(userID: userID, name: name, profileUpdateType: updateType) else {
            return
        }
        
        DDLogInfo("UserProfileData/presentFriendshipNotification/presenting [\(userID)] [\(updateType)]")
        // avoid recording friend notifications as they may arrive again in the future with the same ID
        NotificationRequest.createAndShow(from: metadata, shouldRecord: false)
    }

    @MainActor
    private func removeFriendshipNotification(from userID: UserID) {
        guard UIApplication.shared.applicationState != .active else {
            return
        }

        DDLogInfo("UserProfileData/removeFriendshipNotification/removing [\(userID)] if found")
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [userID])
    }
}

// MARK: - NotificationMetadata + Convenience

extension NotificationMetadata {

    fileprivate convenience init?(userID: UserID, name: String, profileUpdateType: Server_HalloappProfileUpdate.TypeEnum) {
        let contentType: NotificationContentType
        switch profileUpdateType {
        case .friendNotice:
            contentType = .friendRequest
        case .incomingFriendRequest:
            contentType = .friendAccept
        default:
            return nil
        }

        self.init(contentId: userID,
                  contentType: contentType,
                  fromId: userID,
                  groupId: nil,
                  groupType: nil,
                  groupName: nil,
                  timestamp: Date(),
                  data: nil,
                  messageId: nil,
                  pushName: name)
    }
}
