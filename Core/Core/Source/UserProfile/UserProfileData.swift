//
//  UserProfileData.swift
//  Core
//
//  Created by Tanveer on 8/8/23.
//  Copyright © 2023 Hallo App, Inc. All rights reserved.
//

import Foundation
import CoreData
import Combine
import CoreCommon
import CocoaLumberjackSwift

public class UserProfileData: NSObject {

    public let mainDataStore: MainDataStore
    public let service: CoreService
    public let avatarStore: AvatarStore
    public let userData: UserData
    public let userDefaults: UserDefaults

    @UserDefault(key: "friendshipsSyncDateKey")
    private static var lastFriendshipSyncDate: TimeInterval = .zero

    // MARK: Publishers

    private var cancellables: Set<AnyCancellable> = []
    private let _completedInitialFriendSyncPublisher = PassthroughSubject<Void, Never>()

    public init(dataStore: MainDataStore, service: CoreService, avatarStore: AvatarStore, userData: UserData, userDefaults: UserDefaults) {
        self.mainDataStore = dataStore
        self.service = service
        self.avatarStore = avatarStore
        self.userData = userData
        self.userDefaults = userDefaults

        super.init()

        service.didConnect
            .sink { [weak self] in self?.syncFriendshipsIfNeeded() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserData.userDataDidSave)
            .sink { [weak self] _ in self?.syncUserProfile() }
            .store(in: &cancellables)

        // on re-install, the clearing of the store can remove the profile saved during registration
        // re-sync in this case
        mainDataStore.didClearStore
            .filter { [userData] in !userData.userId.isEmpty }
            .sink { [weak self] in self?.syncUserProfile() }
            .store(in: &cancellables)
    }

