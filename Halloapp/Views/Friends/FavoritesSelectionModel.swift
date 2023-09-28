//
//  FavoritesSelectionModel.swift
//  HalloApp
//
//  Created by Tanveer on 9/13/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CoreData
import CoreCommon
import Core
import CocoaLumberjackSwift

extension FavoritesSelectionModel {

    struct Section: Identifiable, DisplayableFriendSection {
        let title: String?
        let friends: [Friend]

        var id: String? {
            title
        }
    }

    struct Friend: Hashable, Identifiable, DisplayableFriend {
        let id: UserID
        let name: String
        let username: String
    }
}

class FavoritesSelectionModel: NSObject, ObservableObject, SelectionModel, NSFetchedResultsControllerDelegate {

    var title: String {
        Localizations.favoritesTitle
    }

    @Published private(set) var selected: [Friend] = []
    @Published private(set) var candidates: [Section] = []

    private let resultsController: NSFetchedResultsController<UserProfile> = {
        let request = UserProfile.fetchRequest()
        request.predicate = NSPredicate(format: "friendshipStatusValue == %d", UserProfile.FriendshipStatus.friends.rawValue)
        request.sortDescriptors = [.init(key: "name", ascending: true, selector: #selector(NSString.caseInsensitiveCompare))]

        return NSFetchedResultsController(fetchRequest: request,
                                          managedObjectContext: MainAppContext.shared.mainDataStore.viewContext,
                                          sectionNameKeyPath: nil, cacheName: nil)
    }()

    override init() {
        super.init()
        resultsController.delegate = self

        do {
            try resultsController.performFetch()
            transformResults()
        } catch {
            DDLogError("FavoritesSelectionModel/fetch failed with error \(String(describing: error))")
        }
    }

    private func transformResults() {
        let profiles = resultsController.fetchedObjects ?? []
        var selected = [Friend]()
        var candidates = [Section]()

        var currentInitial: String?
        var currentFriends = [Friend]()

        for profile in profiles {
            guard let initial = profile.name.first?.uppercased() else {
                continue
            }

            let friend = Friend(id: profile.id, name: profile.name, username: profile.username)

            if profile.isFavorite {
                selected.append(friend)
                continue
            } else if initial == currentInitial {
                currentFriends.append(friend)
                continue
            } else if let currentInitial {
                candidates.append(Section(title: currentInitial, friends: currentFriends))
            }

            currentInitial = initial
            currentFriends = [friend]
        }

        if !currentFriends.isEmpty, let currentInitial {
            candidates.append(Section(title: currentInitial, friends: currentFriends))
        }

        self.selected = selected
        self.candidates = candidates
    }

    func update(selection: Set<UserID>) {
        DDLogInfo("FavoritesSelectionModel/update [\(selection)]")
        let currentFavorites = Set(selected.map { $0.id })
        let removals = currentFavorites.subtracting(selection)
        let additions = selection.subtracting(currentFavorites)

        MainAppContext.shared.mainDataStore.saveSeriallyOnBackgroundContext { context in
            UserProfile.find(with: Array(removals), in: context).forEach {
                $0.isFavorite = false
            }

            UserProfile.find(with: Array(additions), in: context).forEach {
                $0.isFavorite = true
            }
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        transformResults()
    }
}
