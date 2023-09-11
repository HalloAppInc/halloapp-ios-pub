//
//  FriendDataSource.swift
//  HalloApp
//
//  Created by Tanveer on 8/28/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import CoreData
import CoreCommon
import Core
import CocoaLumberjackSwift

extension FriendsDataSource {

    enum Section: Hashable {
        case requests
        case suggestions
        case initial(String)
        case invites
        case incomingRequests(Int)
        case outgoingRequests
        case blank(UUID)
    }

    enum Item: Hashable {
        case incoming(Friend)
        case outgoing(Friend)
        case suggested(Friend)
        case existing(Friend)
        case allRequests(Int)
        case sentRequests(Int)
        case noFriends
        case invite(InviteContact)
    }

    struct Friend: Hashable {

        let id: UserID
        let name: String
        let username: String
        let friendshipStatus: UserProfile.FriendshipStatus
    }
}

@MainActor
class FriendsDataSource: NSObject {

    typealias Snapshot = NSDiffableDataSourceSnapshot<Section, Item>
    typealias CollectionViewDataSource = UICollectionViewDiffableDataSource<Section, Item>
    typealias CellProvider = CollectionViewDataSource.CellProvider
    typealias SupplementaryViewProvider = CollectionViewDataSource.SupplementaryViewProvider

    fileprivate let collectionViewDataSource: UICollectionViewDiffableDataSource<Section, Item>

    init(collectionView: UICollectionView,
         cellProvider: @escaping CellProvider,
         supplementaryViewProvider: @escaping SupplementaryViewProvider) {

        collectionViewDataSource = .init(collectionView: collectionView, cellProvider: cellProvider)
        collectionViewDataSource.supplementaryViewProvider = supplementaryViewProvider

        collectionView.dataSource = collectionViewDataSource
        super.init()
    }

    func section(for indexPath: IndexPath) -> Section? {
        guard #unavailable(iOS 15) else {
            return collectionViewDataSource.sectionIdentifier(for: indexPath.section)
        }

        let sections = collectionViewDataSource.snapshot().sectionIdentifiers
        if indexPath.section < sections.count {
            return sections[indexPath.section]
        }

        return nil
    }

    func numberOfItems(in section: Int) -> Int {
        guard let section = self.section(for: IndexPath(item: 0, section: section)) else {
            return .zero
        }

        return collectionViewDataSource.snapshot().numberOfItems(inSection: section)
    }

    func item(at indexPath: IndexPath) -> Item? {
        collectionViewDataSource.itemIdentifier(for: indexPath)
    }

    fileprivate func makeAndApplySnapshot(animated: Bool = true) {

    }

    fileprivate func apply(_ snapshot: Snapshot, animated: Bool = true) {
        let itemsToReconfigure = boundaryItemsForReconfigure(collectionViewDataSource.snapshot(), snapshot)
        collectionViewDataSource.apply(snapshot, animatingDifferences: animated)

        if !itemsToReconfigure.isEmpty {
            /*
             since the boundary cells in the collection view have slightly different styling, we need to account for
             cases where cells transition between being boundary cells and non-boundary cells without being reconfigured.
             we compare the two boundary items of each section shared between the current and new snapshot, and reconfigure
             the items that are different.
             */
            var snapshot = collectionViewDataSource.snapshot()
            if #available(iOS 15, *) {
                snapshot.reconfigureItems(itemsToReconfigure)
            } else {
                snapshot.reloadItems(itemsToReconfigure)
            }

            collectionViewDataSource.apply(snapshot, animatingDifferences: animated)
        }
    }

    private func boundaryItemsForReconfigure(_ existingSnapshot: Snapshot, _ upcomingSnapshot: Snapshot) -> [Item] {
        let forReconfigure = upcomingSnapshot.sectionIdentifiers.lazy
            .filter { existingSnapshot.indexOfSection($0) != nil }
            .compactMap { section -> [Item]? in
                let existingItems = existingSnapshot.itemIdentifiers(inSection: section)
                let upcomingItems = upcomingSnapshot.itemIdentifiers(inSection: section)

                guard let existingFirst = existingItems.first,
                      let existingFinal = existingItems.last,
                      let upcomingFirst = upcomingItems.first,
                      let upcomingFinal = upcomingItems.last else {
                    return nil
                }

                var forReconfigure = [Item]()
                if existingFirst != upcomingFirst {
                    forReconfigure += [existingFirst, upcomingFirst]
                }
                if existingFinal != upcomingFinal {
                    forReconfigure += [existingFinal, upcomingFinal]
                }

                return forReconfigure.filter { upcomingSnapshot.indexOfItem($0) != nil }
            }
            .reduce(into: Set<Item>()) { reconfigureSet, reconfigureItems in
                reconfigureSet.formUnion(reconfigureItems)
            }

        return forReconfigure.map { $0 }
    }

    func search(using searchText: String) {

    }

    func update(_ userID: UserID, to status: UserProfile.FriendshipStatus) {

    }

    fileprivate class func alphabeticalCategorization(of friends: [Friend]) -> [(String, [Friend])] {
        let sorted = friends.sorted(by: {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })

        var currentInitial: String?
        var currentBucket = [Friend]()
        var buckets = [(String, [Friend])]()

        for friend in sorted {
            guard let initial = friend.name.first?.uppercased() else {
                continue
            }

            if initial == currentInitial {
                currentBucket.append(friend)
                continue
            }

            if let currentInitial {
                buckets.append((currentInitial, currentBucket))
            }

            currentInitial = initial
            currentBucket = [friend]
        }

        if let currentInitial {
            buckets.append((currentInitial, currentBucket))
        }

        return buckets
    }
}

