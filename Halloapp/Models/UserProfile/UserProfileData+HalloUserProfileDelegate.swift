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

        switch profileUpdate.type {
        case .normal:
            // TODO
            break
        case .friendNotice:
            break
        case .incomingFriendRequest:
            // TODO
            break
        case .deleteNotice:
            // TODO
            break
        case .UNRECOGNIZED:
            DDLogError("UserProfileData/unrecognized update type")
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
}
