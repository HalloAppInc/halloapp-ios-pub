//
//  FeedModel.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/1/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import AVKit
import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import CoreData
import Foundation
import SwiftUI

class FeedData: NSObject, ObservableObject, FeedDownloadManagerDelegate, NSFetchedResultsControllerDelegate {

    private let userData: UserData
    private let contactStore: ContactStoreMain
    private let mainDataStore: MainDataStore
    private var service: HalloService

    private var cancellableSet: Set<AnyCancellable> = []

    private(set) var feedNotifications: FeedNotifications?

    let willDestroyStore = PassthroughSubject<Void, Never>()
    let didReloadStore = PassthroughSubject<Void, Never>()

    let shouldReloadView = PassthroughSubject<Void, Never>()

    let didGetRemoveHomeTabIndicator = PassthroughSubject<Void, Never>()

    private struct UserDefaultsKey {
        static let persistentStoreUserID = "feed.store.userID"
    }

    private static let externalShareThumbSize: CGFloat = 800

    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.feed")
    private lazy var downloadManager: FeedDownloadManager = {
        let downloadManager = FeedDownloadManager(mediaDirectoryURL: MainAppContext.mediaDirectoryURL)
        downloadManager.delegate = self
        return downloadManager
    }()

    let mediaUploader: MediaUploader

    private var contentInFlight: Set<String> = []

    init(service: HalloService, contactStore: ContactStoreMain, mainDataStore: MainDataStore, userData: UserData) {
        self.service = service
        self.contactStore = contactStore
        self.mainDataStore = mainDataStore
        self.userData = userData
        self.mediaUploader = MediaUploader(service: service)

        super.init()

        self.service.feedDelegate = self
        mediaUploader.resolveMediaPath = { (relativePath) in
            return MainAppContext.mediaDirectoryURL.appendingPathComponent(relativePath, isDirectory: false)
        }

        // when app resumes, xmpp reconnects, feed should try uploading any pending again
        cancellableSet.insert(
            self.service.didConnect.sink {
                DDLogInfo("Feed: Got event for didConnect")

                self.deleteExpiredPosts()
                self.performSeriallyOnBackgroundContext { managedObjectContext in
                    self.getArchivedPosts { [weak self] posts in
                        self?.deleteAssociatedData(for: posts, in: managedObjectContext)
                    }
                    self.deleteNotifications(olderThan: Self.cutoffDate, in: managedObjectContext)
                }
                self.resendStuckItems()
                self.resendPendingReadReceipts()

                // NB: This value is used to retain posts when a user logs back in to the same account.
                //     Earlier builds did not set it at login, so let's set it in didConnect to support already logged-in users.
                AppContext.shared.userDefaults?.setValue(self.userData.userId, forKey: UserDefaultsKey.persistentStoreUserID)
            })
        
        cancellableSet.insert(
            self.userData.didLogIn.sink {
                if let previousID = AppContext.shared.userDefaults?.string(forKey: UserDefaultsKey.persistentStoreUserID),
                      previousID == self.userData.userId
                {
                    DDLogInfo("FeedData/didLogIn Persistent store matches user ID. Not unloading.")
                } else {
                    DDLogInfo("FeedData/didLogin Persistent store / user ID mismatch. Unloading feed data. \(self.fetchedResultsController.fetchedObjects?.count ?? 0) posts")
                    self.destroyStore()
                    AppContext.shared.userDefaults?.setValue(self.userData.userId, forKey: UserDefaultsKey.persistentStoreUserID)
                }

            })

        cancellableSet.insert(
            self.contactStore.didDiscoverNewUsers.sink { (userIds) in
                userIds.forEach({ self.sharePastPostsWith(userId: $0) })
            })

        fetchFeedPosts()
    }

    // MARK: CoreData stack

    private class var persistentStoreURL: URL {
        get {
            return MainAppContext.feedStoreURL
        }
    }

    private func loadPersistentContainer() {
        let container = self.persistentContainer
        DDLogDebug("FeedData/loadPersistentStore Loaded [\(container)]")
    }

