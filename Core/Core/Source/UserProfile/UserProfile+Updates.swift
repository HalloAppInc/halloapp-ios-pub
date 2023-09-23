//
//  UserProfile+Updates.swift
//  Core
//
//  Created by Tanveer on 9/13/23.
//  Copyright © 2023 Hallo App, Inc. All rights reserved.
//

import CoreCommon

extension UserProfile {

    public func update(with serverProfile: Server_HalloappUserProfile) {
        id = String(serverProfile.uid)

        if serverProfile.username != username {
            username = serverProfile.username
        }

        if serverProfile.name != name {
            name = serverProfile.name
        }

        if serverProfile.avatarID != avatarID {
            avatarID = serverProfile.avatarID
            AppContext.shared.avatarStore.addAvatar(id: serverProfile.avatarID, for: id)
        }

        let serverStatus = serverProfile.status.userProfileFriendshipStatus
        if serverStatus != friendshipStatus {
            friendshipStatus = serverStatus
        }

        if serverProfile.blocked != isBlocked {
            isBlocked = serverProfile.blocked
        }
    }

    public class func updateNames(with mapping: [UserID: String]) {
        guard !mapping.isEmpty else {
            return
        }

        AppContext.shared.mainDataStore.saveSeriallyOnBackgroundContext { context in
            findOrCreate(with: Array(mapping.keys), in: context)
                .forEach { profile in
                    profile.name = mapping[profile.id] ?? profile.name
                }
        }
    }
}
