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
        fetchRequest.predicate = NSPredicate(format: "groupID != nil && timestamp >= %@ && fromExternalShare == NO",
                                             FeedData.postCutoffDate as NSDate)
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
        switch controller {
        case postsFetchedResultsController:
            pendingSnapshot = dataSource.snapshot()
        case threadsFetchedResultsController:
            break
        default:
            DDLogWarn("GroupGridDataSource/received change from unexpected FRC")
        }
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
                    didChange anObject: Any,
                    at indexPath: IndexPath?,
                    for type: NSFetchedResultsChangeType,
                    newIndexPath: IndexPath?) {
        switch controller {
        case postsFetchedResultsController:
            guard var snapshot = pendingSnapshot, let feedPost = anObject as? FeedPost else {
                return
            }

            switch type {
            case .insert:
                if let groupID = feedPost.groupID, snapshot.sectionIdentifiers.contains(groupID) {
                    unreadPostIDs.insert(feedPost.id)
                }
                break
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
            break
        default:
            DDLogWarn("GroupGridDataSource/received change from unexpected FRC")
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        switch controller {
        case postsFetchedResultsController:
            pendingSnapshot.flatMap { dataSource.apply($0) }
            unreadPostsCount.send(unreadPostIDs.count)
        case threadsFetchedResultsController:
            break
        default:
            DDLogWarn("GroupGridDataSource/received change from unexpected FRC")
        }
    }
}