    private lazy var persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: FeedData.persistentStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: false), forKey: NSInferMappingModelAutomaticallyOption)
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let container = NSPersistentContainer(name: "Feed")
        container.persistentStoreDescriptions = [storeDescription]
        self.loadPersistentStores(in: container)
        return container
    }()

    private func loadPersistentStores(in persistentContainer: NSPersistentContainer) {
        persistentContainer.loadPersistentStores { (description, error) in
            if let error = error {
                DDLogError("Failed to load persistent store: \(error)")
                fatalError("Unable to load persistent store: \(error)")
            } else {
                DDLogInfo("FeedData/load-store/completed [\(description)]")
            }
        }
    }
    
    func deletePersistentStores() {
        do {
            try FileManager.default.removeItem(at: FeedData.persistentStoreURL)
            DDLogInfo("FeedData/deletePersistentStores: Deleted feed data")
        } catch {
            DDLogError("FeedData/deletePersistentStores: Error deleting feed data: \(error)")
        }
    }

    // NB: Can be called only from a non-main thread, of the caller's choice
    public func performOnBackgroundContextAndWait(_ block: (NSManagedObjectContext) -> Void) {
        guard !Thread.current.isMainThread else {
            DDLogDebug("FeedData/performOnBackgroundContextAndWait/exit, being called from main thread")
            return
        }
        let managedObjectContext = persistentContainer.newBackgroundContext()
        managedObjectContext.automaticallyMergesChangesFromParent = true
        managedObjectContext.performAndWait { block(managedObjectContext) }
    }

    private func performSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        self.backgroundProcessingQueue.async {
            self.initBgContext()
            guard let bgContext = self.bgContext else {
                let managedObjectContext = self.persistentContainer.newBackgroundContext()
                managedObjectContext.performAndWait { block(managedObjectContext) }
                return
            }
            bgContext.performAndWait { block(bgContext) }
        }
    }

    private func initBgContext() {
        if bgContext == nil {
            bgContext = persistentContainer.newBackgroundContext()
            bgContext?.automaticallyMergesChangesFromParent = true
        }
    }

    private var bgContext: NSManagedObjectContext? = nil    // binded to the background queue, should access only from background queue
    var viewContext: NSManagedObjectContext {
        get {
            self.persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
            return self.persistentContainer.viewContext
        }
    }

    private func save(_ managedObjectContext: NSManagedObjectContext) {
        DDLogVerbose("FeedData/will-save")
        do {
            managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            try managedObjectContext.save()
            DDLogVerbose("FeedData/did-save")
        } catch {
            DDLogError("FeedData/save-error error=[\(error)]")
        }
    }

    func migrate(from oldAppVersion: String?) {
        processUnsupportedItems()
    }

    func destroyStore() {
        DDLogInfo("FeedData/destroy/start")

        // Tell subscribers that everything is going away forever.
        self.willDestroyStore.send()

        self.fetchedResultsController.delegate = nil
        self.feedNotifications = nil

        // TODO: wait for all background tasks to finish.
        // TODO: cancel all media downloads.

        // Delete SQlite database.
        let coordinator = self.persistentContainer.persistentStoreCoordinator
        do {
            let stores = coordinator.persistentStores
            stores.forEach { (store) in
                do {
                    try coordinator.remove(store)
                    DDLogError("FeedData/destroy/remove-store/finised [\(store)]")
                }
                catch {
                    DDLogError("FeedData/destroy/remove-store/error [\(error)]")
                }
            }

            try coordinator.destroyPersistentStore(at: FeedData.persistentStoreURL, ofType: NSSQLiteStoreType, options: nil)
            DDLogInfo("FeedData/destroy/delete-store/complete")
        }
        catch {
            DDLogError("FeedData/destroy/delete-store/error [\(error)]")
            fatalError("Failed to destroy Feed store.")
        }

        // Delete saved Feed media.
        do {
            try FileManager.default.removeItem(at: MainAppContext.mediaDirectoryURL)
            DDLogError("FeedData/destroy/delete-media/finished")
        }
        catch {
            DDLogError("FeedData/destroy/delete-media/error [\(error)]")
        }

        // Load an empty store.
        self.loadPersistentStores(in: self.persistentContainer)

        // Reload fetched results controller.
        self.fetchedResultsController = self.newFetchedResultsController()
        self.fetchFeedPosts()

        // Tell subscribers that store is ready to use again.
        self.didReloadStore.send()

        DDLogInfo("FeedData/destroy/finished")
    }

    // MARK: Fetched Results Controller

    private func processUnsupportedItems() {
        var groupFeedElements = [GroupID: [FeedElement]]()
        var homeFeedElements = [FeedElement]()

        let postsFetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        postsFetchRequest.predicate = NSPredicate(format: "statusValue = %d", FeedPost.Status.unsupported.rawValue)
        do {
            let unsupportedPosts = try viewContext.fetch(postsFetchRequest)
            for post in unsupportedPosts {
                guard let rawData = post.rawData else {
                    DDLogError("FeedData/processUnsupportedItems/posts/error [missing data] [\(post.id)]")
                    continue
                }
                // NB: Set isShared to true to avoid "New Post" banner
                guard let postData = PostData(id: post.id, userId: post.userId, timestamp: post.timestamp, payload: rawData, status: post.feedItemStatus, isShared: true, audience: post.audience) else {
                    DDLogError("FeedData/processUnsupportedItems/posts/error [deserialization] [\(post.id)]")
                    continue
                }
                switch postData.content {
                case .album, .text, .retracted, .voiceNote:
                    DDLogInfo("FeedData/processUnsupportedItems/posts/migrating [\(post.id)]")
                case .unsupported:
                    DDLogInfo("FeedData/processUnsupportedItems/posts/skipping [still unsupported] [\(post.id)]")
                    continue
                case .waiting:
                    DDLogInfo("FeedData/processUnsupportedItems/posts/skipping [still empty] [\(post.id)]")
                    continue
                }
                if let groupID = post.groupId {
                    var elements = groupFeedElements[groupID] ?? []
                    elements.append(.post(postData))
                    groupFeedElements[groupID] = elements
                } else {
                    homeFeedElements.append(.post(postData))
                }
            }
        } catch {
            DDLogError("FeedData/processUnsupportedItems/posts/error [\(error)]")
        }

        let commentsFetchRequest: NSFetchRequest<FeedPostComment> = FeedPostComment.fetchRequest()
        commentsFetchRequest.predicate = NSPredicate(format: "statusValue = %d", FeedPostComment.Status.unsupported.rawValue)
        do {
            let unsupportedComments = try viewContext.fetch(commentsFetchRequest)
            for comment in unsupportedComments {
                guard let rawData = comment.rawData else {
                    DDLogError("FeedData/processUnsupportedItems/comments/error [missing data] [\(comment.id)]")
                    continue
                }
                guard let commentData = CommentData(id: comment.id, userId: comment.userId, feedPostId: comment.post.id, parentId: comment.parent?.id, timestamp: comment.timestamp, payload: rawData, status: comment.feedItemStatus) else {
                    DDLogError("FeedData/processUnsupportedItems/comments/error [deserialization] [\(comment.id)]")
                    continue
                }
                switch commentData.content {
                case .album, .retracted, .voiceNote, .text:
                    DDLogInfo("FeedData/processUnsupportedItems/comments/migrating [\(comment.id)]")
                case .unsupported:
                    DDLogInfo("FeedData/processUnsupportedItems/comments/skipping [still unsupported] [\(comment.id)]")
                    continue
                case .waiting:
                    DDLogInfo("FeedData/processUnsupportedItems/comments/skipping [still empty] [\(comment.id)]")
                    continue
                }
                if let groupID = comment.post.groupId {
                    var elements = groupFeedElements[groupID] ?? []
                    elements.append(.comment(commentData, publisherName: nil))
                    groupFeedElements[groupID] = elements
                } else {
                    homeFeedElements.append(.comment(commentData, publisherName: nil))
                }
            }
        } catch {
            DDLogError("FeedData/processUnsupportedItems/comments/error [\(error)]")
            return
        }

        DDLogInfo("FeedData/processUnsupportedItems/homeFeed [\(homeFeedElements.count)]")
        processIncomingFeedItems(homeFeedElements, groupID: nil, presentLocalNotifications: false, ack: nil)
        for (groupID, elements) in groupFeedElements {
            DDLogInfo("FeedData/processUnsupportedItems/groupFeed [\(groupID)] [\(elements.count)]")
            processIncomingFeedItems(elements, groupID: groupID, presentLocalNotifications: false, ack: nil)
        }
    }

    private func resendStuckItems() {
        let commentsFetchRequest: NSFetchRequest<FeedPostComment> = FeedPostComment.fetchRequest()
        commentsFetchRequest.predicate = NSPredicate(format: "statusValue = %d", FeedPostComment.Status.sending.rawValue)
        do {
            let stuckComments = try viewContext.fetch(commentsFetchRequest)
            for comment in stuckComments {
                if comment.timestamp.addingTimeInterval(Date.days(1)) < Date() {
                    DDLogInfo("FeedData/stuck-comments/\(comment.id)/canceling (too old)")
                    updateFeedPostComment(with: comment.id) { comment in
                        comment.status = .sendError
                    }
                } else {
                    DDLogInfo("FeedData/stuck-comments/\(comment.id)/resending")
                    uploadMediaAndSend(feedComment: comment)
                }
            }
        } catch {
            DDLogError("FeedData/stuck-comments/error [\(error)]")
        }

        let postsFetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        postsFetchRequest.predicate = NSPredicate(format: "statusValue = %d", FeedPost.Status.sending.rawValue)
        do {
            let stuckPosts = try viewContext.fetch(postsFetchRequest)
            for post in stuckPosts {
                if post.timestamp.addingTimeInterval(Date.days(1)) < Date() {
                    DDLogInfo("FeedData/stuck-posts/\(post.id)/canceling (too old)")
                    updateFeedPost(with: post.id) { post in
                        post.status = .sendError
                    }
                } else {
                    DDLogInfo("FeedData/stuck-posts/\(post.id)/resending")
                    uploadMediaAndSend(feedPost: post)
                }
            }
        } catch {
            DDLogError("FeedData/stuck-posts/error [\(error)]")
        }
    }

    private func fetchFeedPosts() {
        do {
            try fetchedResultsController.performFetch()
            if let feedPosts = fetchedResultsController.fetchedObjects {
                DDLogInfo("FeedData/fetch/completed \(feedPosts.count) posts")

                // 1. Mitigate server bug when timestamps were sent in milliseconds.
                // 1.1 Posts
                let cutoffDate = Date(timeIntervalSinceNow: Date.days(1000))
                let postsWithIncorrectTimestamp = feedPosts.filter({ $0.timestamp > cutoffDate })
                if !postsWithIncorrectTimestamp.isEmpty {
                    postsWithIncorrectTimestamp.forEach { (post) in
                        let ts = post.timestamp.timeIntervalSince1970 / 1000
                        let oldTimestamp = post.timestamp
                        let newTImestamp = Date(timeIntervalSince1970: ts)
                        DDLogWarn("FeedData/fetch/fix-timestamp [\(oldTimestamp)] -> [\(newTImestamp)]")
                        post.timestamp = newTImestamp
                    }
                    save(fetchedResultsController.managedObjectContext)
                }
                // 1.2 Comments
                let commentsFetchRequest: NSFetchRequest<FeedPostComment> = FeedPostComment.fetchRequest()
                commentsFetchRequest.predicate = NSPredicate(format: "timestamp > %@", cutoffDate as NSDate)
                do {
                    let commentsWithIncorrectTimestamp = try viewContext.fetch(commentsFetchRequest)
                    if !commentsWithIncorrectTimestamp.isEmpty {
                        commentsWithIncorrectTimestamp.forEach { (comment) in
                            let ts = comment.timestamp.timeIntervalSince1970 / 1000
                            let oldTimestamp = comment.timestamp
                            let newTimestamp = Date(timeIntervalSince1970: ts)
                            DDLogWarn("FeedData/fetch/fix-timestamp [\(oldTimestamp)] -> [\(newTimestamp)]")
                            comment.timestamp = newTimestamp
                        }
                        save(fetchedResultsController.managedObjectContext)
                    }
                }
                catch {
                    DDLogError("FeedData/fetch/error [\(error)]")
                    fatalError("Failed to fetch feed items \(error)")
                }

                // 1.3 Notifications
                let notificationsFetchRequest: NSFetchRequest<FeedNotification> = FeedNotification.fetchRequest()
                notificationsFetchRequest.predicate = NSPredicate(format: "timestamp > %@", cutoffDate as NSDate)
                do {
                    let notificationsWithIncorrectTimestamp = try viewContext.fetch(notificationsFetchRequest)
                    if !notificationsWithIncorrectTimestamp.isEmpty {
                        notificationsWithIncorrectTimestamp.forEach { (notification) in
                            let ts = notification.timestamp.timeIntervalSince1970 / 1000
                            let oldTimestamp = notification.timestamp
                            let newTimestamp = Date(timeIntervalSince1970: ts)
                            DDLogWarn("FeedData/fetch/fix-timestamp [\(oldTimestamp)] -> [\(newTimestamp)]")
                            notification.timestamp = newTimestamp
                        }
                        save(fetchedResultsController.managedObjectContext)
                    }
                }
                catch {
                    DDLogError("FeedData/fetch/error [\(error)]")
                    fatalError("Failed to fetch feed items \(error)")
                }

            }
        }
        catch {
            DDLogError("FeedData/fetch/error [\(error)]")
            fatalError("Failed to fetch feed items \(error)")
        }

        feedNotifications = FeedNotifications(viewContext)

        reloadGroupFeedUnreadCounts()
    }

    private lazy var fetchedResultsController: NSFetchedResultsController<FeedPost> = newFetchedResultsController()

    private func newFetchedResultsController() -> NSFetchedResultsController<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        let fetchedResultsController = NSFetchedResultsController<FeedPost>(fetchRequest: fetchRequest, managedObjectContext: self.viewContext,
                                                                            sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }

    private var trackPerRowChanges = false

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogDebug("FeedData/frc/will-change")
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogDebug("FeedData/frc/did-change")
        setNeedsReloadGroupFeedUnreadCounts()
    }

    // MARK: Fetching Feed Data

    public func feedHistory(for groupID: GroupID, in managedObjectContext: NSManagedObjectContext? = nil, maxNumPosts: Int = Int.max, maxCommentsPerPost: Int = Int.max) -> ([PostData], [CommentData]) {
        let managedObjectContext = managedObjectContext ?? self.viewContext
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        // Fetch all feedposts in the group that have not expired yet.
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "groupId == %@", groupID),
            NSPredicate(format: "timestamp >= %@", Self.cutoffDate as NSDate)
        ])
        // Fetch feedposts in reverse timestamp order.
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false)]
        fetchRequest.returnsObjectsAsFaults = false
        do {
            // Fetch posts and extract postData
            let posts = try managedObjectContext.fetch(fetchRequest).prefix(maxNumPosts)
            let postsData = posts.map{ $0.postData }

            // Fetch comments and extract commentData
            var comments: [FeedPostComment] = []
            for post in posts {
                guard let postComments = post.comments else {
                    break
                }
                let sortedComments = postComments.sorted { $0.timestamp > $1.timestamp }
                comments.append(contentsOf: sortedComments.prefix(maxCommentsPerPost))
            }
            let commentsData = comments.map{ $0.commentData }
            let postIds = posts.map { $0.id }
            let commentIds = comments.map { $0.id }

            // TODO: remove this log eventually.
            DDLogDebug("FeedData/feedHistory/group: \(groupID)/postIds: \(postIds)/commentIds: \(commentIds)")

            DDLogInfo("FeedData/feedHistory/group: \(groupID)/posts: \(posts.count)/comments: \(comments.count)")
            return (postsData, commentsData)
        } catch {
            DDLogError("FeedData/fetch-posts/error  [\(error)]")
            fatalError("Failed to fetch feed posts.")
        }
    }

    public func authoredFeedHistory(for groupID: GroupID, in managedObjectContext: NSManagedObjectContext? = nil) -> ([PostData], [CommentData]) {
        // Fetch all feed history and then filter authored content.
        let (postsData, commentsData) = feedHistory(for: groupID, in: managedObjectContext)
        let ownUserID = userData.userId
        let authoredPostsData = postsData.filter{ $0.userId == ownUserID }
        let authoredCommentsData = commentsData.filter{ $0.userId == ownUserID }

        let authoredPostIds = authoredPostsData.map { $0.id }
        let authoredCommentIds = authoredCommentsData.map { $0.id }
        // TODO: remove this log eventually.
        DDLogDebug("FeedData/authoredFeedHistory/group: \(groupID)/authoredPostIds: \(authoredPostIds)/authoredCommentIds: \(authoredCommentIds)")

        DDLogInfo("FeedData/authoredFeedHistory/group: \(groupID)/authoredPosts: \(authoredPostsData.count)/authoredComments: \(authoredCommentsData.count)")
        return (authoredPostsData, authoredCommentsData)
    }

    private func feedPosts(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext? = nil, archived: Bool = false) -> [FeedPost] {
        let managedObjectContext = managedObjectContext ?? self.viewContext
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        
        if let predicate = predicate {
            if !archived {
                fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    predicate,
                    NSPredicate(format: "timestamp >= %@", Self.cutoffDate as NSDate)
                ])
            } else {
                fetchRequest.predicate = predicate
            }
        } else {
            fetchRequest.predicate = NSPredicate(format: "timestamp >= %@", Self.cutoffDate as NSDate)
        }
        
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let posts = try managedObjectContext.fetch(fetchRequest)
            return posts
        }
        catch {
            DDLogError("FeedData/fetch-posts/error  [\(error)]")
            fatalError("Failed to fetch feed posts.")
        }
    }

    func feedPost(with id: FeedPostID, in managedObjectContext: NSManagedObjectContext? = nil, archived: Bool = false) -> FeedPost? {
        return self.feedPosts(predicate: NSPredicate(format: "id == %@", id), in: managedObjectContext, archived: archived).first
    }

    // Should always be called using the backgroundQueue.
    func fetchResendAttempt(for contentID: String, userID: UserID, in managedObjectContext: NSManagedObjectContext) -> FeedItemResendAttempt {
        let managedObjectContext = managedObjectContext
        let fetchRequest: NSFetchRequest<FeedItemResendAttempt> = FeedItemResendAttempt.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "contentID == %@ AND userID == %@", contentID, userID)
        fetchRequest.returnsObjectsAsFaults = false
        do {
            if let result = try managedObjectContext.fetch(fetchRequest).first {
                return result
            } else {
                let result = FeedItemResendAttempt(context: managedObjectContext)
                result.contentID = contentID
                result.userID = userID
                result.retryCount = 0
                return result
            }
        } catch {
            DDLogError("FeedData/fetchAndUpdateRetryCount/error  [\(error)]")
            fatalError("Failed to fetchAndUpdateRetryCount.")
        }
    }

    private func feedPosts(with ids: Set<FeedPostID>, in managedObjectContext: NSManagedObjectContext? = nil, archived: Bool = false) -> [FeedPost] {
        return feedPosts(predicate: NSPredicate(format: "id in %@", ids), in: managedObjectContext, archived: archived)
    }

    func feedLinkPreview(with id: FeedLinkPreviewID, in managedObjectContext: NSManagedObjectContext? = nil) -> FeedLinkPreview? {
        let managedObjectContext = managedObjectContext ?? self.viewContext
        let fetchRequest: NSFetchRequest<FeedLinkPreview> = FeedLinkPreview.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let linkPreviews = try managedObjectContext.fetch(fetchRequest)
            return linkPreviews.first
        }
        catch {
            DDLogError("FeedData/fetch-link-preview/error  [\(error)]")
            fatalError("Failed to fetch feed link preview.")
        }
    }

    func feedComment(with id: FeedPostCommentID, in managedObjectContext: NSManagedObjectContext? = nil) -> FeedPostComment? {
        let managedObjectContext = managedObjectContext ?? self.viewContext
        let fetchRequest: NSFetchRequest<FeedPostComment> = FeedPostComment.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let comments = try managedObjectContext.fetch(fetchRequest)
            return comments.first
        }
        catch {
            DDLogError("FeedData/fetch-comments/error  [\(error)]")
            fatalError("Failed to fetch feed post comments.")
        }
    }

    private func feedComments(with ids: Set<FeedPostCommentID>, in managedObjectContext: NSManagedObjectContext? = nil) -> [FeedPostComment] {
        let managedObjectContext = managedObjectContext ?? viewContext
        let fetchRequest: NSFetchRequest<FeedPostComment> = FeedPostComment.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id in %@", ids)
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let comments = try managedObjectContext.fetch(fetchRequest)
            return comments
        }
        catch {
            DDLogError("FeedData/fetch-comments/error  [\(error)]")
            fatalError("Failed to fetch feed post comments.")
        }
    }

    // MARK: Group Feed

    /**
     Overview of the feed for a group.
     */
    enum GroupFeedState {
        case noPosts
        case seenPosts(Int)     // total number of posts in group's feed
        case newPosts(Int, Int) // number of new posts, total number of posts
    }

    private(set) var groupFeedStates = CurrentValueSubject<[GroupID: GroupFeedState], Never>([:])

    private func reloadGroupFeedUnreadCounts() {
        var results: [GroupID: GroupFeedState] = [:]

        // Count posts in all groups.
        let countDesc = NSExpressionDescription()
        countDesc.expression = NSExpression(forFunction: "count:", arguments: [ NSExpression(forKeyPath: \FeedPost.groupId) ])
        countDesc.name = "count"
        countDesc.expressionResultType = .integer64AttributeType

        let fetchRequest: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: FeedPost.entity().name!)
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.predicate = NSPredicate(format: "groupId != nil")
        fetchRequest.propertiesToGroupBy = [ "groupId" ]
        fetchRequest.propertiesToFetch = [ "groupId", countDesc ]
        fetchRequest.resultType = .dictionaryResultType
        do {
            let fetchResults = try viewContext.fetch(fetchRequest)
            for result in fetchResults {
                guard let groupId = result["groupId"] as? GroupID, let count = result["count"] as? Int else { continue }
                results[groupId] = .seenPosts(count)
            }
        }
        catch {
            DDLogError("FeedData/fetch-posts/error  [\(error)]")
            fatalError("Failed to fetch feed posts.")
        }

        // Count new posts in groups.
        fetchRequest.predicate = NSPredicate(format: "groupId != nil AND statusValue == %d", FeedPost.Status.incoming.rawValue)
        do {
            let fetchResults = try viewContext.fetch(fetchRequest)
            for result in fetchResults {
                guard let groupId = result["groupId"] as? GroupID, let count = result["count"] as? Int else { continue }
                if case .seenPosts(let totalPostsCount) = results[groupId] {
                    results[groupId] = .newPosts(count, totalPostsCount)
                } else {
                    assert(false, "No total post count for group [\(groupId)]")
                }
            }
        }
        catch {
            DDLogError("FeedData/fetch-posts/error  [\(error)]")
            fatalError("Failed to fetch feed posts.")
        }

        groupFeedStates.send(results)
    }

    private func setNeedsReloadGroupFeedUnreadCounts() {
        DispatchQueue.main.async {
            self.reloadGroupFeedUnreadCounts()
        }
    }

    // MARK: History tombstones
    public func createTombstones(for groupID: GroupID, with contentsDetails: [Clients_ContentDetails]) {
        DDLogInfo("FeedData/createTombstones/groupID: \(groupID)/itemsCount: \(contentsDetails.count)")
        self.performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }

            var feedPostContexts: [FeedPostID: Clients_PostIdContext] = [:]
            var commentContexts: [FeedPostCommentID: Clients_CommentIdContext] = [:]

            contentsDetails.forEach { contentDetails in
                switch contentDetails.contentID {
                case .postIDContext(let postIdContext):
                    // This is to protect against invalid data and clients responding without senderUid
                    if postIdContext.senderUid != 0 {
                        feedPostContexts[postIdContext.feedPostID] = postIdContext
                    }
                case .commentIDContext(let commentIdContext):
                    // This is to protect against invalid data and clients responding without senderUid
                    if commentIdContext.senderUid != 0 {
                        commentContexts[commentIdContext.commentID] = commentIdContext
                    }
                case .none:
                    break
                }
            }
            DDLogInfo("FeedData/createTombstones/groupID: \(groupID)/postsCount: \(feedPostContexts.count)/commentsCount: \(commentContexts.count)")

            var posts = self.feedPosts(with: Set(feedPostContexts.keys), in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
            var comments = self.feedComments(with: Set(commentContexts.keys), in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
            DDLogInfo("FeedData/createTombstones/groupID: \(groupID)/postsAlreadyPresentCount: \(posts.count)")
            DDLogInfo("FeedData/createTombstones/groupID: \(groupID)/commentsAlreadyPresentCount: \(comments.count)")

            // Create post tombstones
            feedPostContexts.forEach { (postId, postIdContext) in
                if posts[postId] == nil {
                    let feedPost = FeedPost(context: managedObjectContext)
                    feedPost.id = postId
                    feedPost.status = .rerequesting
                    feedPost.userId = UserID(postIdContext.senderUid)
                    feedPost.timestamp = Date(timeIntervalSince1970: TimeInterval(postIdContext.timestamp))
                    feedPost.groupId = groupID
                    posts[postId] = feedPost
                } else {
                    DDLogInfo("FeedData/createTombstones/groupID: \(groupID)/post: \(postId)/post already present - skip")
                }
            }

            // Create comment tombsones only when posts are available.
            commentContexts.forEach { (commentId, commentIdContext) in
                if comments[commentId] == nil,
                   let post = posts[commentIdContext.feedPostID] {
                    let feedPostComment = FeedPostComment(context: managedObjectContext)
                    feedPostComment.id = commentId
                    feedPostComment.status = .rerequesting
                    feedPostComment.userId = UserID(commentIdContext.senderUid)
                    feedPostComment.timestamp = Date(timeIntervalSince1970: TimeInterval(commentIdContext.timestamp))
                    feedPostComment.post = post
                    feedPostComment.text = ""
                    comments[commentId] = feedPostComment
                } else {
                    DDLogInfo("FeedData/createTombstones/groupID: \(groupID)/comment: \(commentId)/comment already present or post missing - skip")
                }
            }

            // Update parent comment ids for the comments created.
            commentContexts.forEach { (commentId, commentIdContext) in
                if let comment = comments[commentId],
                   let parentComment = comments[commentIdContext.parentCommentID] {
                    comment.parent = parentComment
                    comments[commentId] = comment
                }
            }

            DDLogInfo("FeedData/createTombstones/groupID: \(groupID)/saving tombstones")
            self.save(managedObjectContext)
            DDLogInfo("FeedData/createTombstones/groupID: \(groupID)/saving tombstones/success")
        }
    }

    // MARK: Updates

    private func updateFeedPost(with id: FeedPostID, block: @escaping (FeedPost) -> (), performAfterSave: (() -> ())? = nil) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            defer {
                if let performAfterSave = performAfterSave {
                    performAfterSave()
                }
            }
            guard let feedPost = self.feedPost(with: id, in: managedObjectContext, archived: true) else {
                DDLogError("FeedData/update-post/missing-post [\(id)]")
                return
            }
            DDLogVerbose("FeedData/update-post [\(id)] - currentStatus: [\(feedPost.status)]")
            block(feedPost)
            DDLogVerbose("FeedData/update-post-afterBlock [\(id)] - currentStatus: [\(feedPost.status)]")
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }

    private func updateFeedPostComment(with id: FeedPostCommentID, block: @escaping (FeedPostComment) -> (), performAfterSave: (() -> ())? = nil) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            defer {
                if let performAfterSave = performAfterSave {
                    performAfterSave()
                }
            }
            guard let comment = self.feedComment(with: id, in: managedObjectContext) else {
                DDLogError("FeedData/update-comment/missing-comment [\(id)]")
                return
            }
            DDLogVerbose("FeedData/update-comment [\(id)]")
            block(comment)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    private func updateFeedLinkPreview(with id: FeedLinkPreviewID, block: @escaping (FeedLinkPreview) -> (), performAfterSave: (() -> ())? = nil) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            defer {
                if let performAfterSave = performAfterSave {
                    performAfterSave()
                }
            }
            guard let feedLinkPreview = self.feedLinkPreview(with: id, in: managedObjectContext) else {
                DDLogError("FeedData/update-feedLinkPreview/missing-feedLinkPreview [\(id)]")
                return
            }
            DDLogVerbose("FeedData/update-feedLinkPreview [\(id)]")
            block(feedLinkPreview)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }

    func markCommentsAsRead(feedPostId: FeedPostID) {
        updateFeedPost(with: feedPostId) { (feedPost) in
            if feedPost.unreadCount != 0 {
                feedPost.unreadCount = 0
            }
        }
        markNotificationsAsRead(for: feedPostId)
    }

    func markCommentAsPlayed(commentId: FeedPostCommentID) {
        updateFeedPostComment(with: commentId) { comment in
            guard comment.userId != MainAppContext.shared.userData.userId else { return }
            guard comment.status != .played else { return }
            comment.status = .played
        }
    }

    // MARK: Process Incoming Feed Data

    let didReceiveFeedPost = PassthroughSubject<FeedPost, Never>()  // feed post that is not a duplicate but can be shared (old)
    let didGetNewFeedPost = PassthroughSubject<FeedPostID, Never>() // feed post that is not a duplicate or shared (old)

    let didReceiveFeedPostComment = PassthroughSubject<FeedPostComment, Never>()

    @discardableResult private func process(posts xmppPosts: [PostData],
                                            receivedIn groupID: GroupID?,
                                            using managedObjectContext: NSManagedObjectContext,
                                            presentLocalNotifications: Bool) -> [FeedPost] {
        guard !xmppPosts.isEmpty else { return [] }

        let postIds = Set(xmppPosts.map{ $0.id })
        let existingPosts = feedPosts(with: postIds, in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
        var newPosts: [FeedPost] = []
        var sharedPosts: [FeedPostID] = []

        for xmppPost in xmppPosts {

            if let existingPost = existingPosts[xmppPost.id] {
                // If status = .none for an existing post, we need to process the newly received post.
                if existingPost.status == .none {
                    DDLogInfo("FeedData/process-posts/existing [\(existingPost.id)]/status is none/need to update")
                } else if existingPost.status == .rerequesting && xmppPost.status == .received {
                    // If status = .rerequesting for an existing post.
                    // We check if we already used the unencrypted payload as fallback.
                    // If we already have content - then just update the status and return.
                    // If we dont have the content already and are still waiting, then we need to process the newly received post.
                    switch existingPost.postData.content {
                    case .waiting:
                        DDLogInfo("FeedData/process-posts/existing [\(existingPost.id)]/content is waiting/need to update")
                    default:
                        DDLogInfo("FeedData/process-posts/existing [\(existingPost.id)]/update status and return")
                        existingPost.status = .incoming
                        continue
                    }
                } else {
                    DDLogError("FeedData/process-posts/existing [\(existingPost.id)], ignoring")
                    continue
                }
            }

            if xmppPost.isShared {
                sharedPosts.append(xmppPost.id)
            }

            let feedPost: FeedPost
            // Fetch or Create new post.
            if let existingPost = existingPosts[xmppPost.id] {
                DDLogError("FeedData/process-posts/existing [\(xmppPost.id)]")
                feedPost = existingPost
            } else {
                // Add new FeedPost to database.
                DDLogDebug("FeedData/process-posts/new [\(xmppPost.id)]")
                feedPost = NSEntityDescription.insertNewObject(forEntityName: FeedPost.entity().name!, into: managedObjectContext) as! FeedPost
            }

            switch feedPost.status {
                // TODO: murali@: verify the timestamp here.
            case .none, .unsupported, .rerequesting:
                DDLogInfo("FeedData/process-posts/updating [\(xmppPost.id)] current status: \(feedPost.status)")
                break
            case .incoming, .seen, .seenSending, .sendError, .sending, .sent, .retracted, .retracting:
                DDLogError("FeedData/process-posts/skipping [duplicate] [\(xmppPost.id)] current status: \(feedPost.status)")
                continue
            }

            feedPost.id = xmppPost.id
            feedPost.userId = xmppPost.userId
            feedPost.groupId = groupID
            feedPost.text = xmppPost.text
            feedPost.timestamp = xmppPost.timestamp

            switch xmppPost.content {
            case .album, .text, .voiceNote:
                // Mark our own posts as seen in case server sends us old posts following re-registration
                if feedPost.userId == userData.userId {
                    feedPost.status = .seen
                } else {
                    // Set status to be rerequesting if necessary.
                    if xmppPost.status == .rerequesting {
                        feedPost.status = .rerequesting
                    } else {
                        feedPost.status = .incoming
                    }
                }
            case .retracted:
                DDLogError("FeedData/process-posts/incoming-retracted-post [\(xmppPost.id)]")
                feedPost.status = .retracted
            case .unsupported(let data):
                feedPost.status = .unsupported
                feedPost.rawData = data
            case .waiting:
                feedPost.status = .rerequesting
                if xmppPost.status != .rerequesting {
                    DDLogError("FeedData/process-posts/invalid content [\(xmppPost.id)] with status: \(xmppPost.status)")
                }
            }
            // Clear cached media if any.
            cachedMedia[feedPost.id] = nil

            var mentions = Set<FeedMention>()
            for xmppMention in xmppPost.orderedMentions {
                let mention = NSEntityDescription.insertNewObject(forEntityName: FeedMention.entity().name!, into: managedObjectContext) as! FeedMention
                mention.index = xmppMention.index
                mention.userID = xmppMention.userID
                mention.name = xmppMention.name
                mentions.insert(mention)
            }
            feedPost.mentions = mentions

            // Post Audience
            if let audience = xmppPost.audience {
                let feedPostInfo = NSEntityDescription.insertNewObject(forEntityName: FeedPostInfo.entity().name!, into: managedObjectContext) as! FeedPostInfo
                feedPostInfo.audienceType = audience.audienceType
                feedPostInfo.receipts = audience.userIds.reduce(into: [UserID : Receipt]()) { (receipts, userId) in
                    receipts[userId] = Receipt()
                }
                feedPost.info = feedPostInfo
            }

            // Process link preview if present
            xmppPost.linkPreviewData.forEach { linkPreviewData in
                DDLogDebug("FeedData/process-posts/new/add-link-preview [\(linkPreviewData.url)]")
                let linkPreview = NSEntityDescription.insertNewObject(forEntityName: FeedLinkPreview.entity().name!, into: managedObjectContext) as! FeedLinkPreview
                linkPreview.id = PacketID.generate()
                linkPreview.url = linkPreviewData.url
                linkPreview.title = linkPreviewData.title
                linkPreview.desc = linkPreviewData.description
                // Set preview image if present
                linkPreviewData.previewImages.forEach { previewMedia in
                    let media = NSEntityDescription.insertNewObject(forEntityName: FeedPostMedia.entity().name!, into: managedObjectContext) as! FeedPostMedia
                    media.type = previewMedia.type
                    media.status = .none
                    media.url = previewMedia.url
                    media.size = previewMedia.size
                    media.key = previewMedia.key
                    media.sha256 = previewMedia.sha256
                    media.linkPreview = linkPreview
                }
                linkPreview.post = feedPost
            }
            // Process post media
            for (index, xmppMedia) in xmppPost.orderedMedia.enumerated() {
                DDLogDebug("FeedData/process-posts/new/add-media [\(xmppMedia.url!)]")
                let feedMedia = NSEntityDescription.insertNewObject(forEntityName: FeedPostMedia.entity().name!, into: managedObjectContext) as! FeedPostMedia
                switch xmppMedia.type {
                case .image:
                    feedMedia.type = .image
                case .video:
                    feedMedia.type = .video
                case .audio:
                    feedMedia.type = .audio
                }
                feedMedia.status = .none
                feedMedia.url = xmppMedia.url
                feedMedia.size = xmppMedia.size
                feedMedia.key = xmppMedia.key
                feedMedia.order = Int16(index)
                feedMedia.sha256 = xmppMedia.sha256
                feedMedia.post = feedPost
                feedMedia.blobVersion = xmppMedia.blobVersion
                feedMedia.chunkSize = xmppMedia.chunkSize
                feedMedia.blobSize = xmppMedia.blobSize
            }

            newPosts.append(feedPost)
        }
        DDLogInfo("FeedData/process-posts/finished \(newPosts.count) new items, \(xmppPosts.count - newPosts.count) duplicates, \(sharedPosts.count) shared (old)")
        save(managedObjectContext)

        try? managedObjectContext.obtainPermanentIDs(for: newPosts)
        let postObjectIDs = newPosts.map { $0.objectID }
        DispatchQueue.main.async {
            let managedObjectContext = self.viewContext
            let feedPosts = postObjectIDs.compactMap{ try? managedObjectContext.existingObject(with: $0) as? FeedPost }

            // Initiate downloads from the main thread to avoid race condition with downloads initiated from FeedTableView.
            // Only initiate downloads for feed posts received in real-time.
            // Media for older posts in the feed will be downloaded as user scrolls down.
            if newPosts.count == 1 {
                self.downloadMedia(in: feedPosts)
            }

            // Show local notifications if necessary.
            if presentLocalNotifications && NotificationSettings.current.isPostsEnabled {
                self.presentLocalNotifications(forFeedPosts: feedPosts)
            }

            // Notify about new posts all interested parties.
            feedPosts.forEach({
                self.didReceiveFeedPost.send($0)
                if !sharedPosts.contains($0.id) {
                    self.didGetNewFeedPost.send($0.id)
                }
            })
        }

        checkForUnreadFeed()
        return newPosts
    }

    @discardableResult private func process(comments xmppComments: [CommentData],
                                            receivedIn groupID: GroupID?,
                                            using managedObjectContext: NSManagedObjectContext,
                                            presentLocalNotifications: Bool) -> [FeedPostComment] {
        guard !xmppComments.isEmpty else { return [] }

        let feedPostIds = Set(xmppComments.map{ $0.feedPostId })
        var posts = feedPosts(with: feedPostIds, in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
        let commentIds = Set(xmppComments.map{ $0.id }).union(Set(xmppComments.compactMap{ $0.parentId }))
        var comments = feedComments(with: commentIds, in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
        var ignoredCommentIds: Set<String> = []
        var xmppCommentsMutable = [CommentData](xmppComments)
        var newComments: [FeedPostComment] = []
        var duplicateCount = 0, numRuns = 0
        while !xmppCommentsMutable.isEmpty && numRuns < 100 {
            for xmppComment in xmppCommentsMutable {

                if let existingComment = comments[xmppComment.id] {
                    // If status = .none for an existing comment, we need to process the newly received comment.
                    if existingComment.status == .none {
                        DDLogInfo("FeedData/process-comments/existing [\(existingComment.id)]/status is none/need to update")
                    } else if existingComment.status == .rerequesting && xmppComment.status == .received {
                        // If status = .rerequesting for an existing comment.
                        // We check if we already used the unencrypted payload as fallback.
                        // If we already have content - then just update the status and return.
                        // If we dont have the content already and are still waiting, then we need to process the newly received comment.
                        switch existingComment.commentData.content {
                        case .waiting:
                            DDLogInfo("FeedData/process-comments/existing [\(existingComment.id)]/content is waiting/need to update")
                        default:
                            DDLogInfo("FeedData/process-comments/existing [\(existingComment.id)]/update status and return")
                            existingComment.status = .incoming
                            continue
                        }
                    } else {
                        DDLogError("FeedData/process-comments/existing [\(existingComment.id)], ignoring")
                        continue
                    }
                }

                // Find comment's post.
                let feedPost: FeedPost
                if let post = posts[xmppComment.feedPostId] {
                    DDLogInfo("FeedData/process-comments/existing-post [\(xmppComment.feedPostId)]")
                    feedPost = post
                } else if let groupID = groupID {
                    // Create a post only for missing group posts.
                    DDLogInfo("FeedData/process-comments/missing-post [\(xmppComment.feedPostId)]/creating one")
                    feedPost = FeedPost(context: managedObjectContext)
                    feedPost.id = xmppComment.feedPostId
                    feedPost.status = .rerequesting
                    feedPost.userId = ""
                    feedPost.timestamp = Date()
                    feedPost.groupId = groupID
                    posts[xmppComment.feedPostId] = feedPost
                } else {
                    DDLogError("FeedData/process-comments/missing-post [\(xmppComment.feedPostId)]/skip comment")
                    ignoredCommentIds.insert(xmppComment.id)
                    continue
                }

                // Additional check: post's groupId must match groupId of the comment.
                guard feedPost.groupId == groupID else {
                    DDLogError("FeedData/process-comments/incorrect-group-id post:[\(feedPost.groupId ?? "")] comment:[\(groupID ?? "")]")
                    ignoredCommentIds.insert(xmppComment.id)
                    continue
                }

                // Check if post has been retracted.
                guard !feedPost.isPostRetracted else {
                    DDLogError("FeedData/process-comments/retracted-post [\(xmppComment.feedPostId)]")
                    ignoredCommentIds.insert(xmppComment.id)
                    continue
                }

                // Find parent if necessary.
                var parentComment: FeedPostComment? = nil
                if let parentId = xmppComment.parentId, !parentId.isEmpty {
                    parentComment = comments[parentId]
                    if parentComment == nil {
                        DDLogInfo("FeedData/process-comments/missing-parent/[\(xmppComment.id)] - [\(parentId)]/creating one")
                        parentComment = FeedPostComment(context: managedObjectContext)
                        parentComment?.id = parentId
                        parentComment?.post = feedPost
                        parentComment?.timestamp = Date()
                        parentComment?.userId = ""
                        parentComment?.text = ""
                        parentComment?.status = .rerequesting
                        comments[parentId] = parentComment
                    }
                }

                let comment: FeedPostComment

                if let existingComment = comments[xmppComment.id] {
                    switch existingComment.status {
                    case .unsupported, .rerequesting, .none:
                        DDLogInfo("FeedData/process-comments/updating [\(xmppComment.id)] current status: \(existingComment.status)")
                        comment = existingComment
                    case .incoming, .retracted, .retracting, .sent, .sending, .sendError, .played:
                        duplicateCount += 1
                        DDLogError("FeedData/process-comments/duplicate [\(xmppComment.id)] current status: \(existingComment.status)")
                        continue
                    }
                } else {
                    // Add new FeedPostComment to database.
                    DDLogDebug("FeedData/process-comments/new [\(xmppComment.id)]")
                    comment = NSEntityDescription.insertNewObject(forEntityName: FeedPostComment.entity().name!, into: managedObjectContext) as! FeedPostComment
                }

                comment.id = xmppComment.id
                comment.userId = xmppComment.userId
                comment.parent = parentComment
                comment.post = feedPost
                comment.timestamp = xmppComment.timestamp
                // Clear cached media if any.
                cachedMedia[comment.id] = nil

                // Set status to be rerequesting if necessary.
                if xmppComment.status == .rerequesting {
                    comment.status = .rerequesting
                } else {
                    comment.status = .incoming
                }

                switch xmppComment.content {
                case .text(let mentionText, let linkPreviewData):
                    comment.status = .incoming
                    comment.text = mentionText.collapsedText
                    var mentions = Set<FeedMention>()
                    for (i, user) in mentionText.mentions {
                        let mention = NSEntityDescription.insertNewObject(forEntityName: FeedMention.entity().name!, into: managedObjectContext) as! FeedMention
                        mention.index = i
                        mention.userID = user.userID
                        mention.name = user.pushName ?? ""
                        mentions.insert(mention)
                    }
                    comment.mentions = mentions
                    // Process link preview if present
                    linkPreviewData.forEach { linkPreviewData in
                        DDLogDebug("FeedData/process-comments/new/add-link-preview [\(linkPreviewData.url)]")
                        let linkPreview = NSEntityDescription.insertNewObject(forEntityName: FeedLinkPreview.entity().name!, into: managedObjectContext) as! FeedLinkPreview
                        linkPreview.id = PacketID.generate()
                        linkPreview.url = linkPreviewData.url
                        linkPreview.title = linkPreviewData.title
                        linkPreview.desc = linkPreviewData.description
                        // Set preview image if present
                        linkPreviewData.previewImages.forEach { previewMedia in
                            let media = NSEntityDescription.insertNewObject(forEntityName: FeedPostMedia.entity().name!, into: managedObjectContext) as! FeedPostMedia
                            media.type = previewMedia.type
                            media.status = .none
                            media.url = previewMedia.url
                            media.size = previewMedia.size
                            media.key = previewMedia.key
                            media.sha256 = previewMedia.sha256
                            media.linkPreview = linkPreview
                        }
                        linkPreview.comment = comment
                    }
                case .album(let mentionText, let media):
                    comment.text = mentionText.collapsedText
                    var mentions = Set<FeedMention>()
                    for (i, user) in mentionText.mentions {
                        let mention = NSEntityDescription.insertNewObject(forEntityName: FeedMention.entity().name!, into: managedObjectContext) as! FeedMention
                        mention.index = i
                        mention.userID = user.userID
                        mention.name = user.pushName ?? ""
                        mentions.insert(mention)
                    }
                    comment.mentions = mentions
                    // Process Comment Media
                    for (index, xmppMedia) in media.enumerated() {
                        DDLogDebug("FeedData/process-comments/new/add-comment-media [\(xmppMedia.url!)]")
                        let feedCommentMedia = NSEntityDescription.insertNewObject(forEntityName: FeedPostMedia.entity().name!, into: managedObjectContext) as! FeedPostMedia
                        switch xmppMedia.type {
                        case .image:
                            feedCommentMedia.type = .image
                        case .video:
                            feedCommentMedia.type = .video
                        case .audio:
                            feedCommentMedia.type = .audio
                        }
                        feedCommentMedia.status = .none
                        feedCommentMedia.url = xmppMedia.url
                        feedCommentMedia.size = xmppMedia.size
                        feedCommentMedia.key = xmppMedia.key
                        feedCommentMedia.order = Int16(index)
                        feedCommentMedia.sha256 = xmppMedia.sha256
                        feedCommentMedia.comment = comment
                        feedCommentMedia.blobVersion = xmppMedia.blobVersion
                        feedCommentMedia.chunkSize = xmppMedia.chunkSize
                        feedCommentMedia.blobSize = xmppMedia.blobSize
                    }
                case .voiceNote(let media):
                    comment.text = ""
                    comment.mentions = Set<FeedMention>()

                    let feedCommentMedia = FeedPostMedia(context: managedObjectContext)
                    feedCommentMedia.type = .audio
                    feedCommentMedia.status = .none
                    feedCommentMedia.url = media.url
                    feedCommentMedia.size = media.size
                    feedCommentMedia.key = media.key
                    feedCommentMedia.order = 0
                    feedCommentMedia.sha256 = media.sha256
                    feedCommentMedia.comment = comment
                case .retracted:
                    DDLogError("FeedData/process-comments/incoming-retracted-comment [\(xmppComment.id)]")
                    comment.status = .retracted
                    comment.text = ""
                case .unsupported(let data):
                    comment.status = .unsupported
                    comment.rawData = data

                    // populate text with empty string as text is required, could be removed if this changes
                    if comment.text.isEmpty {
                        comment.text = ""
                    }
                case .waiting:
                    comment.status = .rerequesting
                    if xmppComment.status != .rerequesting {
                        DDLogError("FeedData/process-comments/invalid content [\(xmppComment.id)] with status: \(xmppComment.status)")
                    }
                    comment.text = ""
                }

                comments[comment.id] = comment
                newComments.append(comment)

                // Increase unread comments counter on post.
                feedPost.unreadCount += 1
            }

            let allCommentIds = Set(comments.keys).union(ignoredCommentIds)
            xmppCommentsMutable.removeAll(where: { allCommentIds.contains($0.id) })

            // Safeguard against infinite loop.
            numRuns += 1
        }
        DDLogInfo("FeedData/process-comments/finished  \(newComments.count) new items.  \(duplicateCount) duplicates.  \(ignoredCommentIds.count) ignored.")
        save(managedObjectContext)

        try? managedObjectContext.obtainPermanentIDs(for: newComments)
        let commentObjectIDs = newComments.map { $0.objectID }
        DispatchQueue.main.async {
            let managedObjectContext = self.viewContext
            let feedPostComments = commentObjectIDs.compactMap{ try? managedObjectContext.existingObject(with: $0) as? FeedPostComment }

            // Show local notifications.
            if presentLocalNotifications && NotificationSettings.current.isCommentsEnabled {
                self.presentLocalNotifications(forComments: feedPostComments)
            }
            
            // Notify about new comments all interested parties.
            feedPostComments.forEach({ self.didReceiveFeedPostComment.send($0) })
        }

        return newComments
    }

    private func processIncomingFeedItems(_ items: [FeedElement], groupID: GroupID?, presentLocalNotifications: Bool, ack: (() -> Void)?) {
        var feedPosts = [PostData]()
        var comments = [CommentData]()
        var contactNames = [UserID:String]()

        for item in items {
            switch item {
            case .post(let post):
                feedPosts.append(post)
                post.orderedMentions.forEach {
                    guard !$0.name.isEmpty else { return }
                    contactNames[$0.userID] = $0.name
                }
            case .comment(let comment, let name):
                comments.append(comment)
                comment.orderedMentions.forEach {
                    guard !$0.name.isEmpty else { return }
                    contactNames[$0.userID] = $0.name
                }
                if let name = name, !name.isEmpty {
                    contactNames[comment.userId] = name
                }
            }
        }

        if !contactNames.isEmpty {
            contactStore.addPushNames(contactNames)
        }
        
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            let posts = self.process(posts: feedPosts, receivedIn: groupID, using: managedObjectContext, presentLocalNotifications: presentLocalNotifications)
            self.generateNotifications(for: posts, using: managedObjectContext)

            let comments = self.process(comments: comments, receivedIn: groupID, using: managedObjectContext, presentLocalNotifications: presentLocalNotifications)
            self.generateNotifications(for: comments, using: managedObjectContext)

            ack?()
        }
    }

    // MARK: Notifications

    private func notificationEvent(for post: FeedPost) -> FeedNotification.Event? {
        let selfId = userData.userId

        if post.mentions?.contains(where: { $0.userID == selfId}) ?? false {
            return .mentionPost
        }

        return nil
    }

    private func notificationEvent(for comment: FeedPostComment) -> FeedNotification.Event? {
        let selfId = userData.userId

        // This would be the person who posted comment.
        let authorId = comment.userId
        guard authorId != selfId else { return nil }

        // Someone replied to your comment.
        if comment.parent != nil && comment.parent?.userId == selfId {
            return .reply
        }
        // Someone commented on your post.
        else if comment.post.userId == selfId {
            return .comment
        }

        // Someone mentioned you in a comment
        else if comment.mentions?.contains(where: { $0.userID == selfId }) ?? false {
            return .mentionComment
        }

        // Someone commented on the post you've commented before.
        if comment.post.comments?.contains(where: { $0.userId == selfId }) ?? false {
            return .otherComment
        }

        return nil
    }

    private func generateNotifications(for posts: [FeedPost], using managedObjectContext: NSManagedObjectContext) {
        guard !posts.isEmpty else { return }

        for post in posts {
            // Step 1. Determine if post is eligible for a notification.
            guard let event = notificationEvent(for: post) else { continue }

            // Step 2. Add notification entry to the database.
            let notification = NSEntityDescription.insertNewObject(forEntityName: FeedNotification.entity().name!, into: managedObjectContext) as! FeedNotification
            notification.commentId = nil
            notification.postId = post.id
            notification.event = event
            notification.userId = post.userId
            notification.timestamp = post.timestamp
            notification.text = post.text

            var mentionSet = Set<FeedMention>()
            for postMention in post.mentions ?? [] {
                let newMention = NSEntityDescription.insertNewObject(forEntityName: FeedMention.entity().name!, into: managedObjectContext) as! FeedMention
                newMention.index = postMention.index
                newMention.userID = postMention.userID
                newMention.name = postMention.name
                mentionSet.insert(newMention)
            }
            notification.mentions = mentionSet

            if let media = post.media?.first {
                switch media.type {
                case .image:
                    notification.mediaType = .image
                case .video:
                    notification.mediaType = .video
                case .audio:
                    notification.mediaType = .audio
                }
            } else {
                notification.mediaType = .none
            }
            DDLogInfo("FeedData/generateNotifications  New notification [\(notification)]")

            // Step 3. Generate media preview for the notification.
            // TODO Nandini check if media preview needs to be updated for media comments
            self.generateMediaPreview(for: [ notification ], feedPost: post, using: managedObjectContext)
        }
        if managedObjectContext.hasChanges {
            self.save(managedObjectContext)
        }
    }

    private func generateNotifications(for comments: [FeedPostComment], using managedObjectContext: NSManagedObjectContext) {
        guard !comments.isEmpty else { return }

        for comment in comments {
            // Step 1. Determine if comment is eligible for a notification.
            guard let event = notificationEvent(for: comment) else { continue }

            // Step 2. Add notification entry to the database.
            let notification = NSEntityDescription.insertNewObject(forEntityName: FeedNotification.entity().name!, into: managedObjectContext) as! FeedNotification
            notification.commentId = comment.id
            notification.postId = comment.post.id
            notification.event = event
            notification.userId = comment.userId
            notification.timestamp = comment.timestamp
            notification.text = comment.text

            var mentionSet = Set<FeedMention>()
            for commentMention in comment.mentions ?? [] {
                let newMention = NSEntityDescription.insertNewObject(forEntityName: FeedMention.entity().name!, into: managedObjectContext) as! FeedMention
                newMention.index = commentMention.index
                newMention.userID = commentMention.userID
                newMention.name = commentMention.name
                mentionSet.insert(newMention)
            }
            notification.mentions = mentionSet

            if let media = comment.post.media?.first {
                switch media.type {
                case .image:
                    notification.mediaType = .image
                case .video:
                    notification.mediaType = .video
                case .audio:
                    notification.mediaType = .audio
                }
            } else {
                notification.mediaType = .none
            }
            DDLogInfo("FeedData/generateNotifications  New notification [\(notification)]")

            // Step 3. Generate media preview for the notification.
            self.generateMediaPreview(for: [ notification ], feedPost: comment.post, using: managedObjectContext)
        }
        if managedObjectContext.hasChanges {
            self.save(managedObjectContext)
        }
    }

    private func notifications(with predicate: NSPredicate, in managedObjectContext: NSManagedObjectContext) -> [ FeedNotification ] {
        let fetchRequest: NSFetchRequest<FeedNotification> = FeedNotification.fetchRequest()
        fetchRequest.predicate = predicate
        do {
            let results = try managedObjectContext.fetch(fetchRequest)
            return results
        }
        catch {
            DDLogError("FeedData/notifications/mark-read-all/error [\(error)]")
            fatalError("Failed to fetch notifications.")
        }
    }

    private func notifications(for postId: FeedPostID, commentId: FeedPostCommentID? = nil, in managedObjectContext: NSManagedObjectContext) -> [FeedNotification] {
        let postIdPredicate = NSPredicate(format: "postId = %@", postId)
        if commentId != nil {
            let commentIdPredicate = NSPredicate(format: "commentId = %@", commentId!)
            return self.notifications(with: NSCompoundPredicate(andPredicateWithSubpredicates: [ postIdPredicate, commentIdPredicate ]), in: managedObjectContext)
        } else {
            return self.notifications(with: postIdPredicate, in: managedObjectContext)
        }
    }

    func markNotificationsAsRead(for postId: FeedPostID? = nil) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            let notifications: [FeedNotification]
            let isNotReadPredicate = NSPredicate(format: "read = %@", NSExpression(forConstantValue: false))
            if postId != nil {
                let postIdPredicate = NSPredicate(format: "postId = %@", postId!)
                notifications = self.notifications(with: NSCompoundPredicate(andPredicateWithSubpredicates: [ isNotReadPredicate, postIdPredicate ]), in: managedObjectContext)
            } else {
                notifications = self.notifications(with: isNotReadPredicate, in: managedObjectContext)
            }
            DDLogInfo("FeedData/notifications/mark-read-all Count: \(notifications.count)")
            guard !notifications.isEmpty else { return }
            notifications.forEach {
                $0.read = true
            }
            self.save(managedObjectContext)

            UNUserNotificationCenter.current().removeDeliveredFeedNotifications(commentIds: notifications.compactMap({ $0.commentId }))
        }
    }

    // MARK: Local Notifications

    private func isCommentEligibleForLocalNotification(_ comment: FeedPostComment) -> Bool {
        let selfId = userData.userId

        // Do not notify about comments posted by user.
        if comment.userId == selfId {
            return false
        }

        // Notify when someone comments on your post.
        if comment.post.userId == selfId {
            return true
        }

        // Notify when someone replies to your comment.
        if comment.parent != nil && comment.parent?.userId == selfId {
            return true
        }

        // Notify when comment contains you as one of the mentions.
        let isUserMentioned = comment.mentions?.contains(where: { mention in
            mention.userID == selfId
        })
        if isUserMentioned == true {
            return true
        }

        // Notify group comments by contacts on group posts
        let isKnownPublisher = AppContext.shared.contactStore.contact(withUserId: comment.userId) != nil
        let isGroupComment = comment.post.groupId != nil
        if ServerProperties.isGroupCommentNotificationsEnabled  && isGroupComment && isKnownPublisher {
            return true
        }

        // Notify group comments on group posts after user has commented on it.
        let interestedPosts = AppContext.shared.userDefaults.value(forKey: AppContext.commentedGroupPostsKey) as? [FeedPostID] ?? []
        if Set(interestedPosts).contains(comment.post.id) {
            return true
        }

        // Do not notify about all other comments.
        return false
    }

    private func presentLocalNotifications(forComments comments: [FeedPostComment]) {
        // present local notifications when applicationState is either .background or .inactive
        guard UIApplication.shared.applicationState != .active else { return }

        var commentIdsToFilterOut = [FeedPostCommentID]()

        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        UNUserNotificationCenter.current().getFeedCommentIdsForDeliveredNotifications { (commentIds) in
            commentIdsToFilterOut = commentIds
            dispatchGroup.leave()
        }

        dispatchGroup.notify(queue: .main) {
            comments.filter { !commentIdsToFilterOut.contains($0.id) && self.isCommentEligibleForLocalNotification($0) }.forEach { (comment) in
                let protobufData = try? comment.commentData.clientContainer.serializedData()
                let contentType: NotificationContentType = comment.post.groupId == nil ? .feedComment : .groupFeedComment
                let metadata = NotificationMetadata(contentId: comment.id,
                                                    contentType: contentType,
                                                    fromId: comment.userId,
                                                    timestamp: comment.timestamp,
                                                    data: protobufData,
                                                    messageId: nil)
                metadata.postId = comment.post.id
                metadata.parentId = comment.parent?.id
                if let groupId = comment.post.groupId,
                   let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                    metadata.groupId = group.groupId
                    metadata.groupName = group.name
                }
                // create and add a notification to the notification center.
                NotificationRequest.createAndShow(from: metadata)
            }
        }
    }

    private func presentLocalNotifications(forFeedPosts feedPosts: [FeedPost]) {
        // present local notifications when applicationState is either .background or .inactive
        guard UIApplication.shared.applicationState != .active else { return }
        var postIdsToFilterOut = [FeedPostID]()

        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        UNUserNotificationCenter.current().getFeedPostIdsForDeliveredNotifications { (feedPostIds) in
            postIdsToFilterOut = feedPostIds
            dispatchGroup.leave()
        }

        dispatchGroup.notify(queue: .main) {
            feedPosts.filter({ !postIdsToFilterOut.contains($0.id) }).forEach { (feedPost) in
                let protoContainer = feedPost.postData.clientContainer
                let protobufData = try? protoContainer.serializedData()
                let metadataContentType: NotificationContentType = feedPost.groupId == nil ? .feedPost : .groupFeedPost
                let metadata = NotificationMetadata(contentId: feedPost.id,
                                                    contentType: metadataContentType,
                                                    fromId: feedPost.userId,
                                                    timestamp: feedPost.timestamp,
                                                    data: protobufData,
                                                    messageId: nil)
                if let groupId = feedPost.groupId,
                   let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                    metadata.groupId = group.groupId
                    metadata.groupName = group.name
                }
                // create and add a notification to the notification center.
                NotificationRequest.createAndShow(from: metadata)
            }
        }
    }

    // MARK: Retracts
    
    let didProcessGroupFeedPostRetract = PassthroughSubject<FeedPostID, Never>()

    private func processPostRetract(_ postId: FeedPostID, completion: @escaping () -> Void) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

            guard let feedPost = self.feedPost(with: postId, in: managedObjectContext, archived: true) else {
                DDLogError("FeedData/retract-post/error Missing post. [\(postId)]")
                completion()
                return
            }
            guard feedPost.status != .retracted  else {
                DDLogError("FeedData/retract-post/error Already retracted. [\(postId)]")
                completion()
                return
            }
            DDLogInfo("FeedData/retract-post [\(postId)]/begin")

            // 1. Delete media.
            self.deleteMedia(feedPost: feedPost)

            // 2. Delete comments.
            feedPost.comments?.forEach {
                // Delete media comments if any
                self.deleteMedia(feedPostComment: $0)
                managedObjectContext.delete($0)
            }

            // 3. Delete all notifications for this post.
            let notifications = self.notifications(for: postId, in: managedObjectContext)
            notifications.forEach { managedObjectContext.delete($0)}

            // 4. Reset post data and mark post as deleted.
            feedPost.text = nil
            feedPost.status = .retracted

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
            DDLogInfo("FeedData/retract-post [\(postId)]/done")

            if feedPost.groupId != nil {
                self.didProcessGroupFeedPostRetract.send(feedPost.id)
            }
            
            self.checkForUnreadFeed()
            
            completion()
        }
    }

    private func processCommentRetract(_ commentId: FeedPostCommentID, completion: @escaping () -> Void) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let feedComment = self.feedComment(with: commentId, in: managedObjectContext) else {
                DDLogError("FeedData/retract-comment/error Missing comment. [\(commentId)]")
                completion()
                return
            }
            guard feedComment.status != .retracted else {
                DDLogError("FeedData/retract-comment/error Already retracted. [\(commentId)]")
                completion()
                return
            }
            DDLogInfo("FeedData/retract-comment [\(commentId)]")

            // 1. Reset comment text and mark comment as deleted.
            // TBD: should replies be deleted too?
            feedComment.text = ""
            feedComment.status = .retracted

            // 2. Delete comment media
            self.deleteMedia(feedPostComment: feedComment)

            // 3. Reset comment text copied over to notifications.
            let notifications = self.notifications(for: feedComment.post.id, commentId: feedComment.id, in: managedObjectContext)
            notifications.forEach { (notification) in
                notification.event = .retractedComment
                notification.text = nil
            }

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }

            completion()
        }
    }

    private func processIncomingFeedRetracts(_ retracts: [FeedRetract], groupID: GroupID?, ack: (() -> Void)?) {
        let processingGroup = DispatchGroup()
        for retract in retracts {
            switch retract {
            case .post(let postID):
                processingGroup.enter()
                processPostRetract(postID) {
                    processingGroup.leave()
                }
            case .comment(let commentID):
                processingGroup.enter()
                processCommentRetract(commentID) {
                    processingGroup.leave()
                }
            }
        }

        ack?()
    }

    func retract(post feedPost: FeedPost, completion: ((Result<Void, Error>) -> Void)? = nil) {
        let postId = feedPost.id
        DDLogInfo("FeedData/retract/postId \(feedPost.id), status: \(feedPost.status)")

        let deletePost: () -> Void = { [weak self] in
            guard let self = self else {
                completion?(.failure(RequestError.malformedRequest))
                return
            }
            switch feedPost.status {

            // these errors mean that server does not have a copy of the post.
            // so we need send retract request to the server - just delete the local copy.
            // Think more on how sending status should be handled here??
            case .none, .sendError:
                DDLogInfo("FeedData/retract/postId \(feedPost.id), delete local copy.")
                self.processPostRetract(postId) {
                    completion?(.success(()))
                }

            // own posts or pending retract posts.
            // .seen is the status for posts reshared after reinstall.
            // This will go away soon once we have e2e everywhere.
            // TODO: why are we marking own posts as seen anyways?
            case .sent, .retracting, .seen:
                DDLogInfo("FeedData/retract/postId \(feedPost.id), sending retract request")
                // Mark post as "being retracted"
                feedPost.status = .retracting
                self.save(self.viewContext)

                // Request to retract.
                self.service.retractPost(feedPost.id, in: feedPost.groupId) { result in
                    switch result {
                    case .success:
                        DDLogInfo("FeedData/retract/postId \(feedPost.id), retract request was successful")
                        self.processPostRetract(postId) {
                            completion?(.success(()))
                        }
                    case .failure(let error):
                        DDLogError("FeedData/retract/postId \(feedPost.id), retract request failed")
                        self.updateFeedPost(with: postId) { (post) in
                            post.status = .sent
                            completion?(.failure(error))
                        }
                    }
                }

            // everything else.
            default:
                DDLogError("FeedData/retract/postId \(feedPost.id) unexpected retract request here: \(feedPost.status)")
                completion?(.failure(RequestError.malformedRequest))
            }
        }

        if self.externalShareInfo(for: postId) != nil {
            self.revokeExternalShareUrl(for: postId) { result in
                switch result {
                case .success:
                    deletePost()
                case .failure(let error):
                    completion?(.failure(error))
                }
            }
        } else {
            deletePost()
        }
    }

    func retract(comment: FeedPostComment) {
        let commentId = comment.id

        // Mark comment as "being retracted".
        comment.status = .retracting
        save(viewContext)

        // Request to retract.
        service.retractComment(id: comment.id, postID: comment.post.id, in: comment.post.groupId) { result in
            switch result {
            case .success:
                self.processCommentRetract(commentId) {}

            case .failure(_):
                self.updateFeedPostComment(with: commentId) { (comment) in
                    comment.status = .sent
                }
            }
        }
    }

    // MARK: Read Receipts

    private func resendPendingReadReceipts() {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let feedPosts = self.feedPosts(predicate: NSPredicate(format: "statusValue == %d", FeedPost.Status.seenSending.rawValue), in: managedObjectContext)
            guard !feedPosts.isEmpty else { return }
            DDLogInfo("FeedData/seen-receipt/resend count=[\(feedPosts.count)]")
            feedPosts.forEach { (feedPost) in
                self.internalSendSeenReceipt(for: feedPost)
            }

            self.save(managedObjectContext)
        }
    }

    private func internalSendSeenReceipt(for feedPost: FeedPost) {
        // Make sure the post is still in a valid state and wasn't retracted just now.
        // We dont send seen receipts until decryption is successful?
        // TODO: murali@: fix this up eventually and test properly!
        guard feedPost.status == .incoming || feedPost.status == .seenSending || feedPost.status == .rerequesting else {
            DDLogWarn("FeedData/seen-receipt/ignore Incorrect post status: \(feedPost.status)")
            return
        }
        guard !feedPost.isWaiting else {
            DDLogWarn("FeedData/seen-receipt/ignore post content is empty: \(feedPost.status)")
            return
        }
        // Send seen receipts for now - but dont update status.
        if !feedPost.isRerequested {
            feedPost.status = .seenSending
        }
        service.sendReceipt(itemID: feedPost.id, thread: .feed, type: .read, fromUserID: userData.userId, toUserID: feedPost.userId)
    }

    func sendSeenReceiptIfNecessary(for feedPost: FeedPost) {
        guard feedPost.status == .incoming || feedPost.status == .rerequesting else { return }

        let postId = feedPost.id
        updateFeedPost(with: postId) { [weak self] (post) in
            guard let self = self else { return }
            // Check status again in case one of these blocks was already queued
            guard post.status == .incoming || feedPost.status == .rerequesting else { return }
            self.internalSendSeenReceipt(for: post)
            self.checkForUnreadFeed()
        }
    }

    func seenReceipts(for feedPost: FeedPost) -> [FeedPostReceipt] {
        guard let seenReceipts = feedPost.info?.receipts else {
            return []
        }

        let contacts = contactStore.contacts(withUserIds: Array(seenReceipts.keys))
        let contactsMap = contacts.reduce(into: [UserID: ABContact]()) { (map, contact) in
            if let userID = contact.userId {
                map[userID] = contact
            }
        }

        var receipts = [FeedPostReceipt]()
        for (userId, receipt) in seenReceipts {
            guard let seenDate = receipt.seenDate else { continue }

            var contactName: String?, phoneNumber: String?
            if let contact = contactsMap[userId] {
                contactName = contact.fullName
                phoneNumber = contact.phoneNumber?.formattedPhoneNumber
            }
            if contactName == nil {
                contactName = contactStore.fullName(for: userId)
            }
            receipts.append(FeedPostReceipt(userId: userId, type: .seen, contactName: contactName!, phoneNumber: phoneNumber, timestamp: seenDate))
        }
        receipts.sort(by: { $0.timestamp > $1.timestamp })

        return receipts
    }

    let didGetUnreadFeedCount = PassthroughSubject<Int, Never>()
    
    func checkForUnreadFeed() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let predicate = NSPredicate(format: "statusValue = %d", FeedPost.Status.incoming.rawValue)
            let unreadFeedPosts = self.feedPosts(predicate: predicate, in: managedObjectContext)
            self.didGetUnreadFeedCount.send(unreadFeedPosts.count)
        }
    }
    
    // MARK: Feed Media

    func media(for post: FeedPost) -> [FeedMedia] {
        if let cachedMedia = cachedMedia[post.id] {
            return cachedMedia
        } else {
            let media = (post.media ?? []).sorted(by: { $0.order < $1.order }).map{ FeedMedia($0) }
            cachedMedia[post.id] = media
            return media
        }
    }

    func media(postID: FeedPostID) -> [FeedMedia]? {
        if let cachedMedia = cachedMedia[postID] {
            return cachedMedia
        } else if let post = MainAppContext.shared.feedData.feedPost(with: postID) {
            return media(for: post)
        } else {
            return nil
        }
    }
    
    func media(for comment: FeedPostComment) -> [FeedMedia] {
        if let cachedMedia = cachedMedia[comment.id] {
            return cachedMedia
        } else {
            let media = (comment.media ?? []).sorted(by: { $0.order < $1.order }).map{ FeedMedia($0) }
            cachedMedia[comment.id] = media
            return media
        }
    }

    func media(commentID: FeedPostCommentID) -> [FeedMedia]? {
        if let cachedMedia = cachedMedia[commentID] {
            return cachedMedia
        } else if let comment = MainAppContext.shared.feedData.feedComment(with: commentID) {
            let media = (comment.media ?? []).sorted(by: { $0.order < $1.order }).map{ FeedMedia($0) }
            cachedMedia[commentID] = media
            return media
        } else {
            return nil
        }
    }

    func media(feedLinkPreviewID: FeedLinkPreviewID) -> [FeedMedia]? {
        if let cachedMedia = cachedMedia[feedLinkPreviewID] {
            return cachedMedia
        } else if let linkPreview = MainAppContext.shared.feedData.feedLinkPreview(with: feedLinkPreviewID) {
            let media = (linkPreview.media ?? []).sorted(by: { $0.order < $1.order }).map{ FeedMedia($0) }
            cachedMedia[feedLinkPreviewID] = media
            return media
        } else {
            return nil
        }
    }

    func loadImages(postID: FeedPostID) {
        guard let media = media(postID: postID) else {
            return
        }
        media.forEach { $0.loadImage() }
    }
    
    func loadImages(commentID: FeedPostCommentID) {
        guard let media = media(commentID: commentID) else {
            return
        }
        media.forEach { $0.loadImage() }
    }

    func loadImages(feedLinkPreviewID: FeedLinkPreviewID) {
        guard let media = media(feedLinkPreviewID: feedLinkPreviewID) else {
            return
        }
        media.forEach { $0.loadImage() }
    }

    // TODO: Refactor FeedMedia to allow unloading images from memory (for now we can't clear cache)
    private var cachedMedia = [FeedPostID: [FeedMedia]]()

    func downloadTask(for mediaItem: FeedMedia) -> FeedDownloadManager.Task? {
        switch mediaItem.feedElementId {
        case .post(let postId):
            guard let feedPost = feedPost(with: postId) else { return nil }
            guard let feedPostMedia = feedPost.media?.first(where: { $0.order == mediaItem.order }) else { return nil }
            return downloadManager.currentTask(for: feedPostMedia)
        case .comment(let commentId):
            guard let feedComment = feedComment(with: commentId) else { return nil }
            guard let feedPostCommentMedia = feedComment.media?.first(where: { $0.order == mediaItem.order }) else { return nil }
            return downloadManager.currentTask(for: feedPostCommentMedia)
        case .linkPreview(let linkPreviewId):
            guard let feedLinkPreview = feedLinkPreview(with: linkPreviewId) else { return nil }
            guard let feedLinkPreviewMedia = feedLinkPreview.media?.first(where: { $0.order == mediaItem.order }) else { return nil }
            return downloadManager.currentTask(for: feedLinkPreviewMedia)
        case .none:
            return nil
        }
    }

    // MARK: Suspending and Resuming

    func suspendMediaDownloads() {
        downloadManager.suspendMediaDownloads()
    }

    // We resume media downloads for all these objects on Application/WillEnterForeground.
    func resumeMediaDownloads() {
        var pendingPostIds: Set<FeedPostID> = []
        var pendingCommentIds: Set<FeedPostCommentID> = []
        // Iterate through all the suspendedMediaObjectIds and download media for those posts.
        downloadManager.suspendedMediaObjectIds.forEach { feedMediaObjectId in
            // Fetch FeedPostMedia
            guard let feedPostMedia = try? viewContext.existingObject(with: feedMediaObjectId) as? FeedPostMedia else {
                DDLogError("FeedData/resumeMediaDownloads/error missing-object [\(feedMediaObjectId)]")
                return
            }
            if let feedPost = feedPostMedia.post {
                DDLogInfo("FeedData/resumeMediaDownloads/pendingPostId/added post_id - \(feedPost.id)")
                pendingPostIds.insert(feedPost.id)
            }
            if let feedComment = feedPostMedia.comment {
                DDLogInfo("FeedData/resumeMediaDownloads/pendingCommentId/added comment_id - \(feedComment.id)")
                pendingCommentIds.insert(feedComment.id)
            }
        }
        downloadManager.suspendedMediaObjectIds.removeAll()
        // Download media for all these posts and comments
        downloadMedia(in: feedPosts(with: pendingPostIds))
        downloadMedia(in: feedComments(with: pendingCommentIds))
    }

    func downloadMedia(in feedPosts: [FeedPost]) {
        guard !feedPosts.isEmpty else { return }

        let feedPostObjectIds = feedPosts.map(\.objectID)
        performSeriallyOnBackgroundContext { [weak self] context in
            guard let self = self else { return }
            let feedPosts = feedPostObjectIds.compactMap { try? context.existingObject(with: $0) as? FeedPost }

            // List of mediaItem info that will need UI update.
            var mediaItems = [(FeedPostID, Int)]()
            var downloadStarted = false
            feedPosts.forEach { feedPost in
                DDLogInfo("FeedData/downloadMedia/post_id - \(feedPost.id)")
                let postDownloadGroup = DispatchGroup()
                var startTime: Date?
                var photosDownloaded = 0
                var videosDownloaded = 0
                var audiosDownloaded = 0
                var totalDownloadSize = 0

                feedPost.media?.forEach { feedPostMedia in
                    // Status could be "downloading" if download has previously started
                    // but the app was terminated before the download has finished.
                    guard feedPostMedia.url != nil, [.none, .downloading, .downloadError].contains(feedPostMedia.status) else {
                        return
                    }
                    let (taskAdded, task) = self.downloadManager.downloadMedia(for: feedPostMedia)
                    if taskAdded {
                        switch feedPostMedia.type {
                        case .image: photosDownloaded += 1
                        case .video: videosDownloaded += 1
                        case .audio: audiosDownloaded += 1
                        }
                        if startTime == nil {
                            startTime = Date()
                            DDLogInfo("FeedData/downloadMedia/post/\(feedPost.id)/starting")
                        }
                        postDownloadGroup.enter()
                        var isDownloadInProgress = true
                        self.cancellableSet.insert(task.downloadProgress.sink() { progress in
                            if isDownloadInProgress && progress == 1 {
                                totalDownloadSize += task.fileSize ?? 0
                                isDownloadInProgress = false
                                postDownloadGroup.leave()
                            }
                        })

                        task.feedMediaObjectId = feedPostMedia.objectID
                        feedPostMedia.status = .downloading
                        downloadStarted = true
                        // Add the mediaItem to a list - so that we can reload and update their UI.
                        mediaItems.append((feedPost.id, Int(feedPostMedia.order)))
                    }
                }
                feedPost.linkPreviews?.forEach { linkPreview in
                    linkPreview.media?.forEach { linkPreviewMedia in
                        guard linkPreviewMedia.url != nil, [.none, .downloading, .downloadError].contains(linkPreviewMedia.status) else {
                            return
                        }
                        let (taskAdded, task) = self.downloadManager.downloadMedia(for: linkPreviewMedia)
                        if taskAdded {
                            switch linkPreviewMedia.type {
                            case .image: photosDownloaded += 1
                            case .video: videosDownloaded += 1
                            case .audio: audiosDownloaded += 1
                            }
                            if startTime == nil {
                                startTime = Date()
                                DDLogInfo("FeedData/downloadMedia/post/linkPreview/post: \(feedPost.id)/link: \(String(describing: linkPreview.url)) starting")
                            }
                            postDownloadGroup.enter()
                            var isDownloadInProgress = true
                            self.cancellableSet.insert(task.downloadProgress.sink() { progress in
                                if isDownloadInProgress && progress == 1 {
                                    totalDownloadSize += task.fileSize ?? 0
                                    isDownloadInProgress = false
                                    postDownloadGroup.leave()
                                }
                            })

                            task.feedMediaObjectId = linkPreviewMedia.objectID
                            linkPreviewMedia.status = .downloading
                            downloadStarted = true
                            // Add the mediaItem to a list - so that we can reload and update their UI.
                            mediaItems.append((feedPost.id, Int(linkPreviewMedia.order)))
                        }
                    }
                }
                postDownloadGroup.notify(queue: .main) {
                    guard photosDownloaded > 0 || videosDownloaded > 0 else { return }
                    guard let startTime = startTime else {
                        DDLogError("FeedData/downloadMedia/post/\(feedPost.id)/error start time not set")
                        return
                    }
                    let duration = Date().timeIntervalSince(startTime)
                    DDLogInfo("FeedData/downloadMedia/post/\(feedPost.id)/finished [photos: \(photosDownloaded)] [videos: \(videosDownloaded)] [t: \(duration)] [bytes: \(totalDownloadSize)]")
                    AppContext.shared.eventMonitor.observe(
                        .mediaDownload(
                            postID: feedPost.id,
                            duration: duration,
                            numPhotos: photosDownloaded,
                            numVideos: videosDownloaded,
                            totalSize: totalDownloadSize))
                }
            }
            // Use `downloadStarted` to prevent recursive saves when posting media.
            if context.hasChanges && downloadStarted {
                self.save(context)

                // Update UI for these items.
                DispatchQueue.main.async {
                    mediaItems.forEach{ (feedPostId, order) in
                        self.reloadMedia(feedPostId: feedPostId, order: order)
                    }
                }
            }
        }
    }
    
    
    func downloadMedia(in feedPostComments: [FeedPostComment]) {
        guard !feedPostComments.isEmpty else { return }

        let feedPostCommentObjectIds = feedPostComments.map(\.objectID)
        performSeriallyOnBackgroundContext { [weak self] context in
            guard let self = self else { return }
            let feedPostComments = feedPostCommentObjectIds.compactMap { try? context.existingObject(with: $0) as? FeedPostComment }

            // List of comment mediaItems that will need UI update.
            var mediaItemsToReload = [(FeedPostCommentID, Int)]()
            var downloadStarted = false
            feedPostComments.forEach { feedComment in
                if let commentMedia = feedComment.media {
                    commentMedia.forEach { media in
                        DDLogInfo("FeedData/downloadMedia/comment/_id - \(feedComment.id)")
                        let commentMediaDownloadGroup = DispatchGroup()
                        var startTime: Date?
                        var photosDownloaded = 0
                        var videosDownloaded = 0
                        var audiosDownloaded = 0
                        var totalDownloadSize = 0

                        if media.url != nil, [.none, .downloading, .downloadError].contains(media.status) {
                            let(taskAdded, task) = self.downloadManager.downloadMedia(for: media)
                            if taskAdded {
                                switch media.type
                                {
                                case .image: photosDownloaded += 1
                                case .video: videosDownloaded += 1
                                case .audio: audiosDownloaded += 1
                                }
                                if startTime == nil {
                                    startTime = Date()
                                    DDLogInfo("FeedData/downloadMedia/comment/\(feedComment.id)/starting")
                                }
                                commentMediaDownloadGroup.enter()
                                var isDownloadInProgress = true
                                self.cancellableSet.insert(task.downloadProgress.sink() { progress in
                                    if isDownloadInProgress && progress == 1 {
                                        totalDownloadSize += task.fileSize ?? 0
                                        isDownloadInProgress = false
                                        commentMediaDownloadGroup.leave()
                                    }
                                })

                                task.feedMediaObjectId = media.objectID
                                media.status = .downloading
                                downloadStarted = true
                                // Add the mediaItem to a list - so that we can reload and update their UI.
                                mediaItemsToReload.append((feedComment.id, 0))
                            }
                        }
                        commentMediaDownloadGroup.notify(queue: .main) {
                            guard photosDownloaded > 0 || videosDownloaded > 0 || audiosDownloaded > 0 else { return }
                            guard let startTime = startTime else {
                                DDLogError("FeedData/downloadMedia/comment/\(feedComment.id)/error start time not set")
                                return
                            }
                            let duration = Date().timeIntervalSince(startTime)
                            DDLogInfo("FeedData/downloadMedia/comment/\(feedComment.id)/finished [photos: \(photosDownloaded)] [videos: \(videosDownloaded)] [audios: \(audiosDownloaded)] [t: \(duration)] [bytes: \(totalDownloadSize)]")
                            // TODO Nandini investigate if below commented code is required for media comments
        //                        AppContext.shared.eventMonitor.observe(
        //                            .mediaDownload(
        //                                postID: feedPost.id,
        //                                commentId: feedComment.id,
        //                                duration: duration,
        //                                numPhotos: photosDownloaded,
        //                                numVideos: videosDownloaded,
        //                                totalSize: totalDownloadSize))
                        }
                    }
                }
                feedComment.linkPreviews?.forEach { linkPreview in
                    linkPreview.media?.forEach { linkPreviewMedia in
                        guard linkPreviewMedia.url != nil, [.none, .downloading, .downloadError].contains(linkPreviewMedia.status) else {
                            return
                        }
                        let (taskAdded, task) = self.downloadManager.downloadMedia(for: linkPreviewMedia)
                        if taskAdded {
                            task.feedMediaObjectId = linkPreviewMedia.objectID
                            linkPreviewMedia.status = .downloading
                            downloadStarted = true
                        }
                    }
                }
            }
            // Use `downloadStarted` to prevent recursive saves when posting media.
            if context.hasChanges && downloadStarted {
                self.save(context)

                // Update UI for these items.
                // TODO Nandini investigate if below code is required
                DispatchQueue.main.async {
                    mediaItemsToReload.forEach{ (feedCommentId, order) in
                        self.reloadMedia(feedCommentID: feedCommentId, order: order)
                    }
                }
            }
        }
    }

    func reloadMedia(feedPostId: FeedPostID, order: Int) {
        DDLogInfo("FeedData/reloadMedia/postId:\(feedPostId), order/\(order)")
        guard let coreDataPost = feedPost(with: feedPostId),
              let coreDataMedia = coreDataPost.media?.first(where: { $0.order == order }),
              let cachedMedia = media(postID: feedPostId)?.first(where: { $0.order == order }) else
        {
            return
        }
        DDLogInfo("FeedData/reloadMedia/postID: cache reload")
        cachedMedia.reload(from: coreDataMedia)
    }

    func reloadMedia(feedCommentID: FeedPostCommentID, order: Int) {
        DDLogInfo("FeedData/reloadMedia/commentId:\(feedCommentID), order/\(order)")
        guard let coreDataComment = feedComment(with: feedCommentID),
              let coreDataMedia = coreDataComment.media?.first(where: { $0.order == order }),
              let cachedMedia = media(commentID: feedCommentID)?.first(where: { $0.order == order }) else
        {
            DDLogInfo("FeedData/reloadMedia/commentId: \(feedCommentID) not reloading media cache")
            return
        }
        DDLogInfo("FeedData/reloadMedia/commentId: \(feedCommentID) cache reload")
        cachedMedia.reload(from: coreDataMedia)
    }

    func reloadMedia(feedLinkPreviewID: FeedLinkPreviewID, order: Int) {
        DDLogInfo("FeedData/reloadMedia/feedLinkPreviewID:\(feedLinkPreviewID), order/\(order)")
        guard let feedLinkPreview = feedLinkPreview(with: feedLinkPreviewID),
              let coreDataMedia = feedLinkPreview.media?.first(where: { $0.order == order }),
              let cachedMedia = media(feedLinkPreviewID: feedLinkPreviewID)?.first(where: { $0.order == order }) else
        {
            DDLogInfo("FeedData/reloadMedia/feedLinkPreviewID: \(feedLinkPreviewID) not reloading media cache")
            return
        }
        DDLogInfo("FeedData/reloadMedia/feedLinkPreviewID: \(feedLinkPreviewID) cache reload")
        cachedMedia.reload(from: coreDataMedia)
    }

    func feedDownloadManager(_ manager: FeedDownloadManager, didFinishTask task: FeedDownloadManager.Task) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            // Step 1: Update FeedPostMedia
            guard let objectID = task.feedMediaObjectId, let feedPostMedia = try? managedObjectContext.existingObject(with: objectID) as? FeedPostMedia else {
                DDLogError("FeedData/download-task/\(task.id)/error  Missing FeedPostMedia  taskId=[\(task.id)]  objectId=[\(task.feedMediaObjectId?.uriRepresentation().absoluteString ?? "nil")))]")
                return
            }

            guard feedPostMedia.relativeFilePath == nil else {
                DDLogError("FeedData/download-task/\(task.id)/error File already exists media=[\(feedPostMedia)]")
                return
            }

            if task.error == nil {
                DDLogInfo("FeedData/download-task/\(task.id)/complete [\(task.decryptedFilePath!)]")
                feedPostMedia.status = .downloaded
                feedPostMedia.relativeFilePath = task.decryptedFilePath
            } else {
                DDLogError("FeedData/download-task/\(task.id)/error [\(task.error!)]")
                feedPostMedia.status = .downloadError

                // TODO: Do an exponential backoff on the client for 1 day and then show a manual retry button for the user.
                // Mark as permanent failure if we encounter hashMismatch or MACMismatch.
                switch task.error {
                case .macMismatch, .hashMismatch, .decryptionFailed:
                    DDLogInfo("FeedData/download-task/\(task.id)/error [\(task.error!) - fail permanently]")
                    feedPostMedia.status = .downloadFailure
                default:
                    break
                }
            }

            self.save(managedObjectContext)

            // Step 2: Update media preview for all notifications for the given post.
            if feedPostMedia.status == .downloaded && feedPostMedia.order == 0 {
                self.updateNotificationMediaPreview(with: feedPostMedia, using: managedObjectContext)
                if managedObjectContext.hasChanges {
                    self.save(managedObjectContext)
                }
            }

            // Step 3: Notify UI about finished download.
            if let  feedPost = feedPostMedia.post {
                let feedPostId = feedPost.id
                let mediaOrder = Int(feedPostMedia.order)
                DispatchQueue.main.async {
                    self.reloadMedia(feedPostId: feedPostId, order: mediaOrder)
                }
            }
            else if let  feedComment = feedPostMedia.comment {
                let feedCommentId = feedComment.id
                let mediaOrder = Int(feedPostMedia.order)
                DispatchQueue.main.async {
                    self.reloadMedia(feedCommentID: feedCommentId, order: mediaOrder)
                }
            }
            else if let feedLinkPreview = feedPostMedia.linkPreview {
                let feedLinkPreviewId = feedLinkPreview.id
                let mediaOrder = Int(feedPostMedia.order)
                DispatchQueue.main.async {
                    self.reloadMedia(feedLinkPreviewID: feedLinkPreviewId, order: mediaOrder)
                }
            }
            // Step 4: Update upload data to avoid duplicate uploads
            // TODO Nandini : check this for comment media
            if let path = feedPostMedia.relativeFilePath, let downloadUrl = feedPostMedia.url {
                let fileUrl = MainAppContext.mediaDirectoryURL.appendingPathComponent(path, isDirectory: false)
                MainAppContext.shared.mediaHashStore.update(url: fileUrl, blobVersion: feedPostMedia.blobVersion, key: feedPostMedia.key, sha256: feedPostMedia.sha256, downloadURL: downloadUrl)
            }
        }
    }

    private func updateNotificationMediaPreview(with postMedia: FeedPostMedia, using managedObjectContext: NSManagedObjectContext) {
        guard postMedia.relativeFilePath != nil else { return }
        if let feedPost = postMedia.post {
            let feedPostId = feedPost.id

            // Fetch all associated notifications.
            let fetchRequest: NSFetchRequest<FeedNotification> = FeedNotification.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "postId == %@", feedPostId)
            do {
                let notifications = try managedObjectContext.fetch(fetchRequest)
                if !notifications.isEmpty {
                    generateMediaPreview(for: notifications, feedPost: feedPost, using: managedObjectContext)
                }
            }
            catch {
                DDLogError("FeedData/fetch-notifications/error  [\(error)]")
                fatalError("Failed to fetch feed notifications.")
            }
        }
        // TODO Nandini : handle this for feedComment = postMedia.comment
    }

    private func generateMediaPreview(for notifications: [FeedNotification], feedPost: FeedPost, using managedObjectContext: NSManagedObjectContext) {
        guard let postMedia = feedPost.orderedMedia.first as? FeedPostMedia else { return }
        guard let mediaPath = postMedia.relativeFilePath else { return }

        DDLogInfo("FeedData/generateMediaPreview/feedPost \(feedPost.id), mediaType: \(postMedia.type)")
        let mediaURL = MainAppContext.mediaDirectoryURL.appendingPathComponent(mediaPath, isDirectory: false)
        switch postMedia.type {
        case .image:
            self.updateMediaPreview(for: notifications, usingImageAt: mediaURL)
        case .video:
            if let image = VideoUtils.videoPreviewImage(url: mediaURL) {
                updateMediaPreview(for: notifications, using: image)
            } else {
                DDLogError("FeedData/generateMediaPreview/error")
                return
            }
        case .audio:
            break
        }
    }

    private func updateMediaPreview(for notifications: [FeedNotification], usingImageAt url: URL) {
        guard let image = UIImage(contentsOfFile: url.path) else {
            DDLogError("FeedData/notification/preview/error  Failed to load image at [\(url)]")
            return
        }
        updateMediaPreview(for: notifications, using: image)
    }

    private func updateMediaPreview(for notifications: [FeedNotification], using image: UIImage) {
        guard let preview = image.resized(to: CGSize(width: 128, height: 128), contentMode: .scaleAspectFill, downscaleOnly: false) else {
            DDLogError("FeedData/notification/preview/error  Failed to generate preview for notifications: \(notifications)")
            return
        }
        guard let imageData = preview.jpegData(compressionQuality: 0.5) else {
            DDLogError("FeedData/notification/preview/error  Failed to generate PNG for notifications: \(notifications)")
            return
        }
        notifications.forEach { $0.mediaPreview = imageData }
    }

    // MARK: Posting
    
    let didSendGroupFeedPost = PassthroughSubject<FeedPost, Never>()

    func post(text: MentionText, media: [PendingMedia], linkPreviewData: LinkPreviewData?, linkPreviewMedia : PendingMedia?, to destination: FeedPostDestination) {
        let postId: FeedPostID = PacketID.generate()

        // Create and save new FeedPost object.
        let managedObjectContext = persistentContainer.viewContext
        DDLogDebug("FeedData/new-post/create [\(postId)]")
        let feedPost = NSEntityDescription.insertNewObject(forEntityName: FeedPost.entity().name!, into: managedObjectContext) as! FeedPost
        feedPost.id = postId
        feedPost.userId = AppContext.shared.userData.userId
        if case .groupFeed(let groupId) = destination {
            feedPost.groupId = groupId
        }
        feedPost.text = text.collapsedText
        feedPost.status = .sending
        feedPost.timestamp = Date()

        // Add mentions
        var mentionSet = Set<FeedMention>()
        for (index, user) in text.mentions {
            let feedMention = NSEntityDescription.insertNewObject(forEntityName: FeedMention.entity().name!, into: managedObjectContext) as! FeedMention
            feedMention.index = index
            feedMention.userID = user.userID
            feedMention.name = contactStore.pushNames[user.userID] ?? user.pushName ?? ""
            if feedMention.name == "" {
                DDLogError("FeedData/new-post/mention/\(user.userID) missing push name")
            }
            mentionSet.insert(feedMention)
        }
        feedPost.mentions = mentionSet

        let shouldStreamFeedVideo = ServerProperties.streamingSendingEnabled && ChunkedMediaTestConstants.STREAMING_FEED_GROUP_IDS.contains(feedPost.groupId ?? "")

        // Add post media.
        for (index, mediaItem) in media.enumerated() {
            DDLogDebug("FeedData/new-post/add-media [\(mediaItem.fileURL!)]")
            let feedMedia = NSEntityDescription.insertNewObject(forEntityName: FeedPostMedia.entity().name!, into: managedObjectContext) as! FeedPostMedia
            feedMedia.type = mediaItem.type
            feedMedia.status = .uploading
            feedMedia.url = mediaItem.url
            feedMedia.size = mediaItem.size!
            feedMedia.key = ""
            feedMedia.sha256 = ""
            feedMedia.order = Int16(index)
            feedMedia.blobVersion = (mediaItem.type == .video && shouldStreamFeedVideo) ? .chunked : .default
            feedMedia.post = feedPost

            if let url = mediaItem.fileURL {
                ImageServer.shared.attach(for: url, id: postId, index: index)
            }

            // Copying depends on all data fields being set, so do this last.
            do {
                try downloadManager.copyMedia(from: mediaItem, to: feedMedia)
            }
            catch {
                DDLogError("FeedData/new-post/copy-media/error [\(error)]")
            }
        }

        // Add feed link preview if any
        var linkPreview: FeedLinkPreview?
        if let linkPreviewData = linkPreviewData {
            linkPreview = FeedLinkPreview(context: managedObjectContext)
            linkPreview?.id = PacketID.generate()
            linkPreview?.url = linkPreviewData.url
            linkPreview?.title = linkPreviewData.title
            linkPreview?.desc = linkPreviewData.description
            // Set preview image if present
            if let linkPreviewMedia = linkPreviewMedia {
                let previewMedia = NSEntityDescription.insertNewObject(forEntityName: FeedPostMedia.entity().name!, into: managedObjectContext) as! FeedPostMedia
                previewMedia.type = linkPreviewMedia.type
                previewMedia.status = .uploading
                previewMedia.url = linkPreviewMedia.url
                previewMedia.size = linkPreviewMedia.size!
                previewMedia.key = ""
                previewMedia.sha256 = ""
                previewMedia.order = 0
                previewMedia.linkPreview = linkPreview

                // Copying depends on all data fields being set, so do this last.
                do {
                    try downloadManager.copyMedia(from: linkPreviewMedia, to: previewMedia)
                }
                catch {
                    DDLogError("FeedData/new-post/copy-likePreviewmedia/error [\(error)]")
                }
            }
            linkPreview?.post = feedPost
        }

        switch destination {
        case .userFeed:
            let feedPostInfo = NSEntityDescription.insertNewObject(forEntityName: FeedPostInfo.entity().name!, into: managedObjectContext) as! FeedPostInfo
            let postAudience = try! MainAppContext.shared.privacySettings.currentFeedAudience()
            let receipts = postAudience.userIds.reduce(into: [UserID : Receipt]()) { (receipts, userId) in
                receipts[userId] = Receipt()
            }
            feedPostInfo.receipts = receipts
            feedPostInfo.audienceType = postAudience.audienceType
            feedPost.info = feedPostInfo
        case .groupFeed(let groupId):
            guard let chatGroup = MainAppContext.shared.chatData.chatGroup(groupId: groupId) else {
                return
            }
            let feedPostInfo = NSEntityDescription.insertNewObject(forEntityName: FeedPostInfo.entity().name!, into: managedObjectContext) as! FeedPostInfo
            var receipts = [UserID : Receipt]()
            chatGroup.members?.forEach({ member in
                receipts[member.userId] = Receipt()
            })
            feedPostInfo.receipts = receipts
            feedPostInfo.audienceType = .group
            feedPost.info = feedPostInfo
        }

        // set a merge policy so that we dont end up with duplicate feedposts.
        managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        save(managedObjectContext)

        
        if let linkPreview = linkPreview {
            // upload link preview media followed by comment media and send over the wire
            uploadMediaAndSend(feedLinkPreview: linkPreview)
        } else {
            // upload comment media if any and send data over the wire.
            uploadMediaAndSend(feedPost: feedPost)
        }
        if feedPost.groupId != nil {
            didSendGroupFeedPost.send(feedPost)
        }
    }

    @discardableResult
    func post(comment: MentionText, media: [PendingMedia], linkPreviewData: LinkPreviewData?, linkPreviewMedia : PendingMedia?, to feedPostID: FeedPostID, replyingTo parentCommentId: FeedPostCommentID? = nil) -> FeedPostCommentID {
        let commentId: FeedPostCommentID = PacketID.generate()

        // Create and save FeedPostComment
        let managedObjectContext = self.persistentContainer.viewContext
        guard let feedPost = self.feedPost(with: feedPostID, in: managedObjectContext) else {
            DDLogError("FeedData/new-comment/error  Missing FeedPost with id [\(feedPostID)]")
            fatalError("Unable to find FeedPost")
        }
        var parentComment: FeedPostComment?
        if parentCommentId != nil {
            parentComment = self.feedComment(with: parentCommentId!, in: managedObjectContext)
            if parentComment == nil {
                DDLogError("FeedData/new-comment/error  Missing parent comment with id=[\(parentCommentId!)]")
            }
        }

        var mentionSet = Set<FeedMention>()
        for (index, user) in comment.mentions {
            let feedMention = NSEntityDescription.insertNewObject(forEntityName: FeedMention.entity().name!, into: managedObjectContext) as! FeedMention
            feedMention.index = index
            feedMention.userID = user.userID
            feedMention.name = contactStore.pushNames[user.userID] ?? user.pushName ?? ""
            if feedMention.name == "" {
                DDLogError("FeedData/new-comment/mention/\(user.userID) missing push name")
            }
            mentionSet.insert(feedMention)
        }

        DDLogDebug("FeedData/new-comment/create id=[\(commentId)]  postId=[\(feedPost.id)]")
        let feedComment = NSEntityDescription.insertNewObject(forEntityName: FeedPostComment.entity().name!, into: managedObjectContext) as! FeedPostComment
        feedComment.id = commentId
        feedComment.userId = AppContext.shared.userData.userId
        feedComment.text = comment.collapsedText
        feedComment.mentions = mentionSet
        feedComment.parent = parentComment
        feedComment.post = feedPost
        feedComment.status = .sending
        feedComment.timestamp = Date()

        // Add post comment media.
        for (index, mediaItem) in media.enumerated() {
            DDLogDebug("FeedData/new-comment/add-media [\(mediaItem.fileURL!)]")

            let feedMedia = NSEntityDescription.insertNewObject(forEntityName: FeedPostMedia.entity().name!, into: managedObjectContext) as! FeedPostMedia
            feedMedia.type = mediaItem.type
            feedMedia.status = .uploading
            feedMedia.url = mediaItem.url
            feedMedia.size = mediaItem.size!
            feedMedia.key = ""
            feedMedia.sha256 = ""
            feedMedia.order = Int16(index)
            feedMedia.comment = feedComment

            // Copying depends on all data fields being set, so do this last.
            do {
                try downloadManager.copyMedia(from: mediaItem, to: feedMedia)
            }
            catch {
                DDLogError("FeedData/new-comment/copy-media/error [\(error)]")
            }
        }
        
        // Add feed link preview if any
        var linkPreview: FeedLinkPreview?
        if let linkPreviewData = linkPreviewData {
            linkPreview = FeedLinkPreview(context: managedObjectContext)
            linkPreview?.id = PacketID.generate()
            linkPreview?.url = linkPreviewData.url
            linkPreview?.title = linkPreviewData.title
            linkPreview?.desc = linkPreviewData.description
            // Set preview image if present
            if let linkPreviewMedia = linkPreviewMedia {
                let previewMedia = NSEntityDescription.insertNewObject(forEntityName: FeedPostMedia.entity().name!, into: managedObjectContext) as! FeedPostMedia
                previewMedia.type = linkPreviewMedia.type
                previewMedia.status = .uploading
                previewMedia.url = linkPreviewMedia.url
                previewMedia.size = linkPreviewMedia.size!
                previewMedia.key = ""
                previewMedia.sha256 = ""
                previewMedia.order = 0
                previewMedia.linkPreview = linkPreview
                
                // Copying depends on all data fields being set, so do this last.
                do {
                    try downloadManager.copyMedia(from: linkPreviewMedia, to: previewMedia)
                }
                catch {
                    DDLogError("FeedData/new-comment/copy-likePreviewmedia/error [\(error)]")
                }
            }
            linkPreview?.comment = feedComment
        }
        

        save(managedObjectContext)
        if let linkPreview = linkPreview {
            // upload link preview media followed by comment media and send over the wire
            uploadMediaAndSend(feedLinkPreview: linkPreview)
        } else {
            // upload comment media if any and send data over the wire.
            uploadMediaAndSend(feedComment: feedComment)
        }
        return commentId
    }

    func retryPosting(postId: FeedPostID) {
        DDLogInfo("FeedData/retryPosting/postId: \(postId)")
        let managedObjectContext = self.persistentContainer.viewContext

        guard let feedPost = self.feedPost(with: postId, in: managedObjectContext) else { return }
        guard feedPost.status == .sendError else { return }

        // Change status to "sending" and start sending / uploading.
        feedPost.status = .sending
        save(managedObjectContext)
        uploadMediaAndSend(feedPost: feedPost)
    }

    func resend(commentWithId commentId: FeedPostCommentID) {
        DDLogInfo("FeedData/resend/commentWithId: \(commentId)")
        let managedObjectContext = self.persistentContainer.viewContext

        guard let comment = self.feedComment(with: commentId, in: managedObjectContext) else { return }
        guard comment.status == .sendError else { return }

        // Change status to "sending" and send.
        comment.status = .sending
        save(managedObjectContext)

        send(comment: comment)
    }

    private func handleRerequest(for contentID: String, contentType: GroupFeedRerequestContentType, from userID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        if contentType == .historyResend {
            mainDataStore.performSeriallyOnBackgroundContext { [mainDataStore] managedObjectContext in
                let resendInfo = mainDataStore.fetchContentResendInfo(for: contentID, userID: userID, in: managedObjectContext)
                resendInfo.retryCount += 1
                // retryCount indicates number of times content has been rerequested until now: increment and use it when sending.
                let rerequestCount = resendInfo.retryCount
                DDLogInfo("FeedData/handleRerequest/\(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount)")
                guard rerequestCount <= 5 else {
                    DDLogError("FeedData/handleRerequest/\(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount) - aborting")
                    completion(.failure(.aborted))
                    return
                }
                guard let content = mainDataStore.groupHistoryInfo(for: contentID, in: managedObjectContext) else {
                    DDLogError("FeedData/handleRerequest/\(contentID)/error could not find groupHistoryInfo")
                    completion(.failure(.aborted))
                    return
                }
                resendInfo.groupHistoryInfo = content
                self.service.resendHistoryResendPayload(id: contentID, groupID: content.groupId, payload: content.payload, to: userID, rerequestCount: rerequestCount) { result in
                    switch result {
                    case .success():
                        DDLogInfo("FeedData/handleRerequest/\(contentID) success/userID: \(userID)/rerequestCount: \(rerequestCount)")
                        // TODO: murali@: update rerequestCount only on success.
                    case .failure(let error):
                        DDLogError("FeedData/handleRerequest/\(contentID) error \(error)")
                    }
                    completion(result)
                }
            }
        } else {
            // TODO: switch this to a case after 2months on 04-01-2022.
            performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                guard let self = self else {
                    completion(.failure(.aborted))
                    return
                }

                let resendAttempt = self.fetchResendAttempt(for: contentID, userID: userID, in: managedObjectContext)
                resendAttempt.retryCount += 1
                // retryCount indicates number of times content has been rerequested until now: increment and use it when sending.
                let rerequestCount = resendAttempt.retryCount
                DDLogInfo("FeedData/fetchResendAttempt/contentID: \(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount)")
                guard rerequestCount <= 5 else {
                    DDLogError("FeedData/fetchResendAttempt/contentID: \(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount) - aborting")
                    completion(.failure(.aborted))
                    return
                }
                self.save(managedObjectContext)

                // Check if contentID is a post
                if let post = self.feedPost(with: contentID, in: managedObjectContext) {
                    DDLogInfo("FeedData/handleRerequest/postID: \(post.id) begin/userID: \(userID)/rerequestCount: \(rerequestCount)")
                    guard let groupId = post.groupId else {
                        DDLogInfo("FeedData/handleRerequest/postID: \(post.id) /groupId is missing")
                        completion(.failure(.aborted))
                        return
                    }
                    let feed: Feed = .group(groupId)
                    resendAttempt.post = post
                    post.addToResendAttempts(resendAttempt)
                    self.save(managedObjectContext)

                    // Handle rerequests for posts based on status.
                    switch post.status {
                    case .retracting, .retracted:
                        DDLogInfo("FeedData/handleRerequest/postID: \(post.id)/userID: \(userID)/sending retract")
                        self.service.retractPost(post.id, in: groupId, to: userID)
                        completion(.success(()))
                    default:
                        self.service.resendPost(post.postData, feed: feed, rerequestCount: rerequestCount, to: userID) { result in
                            switch result {
                            case .success():
                                DDLogInfo("FeedData/handleRerequest/postID: \(post.id) success/userID: \(userID)/rerequestCount: \(rerequestCount)")
                                // TODO: murali@: update rerequestCount only on success.
                            case .failure(let error):
                                DDLogError("FeedData/handleRerequest/postID: \(post.id) error \(error)")
                            }
                            completion(result)
                        }
                    }

                } else if let comment = self.feedComment(with: contentID, in: managedObjectContext) {
                    DDLogInfo("FeedData/handleRerequest/commentID: \(comment.id) begin/userID: \(userID)/rerequestCount: \(rerequestCount)")
                    resendAttempt.comment = comment
                    comment.addToResendAttempts(resendAttempt)
                    self.save(managedObjectContext)

                    guard let groupId = comment.post.groupId else {
                        DDLogInfo("FeedData/handleRerequest/commentID: \(comment.id) /groupId is missing")
                        completion(.failure(.aborted))
                        return
                    }
                    // Handle rerequests for comments based on status.
                    switch comment.status {
                    case .retracting, .retracted:
                        DDLogInfo("FeedData/handleRerequest/commentID: \(comment.id)/userID: \(userID)/sending retract")
                        self.service.retractComment(comment.id, postID: comment.post.id, in: groupId, to: userID)
                        completion(.success(()))
                    default:
                        self.service.resendComment(comment.commentData, groupId: groupId, rerequestCount: rerequestCount, to: userID) { result in
                            switch result {
                            case .success():
                                DDLogInfo("FeedData/handleRerequest/commentID: \(comment.id) success/userID: \(userID)/rerequestCount: \(rerequestCount)")
                                // TODO: murali@: update rerequestCount only on success.
                            case .failure(let error):
                                DDLogError("FeedData/handleRerequest/commentID: \(comment.id) error \(error)")
                            }
                            completion(result)
                        }
                    }
                } else {
                    // Check if contentID is a comment
                    DDLogError("FeedData/handleRerequest/\(contentID)/error could not find post/comment")
                    completion(.failure(.aborted))
                }
            }
        }
    }

    private func send(comment: FeedPostComment) {
        DDLogInfo("FeedData/send-comment/commentID: \(comment.id)")
        let commentId = comment.id
        let groupId = comment.post.groupId
        let postId = comment.post.id

        guard !contentInFlight.contains(commentId) else {
            DDLogInfo("FeedData/send-comment/commentID: \(comment.id) already-in-flight")
            return
        }
        DDLogInfo("FeedData/send-comment/commentID: \(comment.id) begin")
        contentInFlight.insert(commentId)

        service.publishComment(comment.commentData, groupId: groupId) { result in
            switch result {
            case .success(let timestamp):
                DDLogInfo("FeedData/send-comment/commentID: \(comment.id) success")
                self.contentInFlight.remove(commentId)
                self.updateFeedPostComment(with: commentId) { (feedComment) in
                    feedComment.timestamp = timestamp
                    feedComment.status = .sent

                    MainAppContext.shared.endBackgroundTask(feedComment.id)
                }
                if groupId != nil {
                    var interestedPosts = AppContext.shared.userDefaults.value(forKey: AppContext.commentedGroupPostsKey) as? [FeedPostID] ?? []
                    interestedPosts.append(postId)
                    AppContext.shared.userDefaults.set(Array(Set(interestedPosts)), forKey: AppContext.commentedGroupPostsKey)
                }

            case .failure(let error):
                DDLogError("FeedData/send-comment/commentID: \(comment.id) error \(error)")
                self.contentInFlight.remove(commentId)
                // TODO: Track this state more precisely. Even if this attempt was a definite failure, a previous attempt may have succeeded.
                if error.isKnownFailure {
                    self.updateFeedPostComment(with: commentId) { (feedComment) in
                        feedComment.status = .sendError
                        MainAppContext.shared.endBackgroundTask(feedComment.id)
                    }
                }
            }
        }
    }

    private func send(post: FeedPost) {
        let feed: Feed
        if let groupId = post.groupId {
            feed = .group(groupId)
        } else {
            guard let postAudience = post.audience else {
                DDLogError("FeedData/send-post/\(post.id) No audience set")
                post.status = .sendError
                save(post.managedObjectContext!)
                return
            }
            feed = .personal(postAudience)
        }

        let postId = post.id

        guard !contentInFlight.contains(postId) else {
            DDLogInfo("FeedData/send-post/postID: \(postId) already-in-flight")
            return
        }
        DDLogInfo("FeedData/send-post/postID: \(postId) begin")
        contentInFlight.insert(postId)

        service.publishPost(post.postData, feed: feed) { result in
            switch result {
            case .success(let timestamp):
                DDLogInfo("FeedData/send-post/postID: \(postId) success")
                self.contentInFlight.remove(postId)
                self.updateFeedPost(with: postId) { (feedPost) in
                    feedPost.timestamp = timestamp
                    feedPost.status = .sent

                    MainAppContext.shared.endBackgroundTask(postId)
                }

            case .failure(let error):
                DDLogError("FeedData/send-post/postID: \(postId) error \(error)")
                self.contentInFlight.remove(postId)
                // TODO: Track this state more precisely. Even if this attempt was a definite failure, a previous attempt may have succeeded.
                if error.isKnownFailure {
                    self.updateFeedPost(with: postId) { (feedPost) in
                        feedPost.status = .sendError

                        MainAppContext.shared.endBackgroundTask(postId)
                    }
                }
            }
        }
    }

    func sharePastPostsWith(userId: UserID) {
        guard !MainAppContext.shared.privacySettings.blocked.userIds.contains(userId) else {
            DDLogInfo("FeedData/share-posts/\(userId) User is blocked")
            return
        }
        guard userId != userData.userId else {
            DDLogInfo("FeedData/share-posts/\(userId) Cannot share posts with self")
            return
        }

        let predicate = NSPredicate(format: "statusValue == %d AND groupId == nil AND timestamp > %@", FeedPost.Status.sent.rawValue, NSDate(timeIntervalSinceNow: -Date.days(7)))
        let posts = feedPosts(predicate: predicate, in: viewContext)

        var postsToShare: [FeedPost] = []
        for post in posts {
            guard let audience = post.audience else { continue }
            switch audience.audienceType {
            case .all:
                postsToShare.append(post)

            case .whitelist, .blacklist:
                if audience.userIds.contains(userId) {
                    postsToShare.append(post)
                }

            default:
                break
            }
        }

        guard !postsToShare.isEmpty else {
            DDLogWarn("FeedData/share-posts/\(userId) No posts to share")
            return
        }

        DDLogInfo("FeedData/share-posts/\(userId) Sending \(postsToShare.count) posts")
        service.sharePosts(postIds: postsToShare.map({ $0.id }), with: userId) { (result) in
            switch result {
            case .success(_):
                DDLogInfo("FeedData/share-posts/\(userId)/success")

            case .failure(let error):
                DDLogError("FeedData/share-posts/\(userId)/error [\(error)]")
            }
        }
    }

    // MARK: Media Upload
    private func uploadMediaAndSend(feedPost: FeedPost) {
        let postId = feedPost.id

        MainAppContext.shared.beginBackgroundTask(postId)

        // Either all media has already been uploaded or post does not contain media.
        guard let mediaItemsToUpload = feedPost.media?.filter({ [.none, .uploading, .uploadError].contains($0.status) }), !mediaItemsToUpload.isEmpty else {
            send(post: feedPost)
            return
        }

        var numberOfFailedUploads = 0
        var totalUploadSize = 0
        let totalUploads = mediaItemsToUpload.count
        let startTime = Date()
        DDLogInfo("FeedData/upload-media/\(postId)/starting [\(totalUploads)]")

        let uploadGroup = DispatchGroup()
        let uploadCompletion: (Result<Int, Error>) -> Void = { result in
            switch result {
            case .success(let size):
                totalUploadSize += size
            case .failure(_):
                numberOfFailedUploads += 1
            }

            uploadGroup.leave()
        }

        // mediaItem is a CoreData object and it should not be passed across threads.
        for mediaItem in mediaItemsToUpload {
            let mediaIndex = mediaItem.order
            uploadGroup.enter()
            DDLogDebug("FeedData/process-mediaItem/feedPost: \(postId)/\(mediaItem.order), index: \(mediaIndex)")
            let outputFileID = "\(postId)-\(mediaIndex)"

            if let relativeFilePath = mediaItem.relativeFilePath, mediaItem.sha256.isEmpty, mediaItem.key.isEmpty {
                DDLogDebug("FeedData/process-mediaItem/feedPost: \(postId)/\(mediaIndex)/relativeFilePath: \(relativeFilePath)")
                let url = MainAppContext.mediaDirectoryURL.appendingPathComponent(relativeFilePath, isDirectory: false)
                let output = MainAppContext.mediaDirectoryURL.appendingPathComponent(outputFileID, isDirectory: false).appendingPathExtension("processed").appendingPathExtension(url.pathExtension)

                ImageServer.shared.prepare(mediaItem.type, url: url, for: postId, index: Int(mediaIndex), shouldStreamVideo: mediaItem.blobVersion == .chunked) { [weak self] in
                    guard let self = self else { return }
                    switch $0 {
                    case .success(let result):
                        result.copy(to: output)
                        if result.url != url {
                            result.clear()
                        }

                        let path = self.downloadManager.relativePath(from: output)
                        DDLogDebug("FeedData/process-mediaItem/success: \(postId)/\(mediaIndex)")
                        self.updateFeedPost(with: postId, block: { (feedPost) in
                            if let media = feedPost.media?.first(where: { $0.order == mediaIndex }) {
                                media.size = result.size
                                media.key = result.key
                                media.sha256 = result.sha256
                                media.chunkSize = result.chunkSize
                                media.blobSize = result.blobSize
                                media.relativeFilePath = path
                            }
                        }) {
                            self.upload(postId: postId, mediaIndex: mediaIndex, completion: uploadCompletion)
                        }
                    case .failure(_):
                        DDLogDebug("FeedData/process-mediaItem/failure: \(postId)/\(mediaIndex)")
                        numberOfFailedUploads += 1

                        self.updateFeedPost(with: postId, block: { (feedPost) in
                            if let media = feedPost.media?.first(where: { $0.order == mediaIndex }) {
                                media.status = .uploadError
                            }
                        }) {
                            uploadGroup.leave()
                        }
                    }
                }
            } else {
                DDLogDebug("FeedData/process-mediaItem/processed already: \(postId)/\(mediaIndex)")
                self.upload(postId: postId, mediaIndex: mediaIndex, completion: uploadCompletion)
            }
        }

        uploadGroup.notify(queue: .main) {
            DDLogInfo("FeedData/upload-media/\(postId)/all/finished [\(totalUploads-numberOfFailedUploads)/\(totalUploads)]")
            ImageServer.shared.clearAllTasks(for: postId)
            self.mediaUploader.clearTasks(withGroupID: postId)
            if numberOfFailedUploads > 0 {
                self.updateFeedPost(with: postId) { (feedPost) in
                    feedPost.status = .sendError
                }
            } else {
                // TODO(murali@): one way to avoid looking up the object from the database is to keep an updated in-memory version of the post.
                self.performSeriallyOnBackgroundContext { (managedObjectContext) in
                    guard let feedPost = self.feedPost(with: postId, in: managedObjectContext) else {
                        DDLogError("FeedData/missing-post [\(postId)]")
                        return
                    }
                    self.send(post: feedPost)
                    let numPhotos = mediaItemsToUpload.filter { $0.type == .image }.count
                    let numVideos = mediaItemsToUpload.filter { $0.type == .video }.count
                    AppContext.shared.eventMonitor.observe(
                        .mediaUpload(
                            postID: postId,
                            duration: Date().timeIntervalSince(startTime),
                            numPhotos: numPhotos,
                            numVideos: numVideos,
                            totalSize: totalUploadSize))
                }
            }
        }
    }

    private func uploadMediaAndSend(feedLinkPreview: FeedLinkPreview) {

        guard let mediaItemsToUpload = feedLinkPreview.media?.filter({ $0.status == .none || $0.status == .uploading || $0.status == .uploadError }), !mediaItemsToUpload.isEmpty else {
            // no link preview media.. upload
            self.performSeriallyOnBackgroundContext { (managedObjectContext) in
                // Comment link preview
                if let feedComment = feedLinkPreview.comment, let feedComment = self.feedComment(with: feedComment.id, in: managedObjectContext) {
                    self.uploadMediaAndSend(feedComment: feedComment)
                    return
                }
                // Post link preview
                if let feedPost = feedLinkPreview.post, let feedPost = self.feedPost(with: feedPost.id, in: managedObjectContext) {
                    self.uploadMediaAndSend(feedPost: feedPost)
                    return
                }
                DDLogError("FeedData/missing-feedLinkPreview/feedLinkPreviewId [\(feedLinkPreview.id)]")
            }
            return
        }

        var numberOfFailedUploads = 0
        var totalUploadSize = 0
        let totalUploads = 1
        DDLogInfo("FeedData/upload-media/feedLinkPreviewID/\(feedLinkPreview.id)/starting [\(totalUploads)]")

        let uploadGroup = DispatchGroup()
        let uploadCompletion: (Result<Int, Error>) -> Void = { result in
            switch result {
            case .success(let size):
                totalUploadSize += size
            case .failure(_):
                numberOfFailedUploads += 1
            }

            uploadGroup.leave()
        }

        MainAppContext.shared.beginBackgroundTask(feedLinkPreview.id)

        for mediaItemToUpload in mediaItemsToUpload {
            let mediaIndex = mediaItemToUpload.order
            uploadGroup.enter()
            DDLogDebug("FeedData/process-mediaItem/feedLinkPreview: \(feedLinkPreview.id)/\(mediaItemToUpload.order), index: \(mediaIndex)")
            let outputFileID = "\(feedLinkPreview.id)-\(mediaIndex)"

            if let relativeFilePath = mediaItemToUpload.relativeFilePath, mediaItemToUpload.sha256.isEmpty && mediaItemToUpload.key.isEmpty {
                DDLogDebug("FeedData/process-mediaItem/feedLinkPreview: \(feedLinkPreview.id)/\(mediaIndex)/relativeFilePath: \(relativeFilePath)")
                let url = MainAppContext.mediaDirectoryURL.appendingPathComponent(relativeFilePath, isDirectory: false)
                let output = MainAppContext.mediaDirectoryURL.appendingPathComponent(outputFileID, isDirectory: false).appendingPathExtension("processed").appendingPathExtension(url.pathExtension)

                ImageServer.shared.prepare(mediaItemToUpload.type, url: url, for: feedLinkPreview.id, index: Int(mediaIndex), shouldStreamVideo: false) { [weak self] in
                    guard let self = self else { return }
                    switch $0 {
                    case .success(let result):
                        result.copy(to: output)
                        if result.url != url {
                            result.clear()
                        }

                        let path = self.downloadManager.relativePath(from: output)
                        DDLogDebug("FeedData/process-feedLinkPreview-mediaItem/success: \(feedLinkPreview.id)/ index: \(mediaIndex)")
                        self.updateFeedLinkPreview(with: feedLinkPreview.id, block: { (feedLinkPreview) in
                            if let media = feedLinkPreview.media?.first(where: { $0.order == mediaIndex }) {
                                media.size = result.size
                                media.key = result.key
                                media.sha256 = result.sha256
                                media.relativeFilePath = path
                            }
                        }) {
                            self.uploadFeedLinkPreview(feedLinkPreviewId: feedLinkPreview.id, mediaIndex: mediaIndex, completion: uploadCompletion)
                        }
                    case .failure(_):
                        DDLogDebug("FeedData/process-feedLinkPreview-mediaItem/failure: feedLinkPreview \(feedLinkPreview.id)/\(mediaIndex) url\(url) output \(output)")
                        numberOfFailedUploads += 1

                        self.updateFeedLinkPreview(with: feedLinkPreview.id, block: { (feedLinkPreview) in
                            if let media = feedLinkPreview.media?.first(where: { $0.order == mediaIndex }){
                                media.status = .uploadError
                            }
                        }) {
                            uploadGroup.leave()
                        }
                    }
                }
            } else {
                DDLogDebug("FeedData/process-feedLinkPreview-mediaItem/processed already: feedLinkPreview \(feedLinkPreview.id)/\(mediaIndex)")
                self.uploadFeedLinkPreview(feedLinkPreviewId: feedLinkPreview.id, mediaIndex: mediaIndex, completion: uploadCompletion)
            }
        }
    
        uploadGroup.notify(queue: .main) {
            MainAppContext.shared.endBackgroundTask(feedLinkPreview.id)

            DDLogInfo("FeedData/upload-feedLinkPreview-media/\(feedLinkPreview.id)/all/finished [\(totalUploads-numberOfFailedUploads)/\(totalUploads)]")
            ImageServer.shared.clearAllTasks(for: feedLinkPreview.id)
            self.mediaUploader.clearTasks(withGroupID: feedLinkPreview.id)
            if numberOfFailedUploads > 0 {
                if let commentId = feedLinkPreview.comment?.id {
                    self.updateFeedPostComment(with: commentId) { (feedPostComment) in
                        feedPostComment.status = .sendError
                    }
                }
                if let postId = feedLinkPreview.post?.id {
                    self.updateFeedPost(with: postId) { (feedPost) in
                        feedPost.status = .sendError
                    }
                }
            } else {
                // TODO(murali@): one way to avoid looking up the object from the database is to keep an updated in-memory version of the comment.
                self.performSeriallyOnBackgroundContext { (managedObjectContext) in
                    // Comment link preview
                    if let feedComment = feedLinkPreview.comment, let feedComment = self.feedComment(with: feedComment.id, in: managedObjectContext) {
                        self.uploadMediaAndSend(feedComment: feedComment)
                        return
                    }
                    // Post link preview
                    if let feedPost = feedLinkPreview.post, let feedPost = self.feedPost(with: feedPost.id, in: managedObjectContext) {
                        self.uploadMediaAndSend(feedPost: feedPost)
                        return
                    }
                    DDLogError("FeedData/missing-feedLinkPreview/feedLinkPreviewId [\(feedLinkPreview.id)]")
                }
            }
        }
    }
        
        private func uploadMediaAndSend(feedComment: FeedPostComment) {

            MainAppContext.shared.beginBackgroundTask(feedComment.id)

            guard let mediaItemsToUpload = feedComment.media?.filter({ [.none, .uploading, .uploadError].contains($0.status) }), !mediaItemsToUpload.isEmpty else {
                self.performSeriallyOnBackgroundContext { (managedObjectContext) in
                    guard let feedComment = self.feedComment(with: feedComment.id, in: managedObjectContext) else {
                        DDLogError("FeedData/missing-comment [\(feedComment.id)]")
                        return
                    }
                    self.send(comment: feedComment)
                }
                return
            }

            var numberOfFailedUploads = 0
            var totalUploadSize = 0
            let totalUploads = 1
            DDLogInfo("FeedData/upload-media/commentID/\(feedComment.id)/starting [\(totalUploads)]")

            let uploadGroup = DispatchGroup()
            let uploadCompletion: (Result<Int, Error>) -> Void = { result in
                switch result {
                case .success(let size):
                    totalUploadSize += size
                case .failure(_):
                    numberOfFailedUploads += 1
                }

                uploadGroup.leave()
            }

            for mediaItemToUpload in mediaItemsToUpload {
                let mediaIndex = mediaItemToUpload.order
                uploadGroup.enter()
                DDLogDebug("FeedData/process-mediaItem/comment: \(feedComment.id)/\(mediaItemToUpload.order), index: \(mediaIndex)")
                let outputFileID = "\(feedComment.id)-\(mediaIndex)"

                if let relativeFilePath = mediaItemToUpload.relativeFilePath, mediaItemToUpload.sha256.isEmpty && mediaItemToUpload.key.isEmpty {
                    DDLogDebug("FeedData/process-mediaItem/comment: \(feedComment.id)/\(mediaIndex)/relativeFilePath: \(relativeFilePath)")
                    let url = MainAppContext.mediaDirectoryURL.appendingPathComponent(relativeFilePath, isDirectory: false)
                    let output = MainAppContext.mediaDirectoryURL.appendingPathComponent(outputFileID, isDirectory: false).appendingPathExtension("processed").appendingPathExtension(url.pathExtension)

                    ImageServer.shared.prepare(mediaItemToUpload.type, url: url, for: feedComment.id, index: Int(mediaIndex), shouldStreamVideo: mediaItemToUpload.blobVersion == .chunked) { [weak self] in
                        guard let self = self else { return }
                        switch $0 {
                        case .success(let result):
                            result.copy(to: output)
                            if result.url != url {
                                result.clear()
                            }

                            let path = self.downloadManager.relativePath(from: output)
                            DDLogDebug("FeedData/process-comment-mediaItem/success: comment \(feedComment.id)/ commment:\(feedComment.id)\(mediaIndex)")
                            self.updateFeedPostComment(with: feedComment.id, block: { (feedPostComment) in
                                if let media = feedPostComment.media?.first(where: { $0.order == mediaIndex }) {
                                    media.size = result.size
                                    media.key = result.key
                                    media.sha256 = result.sha256
                                    media.chunkSize = result.chunkSize
                                    media.blobSize = result.blobSize
                                    media.relativeFilePath = path
                                }
                            }) {
                                self.uploadCommentMedia(postId: feedComment.post.id, commentId: feedComment.id, mediaIndex: mediaIndex, completion: uploadCompletion)
                            }
                        case .failure(_):
                            DDLogDebug("FeedData/process-comment-mediaItem/failure: comment \(feedComment.id)/\(mediaIndex) url\(url) output \(output)")
                            numberOfFailedUploads += 1

                            self.updateFeedPostComment(with: feedComment.id, block: { (feedComment) in
                                if let media = feedComment.media?.first(where: { $0.order == mediaIndex }){
                                    media.status = .uploadError
                                }
                            }) {
                                uploadGroup.leave()
                            }
                        }
                    }
                } else {
                    DDLogDebug("FeedData/process-comment-mediaItem/processed already: comment \(feedComment.id)/\(mediaIndex)")
                    self.uploadCommentMedia(postId: feedComment.post.id, commentId: feedComment.id, mediaIndex: mediaIndex, completion: uploadCompletion)
                }
            }

        uploadGroup.notify(queue: .main) {
            DDLogInfo("FeedData/upload-comment-media/\(feedComment.id)/all/finished [\(totalUploads-numberOfFailedUploads)/\(totalUploads)]")
            ImageServer.shared.clearAllTasks(for: feedComment.id)
            self.mediaUploader.clearTasks(withGroupID: feedComment.id)
            if numberOfFailedUploads > 0 {
                self.updateFeedPostComment(with: feedComment.id, block: { (feedComment) in
                    feedComment.status = .sendError
                })
            } else {
                // TODO(murali@): one way to avoid looking up the object from the database is to keep an updated in-memory version of the comment.
                self.performSeriallyOnBackgroundContext { (managedObjectContext) in
                    guard let feedComment = self.feedComment(with: feedComment.id, in: managedObjectContext) else {
                        DDLogError("FeedData/missing-comment [\(feedComment.id)]")
                        return
                    }
                    self.send(comment: feedComment)
                    // TODO dini update this with commentid
    //                AppContext.shared.eventMonitor.observe(
    //                    .mediaUpload(
    //                        postID: feedComment.post.id,
    //                        duration: Date().timeIntervalSince(startTime),
    //                        numPhotos: mediaItemsToUpload.filter { $0.type == .image }.count,
    //                        numVideos: mediaItemsToUpload.filter { $0.type == .video }.count,
    //                        totalSize: totalUploadSize))
                }
            }
        }
    }

    private func upload(postId: FeedPostID, mediaIndex: Int16, completion: @escaping (Result<Int, Error>) -> Void) {
        guard let post = self.feedPost(with: postId),
              let postMedia = post.media?.first(where: { $0.order == mediaIndex }) else {
            DDLogError("FeedData/upload/fetch post and media \(postId)/\(mediaIndex) - missing")
            return
        }

        DDLogDebug("FeedData/upload/media \(postId)/\(postMedia.order), index:\(mediaIndex)")
        guard let relativeFilePath = postMedia.relativeFilePath else {
            DDLogError("FeedData/upload-media/\(postId)/\(mediaIndex) missing file path")
            return completion(.failure(MediaUploadError.invalidUrls))
        }
        let processed = MainAppContext.mediaDirectoryURL.appendingPathComponent(relativeFilePath, isDirectory: false)

        MainAppContext.shared.mediaHashStore.fetch(url: processed, blobVersion: postMedia.blobVersion) { [weak self] upload in
            guard let self = self else { return }

            // Lookup object from coredata again instead of passing around the object across threads.
            DDLogInfo("FeedData/upload/fetch upload hash \(postId)/\(mediaIndex)")
            guard let post = self.feedPost(with: postId),
                  let media = post.media?.first(where: { $0.order == mediaIndex }) else {
                DDLogError("FeedData/upload/upload hash finished/fetch post and media/ \(postId)/\(mediaIndex) - missing")
                return
            }

            if let url = upload?.url {
                DDLogInfo("Media \(processed) has been uploaded before at \(url).")
                if let uploadUrl = media.uploadUrl {
                    DDLogInfo("FeedData/upload/upload url is supposed to be nil here/\(postId)/\(media.order), uploadUrl: \(uploadUrl)")
                    // we set it to be nil here explicitly.
                    media.uploadUrl = nil
                }
                media.url = url
            } else {
                DDLogInfo("FeedData/uploading media now\(postId)/\(media.order), index:\(mediaIndex)")
            }

            self.mediaUploader.upload(media: media, groupId: postId, didGetURLs: { (mediaURLs) in
                DDLogInfo("FeedData/upload-media/\(postId)/\(mediaIndex)/acquired-urls [\(mediaURLs)]")

                // Save URLs acquired during upload to the database.
                self.updateFeedPost(with: postId) { (feedPost) in
                    if let media = feedPost.media?.first(where: { $0.order == mediaIndex }) {
                        switch mediaURLs {
                        case .getPut(let getURL, let putURL):
                            media.url = getURL
                            media.uploadUrl = putURL

                        case .patch(let patchURL):
                            media.uploadUrl = patchURL
                            media.url = nil

                        case .download(let downloadURL):
                            media.url = downloadURL
                        }
                    }
                }
            }) { (uploadResult) in
                DDLogInfo("FeedData/upload-media/\(postId)/\(mediaIndex)/finished result=[\(uploadResult)]")

                // Save URLs acquired during upload to the database.
                self.updateFeedPost(with: postId, block: { feedPost in
                    if let media = feedPost.media?.first(where: { $0.order == mediaIndex }) {
                        switch uploadResult {
                        case .success(let details):
                            media.url = details.downloadURL
                            media.status = .uploaded

                            if media.url == upload?.url, let key = upload?.key, let sha256 = upload?.sha256 {
                                media.key = key
                                media.sha256 = sha256
                            }

                            MainAppContext.shared.mediaHashStore.update(url: processed, blobVersion: media.blobVersion, key: media.key, sha256: media.sha256, downloadURL: media.url!)
                        case .failure(_):
                            media.status = .uploadError
                        }
                    }
                }) {
                    completion(uploadResult.map { $0.fileSize })
                }
            }
        }
    }

    private func uploadCommentMedia(postId: FeedPostID, commentId: FeedPostCommentID, mediaIndex: Int16, completion: @escaping (Result<Int, Error>) -> Void) {
        guard let comment = self.feedComment(with: commentId), let postCommentMedia = comment.media?.first(where: { $0.order == mediaIndex }) else {
            DDLogError("FeedData/upload/fetch post, comment and media \(postId)/\(commentId)/\(mediaIndex) - missing")
            return
        }

        DDLogDebug("FeedData/upload/media/coment postid: \(postId)/ commentid: \(commentId)/ order: \(postCommentMedia), index:\(mediaIndex)")
        guard let relativeFilePath = postCommentMedia.relativeFilePath else {
            DDLogError("FeedData/upload-media/comment postid: \(postId)/ commentid: \(commentId)/\(mediaIndex) missing file path")
            return completion(.failure(MediaUploadError.invalidUrls))
        }
        let processed = MainAppContext.mediaDirectoryURL.appendingPathComponent(relativeFilePath, isDirectory: false)

        MainAppContext.shared.mediaHashStore.fetch(url: processed, blobVersion: postCommentMedia.blobVersion) { [weak self] upload in
            guard let self = self else { return }

            // Lookup object from coredata again instead of passing around the object across threads.
            DDLogInfo("FeedData/upload/fetch upload hash comment \(commentId)/\(mediaIndex)")
            guard let comment = self.feedComment(with: commentId),
                  let media = comment.media?.first(where: { $0.order == mediaIndex })  else {
                DDLogError("FeedData/upload/upload hash finished/fetch post and media/ \(postId)/ comment: \(commentId)/\(mediaIndex) - missing")
                return
            }

            if let url = upload?.url {
                DDLogInfo("Media \(processed) has been uploaded before at \(url).")
                if let uploadUrl = media.uploadUrl {
                    DDLogInfo("FeedData/upload/upload url is supposed to be nil here/\(postId)/\(media.order), uploadUrl: \(uploadUrl)")
                    // we set it to be nil here explicitly.
                    media.uploadUrl = nil
                }
                media.url = url
            } else {
                DDLogInfo("FeedData/uploading media now for comment postid: \(postId)/ commentid: \(commentId) /\(media.order) , index:\(mediaIndex)")
            }
            self.mediaUploader.upload(media: media, groupId: commentId, didGetURLs: { (mediaURLs) in
                DDLogInfo("FeedData/upload-media/ comment postid: \(postId)/\(mediaIndex) commentid: \(commentId)/acquired-urls [\(mediaURLs)]")

                // Save URLs acquired during upload to the database.
                self.updateFeedPostComment(with: commentId) { (feedPostComment) in
                    if let media = feedPostComment.media?.first(where: { $0.order == mediaIndex }) {
                        switch mediaURLs {
                        case .getPut(let getURL, let putURL):
                            media.url = getURL
                            media.uploadUrl = putURL

                        case .patch(let patchURL):
                            media.uploadUrl = patchURL
                            media.url = nil

                        case .download(let downloadURL):
                            media.url = downloadURL
                        }
                    }
                }
            }) { (uploadResult) in
                DDLogInfo("FeedData/upload-media/ comment postid: \(postId)/\(mediaIndex)  commentid: \(commentId) /finished result=[\(uploadResult)]")

                // Save URLs acquired during upload to the database.
                self.updateFeedPostComment(with: commentId, block: { feedPostComment in
                    if let media = feedPostComment.media?.first(where: { $0.order == mediaIndex }) {
                        switch uploadResult {
                        case .success(let details):
                            media.url = details.downloadURL
                            media.status = .uploaded

                            if media.url == upload?.url, let key = upload?.key, let sha256 = upload?.sha256 {
                                media.key = key
                                media.sha256 = sha256
                            }

                            MainAppContext.shared.mediaHashStore.update(url: processed, blobVersion: media.blobVersion, key: media.key, sha256: media.sha256, downloadURL: media.url!)
                        case .failure(_):
                            media.status = .uploadError
                        }
                    }
                }) {
                    completion(uploadResult.map { $0.fileSize })
                }
            }
        }
    }
    
    private func uploadFeedLinkPreview(feedLinkPreviewId: FeedLinkPreviewID, mediaIndex: Int16, completion: @escaping (Result<Int, Error>) -> Void) {
        guard let feedLinkPreview = self.feedLinkPreview(with: feedLinkPreviewId), let feedLinkPreviewMedia = feedLinkPreview.media?.first(where: { $0.order == mediaIndex }) else {
            DDLogError("FeedData/upload/fetch feedLinkPreviewID media \(feedLinkPreviewId)/\(mediaIndex) - missing")
            return
        }

        DDLogDebug("FeedData/upload/media/feedLinkPreviewID \(feedLinkPreviewId)/ order: \(feedLinkPreviewMedia), index:\(mediaIndex)")
        guard let relativeFilePath = feedLinkPreviewMedia.relativeFilePath else {
            DDLogError("FeedData/upload-media/feedLinkPreview \(feedLinkPreviewId)/\(mediaIndex) missing file path")
            return completion(.failure(MediaUploadError.invalidUrls))
        }
        let processed = MainAppContext.mediaDirectoryURL.appendingPathComponent(relativeFilePath, isDirectory: false)

        MainAppContext.shared.mediaHashStore.fetch(url: processed, blobVersion: feedLinkPreviewMedia.blobVersion) { [weak self] upload in
            guard let self = self else { return }

            // Lookup object from coredata again instead of passing around the object across threads.
            DDLogInfo("FeedData/upload/fetch upload hash FeedLinkPreview \(feedLinkPreviewId)/\(mediaIndex)")
            guard let feedLinkPreview = self.feedLinkPreview(with: feedLinkPreviewId),
                  let media = feedLinkPreview.media?.first(where: { $0.order == mediaIndex })  else {
                DDLogError("FeedData/upload/upload hash finished/fetch feedLinkPreviewId \(feedLinkPreviewId)/ \(mediaIndex) - missing")
                return
            }

            if let url = upload?.url {
                DDLogInfo("Media \(processed) has been uploaded before at \(url).")
                if let uploadUrl = media.uploadUrl {
                    DDLogInfo("FeedData/upload/upload url is supposed to be nil here feedLinkPreview /\(feedLinkPreviewId)/\(media.order), uploadUrl: \(uploadUrl)")
                    // we set it to be nil here explicitly.
                    media.uploadUrl = nil
                }
                media.url = url
            } else {
                DDLogInfo("FeedData/uploading media now for feedLinkPreviewId \(feedLinkPreviewId)/ \(media.order) , index:\(mediaIndex)")
            }
            self.mediaUploader.upload(media: media, groupId: feedLinkPreviewId, didGetURLs: { (mediaURLs) in
                DDLogInfo("FeedData/upload-media/ feedLinkPreviewId \(feedLinkPreviewId)/\(mediaIndex) /acquired-urls [\(mediaURLs)]")

                // Save URLs acquired during upload to the database.
                self.updateFeedLinkPreview(with: feedLinkPreviewId) { (feedLinkPreview) in
                    if let media = feedLinkPreview.media?.first(where: { $0.order == mediaIndex }) {
                        switch mediaURLs {
                        case .getPut(let getURL, let putURL):
                            media.url = getURL
                            media.uploadUrl = putURL

                        case .patch(let patchURL):
                            media.uploadUrl = patchURL
                            media.url = nil

                        case .download(let downloadURL):
                            media.url = downloadURL
                        }
                    }
                }
            }) { (uploadResult) in
                DDLogInfo("FeedData/upload-media/ feedLinkPreview\(feedLinkPreviewId)/\(mediaIndex) /finished result=[\(uploadResult)]")

                // Save URLs acquired during upload to the database.
                self.updateFeedLinkPreview(with: feedLinkPreviewId, block: { feedLinkPreview in
                    if let media = feedLinkPreview.media?.first(where: { $0.order == mediaIndex }) {
                        switch uploadResult {
                        case .success(let details):
                            media.url = details.downloadURL
                            media.status = .uploaded

                            if media.url == upload?.url, let key = upload?.key, let sha256 = upload?.sha256 {
                                media.key = key
                                media.sha256 = sha256
                            }

                            MainAppContext.shared.mediaHashStore.update(url: processed, blobVersion: media.blobVersion, key: media.key, sha256: media.sha256, downloadURL: media.url!)
                        case .failure(_):
                            media.status = .uploadError
                        }
                    }
                }) {
                    completion(uploadResult.map { $0.fileSize })
                }
            }
        }
    }

    func cancelMediaUpload(postId: FeedPostID) {
        DDLogInfo("FeedData/upload-media/cancel/\(postId)")
        mediaUploader.cancelUpload(groupId: postId)
    }

    // MARK: Clean Up Media Upload Data

    // cleans up old upload data since for now we do not remove the originals right after uploading
    public func cleanUpOldUploadData(directoryURL: URL) {
        DDLogInfo("FeedData/cleanUpOldUploadData")
        guard let enumerator = FileManager.default.enumerator(atPath: directoryURL.path) else { return }
        let encryptedSuffix = "enc"
        let encryptedExtSuffix = ".\(encryptedSuffix)"
        let processedSuffix = "processed"

        enumerator.forEach({ file in
            // check if it's an encrypted file that ends with .enc
            guard let relativeFilePath = file as? String else { return }
            guard relativeFilePath.hasSuffix(encryptedExtSuffix) else { return }

            // get the last part of the path, which is the filename
            var relativeFilePathComponents = relativeFilePath.components(separatedBy: "/")
            guard let fileName = relativeFilePathComponents.last else { return }

            // get the id (with index) of the message from the filename
            var fileNameComponents = fileName.components(separatedBy: ".")
            guard let fileNameWithIndex = fileNameComponents.first else { return }

            var fileNameWithIndexComponents = fileNameWithIndex.components(separatedBy: "-")

            // strip out the index part of the id only if it's a feedPost, comments and urlpreviews do not have index suffix
            // brittle assumption that the index will be less than 3 digits and an id separated with "-" will have more than 2
            if let mediaIndex = fileNameWithIndexComponents.last, mediaIndex.count < 3 {
                fileNameWithIndexComponents.removeLast()
            }
            let contentID = fileNameWithIndexComponents.joined(separator: "-")
            DDLogInfo("FeedData/cleanUpOldUploadData/file: \(file)/contentID: \(contentID)")

            if let feedPost = MainAppContext.shared.feedData.feedPost(with: contentID, in: viewContext) {
                feedPost.media?.forEach { (media) in
                    guard media.status == .uploaded else { return }
                    DDLogVerbose("FeedData/cleanUpOldUploadData/clean up existing feedpost upload data: \(media.relativeFilePath ?? "")")
                    ImageServer.cleanUpUploadData(directoryURL: directoryURL, relativePath: media.relativeFilePath)
                }
                feedPost.comments?.forEach { comment in
                    comment.media?.forEach { media in
                        guard media.status == .uploaded else { return }
                        DDLogVerbose("FeedData/cleanUpOldUploadData/clean up existing media comment upload data: \(media.relativeFilePath ?? "")")
                        ImageServer.cleanUpUploadData(directoryURL: directoryURL, relativePath: media.relativeFilePath)
                    }
                }
                feedPost.linkPreviews?.forEach { linkPreview in
                    linkPreview.media?.forEach { media in
                        guard media.status == .uploaded else { return }
                        DDLogVerbose("FeedData/cleanUpOldUploadData/clean up existing link preview upload data: \(media.relativeFilePath ?? "")")
                        ImageServer.cleanUpUploadData(directoryURL: directoryURL, relativePath: media.relativeFilePath)
                    }
                }
            } else if let feedPostComment = MainAppContext.shared.feedData.feedComment(with: contentID, in: viewContext) {
                feedPostComment.media?.forEach { media in
                    guard media.status == .uploaded else { return }
                    DDLogVerbose("FeedData/cleanUpOldUploadData/clean up existing media comment upload data: \(media.relativeFilePath ?? "")")
                    ImageServer.cleanUpUploadData(directoryURL: directoryURL, relativePath: media.relativeFilePath)
                }
                feedPostComment.linkPreviews?.forEach { linkPreview in
                    linkPreview.media?.forEach { media in
                        guard media.status == .uploaded else { return }
                        DDLogVerbose("FeedData/cleanUpOldUploadData/clean up existing link preview upload data: \(media.relativeFilePath ?? "")")
                        ImageServer.cleanUpUploadData(directoryURL: directoryURL, relativePath: media.relativeFilePath)
                    }
                }
            } else if let feedLinkPreview = MainAppContext.shared.feedData.feedLinkPreview(with: contentID, in: viewContext) {
                feedLinkPreview.media?.forEach { media in
                    guard media.status == .uploaded else { return }
                    DDLogVerbose("FeedData/cleanUpOldUploadData/clean up existing link preview upload data: \(media.relativeFilePath ?? "")")
                    ImageServer.cleanUpUploadData(directoryURL: directoryURL, relativePath: media.relativeFilePath)
                }
            } else {
                // Content does not exist anymore, get the processed relative filepath and clean up
                if fileNameComponents.count == 4, fileNameComponents[3] == encryptedSuffix, fileNameComponents[1] == processedSuffix {
                    // remove .enc
                    fileNameComponents.removeLast()
                    let processedFileName = fileNameComponents.joined(separator: ".")

                    // remove the last part of the path, which is the filename
                    relativeFilePathComponents.removeLast()
                    let relativeFilePathForProcessed = relativeFilePathComponents.joined(separator: "/")

                    // form the processed filename's relative path
                    let processedRelativeFilePath = relativeFilePathForProcessed + "/" + processedFileName

                    DDLogVerbose("FeedData/cleanUpOldUploadData/clean up unused upload data: \(processedRelativeFilePath)")
                    ImageServer.cleanUpUploadData(directoryURL: directoryURL, relativePath: processedRelativeFilePath)
                }
            }
        })
    }

    // MARK: Deletion

    func deleteUnsentPost(postID: FeedPostID) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let feedPost = self.feedPost(with: postID, in: managedObjectContext) else {
                DDLogError("FeedData/delete-unsent-post/missing-post [\(postID)]")
                return
            }
            guard feedPost.status == .sendError else {
                DDLogError("FeedData/delete-unsent-post/invalid status [\(feedPost.status)]")
                return
            }
            DDLogError("FeedData/delete-unsent-post/deleting [\(postID)]")
            self.deleteMedia(feedPost: feedPost)
            managedObjectContext.delete(feedPost)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    func deletePosts(groupId: String) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let feedFetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
            feedFetchRequest.predicate = NSPredicate(format: "groupId == %@", groupId)
            do {
                let groupFeeds = try self.viewContext.fetch(feedFetchRequest)
                
                groupFeeds.forEach {feed in
                    let postID = feed.id
                    guard let feedPost = self.feedPost(with: postID, in: managedObjectContext) else {
                        DDLogError("FeedData/delete-unsent-post/missing-post [\(postID)]")
                        return
                    }
                    self.deleteMedia(feedPost: feedPost)
                    managedObjectContext.delete(feedPost)
                }
                if managedObjectContext.hasChanges {
                    self.save(managedObjectContext)
                }
            }
            catch {
                DDLogError("ChatData/group/delete-feeds/error  [\(error)]")
                return
            }
        }
        
    }
    

    private func deleteMedia(feedPost: FeedPost) {
        feedPost.media?.forEach { (media) in

            // cancel any pending tasks for this media
            DDLogInfo("FeedData/deleteMedia/post-id \(feedPost.id), media-id: \(media.id)")
            if let currentTask = downloadManager.currentTask(for: media) {
                DDLogInfo("FeedData/deleteMedia/cancelTask/task: \(currentTask.id)")
                currentTask.downloadRequest?.cancel(producingResumeData : false)
            }
            if let encryptedFilePath = media.encryptedFilePath {
                let encryptedURL = MainAppContext.mediaDirectoryURL.appendingPathComponent(encryptedFilePath, isDirectory: false)
                do {
                    if FileManager.default.fileExists(atPath: encryptedURL.path) {
                        try FileManager.default.removeItem(at: encryptedURL)
                        DDLogInfo("FeedData/delete-media-encrypted/deleting [\(encryptedURL)]")
                    }
                }
                catch {
                    DDLogError("FeedData/delete-media-encrypted/error [\(error)]")
                }
            }
            if let relativeFilePath = media.relativeFilePath {
                let fileURL = MainAppContext.mediaDirectoryURL.appendingPathComponent(relativeFilePath, isDirectory: false)
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    DDLogInfo("FeedData/delete-media/deleting [\(fileURL)]")
                }
                catch {
                    DDLogError("FeedData/delete-media/error [\(error)]")
                }
            }
            feedPost.managedObjectContext?.delete(media)
        }
        feedPost.comments?.forEach {
            // Delete comment media if any
            self.deleteMedia(feedPostComment: $0)
            feedPost.managedObjectContext?.delete($0)
        }
        feedPost.linkPreviews?.forEach {
            // Delete link previews if any
            self.deleteMedia(feedLinkPreview: $0)
            feedPost.managedObjectContext?.delete($0)
        }
    }
    
    private func deleteMedia(feedPostComment: FeedPostComment) {
        feedPostComment.media?.forEach { (media) in
            // cancel any pending tasks for this media
            DDLogInfo("FeedData/deleteMedia/comment-id \(feedPostComment.id), media-id: \(media.id)")
            if let currentTask = downloadManager.currentTask(for: media) {
                DDLogInfo("FeedData/deleteMedia/cancelTask/task: \(currentTask.id)")
                currentTask.downloadRequest?.cancel(producingResumeData : false)
            }
            if let encryptedFilePath = media.encryptedFilePath {
                let encryptedURL = MainAppContext.mediaDirectoryURL.appendingPathComponent(encryptedFilePath, isDirectory: false)
                do {
                    if FileManager.default.fileExists(atPath: encryptedURL.path) {
                        try FileManager.default.removeItem(at: encryptedURL)
                        DDLogInfo("FeedData/delete-comment-media-encrypted/deleting [\(encryptedURL)]")
                    }
                }
                catch {
                    DDLogError("FeedData/delete-comment-media-encrypted/error [\(error)]")
                }
            }
            if let relativeFilePath = media.relativeFilePath {
                let fileURL = MainAppContext.mediaDirectoryURL.appendingPathComponent(relativeFilePath, isDirectory: false)
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    DDLogInfo("FeedData/delete-comment-media/deleting [\(fileURL)]")
                }
                catch {
                    DDLogError("FeedData/delete-comment-media/error [\(error)]")
                }
            }
            feedPostComment.managedObjectContext?.delete(media)
        }

        feedPostComment.linkPreviews?.forEach {
            // Delete link previews if any
            self.deleteMedia(feedLinkPreview: $0)
            feedPostComment.managedObjectContext?.delete($0)
        }
    }

    private func deleteMedia(feedLinkPreview: FeedLinkPreview) {
        feedLinkPreview.media?.forEach { (media) in
            // cancel any pending tasks for this media
            DDLogInfo("FeedData/deleteMedia/feedLinkPreview-id \(feedLinkPreview.id), media-id: \(media.id)")
            if let currentTask = downloadManager.currentTask(for: media) {
                DDLogInfo("FeedData/deleteMedia/cancelTask/task: \(currentTask.id)")
                currentTask.downloadRequest?.cancel(producingResumeData : false)
            }
            if let encryptedFilePath = media.encryptedFilePath {
                let encryptedURL = MainAppContext.mediaDirectoryURL.appendingPathComponent(encryptedFilePath, isDirectory: false)
                do {
                    if FileManager.default.fileExists(atPath: encryptedURL.path) {
                        try FileManager.default.removeItem(at: encryptedURL)
                        DDLogInfo("FeedData/delete-feedLinkPreview-media-encrypted/deleting [\(encryptedURL)]")
                    }
                }
                catch {
                    DDLogError("FeedData/delete-feedLinkPreview-media-encrypted/error [\(error)]")
                }
            }
            if let relativeFilePath = media.relativeFilePath {
                let fileURL = MainAppContext.mediaDirectoryURL.appendingPathComponent(relativeFilePath, isDirectory: false)
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    DDLogInfo("FeedData/delete-feedLinkPreview-media/deleting [\(fileURL)]")
                }
                catch {
                    DDLogError("FeedData/delete-feedLinkPreview-media/error [\(error)]")
                }
            }
            feedLinkPreview.managedObjectContext?.delete(media)
        }
    }
    
    private func getPosts(olderThan date: Date, in managedObjectContext: NSManagedObjectContext) -> [FeedPost] {
        let fetchRequest = NSFetchRequest<FeedPost>(entityName: FeedPost.entity().name!)
        fetchRequest.predicate = NSPredicate(format: "timestamp < %@", date as NSDate)
        do {
            return try managedObjectContext.fetch(fetchRequest)
        } catch {
            DDLogError("FeedData/posts/get-expired/error  [\(error)]")
            return []
        }
    }

    public func deletePosts(with postIDs: [FeedPostID]) {
        performSeriallyOnBackgroundContext { context in
            self.deletePosts(with: postIDs, in: context)
            self.save(context)
        }
    }

    private func deletePosts(with postIDs: [FeedPostID], in managedObjectContext: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<FeedPost>(entityName: FeedPost.entity().name!)
        
        fetchRequest.predicate = NSPredicate(format: "id IN %@", Set(postIDs))
        
        do {
            let posts = try managedObjectContext.fetch(fetchRequest)
            guard !posts.isEmpty else {
                DDLogInfo("FeedData/posts/delete/empty")
                return
            }
            DDLogInfo("FeedData/posts/delete/begin  count=[\(posts.count)]")
            posts.forEach { post in
                deleteMedia(feedPost: post)
                managedObjectContext.delete(post)
            }
            DDLogInfo("FeedData/posts/delete-expired/finished")
        } catch {
            DDLogError("FeedData/posts/delete-expired/error  [\(error)]")
            return
        }
    }

    private func deleteNotifications(olderThan date: Date, in managedObjectContext: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<FeedNotification>(entityName: FeedNotification.entity().name!)
        fetchRequest.predicate = NSPredicate(format: "timestamp < %@", date as NSDate)
        do {
            let notifications = try managedObjectContext.fetch(fetchRequest)
            guard !notifications.isEmpty else {
                DDLogInfo("FeedData/notifications/delete-expired/empty")
                return
            }
            DDLogInfo("FeedData/notifications/delete-expired/begin  count=[\(notifications.count)]")
            notifications.forEach { notification in
                managedObjectContext.delete(notification)
            }
            DDLogInfo("FeedData/notifications/delete-expired/finished")
        }
        catch {
            DDLogError("FeedData/notifications/delete-expired/error  [\(error)]")
        }
    }

    private func deleteNotifications(forPosts postIDs: [FeedPostID], in managedObjectContext: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<FeedNotification>(entityName: FeedNotification.entity().name!)
        fetchRequest.predicate = NSPredicate(format: "postId IN %@", postIDs)
        do {
            let notifications = try managedObjectContext.fetch(fetchRequest)
            guard !notifications.isEmpty else {
                DDLogInfo("FeedData/notifications/delete-for-post/empty")
                return
            }
            DDLogInfo("FeedData/notifications/delete-for-post/begin  count=[\(notifications.count)]")
            notifications.forEach { notification in
                managedObjectContext.delete(notification)
            }
            DDLogInfo("FeedData/notifications/delete-for-post/finished")
        }
        catch {
            DDLogError("FeedData/notifications/delete-for-post/error  [\(error)]")
        }
    }
    
    /// Cutoff date at which posts expire and are sent to the archive.
    static let postExpiryTimeInterval = -Date.days(31)
    static let cutoffDate = Date(timeIntervalSinceNow: postExpiryTimeInterval)

    private func deleteExpiredPosts() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            DDLogInfo("FeedData/delete-expired  date=[\(Self.cutoffDate)]")
            let expiredPosts = self.getPosts(olderThan: Self.cutoffDate, in: managedObjectContext)

            let postsToDeleteIncludingUser = expiredPosts.map({ $0.id }) // extract ids before objs get deleted

            let postsToDelete = expiredPosts
                .filter({ $0.userId != MainAppContext.shared.userData.userId })
                .map({ $0.id })

            self.deletePosts(with: postsToDelete, in: managedObjectContext)
            self.deleteAssociatedData(for: postsToDelete, in: managedObjectContext)
            self.save(managedObjectContext)

            // update groups list previews
            MainAppContext.shared.chatData.updateThreadPreviewsOfExpiredPosts(expiredPostIDs: postsToDeleteIncludingUser)

            // update groups list unread count (for unseen posts that expired)
            self.reloadGroupFeedUnreadCounts()
        }
    }
    
    /// Gets expired posts that were posted by the user.
    /// - Parameter completion: Callback function that returns the array of feed post ids
    func getArchivedPosts(completion: @escaping ([FeedPostID]) -> ()) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            DDLogInfo("FeedData/get-archived  date=[\(Self.cutoffDate)]")
            let expiredPosts = self.getPosts(olderThan: Self.cutoffDate, in: managedObjectContext)
            
            let archivedPostIDs = expiredPosts
                .filter({ $0.userId == MainAppContext.shared.userData.userId })
                .map({ $0.id })
            
            completion(archivedPostIDs)
        }
    }
    
    /// Delete data that is no longer relevant for archived posts. Data deleted includes notifications and post comment drafts.
    /// - Parameter posts: Posts to delete related data from.
    func deleteAssociatedData(for posts: [FeedPostID], in managedObjectContext: NSManagedObjectContext) {
        self.performSeriallyOnBackgroundContext { managedObjectContext in
            self.deleteNotifications(forPosts: posts, in: managedObjectContext)
            self.deletePostCommentDrafts(forPosts: posts)
            self.deletePostComments(for: posts, in: managedObjectContext)
            do {
                try managedObjectContext.save()
                DDLogVerbose("FeedData/did-save")
            } catch {
                DDLogError("FeedData/save-error error=[\(error)]")
            }
        }
    }
    
    /// Deletes drafts of comments in `userDefaults` for posts that are no longer available to the user.
    /// - Parameter posts: Posts which are no longer valid. The comment drafts for these posts are deleted.
    private func deletePostCommentDrafts(forPosts posts: [FeedPostID]) {
        Self.deletePostCommentDrafts { existingDraft in
            posts.contains(existingDraft.postID)
        }
    }
    
    private func deletePostComments(for posts: [FeedPostID], in managedObjectContext: NSManagedObjectContext) {
        posts.compactMap { id in
            MainAppContext.shared.feedData.feedPost(with: id)
        }.flatMap { post in
            post.comments ?? []
        }.forEach({ comment in
            managedObjectContext.delete(comment)
        })
    }
    
    /// Deletes drafts of comments in `userDefaults` that meet the condition argument.
    /// - Parameter condition: Should return true when the draft passed in needs to be removed. Returns false otherwise.
    static func deletePostCommentDrafts(when condition: (CommentDraft) -> Bool) {
        var draftsArray: [CommentDraft] = []
        
        if let draftsDecoded: [CommentDraft] = try? AppContext.shared.userDefaults.codable(forKey: CommentsViewController.postCommentDraftKey) {
            draftsArray = draftsDecoded
        }
        
        draftsArray.removeAll(where: condition)
        
        try? AppContext.shared.userDefaults.setCodable(draftsArray, forKey: CommentsViewController.postCommentDraftKey)
    }

    // MARK: - External Share

    func externalShareUrl(for postID: FeedPostID, completion: @escaping (Result<URL, Error>) -> Void) {
        if let url = Self.externalShareInfo(for: postID, in: mainDataStore.viewContext)?.externalShareURL {
            completion(.success(url))
        } else {
            guard let post = feedPost(with: postID) else {
                DDLogError("FeedData/externalShareUrl/could not find post with id \(postID)")
                completion(.failure(RequestError.aborted))
                return
            }

            let postData = post.postData
            let expiry = postData.timestamp.addingTimeInterval(-FeedData.postExpiryTimeInterval)
            let encryptedBlob: Data
            let key: Data
            do {
                (encryptedBlob, key) = try ExternalSharePost.encypt(blob: postData.clientPostContainerBlob)
            } catch {
                DDLogError("FeedData/externalShareUrl/error encrypting post \(error)")
                completion(.failure(error))
                return
            }

            let uploadPostForExternalShare: (URL?, CGSize?) -> Void = { [mainDataStore, service] (thumbURL, thumbSize) in
                service.uploadPostForExternalShare(encryptedBlob: encryptedBlob,
                                                   expiry: expiry,
                                                   ogTitle: Localizations.externalShareTitle(name: MainAppContext.shared.userData.name),
                                                   ogDescription: post.externalShareDescription,
                                                   ogThumbURL: thumbURL,
                                                   ogThumbSize: thumbSize) { [mainDataStore] result in
                    switch result {
                    case .success(let blobID):
                        mainDataStore.performSeriallyOnBackgroundContext { [mainDataStore] context in
                            // Somehow, another request completed before us and already saved external share info.
                            // Discard in flight request and return previously saved data
                            if let url = Self.externalShareInfo(for: postID, in: context)?.externalShareURL {
                                completion(.success(url))
                                return
                            }

                            let externalShareInfo = ExternalShareInfo(context: context)
                            externalShareInfo.blobID = blobID
                            externalShareInfo.feedPostID = postID
                            externalShareInfo.key = key

                            // Make sure we can generate a URL before saving
                            guard let url = externalShareInfo.externalShareURL else {
                                context.delete(externalShareInfo)
                                completion(.failure(RequestError.malformedResponse))
                                return
                            }

                            mainDataStore.save(context)
                            completion(.success(url))
                        }
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }

            if let image = externalShareThumbnail(for: post) {
                let relativePath = "externalsharethumb-\(UUID().uuidString).jpg"
                let uploadFileURL = MainAppContext.mediaDirectoryURL.appendingPathComponent(relativePath)
                if image.save(to: uploadFileURL) {
                    let imageSize = image.size
                    let groupID = "\(post.id)-external"
                    mediaUploader.upload(media: SimpleMediaUploadable(encryptedFilePath: relativePath),
                                         groupId: groupID,
                                         didGetURLs: { _ in }) { [weak mediaUploader] result in
                        // By default, completed tasks are not cleard from the media uploader.
                        // This needs to be dispatched on a different queue as clearTasks is synchronous on
                        // mediauploader's queue, which this completion is dispatched on.
                        DispatchQueue.main.async {
                            mediaUploader?.clearTasks(withGroupID: groupID)
                        }
                        do {
                            try FileManager.default.removeItem(at: uploadFileURL)
                        } catch {
                            DDLogError("FeedData/externalShareUrl/could not clean up thumbnail at \(uploadFileURL): \(error)")
                        }
                        switch result {
                        case .success(let details):
                            uploadPostForExternalShare(details.downloadURL, imageSize)
                            break
                        case .failure(let error):
                            DDLogError("FeedData/externalShareUrl/Error uploading thumbnail: \(error)")
                            uploadPostForExternalShare(nil, nil)
                            break
                        }
                    }
                    // don't fall through to no image case - this will happen via the image upload completion handler
                    return
                }
            }

            uploadPostForExternalShare(nil, nil)
        }
    }

    func revokeExternalShareUrl(for postID: FeedPostID, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let blobID = Self.externalShareInfo(for: postID, in: mainDataStore.viewContext)?.blobID else {
            completion(.failure(RequestError.aborted))
            DDLogWarn("FeedData/revokeExternalShareUrl/trying to revoke external share link for post with no link")
            return
        }

        service.revokeExternalShareLink(blobID: blobID) { [mainDataStore] result in
            switch result {
            case .success:
                mainDataStore.performSeriallyOnBackgroundContext { [mainDataStore] context in
                    // if externalShareInfo does not exist, there's nothing to delete
                    if let externalShareInfo = Self.externalShareInfo(for: postID, in: context) {
                        context.delete(externalShareInfo)
                        mainDataStore.save(context)
                    }
                    completion(.success(()))
                }
            case .failure(let error):
                DDLogError("FeedData/revokeExternalShareUrl/error: \(error)")
                completion(.failure(error))
            }
        }
    }

    func externalSharePost(with blobID: String, key: Data, completion: @escaping (Result<ExternalSharePost, Error>) -> Void) {
        let mainQueueCompletion: (Result<ExternalSharePost, Error>) -> Void = { result in
            DispatchQueue.main.async {
                completion(result)
            }
        }
        let transform: (Server_ExternalSharePostContainer) -> Void = { externalSharePostContainer in
            do {
                let postContainerBlob = try ExternalSharePost.decrypt(encryptedBlob: externalSharePostContainer.blob, key: key)
                mainQueueCompletion(.success(ExternalSharePost(name: externalSharePostContainer.name,
                                                               avatarID: externalSharePostContainer.avatarID,
                                                               postContainerBlob: postContainerBlob)))
            } catch {
                DDLogError("FeedData/externalSharePost/decryptionError: \(error)")
                mainQueueCompletion(.failure(error))
            }
        }

        if userData.isLoggedIn {
            DDLogInfo("FeedData/externalSharePost/fetchingViaService")
            service.externalSharePost(blobID: blobID) { result in
                switch result {
                case .success(let externalSharePostContainer):
                    transform(externalSharePostContainer)
                case .failure(let error):
                    mainQueueCompletion(.failure(error))
                }
            }
        } else {
            // If the user is not logged in, fall back to HTTP
            DDLogInfo("FeedData/externalSharePost/fetchingViaHTTP")

            let url = URL(string: "https://\(ExternalShareInfo.externalShareHost)/\(blobID)?format=pb")!
            var request = URLRequest(url: url)
            request.setValue(AppContext.userAgent, forHTTPHeaderField: "User-Agent")
            let task = URLSession.shared.dataTask(with: request) { (data, urlResponse, error) in
                if let error = error {
                    mainQueueCompletion(.failure(error))
                } else if let data = data {
                    do {
                        transform(try Server_ExternalSharePostContainer(serializedData: data))
                    } catch {
                        mainQueueCompletion(.failure(error))
                    }
                } else {
                    mainQueueCompletion(.failure(RequestError.malformedResponse))
                }
            }
            task.resume()
        }
    }

    func externalShareInfo(for postID: FeedPostID) -> ExternalShareInfo? {
        return Self.externalShareInfo(for: postID, in: mainDataStore.viewContext)
    }

    private class func externalShareInfo(for postID: FeedPostID, in context: NSManagedObjectContext) -> ExternalShareInfo? {
        let fetchRequest = ExternalShareInfo.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "feedPostID = %@", postID)
        fetchRequest.fetchLimit = 1
        fetchRequest.returnsObjectsAsFaults = false
        do {
            return try context.fetch(fetchRequest).first
        } catch {
            DDLogError("FeedData/externalShareInfo/error [\(error)]")
            fatalError("Failed to fetch external share info")
        }
    }

    func externalShareThumbnail(for post: FeedPost) -> UIImage? {
        let thumbnailMedia = media(for: post)
            .filter { [.image, .video].contains($0.type) }
            .sorted { return $0.order < $1.order }
            .first { $0.fileURL != nil }

        guard let thumbnailMedia = thumbnailMedia, let fileURL = thumbnailMedia.fileURL else {
            return nil
        }

        switch thumbnailMedia.type {
        case .image:
            return UIImage.thumbnail(contentsOf: fileURL, maxPixelSize: Self.externalShareThumbSize)
        case .video:
            return VideoUtils.videoPreviewImage(url: fileURL, size: CGSize(width: Self.externalShareThumbSize,
                                                                           height: Self.externalShareThumbSize))
        case .audio:
            return nil
        }
    }

    // MARK: Notifications

    func updateFavoritesPromoNotification() {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            let notifications = self.notifications(for: "favorites", in: managedObjectContext)
            if notifications.count > 0 {
                notifications.forEach {
                    if $0.timestamp < FeedData.cutoffDate {
                        managedObjectContext.delete($0)
                    }
                }
                return
            }
            if !AppContext.shared.userDefaults.bool(forKey: "hasFavoritesNotificationBeenSent") {
                AppContext.shared.userDefaults.set(true, forKey: "hasFavoritesNotificationBeenSent")
                let userId = self.userData.userId
                let notification = FeedNotification(context: managedObjectContext)
                notification.postId = String("favorites")
                notification.event = .favoritesPromo
                notification.timestamp = Date()
                notification.userId = userId
                self.save(managedObjectContext)
            }
        }
    }

    // MARK: Merge Data
    
    let didMergeFeedPost = PassthroughSubject<FeedPostID, Never>()
    
    func mergeData(from sharedDataStore: SharedDataStore, completion: @escaping () -> ()) {
        let posts = sharedDataStore.posts()
        let comments = sharedDataStore.comments()
        guard !posts.isEmpty || !comments.isEmpty else {
            DDLogDebug("FeedData/merge-data/ Nothing to merge")
            completion()
            return
        }
        
        performSeriallyOnBackgroundContext { managedObjectContext in
            self.merge(posts: posts, comments: comments, from: sharedDataStore, using: managedObjectContext, completion: completion)
        }
    }

    private func merge(posts: [SharedFeedPost], comments: [SharedFeedComment], from sharedDataStore: SharedDataStore, using managedObjectContext: NSManagedObjectContext, completion: @escaping () -> ()) {
        let postIds = Set(posts.map{ $0.id })
        let existingPosts = feedPosts(with: postIds, in: managedObjectContext).reduce(into: [FeedPostID: FeedPost]()) { $0[$1.id] = $1 }
        var addedPostIDs = Set<FeedPostID>()
        var newMergedPosts: [FeedPostID] = []

        for post in posts {
            // Skip existing posts that have been decrypted successfully, else process these shared posts.
            if let existingPost = existingPosts[post.id] {
                if existingPost.status == .rerequesting, [.received, .acked].contains(post.status) {
                    DDLogInfo("FeedData/merge-data/already-exists [\(post.id)] override failed decryption.")
                } else {
                    DDLogError("FeedData/merge-data/duplicate (pre-existing) [\(post.id)]")
                    continue
                }
            }
            guard !addedPostIDs.contains(post.id) else {
                DDLogError("FeedData/merge-data/duplicate (duplicate in batch) [\(post.id)")
                continue
            }
            // Dont merge posts with invalid status - these posts were interrupted in between by the user.
            // So, we will discard them completeley and let the user retry it.
            guard post.status != .none else {
                DDLogError("FeedData/merge-data/ignore merging post [\(post.id)], status: \(post.status)")
                continue
            }

            let postId = post.id
            addedPostIDs.insert(postId)

            DDLogDebug("FeedData/merge-data/post/\(postId)")
            let feedPost = NSEntityDescription.insertNewObject(forEntityName: FeedPost.entity().name!, into: managedObjectContext) as! FeedPost
            feedPost.id = post.id
            feedPost.userId = post.userId
            feedPost.groupId = post.groupId
            feedPost.text = post.text
            feedPost.status = {
                switch post.status {
                case .received, .acked: return .incoming
                case .sent: return .sent
                case .none, .sendError: return .sendError
                case .decryptionError, .rerequesting: return .rerequesting
                }
            }()
            feedPost.timestamp = post.timestamp
            if let rawData = post.rawData {
                feedPost.rawData = rawData
                feedPost.status = .unsupported
            }
            // Clear cached media if any.
            cachedMedia[postId] = nil

            // Mentions
            var mentionSet = Set<FeedMention>()
            for mention in post.mentions ?? [] {
                let feedMention = NSEntityDescription.insertNewObject(forEntityName: FeedMention.entity().name!, into: managedObjectContext) as! FeedMention
                feedMention.index = mention.index
                feedMention.userID = mention.userID
                feedMention.name = mention.name
                mentionSet.insert(feedMention)
            }
            feedPost.mentions = mentionSet

            // Post Audience
            if let audience = post.audience {
                let feedPostInfo = NSEntityDescription.insertNewObject(forEntityName: FeedPostInfo.entity().name!, into: managedObjectContext) as! FeedPostInfo
                feedPostInfo.audienceType = audience.audienceType
                feedPostInfo.receipts = audience.userIds.reduce(into: [UserID : Receipt]()) { (receipts, userId) in
                    receipts[userId] = Receipt()
                }
                feedPost.info = feedPostInfo
            }
            
            // Process link preview if present
            post.linkPreviews?.forEach { linkPreviewData in
                DDLogDebug("FeedData/merge-data/post/\(postId)/add-link-preview [\(String(describing: linkPreviewData.url))]")
                let linkPreview = NSEntityDescription.insertNewObject(forEntityName: FeedLinkPreview.entity().name!, into: managedObjectContext) as! FeedLinkPreview
                linkPreview.id = PacketID.generate()
                linkPreview.url = linkPreviewData.url
                linkPreview.title = linkPreviewData.title
                linkPreview.desc = linkPreviewData.desc
                // Set preview image if present
                linkPreviewData.media?.forEach { previewMedia in
                    let media = NSEntityDescription.insertNewObject(forEntityName: FeedPostMedia.entity().name!, into: managedObjectContext) as! FeedPostMedia
                    media.type = previewMedia.type
                    media.status = .none
                    media.url = previewMedia.url
                    media.size = previewMedia.size
                    media.key = previewMedia.key
                    media.sha256 = previewMedia.sha256
                    media.linkPreview = linkPreview

                    // Copy media if there'a a local copy (outgoing posts or incoming posts with downloaded media).
                    if let relativeFilePath = previewMedia.relativeFilePath {
                        let pendingMedia = PendingMedia(type: media.type)
                        pendingMedia.fileURL = sharedDataStore.fileURL(forRelativeFilePath: relativeFilePath)
                        if media.status == .uploadError {
                            // Only copy encrypted file if media failed to upload so that upload could be retried.
                            pendingMedia.encryptedFileUrl = pendingMedia.fileURL!.appendingPathExtension("enc")
                        }
                        do {
                            try downloadManager.copyMedia(from: pendingMedia, to: media)
                        }
                        catch {
                            DDLogError("FeedData/merge-data/post/\(postId)/copy-media-error [\(error)]")

                            if media.status == .downloaded {
                                media.status = .none
                            }
                        }
                    }
                }
                linkPreview.post = feedPost
            }

            // Media
            post.media?.forEach { (media) in
                DDLogDebug("FeedData/merge-data/post/\(postId)/add-media [\(media)] - [\(media.status)]")

                let feedMedia = NSEntityDescription.insertNewObject(forEntityName: FeedPostMedia.entity().name!, into: managedObjectContext) as! FeedPostMedia
                feedMedia.type = media.type
                feedMedia.status = {
                    switch media.status {
                    // Incoming
                    case .none: return .none
                    case .downloaded: return .downloaded

                    // Outgoing
                    case .uploaded: return .uploaded
                    case .uploading, .error: return .uploadError
                    }
                }()
                feedMedia.url = media.url
                feedMedia.uploadUrl = media.uploadUrl
                feedMedia.size = media.size
                feedMedia.key = media.key
                feedMedia.order = media.order
                feedMedia.sha256 = media.sha256
                feedMedia.blobVersion = media.blobVersion
                feedMedia.chunkSize = media.chunkSize
                feedMedia.blobSize = media.blobSize
                feedMedia.post = feedPost

                // Copy media if there'a a local copy (outgoing posts or incoming posts with downloaded media).
                if let relativeFilePath = media.relativeFilePath {
                    let pendingMedia = PendingMedia(type: feedMedia.type)
                    pendingMedia.fileURL = sharedDataStore.fileURL(forRelativeFilePath: relativeFilePath)
                    if feedMedia.status == .uploadError {
                        // Only copy encrypted file if media failed to upload so that upload could be retried.
                        pendingMedia.encryptedFileUrl = pendingMedia.fileURL!.appendingPathExtension("enc")
                    }
                    do {
                        try downloadManager.copyMedia(from: pendingMedia, to: feedMedia)
                    }
                    catch {
                        DDLogError("FeedData/merge-data/post/\(postId)/copy-media-error [\(error)]")

                        if feedMedia.status == .downloaded {
                            feedMedia.status = .none
                        }
                    }
                }
            }
            
            newMergedPosts.append(feedPost.id)            
        }

        // Merge comments after posts.
        let newMergedComments = comments.compactMap { merge(sharedComment: $0, into: managedObjectContext) }

        // Save merged objects
        managedObjectContext.mergePolicy = NSRollbackMergePolicy
        save(managedObjectContext)

        // Add comments to the notifications database.
        generateNotifications(for: newMergedComments, using: managedObjectContext)

        // Notify
        newMergedPosts.forEach({ didMergeFeedPost.send($0) })
        newMergedComments.forEach({ didReceiveFeedPostComment.send($0) })

        DDLogInfo("FeedData/merge-data/finished")

        sharedDataStore.delete(posts: posts, comments: comments) {
            completion()
        }
    }
    
    /// Creates new comment with data from shared feed comment and increments parent post's unread count. Does not save context.
    func merge(sharedComment: SharedFeedComment, into managedObjectContext: NSManagedObjectContext) -> FeedPostComment? {
        let postId = sharedComment.postId
        let commentId = sharedComment.id

        // Fetch feedpost
        guard let feedPost = self.feedPost(with: postId, in: managedObjectContext) else {
            DDLogError("FeedData/merge/comment/error  Missing FeedPost with id [\(postId)]")
            return nil
        }
        
        // Fetch parentCommentId
        var parentComment: FeedPostComment?
        if let parentCommentId = sharedComment.parentCommentId {
            parentComment = feedComment(with: parentCommentId, in: managedObjectContext)
            if parentComment == nil {
                DDLogError("FeedData/merge/comment/error  Missing parent comment with id=[\(parentCommentId)]")
            }
        }

        // Skip existing comments that have been decrypted successfully, else process these shared comments.
        if let existingComment = feedComment(with: sharedComment.id, in: managedObjectContext) {
            if existingComment.status == .rerequesting, [.received, .acked].contains(sharedComment.status) {
                DDLogInfo("FeedData/mergeComment/already-exists [\(sharedComment.id)] override failed decryption.")
            } else {
                DDLogError("FeedData/mergeComment/duplicate (pre-existing) [\(sharedComment.id)]")
                return nil
            }
        }

        // Add mentions
        var mentionSet = Set<FeedMention>()
        sharedComment.mentions?.forEach({ mention in
            let feedMention = NSEntityDescription.insertNewObject(forEntityName: FeedMention.entity().name!, into: managedObjectContext) as! FeedMention
            feedMention.index = mention.index
            feedMention.userID = mention.userID
            feedMention.name = mention.name
            if feedMention.name == "" {
                DDLogError("FeedData/merge/comment/mention/\(mention.userID) missing push name")
            }
            mentionSet.insert(feedMention)
        })
        
        // Process link preview if present
        var linkPreviews = Set<FeedLinkPreview>()
        sharedComment.linkPreviews?.forEach { sharedLinkPreviewData in
            DDLogDebug("FeedData/process-comments/new/add-link-preview [\(String(describing: sharedLinkPreviewData.url))]")

            let linkPreview = NSEntityDescription.insertNewObject(forEntityName: FeedLinkPreview.entity().name!, into: managedObjectContext) as! FeedLinkPreview
            linkPreview.id = PacketID.generate()
            linkPreview.url = sharedLinkPreviewData.url
            linkPreview.title = sharedLinkPreviewData.title
            linkPreview.desc = sharedLinkPreviewData.desc
            // Set preview image if present
            sharedLinkPreviewData.media?.forEach { sharedPreviewMedia in
                let media = NSEntityDescription.insertNewObject(forEntityName: FeedPostMedia.entity().name!, into: managedObjectContext) as! FeedPostMedia
                media.type = sharedPreviewMedia.type
                media.status = .none
                media.url = sharedPreviewMedia.url
                media.size = sharedPreviewMedia.size
                media.key = sharedPreviewMedia.key
                media.sha256 = sharedPreviewMedia.sha256
                media.linkPreview = linkPreview
            }
            linkPreviews.insert(linkPreview)
        }

        // Add media
        var mediaItems = Set<FeedPostMedia>()
        sharedComment.media?.forEach({ mediaItem in
            let feedCommentMedia = NSEntityDescription.insertNewObject(forEntityName: FeedPostMedia.entity().name!, into: managedObjectContext) as! FeedPostMedia
            feedCommentMedia.type = mediaItem.type
            feedCommentMedia.status = {
                switch mediaItem.status {
                // Incoming
                case .none: return .none
                case .downloaded: return .downloaded

                // Outgoing
                case .uploaded: return .uploaded
                case .uploading, .error: return .uploadError
                }
            }()
            feedCommentMedia.url = mediaItem.url
            feedCommentMedia.size = mediaItem.size
            feedCommentMedia.key = mediaItem.key
            feedCommentMedia.order = mediaItem.order
            feedCommentMedia.sha256 = mediaItem.sha256
            feedCommentMedia.blobVersion = mediaItem.blobVersion
            feedCommentMedia.chunkSize = mediaItem.chunkSize
            feedCommentMedia.blobSize = mediaItem.blobSize
            mediaItems.insert(feedCommentMedia)
        })
        // Create comment
        DDLogInfo("FeedData/merge/comment id=[\(commentId)]  postId=[\(postId)]")
        let feedComment = NSEntityDescription.insertNewObject(forEntityName: FeedPostComment.entity().name!, into: managedObjectContext) as! FeedPostComment
        feedComment.id = commentId
        feedComment.userId = sharedComment.userId
        feedComment.text = sharedComment.text
        feedComment.mentions = mentionSet
        feedComment.media = mediaItems
        feedComment.linkPreviews = linkPreviews
        feedComment.parent = parentComment
        feedComment.post = feedPost
        feedComment.status = {
            switch sharedComment.status {
            case .received, .acked: return .incoming
            case .sent: return .sent
            case .none, .sendError: return .sendError
            case .decryptionError, .rerequesting: return .rerequesting
            }
        }()
        feedComment.timestamp = sharedComment.timestamp
        // Clear cached media if any.
        cachedMedia[commentId] = nil
        
        if let rawData = sharedComment.rawData {
            feedComment.rawData = rawData
            feedComment.status = .unsupported
        }
        // Increase unread comments counter on post.
        feedPost.unreadCount += 1

        return feedComment
    }
}

