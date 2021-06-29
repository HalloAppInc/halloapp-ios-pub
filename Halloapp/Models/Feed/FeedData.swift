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
import CoreData
import Foundation
import SwiftUI
import Intents
import IntentsUI

class FeedData: NSObject, ObservableObject, FeedDownloadManagerDelegate, NSFetchedResultsControllerDelegate {

    private let userData: UserData
    private let contactStore: ContactStoreMain
    private var service: HalloService

    private var cancellableSet: Set<AnyCancellable> = []

    private(set) var feedNotifications: FeedNotifications?

    let willDestroyStore = PassthroughSubject<Void, Never>()
    let didReloadStore = PassthroughSubject<Void, Never>()
    
    let didGetRemoveHomeTabIndicator = PassthroughSubject<Void, Never>()

    private struct UserDefaultsKey {
        static let persistentStoreUserID = "feed.store.userID"
    }

    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.feed")
    private lazy var downloadManager: FeedDownloadManager = {
        let downloadManager = FeedDownloadManager(mediaDirectoryURL: MainAppContext.mediaDirectoryURL)
        downloadManager.delegate = self
        return downloadManager
    }()

    let mediaUploader: MediaUploader
    private let imageServer = ImageServer()

    init(service: HalloService, contactStore: ContactStoreMain, userData: UserData) {
        self.service = service
        self.contactStore = contactStore
        self.userData = userData
        self.mediaUploader = MediaUploader(service: service)

        super.init()

        self.service.feedDelegate = self
        mediaUploader.resolveMediaPath = { (relativePath) in
            return MainAppContext.mediaDirectoryURL.appendingPathComponent(relativePath, isDirectory: false)
        }

        /* enable videoes to play with sound even when the phone is set to ringer mode */
        do {
           try AVAudioSession.sharedInstance().setCategory(.playback)
        } catch(let error) {
            DDLogError("FeedData/  Failed to set AVAudioSession category to \"Playback\" error=[\(error.localizedDescription)]")
        }

        // when app resumes, xmpp reconnects, feed should try uploading any pending again
        cancellableSet.insert(
            self.service.didConnect.sink {
                DDLogInfo("Feed: Got event for didConnect")

                self.deleteExpiredPosts()
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
                    DDLogInfo("FeedData/didLogin Persistent store / user ID mismatch. Unloading feed data. \(self.feedDataItems.count) posts")
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
                DDLogError("Deleting persistent store at [\(FeedData.persistentStoreURL.absoluteString)]")
                try! FileManager.default.removeItem(at: FeedData.persistentStoreURL)
                fatalError("Unable to load persistent store: \(error)")
            } else {
                DDLogInfo("FeedData/load-store/completed [\(description)]")
            }
        }
    }