// MARK: - FriendRequestsDataSource

class FriendRequestsDataSource: FriendsDataSource {

    private var cancellables: Set<AnyCancellable> = []

    private var friendRequests: [Friend] = []
    private var friendSuggestions: [Friend] = []

    override init(collectionView: UICollectionView,
                  cellProvider: @escaping CellProvider,
                  supplementaryViewProvider: @escaping SupplementaryViewProvider) {
        super.init(collectionView: collectionView, cellProvider: cellProvider, supplementaryViewProvider: supplementaryViewProvider)

        FriendsPublisher(.incoming)
            .sink { [weak self] friends in
                guard let self else {
                    return
                }

                self.friendRequests = friends
                self.makeAndApplySnapshot()
            }
            .store(in: &cancellables)

        Task {
            friendSuggestions = await fetchFriendSuggestions()
            makeAndApplySnapshot()
        }
    }

    override fileprivate func makeAndApplySnapshot(animated: Bool = true) {
        var snapshot = Snapshot()

        let items = friendRequests.compactMap { friend in
            switch friend.friendshipStatus {
            case .incomingPending:
                return Item.incoming(friend)
            case .outgoingPending:
                return Item.outgoing(friend)
            default:
                return nil
            }
        }

        if let first = items.first {
            let final = items.count > 1 ? [first, .allRequests(items.count - 1)] : [first]

            snapshot.appendSections([.requests])
            snapshot.appendItems(final, toSection: .requests)
        }

        if !friendSuggestions.isEmpty {
            snapshot.appendSections([.suggestions])
            snapshot.appendItems(friendSuggestions.map { .suggested($0) }, toSection: .suggestions)
        }

        apply(snapshot, animated: animated)
    }

    private func fetchFriendSuggestions() async -> [Friend] {
        let suggestionProfiles = await withCheckedContinuation { continuation in
            MainAppContext.shared.coreService.friendList(action: .getSuggestions, cursor: "") { result in
                switch result {
                case .success((let profiles, _)):
                    continuation.resume(returning: profiles)
                case .failure(let error):
                    DDLogError("FreindRequestsDataSource/fetch-suggestions/failed with error \(String(describing: error))")
                    continuation.resume(returning: [])
                }
            }
        }

        let suggestions = suggestionProfiles
            .filter { $0.hasUserProfile }
            .map {
                let profile = $0.userProfile
                return Friend(id: UserID(profile.uid),
                              name: profile.name,
                              username: profile.username,
                              friendshipStatus: profile.status.userProfileFriendshipStatus)
            }

        DDLogInfo("FriendsDataSource/fetchFriendSuggestions/fetched [\(suggestions.count)] suggestions")
        return suggestions
    }

