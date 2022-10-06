//
//  GroupGridDataSource.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 5/11/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import CoreData
import UIKit

class GroupGridDataSource: NSObject {

    @Published var isEmpty = true
    let requestScrollToTopAnimatedSubject = PassthroughSubject<Bool, Never>()
    let requestScrollToIndexPathSubject = PassthroughSubject<IndexPath, Never>() // always animated

    var supplementaryViewProvider: UICollectionViewDiffableDataSource<GroupID, FeedPostID>.SupplementaryViewProvider? {
        get {
            return dataSource.supplementaryViewProvider
        }
        set {
            dataSource.supplementaryViewProvider = newValue
        }
    }

    private var searchText: String?
    private let dataSource: UICollectionViewDiffableDataSource<GroupID, FeedPostID>
    private var selfPostIDAddedInLastUpdate: FeedPostID?

    init(collectionView: UICollectionView,
         cellProvider: @escaping UICollectionViewDiffableDataSource<GroupID, FeedPostID>.CellProvider) {
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView, cellProvider: cellProvider)
        super.init()
        postsFetchedResultsController.delegate = self
        groupsFetchedResultsController.delegate = self
    }

    private let postsFetchedResultsController: NSFetchedResultsController<FeedPost> = {
        let fetchRequest = FeedPost.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "groupID != nil"),
            NSPredicate(format: "expiration >= now() || expiration == nil"),
            NSPredicate(format: "fromExternalShare == NO"),
            NSPredicate(format: "NOT statusValue IN %@", [FeedPost.Status.retracting, FeedPost.Status.retracted].map(\.rawValue)),
        ])
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \FeedPost.groupID, ascending: true),
            NSSortDescriptor(keyPath: \FeedPost.lastUpdated, ascending: false),
            NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false),
        ]
        fetchRequest.relationshipKeyPathsForPrefetching = [
            "comments"
        ]
        return NSFetchedResultsController(fetchRequest: fetchRequest,
                                          managedObjectContext: MainAppContext.shared.mainDataStore.viewContext,
                                          sectionNameKeyPath: #keyPath(FeedPost.groupID),
                                          cacheName: nil)
    }()

    private let groupsFetchedResultsController: NSFetchedResultsController<Group> = {
        let fetchRequest = Group.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "typeValue == %d", GroupType.groupFeed.rawValue)
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "lastUpdate", ascending: false),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        return NSFetchedResultsController(fetchRequest: fetchRequest,
                                          managedObjectContext: MainAppContext.shared.mainDataStore.viewContext,
                                          sectionNameKeyPath: nil,
                                          cacheName: nil)
    }()

    func groupID(at section: Int) -> GroupID? {
        return dataSource.snapshot().sectionIdentifiers[section]
    }

    func group(at section: Int) -> Group? {
        guard let groupID = groupID(at: section) else {
            return nil
        }
        return groupsFetchedResultsController.fetchedObjects?.first { $0.id == groupID }
    }

    func feedPostID(at indexPath: IndexPath) -> FeedPostID? {
        return dataSource.itemIdentifier(for: indexPath)
    }

    func feedPost(at indexPath: IndexPath) -> FeedPost? {
        guard let feedPostID = feedPostID(at: indexPath) else {
            return nil
        }

        return postsFetchedResultsController.fetchedObjects?.first { $0.id == feedPostID }
    }

    func reload(animated: Bool, completion: (() -> Void)? = nil) {
        let snapshot = currentSnapshot()
        dataSource.apply(snapshot, animatingDifferences: animated, completion: completion)
        isEmpty = (searchText?.isEmpty ?? true) && snapshot.sectionIdentifiers.isEmpty
    }

    func performFetch() {
        do {
            try postsFetchedResultsController.performFetch()
            try groupsFetchedResultsController.performFetch()
        } catch {
            DDLogError("GroupGridDataSource/Unable to fetch: \(error)")
        }
        reload(animated: false)
    }

    private func currentSnapshot() -> NSDiffableDataSourceSnapshot<GroupID, FeedPostID> {
        if let searchText = searchText, !searchText.isEmpty {
            return snapshot(for: searchText)
        } else {
            return snapshot()
        }
    }

    private func snapshot() -> NSDiffableDataSourceSnapshot<GroupID, FeedPostID> {
        var snapshot = NSDiffableDataSourceSnapshot<GroupID, FeedPostID>()

        if let sortedGroupIDs = groupsFetchedResultsController.fetchedObjects?.map(\.id) {
            snapshot.appendSections(sortedGroupIDs)

            postsFetchedResultsController.sections?.forEach { section in
                guard sortedGroupIDs.contains(section.name), let feedPosts = section.objects as? [FeedPost] else {
                    return
                }
                // Bucket sort to maintain existing order
                var unreadPostIDs: [FeedPostID] = []
                var readPostIDs: [FeedPostID] = []
                for feedPost in feedPosts {
                    if feedPost.status == .incoming {
                        unreadPostIDs.append(feedPost.id)
                    } else {
                        readPostIDs.append(feedPost.id)
                    }
                }
                snapshot.appendItems(unreadPostIDs, toSection: section.name)
                snapshot.appendItems(readPostIDs, toSection: section.name)
            }
        }

        return snapshot
    }

    private func snapshot(for searchText: String) -> NSDiffableDataSourceSnapshot<GroupID, FeedPostID> {
        var snapshot = NSDiffableDataSourceSnapshot<GroupID, FeedPostID>()

        var matchingTitleGroupIDs: [GroupID] = []
        var matchingMemberGroupIDs: [GroupID] = []
        var matchingMemberGroupIDToMemberUserIDs: [GroupID: [UserID]] = [:]

        groupsFetchedResultsController.fetchedObjects?.forEach { group in
            if group.name.localizedCaseInsensitiveContains(searchText) {
                matchingTitleGroupIDs.append(group.id)
            } else {
                let memberUserIDs = MainAppContext.shared.chatData.chatGroupMemberUserIDs(groupID: group.id,
                                                                                          in: MainAppContext.shared.chatData.viewContext)
                let matchingMemberUserIDs = MainAppContext.shared.contactStore.fullNames(forUserIds: Set(memberUserIDs))
                    .filter { $0.value.localizedCaseInsensitiveContains(searchText) }
                    .map { $0.key }

                if !matchingMemberUserIDs.isEmpty {
                    matchingMemberGroupIDs.append(group.id)
                    matchingMemberGroupIDToMemberUserIDs[group.id] = matchingMemberUserIDs
                }
            }
        }

        snapshot.appendSections(matchingTitleGroupIDs)
        snapshot.appendSections(matchingMemberGroupIDs)

        postsFetchedResultsController.sections?.forEach { section in
            guard let feedPosts = section.objects as? [FeedPost] else {
                return
            }

            let groupID = section.name
            if matchingTitleGroupIDs.contains(groupID) {
                snapshot.appendItems(feedPosts.map(\.id), toSection: groupID)
            } else if matchingMemberGroupIDs.contains(groupID), let memberUserIDs = matchingMemberGroupIDToMemberUserIDs[groupID] {
                snapshot.appendItems(feedPosts.filter { memberUserIDs.contains($0.userID) }.map(\.id), toSection: groupID)
            }
        }

        return snapshot
    }
}