    private func performSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        self.backgroundProcessingQueue.async {
            let managedObjectContext = self.persistentContainer.newBackgroundContext()
            managedObjectContext.performAndWait { block(managedObjectContext) }
        }
    }

    var viewContext: NSManagedObjectContext {
        get {
            self.persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
            return self.persistentContainer.viewContext
        }
    }

    private func save(_ managedObjectContext: NSManagedObjectContext) {
        DDLogVerbose("FeedData/will-save")
        do {
            try managedObjectContext.save()
            DDLogVerbose("FeedData/did-save")
        } catch {
            DDLogError("FeedData/save-error error=[\(error)]")
        }
    }

    func destroyStore() {
        DDLogInfo("FeedData/destroy/start")

        // Tell subscribers that everything is going away forever.
        self.willDestroyStore.send()

        self.fetchedResultsController.delegate = nil
        self.feedDataItems = []
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

    var feedDataItems : [FeedDataItem] = []

    private func reloadFeedDataItems(using feedPosts: [FeedPost], fullReload: Bool = true) {
        if fullReload {
            self.feedDataItems = feedPosts.map { FeedDataItem($0) }
            return
        }

        // Reload re-using existing FeedDataItem.
        // Preserving existing objects is a requirement for proper functioning of SwiftUI interfaces.
        let feedDataItemMap = self.feedDataItems.reduce(into: [:]) { $0[$1.id] = $1 }
        self.feedDataItems = feedPosts.map{ (feedPost) -> FeedDataItem in
            if let feedDataItem = feedDataItemMap[feedPost.id] {
                return feedDataItem
            }
            return FeedDataItem(feedPost)
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
                    send(comment: comment)
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
                reloadFeedDataItems(using: feedPosts)
                DDLogInfo("FeedData/fetch/completed \(feedDataItems.count) posts")

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
        self.trackPerRowChanges = !self.feedDataItems.isEmpty
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any,
                    at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        guard trackPerRowChanges else { return }
        switch type {
        case .insert:
            guard let index = newIndexPath?.row, let feedPost = anObject as? FeedPost else {
                return
            }
            DDLogDebug("FeedData/frc/insert [\(feedPost)] at [\(index)]")
            // For some reason FRC can report invalid indexes when downloading initial batch of posts.
            // When that happens, ignore further per-row updates and reload everything altogether in `didChange`.
            if index < self.feedDataItems.count {
                self.feedDataItems.insert(FeedDataItem(feedPost), at: index)
            } else {
                self.trackPerRowChanges = false
            }

        case .delete:
            guard let index = indexPath?.row, let feedPost = anObject as? FeedPost else {
                return
            }
            DDLogDebug("FeedData/frc/delete [\(feedPost)] at [\(index)]")
            if index < self.feedDataItems.count {
                self.feedDataItems.remove(at: index)
            } else {
                self.trackPerRowChanges = false
            }

        case .update:
            guard let index = indexPath?.row, let feedPost = anObject as? FeedPost else {
                return
            }
            DDLogDebug("FeedData/frc/update [\(feedPost)] at [\(index)]")
            self.feedDataItems[index].reload(from: feedPost)

        case .move:
            guard let fromIndex = indexPath?.row, let toIndex = newIndexPath?.row, let feedPost = anObject as? FeedPost else {
                return
            }
            DDLogDebug("FeedData/frc/move [\(feedPost)] from [\(fromIndex)] to [\(toIndex)]")
            // TODO: move

        default:
            break
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogDebug("FeedData/frc/did-change")
        if !trackPerRowChanges {
            if let feedPosts = self.fetchedResultsController.fetchedObjects {
                self.reloadFeedDataItems(using: feedPosts, fullReload: false)
                DDLogInfo("FeedData/frc/reload \(self.feedDataItems.count) posts")
            }
        }

        setNeedsReloadGroupFeedUnreadCounts()
    }

    // MARK: Fetching Feed Data

    func feedDataItem(with id: FeedPostID) -> FeedDataItem? {
        return self.feedDataItems.first(where: { $0.id == id })
    }

    private func feedPosts(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext? = nil) -> [FeedPost] {
        let managedObjectContext = managedObjectContext ?? self.viewContext
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = predicate
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

    func feedPost(with id: FeedPostID, in managedObjectContext: NSManagedObjectContext? = nil) -> FeedPost? {
        return self.feedPosts(predicate: NSPredicate(format: "id == %@", id), in: managedObjectContext).first
    }

    private func feedPosts(with ids: Set<FeedPostID>, in managedObjectContext: NSManagedObjectContext? = nil) -> [FeedPost] {
        return feedPosts(predicate: NSPredicate(format: "id in %@", ids), in: managedObjectContext)
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

    private func feedComments(with ids: Set<FeedPostCommentID>, in managedObjectContext: NSManagedObjectContext) -> [FeedPostComment] {
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

    // MARK: Updates

    private func updateFeedPost(with id: FeedPostID, block: @escaping (FeedPost) -> (), performAfterSave: (() -> ())? = nil) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            defer {
                if let performAfterSave = performAfterSave {
                    performAfterSave()
                }
            }
            guard let feedPost = self.feedPost(with: id, in: managedObjectContext) else {
                DDLogError("FeedData/update-post/missing-post [\(id)]")
                return
            }
            DDLogVerbose("FeedData/update-post [\(id)]")
            block(feedPost)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }

    private func updateFeedPostComment(with id: FeedPostCommentID, block: @escaping (FeedPostComment) -> (), performAfterSave: (() -> ())? = nil) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
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

    func markCommentsAsRead(feedPostId: FeedPostID) {
        updateFeedPost(with: feedPostId) { (feedPost) in
            if feedPost.unreadCount != 0 {
                feedPost.unreadCount = 0
            }
        }
        markNotificationsAsRead(for: feedPostId)
    }

    // MARK: Process Incoming Feed Data

    let didReceiveFeedPost = PassthroughSubject<FeedPost, Never>()

    let didReceiveFeedPostComment = PassthroughSubject<FeedPostComment, Never>()

    @discardableResult private func process(posts xmppPosts: [PostData],
                                            receivedIn group: HalloGroup?,
                                            using managedObjectContext: NSManagedObjectContext,
                                            presentLocalNotifications: Bool) -> [FeedPost] {
        guard !xmppPosts.isEmpty else { return [] }

        let postIds = Set(xmppPosts.map{ $0.id })
        let existingPosts = feedPosts(with: postIds, in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
        var newPosts: [FeedPost] = []
        for xmppPost in xmppPosts {
            guard existingPosts[xmppPost.id] == nil else {
                DDLogError("FeedData/process-posts/duplicate [\(xmppPost.id)]")
                continue
            }

            // Add new FeedPost to database.
            DDLogDebug("FeedData/process-posts/new [\(xmppPost.id)]")
            let feedPost = NSEntityDescription.insertNewObject(forEntityName: FeedPost.entity().name!, into: managedObjectContext) as! FeedPost
            feedPost.id = xmppPost.id
            feedPost.userId = xmppPost.userId
            feedPost.groupId = group?.groupId
            feedPost.text = xmppPost.text
            feedPost.timestamp = xmppPost.timestamp

            switch xmppPost.content {
            case .album, .text:
                // Mark our own posts as seen in case server sends us old posts following re-registration
                feedPost.status = feedPost.userId == userData.userId ? .seen : .incoming
            case .retracted:
                DDLogError("FeedData/process-posts/incoming-retracted-post [\(xmppPost.id)]")
                feedPost.status = .retracted
            case .unsupported(let data):
                feedPost.status = .unsupported
                feedPost.rawData = data
            }

            var mentions = Set<FeedMention>()
            for xmppMention in xmppPost.orderedMentions {
                let mention = NSEntityDescription.insertNewObject(forEntityName: FeedMention.entity().name!, into: managedObjectContext) as! FeedMention
                mention.index = xmppMention.index
                mention.userID = xmppMention.userID
                mention.name = xmppMention.name
                mentions.insert(mention)
            }
            feedPost.mentions = mentions

            // Process post media
            for (index, xmppMedia) in xmppPost.orderedMedia.enumerated() {
                DDLogDebug("FeedData/process-posts/new/add-media [\(xmppMedia.url!)]")
                let feedMedia = NSEntityDescription.insertNewObject(forEntityName: FeedPostMedia.entity().name!, into: managedObjectContext) as! FeedPostMedia
                switch xmppMedia.type {
                case .image:
                    feedMedia.type = .image
                case .video:
                    feedMedia.type = .video
                }
                feedMedia.status = .none
                feedMedia.url = xmppMedia.url
                feedMedia.size = xmppMedia.size
                feedMedia.key = xmppMedia.key
                feedMedia.order = Int16(index)
                feedMedia.sha256 = xmppMedia.sha256
                feedMedia.post = feedPost
            }

            newPosts.append(feedPost)
        }
        DDLogInfo("FeedData/process-posts/finished  \(newPosts.count) new items.  \(xmppPosts.count - newPosts.count) duplicates.")
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
            feedPosts.forEach({ self.didReceiveFeedPost.send($0) })
        }

        checkForUnreadFeed()
        return newPosts
    }

    @discardableResult private func process(comments xmppComments: [CommentData],
                                            receivedIn group: HalloGroup?,
                                            using managedObjectContext: NSManagedObjectContext,
                                            presentLocalNotifications: Bool) -> [FeedPostComment] {
        guard !xmppComments.isEmpty else { return [] }

        let feedPostIds = Set(xmppComments.map{ $0.feedPostId })
        let posts = feedPosts(with: feedPostIds, in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
        let commentIds = Set(xmppComments.map{ $0.id }).union(Set(xmppComments.compactMap{ $0.parentId }))
        var comments = feedComments(with: commentIds, in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
        var ignoredCommentIds: Set<String> = []
        var xmppCommentsMutable = [CommentData](xmppComments)
        var newComments: [FeedPostComment] = []
        var duplicateCount = 0, numRuns = 0
        while !xmppCommentsMutable.isEmpty && numRuns < 100 {
            for xmppComment in xmppCommentsMutable {
                // Detect duplicate comments.
                guard comments[xmppComment.id] == nil else {
                    duplicateCount += 1
                    DDLogError("FeedData/process-comments/duplicate [\(xmppComment.id)]")
                    continue
                }

                // Find comment's post.
                guard let feedPost = posts[xmppComment.feedPostId] else {
                    DDLogError("FeedData/process-comments/missing-post [\(xmppComment.feedPostId)]")
                    ignoredCommentIds.insert(xmppComment.id)
                    continue
                }

                // Additional check: post's groupId must match groupId of the comment.
                guard feedPost.groupId == group?.groupId else {
                    DDLogError("FeedData/process-comments/incorrect-group-id post:[\(feedPost.groupId ?? "")] comment:[\(group?.groupId ?? "")]")
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
                if xmppComment.parentId != nil {
                    parentComment = comments[xmppComment.parentId!]
                    if parentComment == nil {
                        DDLogInfo("FeedData/process-comments/missing-parent/skip [\(xmppComment.id)]")
                        continue
                    }
                }

                // Add new FeedPostComment to database.
                DDLogDebug("FeedData/process-comments/new [\(xmppComment.id)]")
                let comment = NSEntityDescription.insertNewObject(forEntityName: FeedPostComment.entity().name!, into: managedObjectContext) as! FeedPostComment
                comment.id = xmppComment.id
                comment.userId = xmppComment.userId
                comment.parent = parentComment
                comment.post = feedPost

                switch xmppComment.content {
                case .text(let mentionText):
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
                case .retracted:
                    DDLogError("FeedData/process-comments/incoming-retracted-comment [\(xmppComment.id)]")
                    comment.status = .retracted
                case .unsupported(let data):
                    comment.status = .unsupported
                    comment.rawData = data
                }
                comment.timestamp = xmppComment.timestamp

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

    private func processIncomingFeedItems(_ items: [FeedElement], group: HalloGroup?, presentLocalNotifications: Bool, ack: (() -> Void)?) {
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
                switch comment.content {
                case .text(let mentionText):
                    for (_, user) in mentionText.mentions {
                        guard let pushName = user.pushName, !pushName.isEmpty else { continue }
                        contactNames[user.userID] = pushName
                    }
                case .retracted, .unsupported:
                    break
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
            let posts = self.process(posts: feedPosts, receivedIn: group, using: managedObjectContext, presentLocalNotifications: presentLocalNotifications)
            self.generateNotifications(for: posts, using: managedObjectContext)

            let comments = self.process(comments: comments, receivedIn: group, using: managedObjectContext, presentLocalNotifications: presentLocalNotifications)
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
                }
            } else {
                notification.mediaType = .none
            }
            DDLogInfo("FeedData/generateNotifications  New notification [\(notification)]")

            // Step 3. Generate media preview for the notification.
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
                guard let protoContainer = feedPost.clientContainer else { return }
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

            guard let feedPost = self.feedPost(with: postId, in: managedObjectContext) else {
                DDLogError("FeedData/retract-post/error Missing post. [\(postId)]")
                completion()
                return
            }
            guard feedPost.status != .retracted  else {
                DDLogError("FeedData/retract-post/error Already retracted. [\(postId)]")
                completion()
                return
            }
            DDLogInfo("FeedData/retract-post [\(postId)]")

            // 1. Delete media.
            self.deleteMedia(in: feedPost)

            // 2. Delete comments.
            feedPost.comments?.forEach { managedObjectContext.delete($0) }

            // 3. Reset all notifications for this post.
            let notifications = self.notifications(for: postId, in: managedObjectContext)
            notifications.forEach { (notification) in
                notification.event = .retractedPost
                notification.text = nil
                notification.mediaType = .none
                notification.mediaPreview = nil
            }

            // 4. Reset post data and mark post as deleted.
            feedPost.text = nil
            feedPost.status = .retracted

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }

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

            // 2. Reset comment text copied over to notifications.
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

    private func processIncomingFeedRetracts(_ retracts: [FeedRetract], group: HalloGroup?, ack: (() -> Void)?) {
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

    func retract(post feedPost: FeedPost) {
        let postId = feedPost.id

        // Mark post as "being retracted"
        feedPost.status = .retracting
        save(viewContext)

        // Request to retract.
        service.retractPost(feedPost) { result in
            switch result {
            case .success:
                self.processPostRetract(postId) {}

            case .failure(_):
                self.updateFeedPost(with: postId) { (post) in
                    post.status = .sent
                }
            }
        }
    }

    func retract(comment: FeedPostComment) {
        let commentId = comment.id

        // Mark comment as "being retracted".
        comment.status = .retracting
        save(viewContext)

        // Request to retract.
        service.retractComment(id: comment.id, postID: comment.post.id) { result in
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
        guard feedPost.status == .incoming || feedPost.status == .seenSending else {
            DDLogWarn("FeedData/seen-receipt/ignore Incorrect post status: \(feedPost.status)")
            return
        }
        feedPost.status = .seenSending
        service.sendReceipt(itemID: feedPost.id, thread: .feed, type: .read, fromUserID: userData.userId, toUserID: feedPost.userId)
    }

    func sendSeenReceiptIfNecessary(for feedPost: FeedPost) {
        guard feedPost.status == .incoming else { return }

        let postId = feedPost.id
        updateFeedPost(with: postId) { [weak self] (post) in
            guard let self = self else { return }
            // Check status again in case one of these blocks was already queued
            guard post.status == .incoming else { return }
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
            map[contact.userId!] = contact
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
            var predicate = NSPredicate(format: "groupId = nil && statusValue = %d", FeedPost.Status.incoming.rawValue)
            if ServerProperties.isCombineFeedEnabled {
                predicate = NSPredicate(format: "statusValue = %d", FeedPost.Status.incoming.rawValue)
            }
            let unreadFeedPosts = self.feedPosts(predicate: predicate, in: managedObjectContext)
            self.didGetUnreadFeedCount.send(unreadFeedPosts.count)
        }
    }
    
    // MARK: Feed Media

    func downloadTask(for mediaItem: FeedMedia) -> FeedDownloadManager.Task? {
        guard let feedPost = feedPost(with: mediaItem.feedPostId) else { return nil }
        guard let feedPostMedia = feedPost.media?.first(where: { $0.order == mediaItem.order }) else { return nil }
        return downloadManager.currentTask(for: feedPostMedia)
    }

    // MARK: Suspending and Resuming

    func suspendMediaDownloads() {
        downloadManager.suspendMediaDownloads()
    }

    // We resume media downloads for all these objects on Application/WillEnterForeground.
    func resumeMediaDownloads() {
        var pendingPostIds: Set<FeedPostID> = []
        // Iterate through all the suspendedMediaObjectIds and download media for those posts.
        downloadManager.suspendedMediaObjectIds.forEach { feedMediaObjectId in
            // Fetch FeedPostMedia
            guard let feedPostMedia = try? viewContext.existingObject(with: feedMediaObjectId) as? FeedPostMedia else {
                DDLogError("FeedData/resumeMediaDownloads/error missing-object [\(feedMediaObjectId)]")
                return
            }
            pendingPostIds.insert(feedPostMedia.post.id)
            DDLogInfo("FeedData/resumeMediaDownloads/pendingPostId/added post_id - \(feedPostMedia.post.id)")
        }
        downloadManager.suspendedMediaObjectIds.removeAll()
        // Download media for all these posts.
        downloadMedia(in: feedPosts(with: pendingPostIds))
    }

    /**
     This method must be run on the main queue to avoid race condition.
     */
    // Why use viewContext to update FeedPostMedia here?
    // Why does this need to run on the main queue - UI updates are anyways posted to the main queue?
    func downloadMedia(in feedPosts: [FeedPost]) {
        guard !feedPosts.isEmpty else { return }
        let managedObjectContext = self.viewContext
        // FeedPost objects should belong to main queue's context.
        assert(feedPosts.first!.managedObjectContext! == managedObjectContext)

        // List of mediaItem info that will need UI update.
        var mediaItems = [(FeedPostID, Int)]()
        var downloadStarted = false
        feedPosts.forEach { feedPost in
            DDLogInfo("FeedData/downloadMedia/post_id - \(feedPost.id)")
            let postDownloadGroup = DispatchGroup()
            var startTime: Date?
            var photosDownloaded = 0
            var videosDownloaded = 0
            var totalDownloadSize = 0

            feedPost.media?.forEach { feedPostMedia in
                // Status could be "downloading" if download has previously started
                // but the app was terminated before the download has finished.
                if feedPostMedia.url != nil && (feedPostMedia.status == .none || feedPostMedia.status == .downloading || feedPostMedia.status == .downloadError) {
                    let (taskAdded, task) = downloadManager.downloadMedia(for: feedPostMedia)
                    if taskAdded {
                        switch feedPostMedia.type {
                        case .image: photosDownloaded += 1
                        case .video: videosDownloaded += 1
                        }
                        if startTime == nil {
                            startTime = Date()
                            DDLogInfo("FeedData/downloadMedia/post/\(feedPost.id)/starting")
                        }
                        postDownloadGroup.enter()
                        var isDownloadInProgress = true
                        cancellableSet.insert(task.downloadProgress.sink() { progress in
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
            }
            postDownloadGroup.notify(queue: .main) {
                guard photosDownloaded > 0 || videosDownloaded > 0 else { return }
                guard let startTime = startTime else {
                    DDLogError("FeedData/downloadMedia/post/\(feedPost.id)/error start time not set")
                    return
                }
                let duration = Date().timeIntervalSince(startTime)
                DDLogInfo("FeedData/downloadMedia/post/\(feedPost.id)/finished [photos: \(photosDownloaded)] [videos: \(videosDownloaded)] [t: \(duration)]")
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
        if managedObjectContext.hasChanges && downloadStarted {
            self.save(managedObjectContext)

            // Update UI for these items.
            DispatchQueue.main.async {
                mediaItems.forEach{ (feedPostId, order) in
                    self.reloadMedia(feedPostId: feedPostId, order: order)
                }
            }
        }
    }

    func reloadMedia(feedPostId: FeedPostID, order: Int) {
        DDLogInfo("FeedData/reloadMedia/postId:\(feedPostId), order/\(order)")
        guard let feedDataItem = self.feedDataItem(with: feedPostId) else { return }
        guard let feedPost = self.feedPost(with: feedPostId) else { return }
        feedDataItem.reloadMedia(from: feedPost, order: order)
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
            let feedPostId = feedPostMedia.post.id
            let mediaOrder = Int(feedPostMedia.order)
            DispatchQueue.main.async {
                self.reloadMedia(feedPostId: feedPostId, order: mediaOrder)
            }

            // Step 4: Update upload data to avoid duplicate uploads
            if let path = feedPostMedia.relativeFilePath, let downloadUrl = feedPostMedia.url {
                let fileUrl = MainAppContext.mediaDirectoryURL.appendingPathComponent(path, isDirectory: false)
                MainAppContext.shared.uploadData.update(upload: fileUrl, key: feedPostMedia.key, sha256: feedPostMedia.sha256, downloadURL: downloadUrl)
            }
        }
    }

    private func updateNotificationMediaPreview(with postMedia: FeedPostMedia, using managedObjectContext: NSManagedObjectContext) {
        guard postMedia.relativeFilePath != nil else { return }
        let feedPost = postMedia.post
        let feedPostId = postMedia.post.id

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

    func post(text: MentionText, media: [PendingMedia], to destination: FeedPostDestination) {
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
            feedMedia.post = feedPost

            // Copying depends on all data fields being set, so do this last.
            do {
                try downloadManager.copyMedia(from: mediaItem, to: feedMedia)

                if let encryptedFileURL = mediaItem.encryptedFileUrl {
                    try FileManager.default.removeItem(at: encryptedFileURL)
                    DDLogInfo("FeedData/new-post/removed-temporary-file [\(encryptedFileURL.absoluteString)]")
                }
            }
            catch {
                DDLogError("FeedData/new-post/copy-media/error [\(error)]")
            }
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
            
            addIntent(chatGroup: chatGroup)
        }

        // set a merge policy so that we dont end up with duplicate feedposts.
        managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        save(managedObjectContext)

        uploadMediaAndSend(feedPost: feedPost)
        
        if feedPost.groupId != nil {
            didSendGroupFeedPost.send(feedPost)
        }
    }

    @discardableResult
    func post(comment: MentionText, to feedItem: FeedDataItem, replyingTo parentCommentId: FeedPostCommentID? = nil) -> FeedPostCommentID {
        let commentId: FeedPostCommentID = PacketID.generate()

        // Create and save FeedPostComment
        let managedObjectContext = self.persistentContainer.viewContext
        guard let feedPost = self.feedPost(with: feedItem.id, in: managedObjectContext) else {
            DDLogError("FeedData/new-comment/error  Missing FeedPost with id [\(feedItem.id)]")
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
        save(managedObjectContext)

        // Now send data over the wire.
        send(comment: feedComment)
        
        if let groupId = feedPost.groupId, let chatGroup = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
            addIntent(chatGroup: chatGroup)
        }

        return commentId
    }

    func retryPosting(postId: FeedPostID) {
        let managedObjectContext = self.persistentContainer.viewContext

        guard let feedPost = self.feedPost(with: postId, in: managedObjectContext) else { return }
        guard feedPost.status == .sendError else { return }

        // Change status to "sending" and start sending / uploading.
        feedPost.status = .sending
        save(managedObjectContext)
        uploadMediaAndSend(feedPost: feedPost)
    }

    func resend(commentWithId commentId: FeedPostCommentID) {
        let managedObjectContext = self.persistentContainer.viewContext

        guard let comment = self.feedComment(with: commentId, in: managedObjectContext) else { return }
        guard comment.status == .sendError else { return }

        // Change status to "sending" and send.
        comment.status = .sending
        save(managedObjectContext)

        send(comment: comment)
    }

    private func send(comment: FeedPostComment) {
        let commentId = comment.id
        let groupId = comment.post.groupId
        service.publishComment(comment.commentData, groupId: groupId) { result in
            switch result {
            case .success(let timestamp):
                self.updateFeedPostComment(with: commentId) { (feedComment) in
                    feedComment.timestamp = timestamp
                    feedComment.status = .sent
                }

            case .failure(let error):
                // TODO: Track this state more precisely. Even if this attempt was a definite failure, a previous attempt may have succeeded.
                if error.isKnownFailure {
                    self.updateFeedPostComment(with: commentId) { (feedComment) in
                        feedComment.status = .sendError
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
        service.publishPost(post, feed: feed) { result in
            switch result {
            case .success(let timestamp):
                self.updateFeedPost(with: postId) { (feedPost) in
                    feedPost.timestamp = timestamp
                    feedPost.status = .sent
                }

            case .failure(let error):
                // TODO: Track this state more precisely. Even if this attempt was a definite failure, a previous attempt may have succeeded.
                if error.isKnownFailure {
                    self.updateFeedPost(with: postId) { (feedPost) in
                        feedPost.status = .sendError
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
    
    /// Donates an intent to Siri for improved suggestions when sharing content.
    ///
    /// Intents are used by iOS to provide contextual suggestions to the user for certain interactions. In this case, we are suggesting the user send another message to the user they just shared with.
    /// For more information, see [this documentation](https://developer.apple.com/documentation/sirikit/insendmessageintent)\.
    /// - Parameter chatGroup: The ID for the group the user is sharing to
    /// - Remark: This is different from the implementation in `ShareComposerViewController.swift` because `MainAppContext` isn't available in the share extension.
    private func addIntent(chatGroup: ChatGroup) {
        if #available(iOS 14.0, *) {
            let recipient = INSpeakableString(spokenPhrase: chatGroup.name)
            let sendMessageIntent = INSendMessageIntent(recipients: nil,
                                                        content: nil,
                                                        speakableGroupName: recipient,
                                                        conversationIdentifier: ConversationID(id: chatGroup.groupId, type: .group).description,
                                                        serviceName: nil,
                                                        sender: nil)
            
            let potentialUserAvatar = MainAppContext.shared.avatarStore.groupAvatarData(for: chatGroup.groupId).image
            guard let defaultAvatar = UIImage(named: "AvatarGroup") else { return }
            
            // Have to convert UIImage to data and then NIImage because NIImage(uiimage: UIImage) initializer was throwing exception
            guard let userAvaterUIImage = (potentialUserAvatar ?? defaultAvatar).pngData() else { return }
            let userAvatar = INImage(imageData: userAvaterUIImage)
            
            sendMessageIntent.setImage(userAvatar, forParameterNamed: \.speakableGroupName)
            
            let interaction = INInteraction(intent: sendMessageIntent, response: nil)
            interaction.donate(completion: { error in
                if let error = error {
                    DDLogDebug("ChatViewController/sendMessage/\(error.localizedDescription)")
                }
            })
        }
    }

    // MARK: Media Upload
    private func uploadMediaAndSend(feedPost: FeedPost) {
        let postId = feedPost.id

        // Either all media has already been uploaded or post does not contain media.
        guard let mediaItemsToUpload = feedPost.media?.filter({ $0.status == .none || $0.status == .uploading || $0.status == .uploadError }), !mediaItemsToUpload.isEmpty else {
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
            DDLogDebug("FeedData/process-mediaItem: \(postId)/\(mediaItem.order), index: \(mediaIndex)")
            if let relativeFilePath = mediaItem.relativeFilePath, mediaItem.sha256.isEmpty && mediaItem.key.isEmpty {
                let url = MainAppContext.mediaDirectoryURL.appendingPathComponent(relativeFilePath, isDirectory: false)
                let output = url.deletingPathExtension().appendingPathExtension("processed").appendingPathExtension(url.pathExtension)

                imageServer.prepare(mediaItem.type, url: url, output: output) { [weak self] in
                    guard let self = self else { return }
                    switch $0 {
                    case .success(let result):
                        let path = self.downloadManager.relativePath(from: output)
                        DDLogDebug("FeedData/process-mediaItem/success: \(postId)/\(mediaIndex)")
                        self.updateFeedPost(with: postId, block: { (feedPost) in
                            if let media = feedPost.media?.first(where: { $0.order == mediaIndex }) {
                                media.size = result.size
                                media.key = result.key
                                media.sha256 = result.sha256
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
            if numberOfFailedUploads > 0 {
                self.updateFeedPost(with: postId) { (feedPost) in
                    feedPost.status = .sendError
                }
            } else if let feedPost = self.feedPost(with: postId) {
                self.send(post: feedPost)
                AppContext.shared.eventMonitor.observe(
                    .mediaUpload(
                        postID: postId,
                        duration: Date().timeIntervalSince(startTime),
                        numPhotos: mediaItemsToUpload.filter { $0.type == .image }.count,
                        numVideos: mediaItemsToUpload.filter { $0.type == .video }.count,
                        totalSize: totalUploadSize))
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

        MainAppContext.shared.uploadData.fetch(upload: processed) { [weak self] upload in
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

                            MainAppContext.shared.uploadData.update(upload: processed, key: media.key, sha256: media.sha256, downloadURL: media.url!)
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
            self.deleteMedia(in: feedPost)
            managedObjectContext.delete(feedPost)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }

    private func deleteMedia(in feedPost: FeedPost) {
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
    }

    @discardableResult
    private func deletePosts(olderThan date: Date, in managedObjectContext: NSManagedObjectContext) -> [FeedPostID] {
        let fetchRequest = NSFetchRequest<FeedPost>(entityName: FeedPost.entity().name!)
        fetchRequest.predicate = NSPredicate(format: "timestamp < %@", date as NSDate)
        do {
            let posts = try managedObjectContext.fetch(fetchRequest)
            let postIDs = posts.map { $0.id }
            guard !posts.isEmpty else {
                DDLogInfo("FeedData/posts/delete-expired/empty")
                return postIDs
            }
            DDLogInfo("FeedData/posts/delete-expired/begin  count=[\(posts.count)]")
            posts.forEach { post in
                deleteMedia(in: post)
                managedObjectContext.delete(post)
            }
            DDLogInfo("FeedData/posts/delete-expired/finished")
            return postIDs
        }
        catch {
            DDLogError("FeedData/posts/delete-expired/error  [\(error)]")
            return []
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

    private func deleteExpiredPosts() {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let cutoffDate = Date(timeIntervalSinceNow: -Date.days(31))
            DDLogInfo("FeedData/delete-expired  date=[\(cutoffDate)]")
            let expiredPostIDs = self.deletePosts(olderThan: cutoffDate, in: managedObjectContext)
            self.deleteNotifications(olderThan: cutoffDate, in: managedObjectContext)
            self.deleteNotifications(forPosts: expiredPostIDs, in: managedObjectContext)
            self.deletePostCommentDrafts(forPosts: expiredPostIDs)
            self.save(managedObjectContext)
        }
    }
    
    /// Deletes drafts of comments in `userDefaults` for posts that are no longer available to the user.
    /// - Parameter posts: Posts which are no longer valid. The comment drafts for these posts are deleted.
    private func deletePostCommentDrafts(forPosts posts: [FeedPostID]) {
        Self.deletePostCommentDrafts { existingDraft in
            posts.contains(existingDraft.postID)
        }
    }
    
    /// Deletes drafts of comments in `userDefaults` that meet the condition argument.
    /// - Parameter condition: Should return true when the draft passed in needs to be removed. Returns false otherwise.
    static func deletePostCommentDrafts(when condition: (CommentDraft) -> Bool) {
        var draftsArray: [CommentDraft] = []
        
        if let draftsDecoded: [CommentDraft] = try? AppContext.shared.userDefaults.codable(forKey: CommentsViewController.postCommentDraftKey) {
            draftsArray = draftsDecoded
        }
        
        draftsArray.removeAll(where: condition)
        
        try? AppContext.shared.userDefaults.setValue(value: draftsArray, forKey: CommentsViewController.postCommentDraftKey)
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
            guard existingPosts[post.id] == nil else {
                DDLogError("FeedData/merge-data/duplicate (pre-existing) [\(post.id)]")
                continue
            }
            guard !addedPostIDs.contains(post.id) else {
                DDLogError("FeedData/merge-data/duplicate (duplicate in batch) [\(post.id)")
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
                case .received: return .incoming
                case .sent: return .sent
                case .none, .sendError: return .sendError
                }
            }()
            feedPost.timestamp = post.timestamp

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

            // Media
            post.media?.forEach { (media) in
                DDLogDebug("FeedData/merge-data/post/\(postId)/add-media [\(media)]")

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

        // Create comment
        DDLogInfo("FeedData/merge/comment id=[\(commentId)]  postId=[\(postId)]")
        let feedComment = NSEntityDescription.insertNewObject(forEntityName: FeedPostComment.entity().name!, into: managedObjectContext) as! FeedPostComment
        feedComment.id = commentId
        feedComment.userId = sharedComment.userId
        feedComment.text = sharedComment.text
        feedComment.mentions = mentionSet
        feedComment.parent = parentComment
        feedComment.post = feedPost
        feedComment.status = {
            switch sharedComment.status {
            case .received: return .incoming
            case .sent: return .sent
            case .none, .sendError: return .sendError
            }
        }()
        feedComment.timestamp = sharedComment.timestamp
        
        // Increase unread comments counter on post.
        feedPost.unreadCount += 1

        return feedComment
    }
}

extension FeedData: HalloFeedDelegate {

    func halloService(_ halloService: HalloService, didReceiveFeedPayload payload: HalloServiceFeedPayload, ack: (() -> Void)?) {
        switch payload.content {
        case .newItems(let feedItems):
            processIncomingFeedItems(feedItems, group: payload.group, presentLocalNotifications: payload.isEligibleForNotification, ack: ack)

        case .retracts(let retracts):
            processIncomingFeedRetracts(retracts, group: payload.group, ack: ack)
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
            if !feedPost.isPostRetracted {
                feedPost.status = .seen
            }
        }
    }
}
