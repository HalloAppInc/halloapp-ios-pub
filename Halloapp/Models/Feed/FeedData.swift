//
//  FeedModel.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/1/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import AVKit
import CocoaLumberjack
import Combine
import Core
import CoreData
import Foundation
import SwiftUI

class FeedData: NSObject, ObservableObject, FeedDownloadManagerDelegate, NSFetchedResultsControllerDelegate {

    private let userData: UserData
    private let contactStore: ContactStoreMain
    private var service: HalloService

    private var cancellableSet: Set<AnyCancellable> = []

    private(set) var feedNotifications: FeedNotifications?

    let willDestroyStore = PassthroughSubject<Void, Never>()
    let didReloadStore = PassthroughSubject<Void, Never>()

    private struct UserDefaultsKey {
        static let persistentStoreUserID = "feed.store.userID"
    }

    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.feed")
    private var bgContext: NSManagedObjectContext
    
    private lazy var downloadManager: FeedDownloadManager = {
        let downloadManager = FeedDownloadManager(mediaDirectoryURL: MainAppContext.mediaDirectoryURL)
        downloadManager.delegate = self
        return downloadManager
    }()

    let mediaUploader: MediaUploader

    init(service: HalloService, contactStore: ContactStoreMain, userData: UserData) {
        self.service = service
        self.contactStore = contactStore
        self.userData = userData
        self.bgContext = self.persistentContainer.newBackgroundContext()
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

        cancellableSet.insert(
            NotificationCenter.default
                .publisher(for: UIContentSizeCategory.didChangeNotification)
                .eraseToAnyPublisher()
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    self.feedDataItems.forEach({ $0.cachedCellHeight = nil })
                })