extension GroupGridDataSource: NSFetchedResultsControllerDelegate {

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        selfPostIDAddedInLastUpdate = nil
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
                    didChange anObject: Any,
                    at indexPath: IndexPath?,
                    for type: NSFetchedResultsChangeType,
                    newIndexPath: IndexPath?) {
        guard controller == postsFetchedResultsController, let feedPost = anObject as? FeedPost else {
            return
        }
        switch type {
        case .insert:
            if feedPost.userID == MainAppContext.shared.userData.userId {
                selfPostIDAddedInLastUpdate = feedPost.id
            }
        default:
            break
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        reload(animated: true)

        if let selfPostIDAddedInLastUpdate = selfPostIDAddedInLastUpdate, let indexPath = dataSource.indexPath(for: selfPostIDAddedInLastUpdate) {
            requestScrollToIndexPathSubject.send(indexPath)
        }
    }
}

extension GroupGridDataSource: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        let currentSearchText: String? = {
            if !searchController.isActive {
                return nil
            }

            let trimmedSearchText = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines)

            // normalize "" -> nil
            if trimmedSearchText?.isEmpty ?? true {
                return nil
            }

            return trimmedSearchText
        }()

        if searchText != currentSearchText {
            searchText = currentSearchText
            requestScrollToTopAnimatedSubject.send(false)
            reload(animated: false)
        }
    }
}
