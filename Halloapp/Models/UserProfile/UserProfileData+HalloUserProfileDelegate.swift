//
//  UserProfileData+HalloUserProfileDelegate.swift
//  HalloApp
//
//  Created by Tanveer on 8/8/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CoreData
import Core
import CoreCommon
import CocoaLumberjackSwift

extension UserProfileData: HalloUserProfileDelegate {

    func halloService(_ halloService: HalloService, didReceiveProfileUpdate profileUpdate: Server_HalloappProfileUpdate, ack: (() -> Void)?) {
        let serverProfile = profileUpdate.profile
        let userID = String(serverProfile.uid)
        let updatedFriendshipStatus = serverProfile.status.userProfileFriendshipStatus
        let profileUpdateType = profileUpdate.type
        DDLogInfo("UserProfileData/didReceiveProfileUpdate/\(userID)/\(profileUpdate.type)")

        mainDataStore.saveSeriallyOnBackgroundContext { context in
            let profile = UserProfile.findOrCreate(with: userID, in: context)
            let currentFriendshipStatus = profile.friendshipStatus
            let isNoLongerFriend = currentFriendshipStatus == .friends && updatedFriendshipStatus != .friends
            
            profile.update(with: serverProfile)
            self.updateFriendActivity(for: userID, after: profileUpdateType, friendshipStatus: updatedFriendshipStatus, in: context)

            switch profileUpdateType {
            case .normal where isNoLongerFriend:
                UserProfile.removeContent(for: userID, in: context, options: .unfriended)
            case .deleteNotice:
                UserProfile.removeContent(for: userID, in: context, options: .deletedAccount)
            default:
                break
            }

        } completion: { result in
            switch result {
            case .success:
                ack?()
                Task { await self.updateFriendshipNotifications(for: userID, serverProfile: serverProfile, updateType: profileUpdateType) }
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

    // MARK: Activities

    private func updateFriendActivity(for userID: UserID,
                                      after updateType: Server_HalloappProfileUpdate.TypeEnum,
                                      friendshipStatus: UserProfile.FriendshipStatus,
                                      in context: NSManagedObjectContext) {
        switch updateType {
        case .incomingFriendRequest:
            // show a notification for a pending incoming request
            FriendActivity.findOrCreate(with: userID, in: context).status = .pending
        case .friendNotice:
            // show a notification indicating an accepted outgoing request
            FriendActivity.findOrCreate(with: userID, in: context).status = .accepted
        default:
            if case .none = friendshipStatus {
                FriendActivity.find(with: userID, in: context)?.status = .none
            }
        }
    }

    // MARK: Notifications

    @MainActor
    private func updateFriendshipNotifications(for userID: UserID, serverProfile: Server_HalloappUserProfile, updateType: Server_HalloappProfileUpdate.TypeEnum) {
        guard UIApplication.shared.applicationState != .active else {
            return
        }

        let name = serverProfile.name
        let isFriend = serverProfile.status.userProfileFriendshipStatus == .friends

        switch updateType {
        case .friendNotice, .incomingFriendRequest:
            guard let metadata = NotificationMetadata(userID: userID, name: name, profileUpdateType: updateType) else {
                break
            }
            DDLogInfo("UserProfileData/updateFriendshipNotifications/presenting [\(userID)] [\(updateType)]")
            NotificationRequest.createAndShow(from: metadata, shouldRecord: false)

        case .normal, .deleteNotice:
            guard !isFriend else {
                break
            }
            DDLogInfo("UserProfileData/updateFriendshipNotifications/removing [\(userID)] if found")
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [userID])

        case .UNRECOGNIZED:
            DDLogError("UserProfileData/unrecognized update type")
        }
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
