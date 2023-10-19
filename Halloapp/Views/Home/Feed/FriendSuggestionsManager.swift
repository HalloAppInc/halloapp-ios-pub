//
//  FriendSuggestionsManager.swift
//  HalloApp
//
//  Created by Tanveer on 10/10/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreData
import CoreCommon
import Core
import CocoaLumberjackSwift

extension FriendSuggestionsManager {

    struct Suggestion: Hashable {
        let id: UserID
        let name: String
        let username: String
        let friendshipStatus: UserProfile.FriendshipStatus
    }
}

@MainActor
class FriendSuggestionsManager: NSObject {

    private var fetch: Task<Void, Never>?
    var suggestionsDidChange: ((Bool) -> Void)?

    private var addedSuggestions: Set<UserID> = []
    private(set) var suggestions: [Suggestion] = [] {
        didSet {
            suggestionsDidChange?(oldValue.count != suggestions.count)
        }
    }

    private lazy var resultsController: NSFetchedResultsController<UserProfile> = {
        let request = UserProfile.fetchRequest()
        request.sortDescriptors = []
        request.propertiesToFetch = ["id"]
        return NSFetchedResultsController<UserProfile>(fetchRequest: request,
                                                       managedObjectContext: MainAppContext.shared.mainDataStore.viewContext,
                                                       sectionNameKeyPath: nil, cacheName: nil)
    }()

    override init() {
        super.init()
        resultsController.delegate = self
    }

    func refresh() async {
        let task = fetch ?? Task(priority: .userInitiated) {
            let serverSuggestions = await performFetch()
            var seenSuggestions = Set<UserID>()
            var avatars = [UserID: AvatarID]()

            let transformed: [Suggestion] = serverSuggestions.compactMap {
                let userID = UserID($0.userProfile.uid)
                guard !seenSuggestions.contains(userID) else {
                    return nil
                }

                seenSuggestions.insert(userID)
                avatars[userID] = $0.userProfile.avatarID

                return Suggestion(id: userID,
                                  name: $0.userProfile.name,
                                  username: $0.userProfile.username,
                                  friendshipStatus: $0.userProfile.status.userProfileFriendshipStatus)
            }

            MainAppContext.shared.avatarStore.processContactSync(avatars)
            updatePredicate(with: transformed)

            suggestions = transformed
            fetch = nil
        }

        fetch = task
        await task.value
    }

    private func performFetch() async -> [Server_FriendProfile] {
        await withCheckedContinuation { continuation in
            let service = MainAppContext.shared.service
            service.execute(whenConnectionStateIs: .connected, onQueue: .global(qos: .userInitiated)) {
                service.friendList(action: .getSuggestions, cursor: "") { result in
                    switch result {
                    case .success((let serverProfiles, _)):
                        let prefixed = Array(serverProfiles.prefix(20))
                        continuation.resume(returning: prefixed)
                    case .failure(let error):
                        DDLogError("SuggestionsDataSource/fetch/failed with error \(String(describing: error))")
                        continuation.resume(returning: [])
                    }
                }
            }
        }
    }

    private func updatePredicate(with suggestions: [Suggestion]) {
        let userIDs = suggestions.map { $0.id }
        let predicate = NSPredicate(format: "id IN %@", userIDs)
        resultsController.fetchRequest.predicate = predicate
        
        do {
            try resultsController.performFetch()
        } catch {
            DDLogError("FriendSuggestionsManager/updatePredicate/fetch failed with error \(String(describing: error))")
        }
    }

    func clearAddedSuggestions() {
        guard !addedSuggestions.isEmpty else {
            return
        }

        suggestions = suggestions.filter { !addedSuggestions.contains($0.id) }
        addedSuggestions = []
    }

    // MARK: Actions

    func add(_ suggestion: Suggestion) {
        addedSuggestions.insert(suggestion.id)
        suggestions = suggestions.map {
            guard $0.id == suggestion.id else {
                return $0
            }
            return Suggestion(id: $0.id, name: $0.name, username: $0.username, friendshipStatus: .outgoingPending)
        }

        Task(priority: .userInitiated) {
            do {
                try await MainAppContext.shared.userProfileData.addFriend(userID: suggestion.id)
            } catch {
                DDLogError("FriendSuggestionsManager/add/failed with error \(String(describing: error))")
            }
        }
    }

    func cancelRequest(for suggestion: Suggestion) {
        addedSuggestions.remove(suggestion.id)
        suggestions = suggestions.map {
            guard $0.id == suggestion.id else {
                return $0
            }
            return Suggestion(id: $0.id, name: $0.name, username: $0.username, friendshipStatus: .none)
        }

        Task(priority: .userInitiated) {
            do {
                try await MainAppContext.shared.userProfileData.cancelRequest(userID: suggestion.id)
            } catch {
                DDLogError("FriendSuggestionsManager/cancel/failed with error \(String(describing: error))")
            }
        }
    }

    func hide(_ suggestion: Suggestion) {
        suggestions = suggestions.filter { $0.id != suggestion.id }

        Task(priority: .userInitiated) {
            do {
                try await MainAppContext.shared.userProfileData.ignoreSuggestion(userID: suggestion.id)
            } catch {
                DDLogError("FriendSuggestionsManager/hide/failed with error \(String(describing: error))")
            }
        }
    }
}

// MARK: - FriendSuggestionsManager + NSFetchedResultsControllerDelegate

extension FriendSuggestionsManager: NSFetchedResultsControllerDelegate {

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        let map = (resultsController.fetchedObjects ?? [])
            .reduce(into: [:]) {
                $0[$1.id] = $1.friendshipStatus
            }

        var hasChanges = false
        let updated = suggestions.map {
            guard let status = map[$0.id], status != $0.friendshipStatus else {
                return $0
            }

            hasChanges = true
            return Suggestion(id: $0.id, name: $0.name, username: $0.username, friendshipStatus: status)
        }

        if hasChanges {
            // keep server suggestions in sync with local state
            suggestions = updated
        }
    }
}
