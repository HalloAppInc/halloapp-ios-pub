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
            // TODO
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
            UserProfile.findOrCreate(with: userID, in: context).update(with: serverProfile)

        } completion: { result in
            switch result {
            case .success:
                ack?()
            case .failure(let error):
                DDLogError("UserProfileData/failed to update profile \(String(describing: error))")
            }
        }
    }
}
