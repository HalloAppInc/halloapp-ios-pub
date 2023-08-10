//
//  UserProfileData.swift
//  Core
//
//  Created by Tanveer on 8/8/23.
//  Copyright © 2023 Hallo App, Inc. All rights reserved.
//

import Foundation
import CoreData
import CoreCommon
import CocoaLumberjackSwift

public class UserProfileData: NSObject {

    public let mainDataStore: MainDataStore
    public let service: CoreService
    public let avatarStore: AvatarStore
    public let userData: UserData

    public init(dataStore: MainDataStore, service: CoreService, avatarStore: AvatarStore, userData: UserData) {
        self.mainDataStore = dataStore
        self.service = service
        self.avatarStore = avatarStore
        self.userData = userData

        super.init()

        // TODO: sync friendships
    }

    // MARK: Actions

    public func addFriend(userID: UserID) async throws {
        let updatedProfile = try await perform(action: .addFriend, for: userID)
        try await perform { context in
            UserProfile.findOrCreate(with: userID, in: context).update(with: updatedProfile)
        }
    }

    public func acceptFriend(userID: UserID) async throws {
        let updatedProfile = try await perform(action: .acceptFriend, for: userID)
        try await perform { context in
            UserProfile.findOrCreate(with: userID, in: context).update(with: updatedProfile)
        }
    }

    public func removeFriend(userID: UserID) async throws {
        let updatedProfile = try await perform(action: .removeFriend, for: userID)
        try await perform { context in
            UserProfile.findOrCreate(with: userID, in: context).update(with: updatedProfile)

            // TODO: delete content from unfriended user
        }
    }

    public func block(userID: UserID) async throws {
        let updatedProfile = try await perform(action: .block, for: userID)
        try await perform { context in
            UserProfile.findOrCreate(with: userID, in: context).update(with: updatedProfile)

            // TODO: delete content from blocked user
        }
    }

    public func unblock(userID: UserID) async throws {
        let updatedProfile = try await perform(action: .unblock, for: userID)
        try await perform { context in
            UserProfile.findOrCreate(with: userID, in: context).update(with: updatedProfile)
        }
    }

    private func perform(action: Server_FriendshipRequest.Action, for userID: UserID) async throws -> Server_HalloappUserProfile {
        try await withCheckedThrowingContinuation { continuation in
            DDLogInfo("UserProfileData/perform \(action) for \(userID)")

            service.modifyFriendship(userID: userID, action: action) { result in
                switch result {
                case .success(let profile):
                    continuation.resume(returning: profile)
                case .failure(let error):
                    DDLogError("UserProfileData/perform action failed \(String(describing: error))")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func perform(_ block: @escaping (NSManagedObjectContext) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            mainDataStore.performSeriallyOnBackgroundContext { context in
                block(context)

                if context.hasChanges {
                    do {
                        try context.save()
                        continuation.resume()
                    } catch {
                        DDLogError("UserProfileData/perform/save failed with error \(String(describing: error))")
                    }
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func syncFriendshipsIfNeeded() {
        let listTypes: [Server_FriendListRequest.Action] = [.getFriends, .getIncomingPending, .getIncomingPending, .getOutgoingPending]

        Task {
            for type in listTypes {
                var profiles = [Server_HalloappUserProfile]()
                var cursor = ""

                repeat {
                    let friendList = try await friendshipList(for: type, cursor: cursor)
                    profiles.append(contentsOf: friendList.profiles)
                    cursor = friendList.cursor
                } while !cursor.isEmpty

                do {
                    try await processFriendshipList(type: type, serverProfiles: profiles)
                } catch {
                    DDLogError("UserProfileData/syncFriendshipsIfNeeded/failed with error \(String(describing: error))")
                }
            }
        }
    }

    private func processFriendshipList(type: Server_FriendListRequest.Action, serverProfiles: [Server_HalloappUserProfile]) async throws {
        var avatars = [UserID: AvatarID]()

        try await perform { context in
            let userIDs = serverProfiles.map { String($0.uid) }
            let userProfiles = UserProfile.find(with: userIDs, in: context).reduce(into: [UserID: UserProfile]()) { $0[$1.id] = $1 }

            for serverProfile in serverProfiles {
                let userID = String(serverProfile.uid)
                let localProfile = userProfiles[userID] ?? UserProfile(context: context)

                localProfile.update(with: serverProfile)
                avatars[userID] = serverProfile.avatarID
            }

            func resetFriendStatus(profileStatus: UserProfile.FriendshipStatus) {
                let predicate = NSPredicate(format: "NOT id in %@ AND friendshipStatusValue = %d", userIDs, profileStatus.rawValue)
                UserProfile.find(predicate: predicate, in: context).forEach { $0.friendshipStatus = .none }
            }

            switch type {
            case .getFriends:
                resetFriendStatus(profileStatus: .friends)

            case .getIncomingPending:
                resetFriendStatus(profileStatus: .incomingPending)

            case .getOutgoingPending:
                resetFriendStatus(profileStatus: .outgoingPending)

            case .getSuggestions:
                break
            case .UNRECOGNIZED(_):
                break
            }
        }

        avatarStore.processContactSync(avatars)
    }

    private func friendshipList(for type: Server_FriendListRequest.Action, cursor: String) async throws -> (profiles: [Server_HalloappUserProfile], cursor: String) {
        try await withCheckedThrowingContinuation { continuation in
            service.friendList(action: type, cursor: cursor) { result in
                switch result {
                case .success(let response):
                    let userProfiles = response.profiles
                        .filter { $0.hasUserProfile }
                        .map { $0.userProfile }

                    continuation.resume(returning: (profiles: userProfiles, cursor: response.cursor))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