extension FeedData: HalloFeedDelegate {

    func halloService(_ halloService: HalloService, didRerequestGroupFeedItem contentID: String, contentType: GroupFeedRerequestContentType, from userID: UserID, ack: (() -> Void)?) {
        DDLogDebug("FeedData/didRerequestContent [\(contentID)] - [\(contentType)] - from: \(userID)")

        handleRerequest(for: contentID, contentType: contentType, from: userID) { result in
            switch result {
            case .failure(let error):
                DDLogError("FeedData/didRerequestGroupFeedItem/\(contentID)/\(contentType)/error: \(error)/from: \(userID)")
                if error.canAck {
                    ack?()
                }
            case .success:
                DDLogInfo("FeedData/didRerequestGroupFeedItem/\(contentID)/\(contentType)success/from: \(userID)")
                ack?()
            }
        }
    }

    func halloService(_ halloService: HalloService, didRerequestGroupFeedHistory contentID: String, from userID: UserID, ack: (() -> Void)?) {
        mainDataStore.performSeriallyOnBackgroundContext{ [mainDataStore] managedObjectContext in
            let resendInfo = mainDataStore.fetchContentResendInfo(for: contentID, userID: userID, in: managedObjectContext)
            resendInfo.retryCount += 1
            // retryCount indicates number of times content has been rerequested until now: increment and use it when sending.
            let rerequestCount = resendInfo.retryCount
            DDLogInfo("FeedData/didRerequestGroupFeedHistory/\(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount)")

            guard rerequestCount <= 5 else {
                DDLogError("FeedData/didRerequestGroupFeedHistory/\(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount) - aborting")
                ack?()
                return
            }

            guard let content = mainDataStore.groupHistoryInfo(for: contentID, in: managedObjectContext) else {
                DDLogError("FeedData/didRerequestGroupFeedHistory/\(contentID)/error could not find groupHistoryInfo")
                ack?()
                return
            }

            resendInfo.groupHistoryInfo = content
            self.service.sendGroupFeedHistoryPayload(id: contentID, groupID: content.groupId, payload: content.payload, to: userID, rerequestCount: rerequestCount) { result in
                switch result {
                case .success():
                    DDLogInfo("FeedData/didRerequestGroupFeedHistory/\(contentID) success/userID: \(userID)/rerequestCount: \(rerequestCount)")
                    ack?()
                case .failure(let error):
                    DDLogError("FeedData/didRerequestGroupFeedHistory/\(contentID) error \(error)")
                }
            }
        }
    }

