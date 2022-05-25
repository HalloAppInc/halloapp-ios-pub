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
import CoreData
import UIKit

class GroupGridDataSource: NSObject {

    let unreadPostsCount = CurrentValueSubject<Int, Never>(0)

    var supplementaryViewProvider: UICollectionViewDiffableDataSource<GroupID, FeedPostID>.SupplementaryViewProvider? {
        get {
            return dataSource.supplementaryViewProvider
        }
        set {
            dataSource.supplementaryViewProvider = newValue
        }
    }

    private var pendingSnapshot: NSDiffableDataSourceSnapshot<GroupID, FeedPostID>?
    private let dataSource: UICollectionViewDiffableDataSource<GroupID, FeedPostID>
    private var unreadPostIDs = Set<FeedPostID>()

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

    func reloadSnapshot(animated: Bool, completion: (() -> Void)? = nil) {
        unreadPostIDs.removeAll()
        unreadPostsCount.send(0)

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
            snapshot.appendItems(feedPosts.map(\.id), toSection: section.name)
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
                if feedPost.userID == AppContext.shared.userData.userId {
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
                    } else {
                        snapshot.appendItems([feedPost.id], toSection: groupID)
                    }


                } else if snapshot.sectionIdentifiers.contains(groupID) {
                    unreadPostIDs.insert(feedPost.id)
                }
            case .delete:
                unreadPostIDs.remove(feedPost.id)
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
        unreadPostsCount.send(unreadPostIDs.count)
    }
}