    override func update(_ userID: UserID, to status: UserProfile.FriendshipStatus) {
        let updateStatus = { (friend: Friend) in
            guard friend.id == userID else {
                return friend
            }

            return Friend(id: friend.id, name: friend.name, username: friend.username, friendshipStatus: status)
        }

        friendRequests = friendRequests.map(updateStatus)
        friendSuggestions = friendSuggestions.map(updateStatus)

        makeAndApplySnapshot(animated: false)
    }
}

// MARK: - CurrentFriendsDataSource

class CurrentFriendsDataSource: FriendsDataSource, NSFetchedResultsControllerDelegate {

    private var cancellables: Set<AnyCancellable> = []

    private lazy var inviteManager: InviteContactsManager = {
        let manager = InviteContactsManager(hideInvitedAndHidden: true, sort: .numPotentialContacts)
        manager.contactsChanged = { [weak self] in
            self?.makeAndApplySnapshot()
        }
        return manager
    }()

    private var currentFriends: [Friend] = []
    private var numberOfOutgoingRequests = 0

    override init(collectionView: UICollectionView,
                  cellProvider: @escaping CellProvider,
                  supplementaryViewProvider: @escaping SupplementaryViewProvider) {
        super.init(collectionView: collectionView, cellProvider: cellProvider, supplementaryViewProvider: supplementaryViewProvider)

        var initialized = false
        let onUpdate = { [weak self] in
            guard let self, initialized else {
                return
            }
            self.makeAndApplySnapshot()
        }

        FriendsPublisher(.outgoing)
            .map { $0.count }
            .sink { [weak self] outgoingCount in
                guard let self else {
                    return
                }
                self.numberOfOutgoingRequests = outgoingCount
                onUpdate()
            }
            .store(in: &cancellables)

        FriendsPublisher(.friends)
            .sink { [weak self] friends in
                guard let self else {
                    return
                }
                self.currentFriends = friends

                initialized = true
                onUpdate()
            }
            .store(in: &cancellables)
    }

    override fileprivate func makeAndApplySnapshot(animated: Bool = true) {
        var snapshot = Snapshot()

        for (initial, friends) in Self.alphabeticalCategorization(of: currentFriends) {
            let section = Section.initial(initial)
            let items = friends.map { Item.existing($0) }
            snapshot.appendSections([section])
            snapshot.appendItems(items, toSection: section)
        }

        if snapshot.sectionIdentifiers.isEmpty {
            let section = Section.blank(UUID())
            snapshot.appendSections([section])
            snapshot.appendItems([.noFriends], toSection: section)
        }

        if numberOfOutgoingRequests > 0 {
            let section = Section.blank(UUID())
            snapshot.appendSections([section])
            snapshot.appendItems([.sentRequests(numberOfOutgoingRequests)], toSection: section)
        }

        if let contacts = inviteManager.fetchedResultsController.fetchedObjects, !contacts.isEmpty {
            let items = contacts
                .filter { $0.userId == nil }
                .compactMap { InviteContact(from: $0) }
                .map { Item.invite($0) }

            snapshot.appendSections([.invites])
            snapshot.appendItems(items, toSection: .invites)
        }

        apply(snapshot, animated: animated)
    }

    override func update(_ userID: UserID, to status: UserProfile.FriendshipStatus) {
        currentFriends = currentFriends.map { friend in
            guard friend.id == userID else {
                return friend
            }

            return Friend(id: friend.id, name: friend.name, username: friend.username, friendshipStatus: status)
        }

        makeAndApplySnapshot(animated: true)
    }
}

// MARK: - FriendSearchDataSource

class FriendSearchDataSource: FriendsDataSource {

    private var searchTask: Task<Void, Never>?
    private var searchResults: [Friend] = []

