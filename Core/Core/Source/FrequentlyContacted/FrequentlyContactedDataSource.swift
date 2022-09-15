//
//  FrequentlyContactedDataSource.swift
//  Core
//
//  Created by Chris Leonavicius on 9/14/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import CoreCommon
import CoreData

public class FrequentlyContactedDataSource: NSObject {

    public enum FrequentlyContactedEntity {
        case user(userID: UserID)
        case group(groupID: GroupID)
    }

    public let subject = CurrentValueSubject<[FrequentlyContactedEntity], Never>([])

    // 7 days ago
    private let cutoffDate = Date(timeIntervalSinceNow: -7 * 24 * 60 * 60) as NSDate

    private lazy var postsFetchedResultsController: NSFetchedResultsController<FeedPost> = {
        let fetchRequest = FeedPost.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userID == %@", AppContext.shared.userData.userId),
            NSPredicate(format: "timestamp >= %@", cutoffDate),
            NSPredicate(format: "fromExternalShare == NO"),
        ])
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false),
        ]
        return NSFetchedResultsController(fetchRequest: fetchRequest,
                                          managedObjectContext: AppContext.shared.mainDataStore.viewContext,
                                          sectionNameKeyPath: nil,
                                          cacheName: nil)
    }()

    private lazy var commentsFetchedResultsController: NSFetchedResultsController<FeedPostComment> = {
        let fetchRequest = FeedPostComment.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userID == %@", AppContext.shared.userData.userId),
            NSPredicate(format: "timestamp >= %@", cutoffDate),
        ])
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \FeedPostComment.timestamp, ascending: false),
        ]
        fetchRequest.relationshipKeyPathsForPrefetching = [
            "post"
        ]
        return NSFetchedResultsController(fetchRequest: fetchRequest,
                                          managedObjectContext: AppContext.shared.mainDataStore.viewContext,
                                          sectionNameKeyPath: nil,
                                          cacheName: nil)
    }()

    private lazy var chatMessagesFetchedResultsController: NSFetchedResultsController<ChatMessage> = {
        let fetchRequest = ChatMessage.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "fromUserID == %@", AppContext.shared.userData.userId),
            NSPredicate(format: "timestamp >= %@", cutoffDate),
        ])
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: false),
        ]
        return NSFetchedResultsController(fetchRequest: fetchRequest,
                                          managedObjectContext: AppContext.shared.mainDataStore.viewContext,
                                          sectionNameKeyPath: nil,
                                          cacheName: nil)
    }()

    private lazy var reactionsFetchedResultsController: NSFetchedResultsController<CommonReaction> = {
        let fetchRequest = CommonReaction.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "fromUserID == %@", AppContext.shared.userData.userId),
            NSPredicate(format: "timestamp >= %@", cutoffDate),
        ])
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \CommonReaction.timestamp, ascending: false),
        ]
        return NSFetchedResultsController(fetchRequest: fetchRequest,
                                          managedObjectContext: AppContext.shared.mainDataStore.viewContext,
                                          sectionNameKeyPath: nil,
                                          cacheName: nil)
    }()

    override public init() {
        super.init()

        postsFetchedResultsController.delegate = self
        commentsFetchedResultsController.delegate = self
        chatMessagesFetchedResultsController.delegate = self
        reactionsFetchedResultsController.delegate = self
    }

    public func performFetch() {
        do {
            try postsFetchedResultsController.performFetch()
            try commentsFetchedResultsController.performFetch()
            try chatMessagesFetchedResultsController.performFetch()
            try reactionsFetchedResultsController.performFetch()
        } catch {
            DDLogError("FrequentlyContactedDataSource/failed to fetch: \(error)")
        }
        updateData()
    }

    private func updateData() {
        var userIDCounts: [UserID: Int] = [:]
        var groupIDCounts: [GroupID: Int] = [:]

        postsFetchedResultsController.fetchedObjects?.forEach { post in
            if let groupID = post.groupID {
                groupIDCounts[groupID, default: 0] += 1
            }
        }

        commentsFetchedResultsController.fetchedObjects?.forEach { comment in
            if let groupID = comment.post.groupID {
                groupIDCounts[groupID, default: 0] += 1
            } else {
                userIDCounts[comment.post.userID, default: 0] += 1
            }
        }

        chatMessagesFetchedResultsController.fetchedObjects?.forEach { chatMessage in
            if let toUserId = chatMessage.toUserId {
                userIDCounts[toUserId, default: 0] += 1
            }
        }

        reactionsFetchedResultsController.fetchedObjects?.forEach { reaction in
            if let toUserId = reaction.toUserID {
                userIDCounts[toUserId, default: 0] += 1
            }
        }

        let contactedUsers = userIDCounts.map { (entity: FrequentlyContactedEntity.user(userID: $0), count: $1) }
        let contactedGroups = groupIDCounts.map { (entity: FrequentlyContactedEntity.group(groupID: $0), count: $1) }

        let sortedEntities = (contactedUsers + contactedGroups)
            .sorted { $0.count > $1.count }
            .map { $0.entity }
        subject.send(sortedEntities)
    }
}

extension FrequentlyContactedDataSource: NSFetchedResultsControllerDelegate {

    public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        updateData()
    }
}
