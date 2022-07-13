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

    var supplementaryViewProvider: UICollectionViewDiffableDataSource<GroupID, FeedPostID>.SupplementaryViewProvider? {
        get {
            return dataSource.supplementaryViewProvider
        }
        set {
            dataSource.supplementaryViewProvider = newValue
        }
    }

    // Must call reloadData after setting to true
    private var isSearching = false
    private let dataSource: UICollectionViewDiffableDataSource<GroupID, FeedPostID>
    private var didLoadInitialSearchResultsForSearchSession = false
    private var didAddSelfPostInLastUpdate = false
    private var updatedPostIDs: [FeedPostID] = []

    init(collectionView: UICollectionView,
         cellProvider: @escaping UICollectionViewDiffableDataSource<GroupID, FeedPostID>.CellProvider) {
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView, cellProvider: cellProvider)
        super.init()
        postsFetchedResultsController.delegate = self
        threadsFetchedResultsController.delegate = self
    }

    private let postsFetchedResultsController: NSFetchedResultsController<FeedPost> = {
        let fetchRequest = FeedPost.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "groupID != nil"),
            NSPredicate(format: "timestamp >= %@", FeedData.postCutoffDate as NSDate),
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

    private let threadsFetchedResultsController: NSFetchedResultsController<CommonThread> = {
        let fetchRequest = CommonThread.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "groupID != nil")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "lastTimestamp", ascending: false),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        return NSFetchedResultsController(fetchRequest: fetchRequest,
                                          managedObjectContext: MainAppContext.shared.mainDataStore.viewContext,
                                          sectionNameKeyPath: nil,
                                          cacheName: nil)
    }()

    func groupID(at section: Int) -> GroupID? {
        return dataSource.snapshot().sectionIdentifiers[section]
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
        isEmpty = !isSearching && snapshot.sectionIdentifiers.isEmpty
    }

    func performFetch() {
        do {
            try postsFetchedResultsController.performFetch()
            try threadsFetchedResultsController.performFetch()
        } catch {
            DDLogError("GroupGridDataSource/Unable to fetch: \(error)")
        }
        reload(animated: false)
    }

    private func currentSnapshot() -> NSDiffableDataSourceSnapshot<GroupID, FeedPostID> {
        var snapshot = NSDiffableDataSourceSnapshot<GroupID, FeedPostID>()

        if let sortedGroupIDs = threadsFetchedResultsController.fetchedObjects?.compactMap(\.groupID) {
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
}

extension GroupGridDataSource: NSFetchedResultsControllerDelegate {

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        updatedPostIDs.removeAll()
        didAddSelfPostInLastUpdate = false
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
                didAddSelfPostInLastUpdate = true
            }
        default:
            break
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        var snapshot: NSDiffableDataSourceSnapshot<GroupID, FeedPostID>
        if isSearching {
            snapshot = dataSource.snapshot()
        } else {
            snapshot = currentSnapshot()
        }

        dataSource.apply(snapshot)
        isEmpty = !isSearching && snapshot.sectionIdentifiers.isEmpty

        if didAddSelfPostInLastUpdate {
            requestScrollToTopAnimatedSubject.send(true)
        }
    }
}

extension GroupGridDataSource: UISearchResultsUpdating {

    private func snapshot(for search: String) -> NSDiffableDataSourceSnapshot<GroupID, FeedPostID> {
        var snapshot = NSDiffableDataSourceSnapshot<GroupID, FeedPostID>()

        var matchingTitleGroupIDs: [GroupID] = []
        var matchingMemberGroupIDs: [GroupID] = []
        var matchingMemberGroupIDToMemberUserIDs: [GroupID: [UserID]] = [:]

        threadsFetchedResultsController.fetchedObjects?.forEach { thread in
            guard let groupID = thread.groupID else {
                return
            }

            if thread.title?.localizedCaseInsensitiveContains(search) ?? false {
                matchingTitleGroupIDs.append(groupID)
            } else {
                let memberUserIDs = MainAppContext.shared.chatData.chatGroupMemberUserIDs(groupID: groupID,
                                                                                          in: MainAppContext.shared.chatData.viewContext)
                let matchingMemberUserIDs = MainAppContext.shared.contactStore.fullNames(forUserIds: Set(memberUserIDs))
                    .filter { $0.value.localizedCaseInsensitiveContains(search) }
                    .map { $0.key }

                if !matchingMemberUserIDs.isEmpty {
                    matchingMemberGroupIDs.append(groupID)
                    matchingMemberGroupIDToMemberUserIDs[groupID] = matchingMemberUserIDs
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

    func updateSearchResults(for searchController: UISearchController) {
        if searchController.isActive, let searchText = searchController.searchBar.text, !searchText.isEmpty {
            isSearching = true
            didLoadInitialSearchResultsForSearchSession = true
            isEmpty = false
            dataSource.apply(snapshot(for: searchText), animatingDifferences: false)
            requestScrollToTopAnimatedSubject.send(false)
        } else {
            isSearching = false
            reload(animated: false)
            if didLoadInitialSearchResultsForSearchSession {
                requestScrollToTopAnimatedSubject.send(false)
                didLoadInitialSearchResultsForSearchSession = false
            }
        }
    }
}