    override fileprivate func makeAndApplySnapshot(animated: Bool = true) {
        var snapshot = Snapshot()
        var currentFriends = [Friend]()
        var others = [Item]()

        for friend in searchResults {
            switch friend.friendshipStatus {
            case .friends:
                currentFriends.append(friend)
            case .incomingPending:
                others.append(.incoming(friend))
            case .outgoingPending:
                others.append(.outgoing(friend))
            case .none:
                others.append(.suggested(friend))
            }
        }

        for (initial, friends) in Self.alphabeticalCategorization(of: currentFriends) {
            let section = Section.initial(initial)
            let items = friends.map { Item.existing($0) }
            snapshot.appendSections([section])
            snapshot.appendItems(items, toSection: section)
        }

        if !others.isEmpty {
            let section = Section.blank(UUID())
            snapshot.appendSections([section])
            snapshot.appendItems(others, toSection: section)
        }

        apply(snapshot, animated: animated)
    }

    override func search(using searchText: String) {
        searchTask?.cancel()
        guard !searchText.isEmpty else {
            searchResults = []
            return makeAndApplySnapshot()
        }

        searchTask = Task {
            let results = await fetch(using: searchText)

            if Task.isCancelled {
                return
            }

            searchResults = results
            makeAndApplySnapshot()
        }
    }

    private func fetch(using searchText: String) async -> [Friend] {
        let serverProfiles: [Server_HalloappUserProfile] = await withCheckedContinuation { continuation in
            MainAppContext.shared.coreService.searchUsernames(string: searchText) { result in
                switch result {
                case .success(let profiles):
                    continuation.resume(returning: profiles)
                case .failure(let error):
                    DDLogError("FriendSearchDataSource/fetch/failed with error \(String(describing: error))")
                    continuation.resume(returning: [])
                }
            }
        }

        return serverProfiles.map {
            Friend(id: UserID($0.uid), name: $0.name, username: $0.username, friendshipStatus: $0.status.userProfileFriendshipStatus )
        }
    }

    override func update(_ userID: UserID, to status: UserProfile.FriendshipStatus) {
        searchResults = searchResults.map { friend in
            guard friend.id == userID else {
                return friend
            }

            return Friend(id: friend.id, name: friend.name, username: friend.username, friendshipStatus: status)
        }

        makeAndApplySnapshot(animated: false)
    }
}

// MARK: - FriendAllRequestsDataSource

class FriendAllRequestsDataSource: FriendsDataSource {

    private var cancellables: Set<AnyCancellable> = []

    private var pendingFriends: [Friend] = []

    override init(collectionView: UICollectionView,
                  cellProvider: @escaping CellProvider,
                  supplementaryViewProvider: @escaping SupplementaryViewProvider) {

        super.init(collectionView: collectionView, cellProvider: cellProvider, supplementaryViewProvider: supplementaryViewProvider)

        FriendsPublisher(.pending)
            .sink { [weak self] friends in
                guard let self else {
                    return
                }

                self.pendingFriends = friends
                self.makeAndApplySnapshot()
            }
            .store(in: &cancellables)
    }

    override func makeAndApplySnapshot(animated: Bool = true) {
        var incoming = [Friend]()
        var outgoing = [Friend]()
        var snapshot = Snapshot()

        for friend in pendingFriends {
            switch friend.friendshipStatus {
            case .incomingPending:
                incoming.append(friend)
            case .outgoingPending:
                outgoing.append(friend)
            default:
                continue
            }
        }

        if !incoming.isEmpty {
            let section = Section.incomingRequests(incoming.count)
            snapshot.appendSections([section])
            snapshot.appendItems(incoming.map { .incoming($0) }, toSection: section)
        }

        if !outgoing.isEmpty {
            let section = Section.outgoingRequests
            snapshot.appendSections([section])
            snapshot.appendItems(outgoing.map { .outgoing($0) }, toSection: section)
        }

        apply(snapshot, animated: animated)
    }

    override func update(_ userID: UserID, to status: UserProfile.FriendshipStatus) {
        pendingFriends = pendingFriends.map { friend in
            guard friend.id == userID else {
                return friend
            }

            return Friend(id: friend.id, name: friend.name, username: friend.username, friendshipStatus: status)
        }

        makeAndApplySnapshot(animated: true)
    }
}
