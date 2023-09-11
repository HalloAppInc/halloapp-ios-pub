//
//  UserProfile+CoreDataClass.swift
//  Core
//
//  Created by Tanveer on 8/1/23.
//  Copyright © 2023 Hallo App, Inc. All rights reserved.
//
//

import Foundation
import CoreData
import CoreCommon

@objc(UserProfile)
public class UserProfile: NSManagedObject {

}

// MARK: - Friendship status

extension UserProfile {

    public enum FriendshipStatus: Int16 {
        case none = 0
        case incomingPending = 1
        case outgoingPending = 2
        case friends = 3
    }

    public var friendshipStatus: FriendshipStatus {
        get {
            FriendshipStatus(rawValue: friendshipStatusValue) ?? .none
        }

        set {
            friendshipStatusValue = newValue.rawValue
        }
    }
}

// MARK: - Updates

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
}

// MARK: -

extension Server_FriendshipStatus {

    public var userProfileFriendshipStatus: UserProfile.FriendshipStatus {
        switch self {
        case .noneStatus:
            return .none
        case .incomingPending:
            return .incomingPending
        case .outgoingPending:
            return .outgoingPending
        case .friends:
            return .friends
        case .UNRECOGNIZED(_):
            return .none
        }
    }
}