        fetchFeedPosts()
    }

    // MARK: CoreData stack

    private class var persistentStoreURL: URL {
        get {
            return MainAppContext.feedStoreURL
        }
    }

    private var persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: FeedData.persistentStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let container = NSPersistentContainer(name: "Feed")
        container.persistentStoreDescriptions = [storeDescription]
        container.loadPersistentStores { (description, error) in
            if let error = error {
                DDLogError("FeedData/Failed to load persistent store: \(error)")
                fatalError("FeedData/Unable to load persistent store: \(error)")
            } else {
                DDLogInfo("FeedData/load-store/completed [\(description)]")
            }
        }
        return container
    }()

    private func loadPersistentStores(in persistentContainer: NSPersistentContainer) {
        persistentContainer.loadPersistentStores { (description, error) in
            if let error = error {
                DDLogError("FeedData/loadPersistentStores/Failed to load persistent store: \(error)")
                fatalError("FeedData/loadPersistentStores/Unable to load persistent store: \(error)")
            } else {
                DDLogInfo("FeedData/loadPersistentStores/load-store/completed [\(description)]")
            }
        }
    }

    private func performSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        backgroundProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            self.bgContext.performAndWait { block(self.bgContext) }
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

    @Published var isFeedEmpty: Bool = true

    var feedDataItems : [FeedDataItem] = [] {
        didSet {
            self.isFeedEmpty = feedDataItems.isEmpty
        }
    }

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

    private func fetchFeedPosts() {
        do {
            try fetchedResultsController.performFetch()
            if let feedPosts = fetchedResultsController.fetchedObjects {
                reloadFeedDataItems(using: feedPosts)
                DDLogInfo("FeedData/fetch/completed \(feedDataItems.count) posts")

                // 1. Turn tasks stuck in "sending" state into "sendError".
                let idsOfTasksInProgress = mediaUploader.activeTaskGroupIdentifiers()
                let stuckPosts = feedPosts.filter({ $0.status == .sending }).filter({ !idsOfTasksInProgress.contains($0.id) })
                if !stuckPosts.isEmpty {
                    stuckPosts.forEach({ $0.status = .sendError })
                    save(fetchedResultsController.managedObjectContext)
                }

                // 2. Mitigate server bug when timestamps were sent in milliseconds.
                // 2.1 Posts
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
                // 2.2 Comments
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

                // 2.3 Notifications
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
        } else {
            self.isFeedEmpty = self.feedDataItems.isEmpty
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

    @discardableResult private func process(posts xmppPosts: [FeedPostProtocol],
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
            
            if feedPost.userId == userData.userId {
                // This only happens when the user re-register,
                // and the server sends us old posts.
                feedPost.status = .seen
            } else {
                feedPost.status = .incoming
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

    @discardableResult private func process(comments xmppComments: [FeedCommentProtocol],
                                            receivedIn group: HalloGroup?,
                                            using managedObjectContext: NSManagedObjectContext,
                                            presentLocalNotifications: Bool) -> [FeedPostComment] {
        guard !xmppComments.isEmpty else { return [] }

        let feedPostIds = Set(xmppComments.map{ $0.feedPostId })
        let posts = feedPosts(with: feedPostIds, in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
        let commentIds = Set(xmppComments.map{ $0.id }).union(Set(xmppComments.compactMap{ $0.parentId }))
        var comments = feedComments(with: commentIds, in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
        var ignoredCommentIds: Set<String> = []
        var xmppCommentsMutable = [FeedCommentProtocol](xmppComments)
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

                // Check if parent comment has been retracted.
                if parentComment?.isRetracted ?? false {
                    DDLogError("FeedData/process-comments/retracted-parent [\(parentComment!.id)]")
                    ignoredCommentIds.insert(xmppComment.id)
                    continue
                }

                // Add new FeedPostComment to database.
                DDLogDebug("FeedData/process-comments/new [\(xmppComment.id)]")
                let comment = NSEntityDescription.insertNewObject(forEntityName: FeedPostComment.entity().name!, into: managedObjectContext) as! FeedPostComment
                comment.id = xmppComment.id
                comment.userId = xmppComment.userId
                comment.text = xmppComment.text
                comment.parent = parentComment
                comment.post = feedPost
                comment.status = .incoming
                comment.timestamp = xmppComment.timestamp

                var mentions = Set<FeedMention>()
                for xmppMention in xmppComment.orderedMentions {
                    let mention = NSEntityDescription.insertNewObject(forEntityName: FeedMention.entity().name!, into: managedObjectContext) as! FeedMention
                    mention.index = xmppMention.index
                    mention.userID = xmppMention.userID
                    mention.name = xmppMention.name
                    mentions.insert(mention)
                }
                comment.mentions = mentions

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
        var feedPosts = [FeedPostProtocol]()
        var comments = [FeedCommentProtocol]()
        var contactNames = [UserID:String]()

        for item in items {
            switch item {
            case .post(let post):
                feedPosts.append(post)
            case .comment(let comment, let name):
                comments.append(comment)
                if let name = name {
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
            self.generateMediaPreview(for: notification, feedPost: post, using: managedObjectContext)
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
            self.generateMediaPreview(for: notification, feedPost: comment.post, using: managedObjectContext)
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
        guard UIApplication.shared.applicationState == .background else { return }

        let userIds = Set(comments.map { $0.userId })
        let contactNames = contactStore.fullNames(forUserIds: userIds)

        var commentIdsToFilterOut = [FeedPostCommentID]()

        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        UNUserNotificationCenter.current().getFeedCommentIdsForDeliveredNotifications { (commentIds) in
            commentIdsToFilterOut = commentIds
            dispatchGroup.leave()
        }

        dispatchGroup.notify(queue: .main) {
            var notifications: [UNMutableNotificationContent] = []
            comments.filter { !commentIdsToFilterOut.contains($0.id) && self.isCommentEligibleForLocalNotification($0) }.forEach { (comment) in
                let protoContainer = comment.protoContainer
                let protobufData = try? protoContainer.serializedData()
                let contentType: NotificationContentType = comment.post.groupId == nil ? .feedComment : .groupFeedComment
                let metadata = NotificationMetadata(contentId: comment.id,
                                                    contentType: contentType,
                                                    fromId: comment.userId,
                                                    data: protobufData,
                                                    timestamp: comment.timestamp)
                if let groupId = comment.post.groupId,
                   let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                    metadata.groupId = group.groupId
                    metadata.groupName = group.name
                }

                let contactName = contactNames[comment.userId] ?? Localizations.unknownContact
                let notification = UNMutableNotificationContent()
                notification.title = [contactName, metadata.groupName].compactMap({ $0 }).joined(separator: " @ ")
                notification.populate(withDataFrom: protoContainer, notificationMetadata: metadata, mentionNameProvider: { userID in
                    self.contactStore.mentionName(for: userID, pushName: protoContainer.mentionPushName(for: userID))
                })
                notification.userInfo[NotificationMetadata.userInfoKey] = metadata.rawData

                notifications.append(notification)
            }

            guard !notifications.isEmpty else { return }

            let notificationCenter = UNUserNotificationCenter.current()
            notifications.forEach { (notificationContent) in
                notificationCenter.add(UNNotificationRequest(identifier: UUID().uuidString, content: notificationContent, trigger: nil))
            }
        }
    }

    private func presentLocalNotifications(forFeedPosts feedPosts: [FeedPost]) {
        guard UIApplication.shared.applicationState == .background else { return }

        let userIds = Set(feedPosts.map { $0.userId })
        let contactNames = contactStore.fullNames(forUserIds: userIds)

        var postIdsToFilterOut = [FeedPostID]()

        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        UNUserNotificationCenter.current().getFeedPostIdsForDeliveredNotifications { (feedPostIds) in
            postIdsToFilterOut = feedPostIds
            dispatchGroup.leave()
        }

        dispatchGroup.notify(queue: .main) {
            var notifications: [UNMutableNotificationContent] = []
            feedPosts.filter({ !postIdsToFilterOut.contains($0.id) }).forEach { (feedPost) in
                let protoContainer = feedPost.protoContainer
                let protobufData = try? protoContainer.serializedData()
                let metadataContentType: NotificationContentType = feedPost.groupId == nil ? .feedPost : .groupFeedPost
                let metadata = NotificationMetadata(contentId: feedPost.id,
                                                    contentType: metadataContentType,
                                                    fromId: feedPost.userId,
                                                    data: protobufData,
                                                    timestamp: feedPost.timestamp)
                if let groupId = feedPost.groupId,
                   let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                    metadata.groupId = group.groupId
                    metadata.groupName = group.name
                }

                let contactName = contactNames[feedPost.userId] ?? Localizations.unknownContact
                let notification = UNMutableNotificationContent()
                notification.title = [contactName, metadata.groupName].compactMap({ $0 }).joined(separator: " @ ")
                notification.populate(withDataFrom: protoContainer, notificationMetadata: metadata, mentionNameProvider: { userID in
                    self.contactStore.mentionName(for: userID, pushName: protoContainer.mentionPushName(for: userID))
                })
                notification.userInfo[NotificationMetadata.userInfoKey] = metadata.rawData

                notifications.append(notification)
            }

            let notificationCenter = UNUserNotificationCenter.current()
            notifications.forEach { (notificationContent) in
                notificationCenter.add(UNNotificationRequest(identifier: UUID().uuidString, content: notificationContent, trigger: nil))
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

            // 5. Clear cached cell height
            self.feedDataItem(with: feedPost.id)?.cachedCellHeight = nil

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }

            if feedPost.groupId != nil {
                self.didProcessGroupFeedPostRetract.send(feedPost.id)
            }
            
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
        service.retractFeedItem(feedPost) { result in
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
        service.retractFeedItem(comment) { result in
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

    func sentReceipts(from userIds: Set<UserID>) -> [FeedPostReceipt] {

        var unknownContactIDs = userIds

        // Known contacts go first, sorted using Address Book sort.
        var receipts: [FeedPostReceipt] = []
        let knownContacts = contactStore.sortedContacts(withUserIds: Array(userIds))
        var uniqueUserIDs: Set<UserID> = [] // Contacts need to be de-duped by userId.
        for abContact in knownContacts {
            if let userId = abContact.userId, uniqueUserIDs.insert(userId).inserted {
                let phoneNumber = abContact.phoneNumber?.formattedPhoneNumber
                receipts.append(FeedPostReceipt(userId: userId, type: .sent, contactName: abContact.fullName, phoneNumber: phoneNumber, timestamp: Date()))
                unknownContactIDs.remove(userId)
            }
        }

        // Unknown contacts are at the end, sorted by push name.
        var receiptsForUnknownContacts: [FeedPostReceipt] = []
        for userId in unknownContactIDs {
            let contactName = contactStore.fullName(for: userId)
            receiptsForUnknownContacts.append(FeedPostReceipt(userId: userId, type: .sent, contactName: contactName, phoneNumber: nil, timestamp: Date()))
        }
        receiptsForUnknownContacts.sort(by: { $0.contactName! < $1.contactName! })

        receipts.append(contentsOf: receiptsForUnknownContacts)

        return receipts
    }

    let didFindUnreadFeed = PassthroughSubject<Int, Never>()
    
    func checkForUnreadFeed() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            var predicate = NSPredicate(format: "groupId = nil && statusValue = %d", FeedPost.Status.incoming.rawValue)
            if ServerProperties.isCombineFeedEnabled {
                predicate = NSPredicate(format: "statusValue = %d", FeedPost.Status.incoming.rawValue)
            }
            let unreadFeedPosts = self.feedPosts(predicate: predicate, in: managedObjectContext)
            self.didFindUnreadFeed.send(unreadFeedPosts.count)
        }
    }
    
    // MARK: Feed Media

    func downloadTask(for mediaItem: FeedMedia) -> FeedDownloadManager.Task? {
        guard let feedPost = feedPost(with: mediaItem.feedPostId) else { return nil }
        guard let feedPostMedia = feedPost.media?.first(where: { $0.order == mediaItem.order }) else { return nil }
        return downloadManager.currentTask(for: feedPostMedia)
    }

    func suspendMediaDownloads() {
        downloadManager.suspendMediaDownloads()
    }
    /**
     This method must be run on the main queue to avoid race condition.
     */
    func downloadMedia(in feedPosts: [FeedPost]) {
        guard !feedPosts.isEmpty else { return }
        let managedObjectContext = self.viewContext
        // FeedPost objects should belong to main queue's context.
        assert(feedPosts.first!.managedObjectContext! == managedObjectContext)

        var downloadStarted = false
        feedPosts.forEach { feedPost in
            let postDownloadGroup = DispatchGroup()
            var startTime: Date?
            var photosDownloaded = 0
            var videosDownloaded = 0

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
                                isDownloadInProgress = false
                                postDownloadGroup.leave()
                            }
                        })

                        task.feedMediaObjectId = feedPostMedia.objectID
                        feedPostMedia.status = .downloading
                        downloadStarted = true
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
                        numVideos: videosDownloaded))
            }
        }
        // Use `downloadStarted` to prevent recursive saves when posting media.
        if managedObjectContext.hasChanges && downloadStarted {
            self.save(managedObjectContext)
        }
    }

    func reloadMedia(feedPostId: FeedPostID, order: Int) {
        guard let feedDataItem = self.feedDataItem(with: feedPostId) else { return }
        guard let feedPost = self.feedPost(with: feedPostId) else { return }
        feedDataItem.reloadMedia(from: feedPost, order: order)
    }

    func feedDownloadManager(_ manager: FeedDownloadManager, didFinishTask task: FeedDownloadManager.Task) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            // Step 1: Update FeedPostMedia
            guard let feedPostMedia = try? managedObjectContext.existingObject(with: task.feedMediaObjectId!) as? FeedPostMedia else {
                DDLogError("FeedData/download-task/\(task.id)/error  Missing FeedPostMedia  taskId=[\(task.id)]  objectId=[\(task.feedMediaObjectId!)]")
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
        }
    }

    private func updateNotificationMediaPreview(with postMedia: FeedPostMedia, using managedObjectContext: NSManagedObjectContext) {
        guard postMedia.relativeFilePath != nil else { return }
        // TODO: add support for video previews
        guard postMedia.type == .image else { return }
        let feedPostId = postMedia.post.id

        // Fetch all associated notifications.
        let fetchRequest: NSFetchRequest<FeedNotification> = FeedNotification.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "postId == %@", feedPostId)
        do {
            let notifications = try managedObjectContext.fetch(fetchRequest)
            if !notifications.isEmpty {
                self.updateMediaPreview(for: notifications, usingImageAt: MainAppContext.mediaDirectoryURL.appendingPathComponent(postMedia.relativeFilePath!, isDirectory: false))
            }
        }
        catch {
            DDLogError("FeedData/fetch-notifications/error  [\(error)]")
            fatalError("Failed to fetch feed notifications.")
        }
    }

    private func generateMediaPreview(for notification: FeedNotification, feedPost: FeedPost, using managedObjectContext: NSManagedObjectContext) {
        guard let postMedia = feedPost.orderedMedia.first as? FeedPostMedia else { return }
        guard postMedia.type == .image else { return }
        // TODO: add support for video previews
        guard let mediaPath = postMedia.relativeFilePath else { return }
        self.updateMediaPreview(for: [ notification ], usingImageAt: MainAppContext.mediaDirectoryURL.appendingPathComponent(mediaPath, isDirectory: false))
    }

    private func updateMediaPreview(for notifications: [FeedNotification], usingImageAt url: URL) {
        guard let image = UIImage(contentsOfFile: url.path) else {
            DDLogError("FeedData/notification/preview/error  Failed to load image at [\(url)]")
            return
        }
        guard let preview = image.resized(to: CGSize(width: 128, height: 128), contentMode: .scaleAspectFill, downscaleOnly: false) else {
            DDLogError("FeedData/notification/preview/error  Failed to generate preview for image at [\(url)]")
            return
        }
        guard let imageData = preview.jpegData(compressionQuality: 0.5) else {
            DDLogError("FeedData/notification/preview/error  Failed to generate PNG for image at [\(url)]")
            return
        }
        notifications.forEach { $0.mediaPreview = imageData }
    }

    // MARK: Posting
    
    let didSendGroupFeedPost = PassthroughSubject<FeedPost, Never>()

    func post(text: MentionText, media: [PendingMedia], to destination: FeedPostDestination) {
        let postId: FeedPostID = UUID().uuidString

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
        for (index, userID) in text.mentions {
            let feedMention = NSEntityDescription.insertNewObject(forEntityName: FeedMention.entity().name!, into: managedObjectContext) as! FeedMention
            feedMention.index = index
            feedMention.userID = userID
            feedMention.name = contactStore.pushNames[userID] ?? ""
            if feedMention.name == "" {
                DDLogError("FeedData/new-post/mention/\(userID) missing push name")
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
            feedMedia.key = mediaItem.key!
            feedMedia.sha256 = mediaItem.sha256!
            feedMedia.order = Int16(index)
            feedMedia.post = feedPost

            // Copying depends on all data fields being set, so do this last.
            do {
                try downloadManager.copyMedia(from: mediaItem, to: feedMedia)
            }
            catch {
                DDLogError("FeedData/new-post/copy-media/error [\(error)]")
            }
        }

        // For items posted to user's feed we save current audience in FeedPostInfo.
        // Not pre-populating audience for groups - will be querying participants from ChatData.
        if case .userFeed = destination {
            let feedPostInfo = NSEntityDescription.insertNewObject(forEntityName: FeedPostInfo.entity().name!, into: managedObjectContext) as! FeedPostInfo
            let postAudience = try! MainAppContext.shared.privacySettings.currentFeedAudience()
            let receipts = postAudience.userIds.reduce(into: [UserID : Receipt]()) { (receipts, userId) in
                receipts[userId] = Receipt()
            }
            feedPostInfo.receipts = receipts
            feedPostInfo.privacyListType = postAudience.privacyListType
            feedPost.info = feedPostInfo
        }

        save(managedObjectContext)

        uploadMediaAndSend(feedPost: feedPost)
        
        if feedPost.groupId != nil {
            didSendGroupFeedPost.send(feedPost)
        }
    }

    @discardableResult
    func post(comment: MentionText, to feedItem: FeedDataItem, replyingTo parentCommentId: FeedPostCommentID? = nil) -> FeedPostCommentID {
        let commentId: FeedPostCommentID = UUID().uuidString

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
        for (index, userID) in comment.mentions {
            let feedMention = NSEntityDescription.insertNewObject(forEntityName: FeedMention.entity().name!, into: managedObjectContext) as! FeedMention
            feedMention.index = index
            feedMention.userID = userID
            feedMention.name = contactStore.pushNames[userID] ?? ""
            if feedMention.name == "" {
                DDLogError("FeedData/new-comment/mention/\(userID) missing push name")
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
        self.save(managedObjectContext)

        // Now send data over the wire.
        send(comment: feedComment)

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
        service.publishComment(comment, groupId: groupId) { result in
            switch result {
            case .success(let timestamp):
                self.updateFeedPostComment(with: commentId) { (feedComment) in
                    feedComment.timestamp = timestamp
                    feedComment.status = .sent
                }

            case .failure(_):
                self.updateFeedPostComment(with: commentId) { (feedComment) in
                    feedComment.status = .sendError
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

            case .failure(_):
                self.updateFeedPost(with: postId) { (feedPost) in
                    feedPost.status = .sendError
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
            switch audience.privacyListType {
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

        // Either all media has already been uploaded or post does not contain media.
        guard let mediaItemsToUpload = feedPost.media?.filter({ $0.status == .none || $0.status == .uploading || $0.status == .uploadError }), !mediaItemsToUpload.isEmpty else {
            send(post: feedPost)
            return
        }

        var numberOfFailedUploads = 0
        let totalUploads = mediaItemsToUpload.count
        let startTime = Date()
        DDLogInfo("FeedData/upload-media/\(postId)/starting [\(totalUploads)]")

        let uploadGroup = DispatchGroup()
        for mediaItem in mediaItemsToUpload {
            let mediaIndex = mediaItem.order
            uploadGroup.enter()
            mediaUploader.upload(media: mediaItem, groupId: postId, didGetURLs: { (mediaURLs) in
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
                        }
                    }
                }
            }) { (uploadResult) in
                DDLogInfo("FeedData/upload-media/\(postId)/\(mediaIndex)/finished result=[\(uploadResult)]")

                // Save URLs acquired during upload to the database.
                self.updateFeedPost(with: postId,
                                    block: { feedPost in
                                        if let media = feedPost.media?.first(where: { $0.order == mediaIndex }) {
                                            switch uploadResult {
                                            case .success(let url):
                                                media.url = url
                                                media.status = .uploaded

                                            case .failure(_):
                                                numberOfFailedUploads += 1
                                                media.status = .uploadError
                                            }
                                        }
                                    },
                                    performAfterSave: {
                                        uploadGroup.leave()
                                    })
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
                        numVideos: mediaItemsToUpload.filter { $0.type == .video }.count))
            }
        }
    }

    func cancelMediaUpload(postId: FeedPostID) {
        DDLogInfo("FeedData/upload-media/cancel/\(postId)")
        mediaUploader.cancelUpload(groupId: postId)
    }

    // MARK: Deletion

    private func deleteMedia(in feedPost: FeedPost) {
        feedPost.media?.forEach { (media) in
            if media.relativeFilePath != nil {
                let fileURL = MainAppContext.mediaDirectoryURL.appendingPathComponent(media.relativeFilePath!, isDirectory: false)
                do {
                    try FileManager.default.removeItem(at: fileURL)
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
            let cutoffDate = Date(timeIntervalSinceNow: -Date.days(30))
            DDLogInfo("FeedData/delete-expired  date=[\(cutoffDate)]")
            let expiredPostIDs = self.deletePosts(olderThan: cutoffDate, in: managedObjectContext)
            self.deleteNotifications(olderThan: cutoffDate, in: managedObjectContext)
            self.deleteNotifications(forPosts: expiredPostIDs, in: managedObjectContext)
            self.save(managedObjectContext)
        }
    }
    
    // MARK: Merge Data
    
    let didMergeFeedPost = PassthroughSubject<FeedPostID, Never>()
    
    func mergeData(from sharedDataStore: SharedDataStore, completion: @escaping () -> ()) {
        let posts = sharedDataStore.posts()
        guard !posts.isEmpty else {
            DDLogDebug("FeedData/merge-data/ Nothing to merge")
            completion()
            return
        }

        //TODO: merge comments
        
        performSeriallyOnBackgroundContext { managedObjectContext in
            self.merge(posts: posts, from: sharedDataStore, using: managedObjectContext, completion: completion)
        }
    }

    private func merge(posts: [SharedFeedPost], from sharedDataStore: SharedDataStore, using managedObjectContext: NSManagedObjectContext, completion: @escaping () -> ()) {
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
                feedPostInfo.privacyListType = audience.privacyListType
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

        save(managedObjectContext)

        newMergedPosts.forEach({ didMergeFeedPost.send($0) })
    
        DDLogInfo("FeedData/merge-data/finished")

        sharedDataStore.delete(posts: posts) {
            completion()
        }
    }
}

extension FeedData: HalloFeedDelegate {

    func halloService(_ halloService: HalloService, didReceiveFeedPayload payload: HalloServiceFeedPayload, ack: (() -> Void)?) {
        switch payload.content {
        case .newItems(let feedItems):
            processIncomingFeedItems(feedItems, group: payload.group, presentLocalNotifications: !payload.isPushSent, ack: ack)

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
