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

    let unreadPostsCountSubject = CurrentValueSubject<Int, Never>(0)
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
    private var pendingSnapshot: NSDiffableDataSourceSnapshot<GroupID, FeedPostID>?
    private let dataSource: UICollectionViewDiffableDataSource<GroupID, FeedPostID>
    private var pendingUnreadPostIDs = Set<FeedPostID>()
    private var didLoadInitialSearchResultsForSearchSession = false
    private var didAddSelfPostInLastUpdate = false
    private var unreadPostIDsByGroupID: [GroupID: Set<FeedPostID>] = [:]
    private var unreadPostCountSubjects = NSMapTable<NSString, CurrentValueSubject<Int, Never>>.strongToWeakObjects()

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
            NSPredicate(format: "NOT statusValue IN %@", [FeedPost.Status.retracting, FeedPost.Status.retracted].map(\.rawValue))
        ])
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \FeedPost.groupID, ascending: true),
            NSSortDescriptor(keyPath: \FeedPost.lastUpdated, ascending: false),
            NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false),
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

    func unreadPostCountSubject(for groupID: GroupID) -> CurrentValueSubject<Int, Never> {
        if let unreadPostCountSubject = unreadPostCountSubjects.object(forKey: groupID as NSString) {
            return unreadPostCountSubject
        }
        let unreadPostCountSubject = CurrentValueSubject<Int, Never>(unreadPostIDsByGroupID[groupID]?.count ?? 0)
        unreadPostCountSubjects.setObject(unreadPostCountSubject, forKey: groupID as String as NSString)
        return unreadPostCountSubject
    }

    func reloadSnapshot(animated: Bool, completion: (() -> Void)? = nil) {
        unreadPostIDsByGroupID.removeAll()
        pendingUnreadPostIDs.removeAll()
        unreadPostsCountSubject.send(0)

        var snapshot = NSDiffableDataSourceSnapshot<GroupID, FeedPostID>()

        defer {
            dataSource.apply(snapshot, animatingDifferences: animated, completion: completion)
        }

        guard let sortedGroupIDs = threadsFetchedResultsController.fetchedObjects?.compactMap(\.groupID) else {
            return
        }
        snapshot.appendSections(sortedGroupIDs)

        postsFetchedResultsController.sections?.forEach { section in
            guard sortedGroupIDs.contains(section.name), let feedPosts = section.objects as? [FeedPost] else {
                return
            }
            unreadPostIDsByGroupID[section.name] = Set(feedPosts.filter { $0.status == .incoming }.map(\.id))
            snapshot.appendItems(feedPosts.map(\.id), toSection: section.name)
        }

        // Send new unread counts to all active subjects
        for case let groupID as NSString in unreadPostCountSubjects.keyEnumerator() {
            unreadPostCountSubjects.object(forKey: groupID)?.send(unreadPostIDsByGroupID[groupID as String]?.count ?? 0)
        }
    }

    func performFetch() {
        do {
            try postsFetchedResultsController.performFetch()
            try threadsFetchedResultsController.performFetch()
        } catch {
            DDLogError("GroupGridDataSource/Unable to fetch: \(error)")
        }
        reloadSnapshot(animated: false)
    }
}