    func halloService(_ halloService: HalloService, didReceiveFeedPayload payload: HalloServiceFeedPayload, ack: (() -> Void)?) {
        switch payload.content {
        case .newItems(let feedItems):
            processIncomingFeedItems(feedItems, groupID: payload.group?.groupId, presentLocalNotifications: payload.isEligibleForNotification, ack: ack)

        case .retracts(let retracts):
            processIncomingFeedRetracts(retracts, groupID: payload.group?.groupId, ack: ack)
        }
    }

    func halloService(_ halloService: HalloService, didReceiveFeedReceipt receipt: HalloReceipt, ack: (() -> Void)?) {
        DDLogInfo("FeedData/seen-receipt/incoming itemId=[\(receipt.itemId)]")
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let feedPost = self.feedPost(with: receipt.itemId, in: managedObjectContext) else {
                DDLogError("FeedData/seen-receipt/missing-post [\(receipt.itemId)]")
                ack?()
                return
            }
            feedPost.willChangeValue(forKey: "info")
            if feedPost.info == nil {
                feedPost.info = NSEntityDescription.insertNewObject(forEntityName: FeedPostInfo.entity().name!, into: managedObjectContext) as? FeedPostInfo
            }
            var receipts = feedPost.info!.receipts ?? [:]
            if receipts[receipt.userId] == nil {
                receipts[receipt.userId] = Receipt()
            }
            receipts[receipt.userId]!.seenDate = receipt.timestamp
            DDLogInfo("FeedData/seen-receipt/update  userId=[\(receipt.userId)]  ts=[\(receipt.timestamp!)]  itemId=[\(receipt.itemId)]")
            feedPost.info!.receipts = receipts
            feedPost.didChangeValue(forKey: "info")

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }

            ack?()
        }
    }

    func halloService(_ halloService: HalloService, didSendFeedReceipt receipt: HalloReceipt) {
        updateFeedPost(with: receipt.itemId) { (feedPost) in
            // Dont mark the status to be seen if the post is retracted or if the post is rerequested.
            if !feedPost.isPostRetracted && !feedPost.isRerequested {
                feedPost.status = .seen
            }
        }
    }
}
