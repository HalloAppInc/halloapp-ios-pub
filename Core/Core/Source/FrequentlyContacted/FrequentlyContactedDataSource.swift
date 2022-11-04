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

    public struct EntityType: OptionSet {
        public let rawValue: Int

        public static let user = EntityType(rawValue: 1 << 0)
        public static let feedGroup = EntityType(rawValue: 1 << 1)
        public static let chatGroup = EntityType(rawValue: 1 << 2)

        public static let all: EntityType = [.user, .feedGroup, .chatGroup]

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    public enum FrequentlyContactedEntity {
        case user(userID: UserID)
        case feedGroup(groupID: GroupID)
        case chatGroup(groupID: GroupID)
    }

    public let subject = CurrentValueSubject<[FrequentlyContactedEntity], Never>([])

    public let supportedEntityTypes: EntityType

    // 7 days ago
    private let cutoffDate = Date(timeIntervalSinceNow: -7 * 24 * 60 * 60) as NSDate

    private lazy var postsFetchedResultsController: NSFetchedResultsController<FeedPost> = {
        let fetchRequest = FeedPost.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userID == %@", AppContext.shared.userData.userId),
            NSPredicate(format: "timestamp >= %@", cutoffDate),
            NSPredicate(format: "fromExternalShare == NO"),
            NSPredicate(format: "groupID != nil"),
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
        fetchRequest.relationshipKeyPathsForPrefetching = [
            "comment",
            "message",
            "post",
        ]
        return NSFetchedResultsController(fetchRequest: fetchRequest,
                                          managedObjectContext: AppContext.shared.mainDataStore.viewContext,
                                          sectionNameKeyPath: nil,
                                          cacheName: nil)
    }()

    public init(supportedEntityTypes: EntityType = .all) {
        self.supportedEntityTypes = supportedEntityTypes

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
        let currentUserID = AppContext.shared.userData.userId

        var userIDCounts = [UserID: Int]()
        var chatGroupIDCounts = [GroupID: Int]()
        var feedGroupIDCounts = [GroupID: Int]()

        postsFetchedResultsController.fetchedObjects?.forEach { post in
            if let groupID = post.groupID {
                feedGroupIDCounts[groupID, default: 0] += 1
            }
        }

        commentsFetchedResultsController.fetchedObjects?.forEach { comment in
            if let groupID = comment.post.groupID {
                feedGroupIDCounts[groupID, default: 0] += 1
            }
            if comment.post.userID != currentUserID {
                userIDCounts[comment.post.userID, default: 0] += 1
            }
        }

        chatMessagesFetchedResultsController.fetchedObjects?.forEach { chatMessage in
            switch chatMessage.chatMessageRecipient {
            case .oneToOneChat(toUserId: let toUserID, _):
                userIDCounts[toUserID, default: 0] += 1
            case .groupChat(toGroupId: let toGroupID, let fromUserID):
                chatGroupIDCounts[toGroupID, default: 0] += 1
                if currentUserID != fromUserID {
                    userIDCounts[fromUserID, default: 0] += 1
                }
            }
        }

        reactionsFetchedResultsController.fetchedObjects?.forEach { reaction in
            if let comment = reaction.comment {
                guard comment.userID != currentUserID else {
                    return
                }
                userIDCounts[comment.userID, default: 0] += 1
            } else if let chatMessage = reaction.message {
                switch chatMessage.chatMessageRecipient {
                case .oneToOneChat(toUserId: let toUserID, let fromUserID):
                    userIDCounts[currentUserID == toUserID ? fromUserID : toUserID, default: 0] += 1
                case .groupChat(toGroupId: let toGroupID, fromUserId: let fromUserID):
                    chatGroupIDCounts[toGroupID, default: 0] += 1
                    if currentUserID != fromUserID {
                        userIDCounts[fromUserID, default: 0] += 1
                    }
                }
            } else if let post = reaction.post {
                if let groupID = post.groupID {
                    feedGroupIDCounts[groupID, default: 0] += 1
                }
                if post.userID != currentUserID {
                    userIDCounts[post.userID, default: 0] += 1
                }
            }
        }

        let contactedUsers = userIDCounts.map { (entity: FrequentlyContactedEntity.user(userID: $0), count: $1) }
        let contactedChatGroups = chatGroupIDCounts.map { (entity: FrequentlyContactedEntity.chatGroup(groupID: $0), count: $1) }
        let contactedFeedGroups = feedGroupIDCounts.map { (entity: FrequentlyContactedEntity.feedGroup(groupID: $0), count: $1) }

        let sortedEntities = (contactedUsers + contactedChatGroups + contactedFeedGroups)
            .sorted { $0.count > $1.count }
            .map { $0.entity }
            .filter {
                switch $0 {
                case .user:
                    return supportedEntityTypes.contains(.user)
                case .chatGroup:
                    return supportedEntityTypes.contains(.chatGroup)
                case .feedGroup:
                    return supportedEntityTypes.contains(.feedGroup)
                }
            }
        subject.send(sortedEntities)
    }
}

extension FrequentlyContactedDataSource: NSFetchedResultsControllerDelegate {

    public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        updateData()
    }
}
