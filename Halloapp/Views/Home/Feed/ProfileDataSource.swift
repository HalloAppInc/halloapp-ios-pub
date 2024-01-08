//
//  ProfileDataSource.swift
//  HalloApp
//
//  Created by Tanveer on 10/18/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import Foundation
import CoreData
import Core
import CoreCommon
import CocoaLumberjackSwift

protocol DisplayableProfile {
    var displayable: ProfileInfo { get }
}

@MainActor
class ProfileDataSource: NSObject {

    private let id: UserID
    @Published private(set) var profile: ProfileInfo?
    @Published private(set) var mutuals: (friends: [UserID], groups: [GroupID]) = ([], [])

    private let resultsController: NSFetchedResultsController<UserProfile> = {
        let request = UserProfile.fetchRequest()
        request.sortDescriptors = []
        request.fetchLimit = 1
        return NSFetchedResultsController<UserProfile>(fetchRequest: request,
                                                       managedObjectContext: MainAppContext.shared.mainDataStore.viewContext,
                                                       sectionNameKeyPath: nil,
                                                       cacheName: nil)
    }()

    private var isOwnProfile: Bool {
        id == MainAppContext.shared.userData.userId
    }

    init(id: UserID) {
        self.id = id
        super.init()

        setup(useInitialFetch: true)
    }

    init(profile: DisplayableProfile) {
        let profile = profile.displayable
        self.id = profile.id
        super.init()

        self.profile = profile
        setup(useInitialFetch: false)
    }

    private func setup(useInitialFetch: Bool) {
        setupResultsController()
        if useInitialFetch {
            update()
        }

        if !isOwnProfile {
            Task(priority: .userInitiated) {
                await updateFromServer()
            }
        }
    }

    private func setupResultsController() {
        resultsController.fetchRequest.predicate = NSPredicate(format: "id == %@", id)
        resultsController.delegate = self

        do {
            try resultsController.performFetch()
        } catch {
            DDLogError("ProfileDataSource/init/fetch failed with error \(String(describing: error))")
        }
    }

    private func update() {
        DDLogInfo("ProfileDataSource/update/[\(id)]")
        profile = resultsController.fetchedObjects?.first?.displayable
    }

    private func updateFromServer() async {
        do {
            let serverProfile = try await serverProfile
            try await MainAppContext.shared.mainDataStore.saveSeriallyOnBackgroundContext { [id] context in
                UserProfile.findOrCreate(with: id, in: context).update(with: serverProfile)
            }
            let mutualFriends = serverProfile.mutualFriendUids.map { UserID($0) }
            mutuals = (mutualFriends, serverProfile.mutualGids)
            DDLogInfo("ProfileDataSource/updateFromServer/success [\(id)]")
        } catch {
            DDLogError("ProfileDataSource/updateFromServer/failed with error \(String(describing: error))")
        }
    }

    private var serverProfile: Server_HalloappUserProfile {
        get async throws {
            try await withCheckedThrowingContinuation { continuation in
                let service = MainAppContext.shared.service
                service.execute(whenConnectionStateIs: .connected, onQueue: .global(qos: .userInitiated)) { [id] in
                    service.userProfile(userID: id) { result in
                        switch result {
                        case .success(let serverProfile):
                            continuation.resume(returning: serverProfile)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - ProfileDataSource + NSFetchedResultsControllerDelegate

extension ProfileDataSource: NSFetchedResultsControllerDelegate {

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        update()
    }
}

// MARK: - UserProfile + DisplayableProfile

extension UserProfile: DisplayableProfile {

    public var displayable: ProfileInfo {
        ProfileInfo(id: id, 
                    name: name,
                    username: username,
                    friendshipStatus: friendshipStatus,
                    profileLinks: links.sorted(),
                    isFavorite: isFavorite,
                    isBlocked: isBlocked)
    }
}

// MARK: - Server_HalloappUserProfile + DisplayableProfile

extension Server_HalloappUserProfile: DisplayableProfile {

    public var displayable: ProfileInfo {
        let links = links
            .map { ProfileLink(serverLink: $0) }
            .sorted()

        return ProfileInfo(id: UserID(uid),
                           name: name,
                           username: username,
                           friendshipStatus: status.userProfileFriendshipStatus,
                           profileLinks: links,
                           isFavorite: false,
                           isBlocked: blocked)
    }
}

// MARK: - FriendsDataSource.Friend + DisplayableProfile

extension FriendsDataSource.Friend: DisplayableProfile {

    public var displayable: ProfileInfo {
        ProfileInfo(id: id, 
                    name: name,
                    username: username,
                    friendshipStatus: friendshipStatus,
                    profileLinks: [],
                    isFavorite: false,
                    isBlocked: false)
    }
}

// MARK: - FriendSuggestionsManager.Suggestion + DisplayableProfile

extension FriendSuggestionsManager.Suggestion: DisplayableProfile {

    public var displayable: ProfileInfo {
        ProfileInfo(id: id,
                    name: name,
                    username: username,
                    friendshipStatus: friendshipStatus,
                    profileLinks: [],
                    isFavorite: false,
                    isBlocked: false)
    }
}
