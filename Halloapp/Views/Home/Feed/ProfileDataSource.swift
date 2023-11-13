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
    var id: UserID { get }
    var name: String { get }
    var username: String { get }
    var friendshipStatus: UserProfile.FriendshipStatus { get }
    var profileLinks: [ProfileLink] { get }
    var isFavorite: Bool { get }
    var isBlocked: Bool { get }
}

@MainActor
class ProfileDataSource: NSObject {

    private let id: UserID
    @Published private(set) var profile: DisplayableProfile?

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
        profile = resultsController.fetchedObjects?.first
    }

    private func updateFromServer() async {
        do {
            let serverProfile = try await serverProfile
            try await MainAppContext.shared.mainDataStore.saveSeriallyOnBackgroundContext { [id] context in
                UserProfile.findOrCreate(with: id, in: context).update(with: serverProfile)
            }
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

    var profileLinks: [ProfileLink] {
        links.sorted()
    }
}

// MARK: - Server_HalloappUserProfile + DisplayableProfile

extension Server_HalloappUserProfile: DisplayableProfile {

    var id: UserID {
        UserID(uid)
    }

    var friendshipStatus: UserProfile.FriendshipStatus {
        status.userProfileFriendshipStatus
    }

    var profileLinks: [ProfileLink] {
        links
            .map { ProfileLink(serverLink: $0) }
            .sorted()
    }

    var isFavorite: Bool {
        false
    }

    var isBlocked: Bool {
        blocked
    }
}

// MARK: - FriendsDataSource.Friend + DisplayableProfile

extension FriendsDataSource.Friend: DisplayableProfile {
    
    var isFavorite: Bool {
        false
    }
    
    var isBlocked: Bool {
        false
    }

    var profileLinks: [ProfileLink] {
        []
    }
}

// MARK: - FriendSuggestionsManager.Suggestion + DisplayableProfile

extension FriendSuggestionsManager.Suggestion: DisplayableProfile {
    
    var isFavorite: Bool {
        false
    }
    
    var isBlocked: Bool {
        false
    }

    var profileLinks: [ProfileLink] {
        []
    }
}