    public var completedInitialFriendSyncPublisher: AnyPublisher<Void, Never> {
        _completedInitialFriendSyncPublisher.eraseToAnyPublisher()
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
            FriendActivity.find(with: userID, in: context)?.status = .none
        }
    }

    public func removeFriend(userID: UserID) async throws {
        let updatedProfile = try await perform(action: .removeFriend, for: userID)
        try await perform { context in
            UserProfile.findOrCreate(with: userID, in: context).update(with: updatedProfile)
            UserProfile.removeContent(for: userID, in: context, options: .unfriended)
        }
    }

    public func cancelRequest(userID: UserID) async throws {
        let updatedProfile = try await perform(action: .withdrawFriendRequest, for: userID)
        try await perform { context in
            UserProfile.findOrCreate(with: userID, in: context).update(with: updatedProfile)
        }
    }

    public func ignoreRequest(userID: UserID) async throws {
        let updatedProfile = try await perform(action: .rejectFriend, for: userID)
        try await perform { context in
            UserProfile.findOrCreate(with: userID, in: context).update(with: updatedProfile)
            FriendActivity.find(with: userID, in: context)?.status = .none
        }
    }

    public func ignoreSuggestion(userID: UserID) async throws {
        let updatedProfile = try await perform(action: .rejectSuggestion, for: userID)
        try await perform { context in
            UserProfile.findOrCreate(with: userID, in: context).update(with: updatedProfile)
        }
    }

    public func block(userID: UserID) async throws {
        let updatedProfile = try await perform(action: .block, for: userID)
        try await perform { context in
            UserProfile.findOrCreate(with: userID, in: context).update(with: updatedProfile)
            UserProfile.removeContent(for: userID, in: context, options: .blocked)
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

    // MARK: Activities

    public func markAllFriendEventsAsRead() {
        mainDataStore.saveSeriallyOnBackgroundContext { context in
            FriendActivity.find(predicate: .init(format: "read == NO"), in: context)
                .forEach { $0.read = true }
        }
    }

    public func markFriendEventAsRead(userID: UserID) {
        mainDataStore.saveSeriallyOnBackgroundContext { context in
            FriendActivity.find(with: userID, in: context)?.read = true
        }
    }

    // MARK: Sync

    private func syncFriendshipsIfNeeded() {
        let lastSyncInterval = Self.lastFriendshipSyncDate
        let lastSyncDate = Date(timeIntervalSince1970: lastSyncInterval)
        let hasCompletedInitialSync = lastSyncInterval != .zero

        guard lastSyncDate < Date(timeIntervalSinceNow: -ServerProperties.relationshipSyncFrequency) else {
            DDLogInfo("UserProfileData/syncFriendshipsIfNeeded/skipping sync")
            return
        }

        Task {
            await syncFriendships()
            if !hasCompletedInitialSync {
                _completedInitialFriendSyncPublisher.send()
            }
        }
    }

    public func syncFriendships() async {
        DDLogInfo("UserProfileData/syncFriendships/start")
        let listTypes: [Server_FriendListRequest.Action] = [.getFriends, .getOutgoingPending, .getIncomingPending, .getBlocked]

        for type in listTypes {
            var profiles = [Server_HalloappUserProfile]()
            var cursor = ""

            repeat {
                do {
                    let friendList = try await friendshipList(for: type, cursor: cursor)
                    profiles.append(contentsOf: friendList.profiles)
                    cursor = friendList.cursor
                } catch {
                    DDLogError("UserProfileData/syncFriendships/failed to fetch list \(String(describing: error))")
                    return
                }
            } while !cursor.isEmpty

            do {
                try await processFriendshipList(type: type, serverProfiles: profiles)
            } catch {
                DDLogError("UserProfileData/syncFriendshipsIfNeeded/failed with error \(String(describing: error))")
            }
        }

        DDLogInfo("UserProfileData/syncFriendships/finished")
        Self.lastFriendshipSyncDate = Date().timeIntervalSince1970
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

            case .getBlocked:
                let predicate = NSPredicate(format: "NOT id in %@ AND isBlocked == YES", userIDs)
                UserProfile.find(predicate: predicate, in: context).forEach { $0.isBlocked = false }

            case .getSuggestions:
                break
            case .syncAll:
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
                    let userProfiles = response.profiles.map { $0.userProfile }
                    continuation.resume(returning: (profiles: userProfiles, cursor: response.cursor))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func syncUserProfile() {
        DDLogInfo("UserProfileData/syncUserProfile")
        let userID = userData.userId
        let name = userData.name
        let username = userData.username

        mainDataStore.saveSeriallyOnBackgroundContext { context in
            DDLogInfo("UserProfileData/saveAfterSync/\(name) \(username)")
            let userProfile = UserProfile.findOrCreate(with: userID, in: context)
            userProfile.name = name
            userProfile.username = username
        }
    }
}

// MARK: - Migration

extension UserProfileData {

    public func migrateRegisteredContacts(_ contactInfo: [UserID: String]) throws {
        try mainDataStore.saveSeriallyOnBackgroundContextAndWait { context in
            DDLogInfo("UserProfileData/migrateRegisteredContacts/begin")
            for (id, name) in contactInfo {
                migrateRegisteredContact(id, name, in: context)
            }
            DDLogInfo("UserProfileData/migrateRegisteredContacts/finished")
        }
    }

    private func migrateRegisteredContact(_ id: UserID, _ name: String, in context: NSManagedObjectContext) {
        let profile = UserProfile.findOrCreate(with: id, in: context)

        if profile.name.isEmpty {
            profile.name = name
        }
    }

    public func migrateFavorites(_ favorites: [UserID]) throws {
        try mainDataStore.saveSeriallyOnBackgroundContextAndWait { context in
            DDLogInfo("UserProfileData/migrateFavorites/begin")
            UserProfile.findOrCreate(with: favorites, in: context).forEach {
                $0.isFavorite = true
            }
            DDLogInfo("UserProfileData/migrateFavorites/finished")
        }
    }

    public func migrateAvatarIDs(_ avatarIDs: [UserID: AvatarID]) throws {
        try mainDataStore.saveSeriallyOnBackgroundContextAndWait { context in
            DDLogInfo("UserProfileData/migrate avatars/begin")
            UserProfile.findOrCreate(with: Array(avatarIDs.keys), in: context).forEach {
                $0.avatarID = avatarIDs[$0.id]
            }
            DDLogInfo("UserProfileData/migrate avatars/finished")
        }
    }
}

// MARK: - UserDefault

@propertyWrapper
fileprivate struct UserDefault<T> {

    let key: String
    let defaultValue: T
    private let userDefaults: UserDefaults

    init(wrappedValue: T, key: String) {
        self.defaultValue = wrappedValue
        self.key = key
        self.userDefaults = AppContext.shared.userDefaults
    }

    var wrappedValue: T {
        get {
            userDefaults.value(forKey: key) as? T ?? defaultValue
        }

        set {
            userDefaults.setValue(newValue, forKey: key)
        }
    }
}