extension GroupGridDataSource: NSFetchedResultsControllerDelegate {

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        pendingSnapshot = dataSource.snapshot()
        didAddSelfPostInLastUpdate = false
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
                    didChange anObject: Any,
                    at indexPath: IndexPath?,
                    for type: NSFetchedResultsChangeType,
                    newIndexPath: IndexPath?) {
        guard var snapshot = pendingSnapshot else {
            return
        }

        switch controller {
        case postsFetchedResultsController:
            guard let feedPost = anObject as? FeedPost, let groupID = feedPost.groupID else {
                return
            }

            switch type {
            case .insert:
                guard !isSearching else {
                    break
                }
                if feedPost.userID == AppContext.shared.userData.userId {
                    guard snapshot.sectionIdentifiers.contains(groupID) else {
                        break
                    }
                    didAddSelfPostInLastUpdate = true
                    // Display any of our own posts right away
                    let itemIdentifiers = snapshot.itemIdentifiers(inSection: groupID)
                    // Theoretically we would always be the first post, but attempt to insert in order
                    let postIDToInsertBefore = itemIdentifiers.first { postID in
                        if let post = postsFetchedResultsController.fetchedObjects?.first(where: { $0.id == postID }),
                           (post.lastUpdated ?? .distantPast) < (feedPost.lastUpdated ?? .distantPast) {
                            return true
                        }
                        return false
                    }
                    if let postIDToInsertBefore = postIDToInsertBefore {
                        snapshot.insertItems([feedPost.id], beforeItem: postIDToInsertBefore)
                    } else if snapshot.sectionIdentifiers.contains(groupID) {
                        snapshot.appendItems([feedPost.id], toSection: groupID)
                    }
                    // Move section to top
                    if let firstSectionGroupID = snapshot.sectionIdentifiers.first, firstSectionGroupID != groupID {
                        snapshot.moveSection(groupID, beforeSection: firstSectionGroupID)
                    }
                } else if snapshot.sectionIdentifiers.contains(groupID) {
                    pendingUnreadPostIDs.insert(feedPost.id)
                }
            case .delete:
                updateUnreadCounts(for: feedPost.id, in: groupID, isRead: true)
                pendingUnreadPostIDs.remove(feedPost.id)
                snapshot.deleteItems([feedPost.id])
            case .move:
                // Do not reflect moves until reloaded
                break
            case .update:
                if snapshot.itemIdentifiers.contains(feedPost.id) {
                    if #available(iOS 15.0, *) {
                        snapshot.reconfigureItems([feedPost.id])
                    } else {
                        snapshot.reloadItems([feedPost.id])
                    }
                    updateUnreadCounts(for: feedPost.id, in: groupID, isRead: feedPost.status != .incoming)
                }
            @unknown default:
                break
            }
            // Snapshot uses copy semantics, so we must set it back to the property
            pendingSnapshot = snapshot
        case threadsFetchedResultsController:
            guard let thread = anObject as? CommonThread, let groupID = thread.groupID else {
                return
            }

            switch type {
            case .insert:
                guard !isSearching else {
                    break
                }
                let sectionIDToInsertBefore = snapshot.sectionIdentifiers.first { existingGroupID in
                    if let existingThread = threadsFetchedResultsController.fetchedObjects?.first(where: { $0.groupID == existingGroupID }),
                       (existingThread.lastTimestamp ?? .distantPast) < (thread.lastTimestamp ?? .distantPast) {
                        return true
                    }
                    return false
                }
                if let sectionIDToInsertBefore = sectionIDToInsertBefore {
                    snapshot.insertSections([groupID], beforeSection: sectionIDToInsertBefore)
                } else {
                    snapshot.appendSections([groupID])
                }
                if let posts = postsFetchedResultsController.sections?.first(where: { $0.name == groupID })?.objects as? [FeedPost] {
                    snapshot.appendItems(posts.map(\.id), toSection: groupID)
                }
            case .delete:
                if snapshot.sectionIdentifiers.contains(groupID) {
                    snapshot.deleteSections([groupID])
                }
            case .move:
                break
            case .update:
                break
            @unknown default:
                break
            }
        default:
            DDLogWarn("GroupGridDataSource/received change from unexpected FRC")
        }

        // Snapshot uses copy semantics, so we must set it back to the property
        pendingSnapshot = snapshot
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        pendingSnapshot.flatMap { dataSource.apply($0) }
        unreadPostsCountSubject.send(pendingUnreadPostIDs.count)

        if didAddSelfPostInLastUpdate {
            requestScrollToTopAnimatedSubject.send(true)
        }
    }

    // Unread post count helper functions

    private func updateUnreadCounts(for postID: FeedPostID, in groupID: GroupID, isRead: Bool) {
        var unreadPostIDs = unreadPostIDsByGroupID[groupID] ?? Set()
        if isRead {
            unreadPostIDs.remove(postID)
        } else {
            unreadPostIDs.insert(postID)
        }
        unreadPostIDsByGroupID[groupID] = unreadPostIDs
        unreadPostCountSubjects.object(forKey: groupID as NSString)?.send(unreadPostIDs.count)
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
        if searchController.isActive {
            isSearching = true

            // reset any pending post notifications, we will reload after search is completed
            pendingUnreadPostIDs.removeAll()
            unreadPostsCountSubject.send(0)

            if let searchText = searchController.searchBar.text, !searchText.isEmpty {
                dataSource.apply(snapshot(for: searchText), animatingDifferences: false)
                requestScrollToTopAnimatedSubject.send(false)
                didLoadInitialSearchResultsForSearchSession = true

                // Remove unread post counts when we start typing
                unreadPostIDsByGroupID.removeAll()
                for case let groupID as NSString in unreadPostCountSubjects.keyEnumerator() {
                    unreadPostCountSubjects.object(forKey: groupID)?.send(0)
                }
            } else if didLoadInitialSearchResultsForSearchSession { // don't modify results until user has actually started to search
                requestScrollToTopAnimatedSubject.send(false)
                reloadSnapshot(animated: false)
            }
        } else {
            didLoadInitialSearchResultsForSearchSession = false
            isSearching = false
            reloadSnapshot(animated: false)
            requestScrollToTopAnimatedSubject.send(false)
        }
    }
}
