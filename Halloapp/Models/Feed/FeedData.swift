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
import Foundation
import SwiftUI
import XMPPFramework

// MARK: Types

typealias FeedPostID = String
typealias FeedPostCommentID = String
enum FeedMediaType: Int {
    case image = 0
    case video = 1
}

class FeedData: NSObject, ObservableObject, FeedDownloadManagerDelegate, NSFetchedResultsControllerDelegate, XMPPControllerFeedDelegate {

    private var userData: UserData
    private var xmppController: XMPPController
    private var cancellableSet: Set<AnyCancellable> = []

    private(set) var feedNotifications: FeedNotifications?

    let willDestroyStore = PassthroughSubject<Void, Never>()
    let didReloadStore = PassthroughSubject<Void, Never>()

    // Temporary until server implements pushing user's own past posts on first connect.
    private var fetchOwnFeedOnConnect = false

    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.feed")
    private lazy var downloadManager: FeedDownloadManager = {
        let manager = FeedDownloadManager()
        manager.delegate = self
        return manager
    }()

    init(xmppController: XMPPController, userData: UserData) {
        self.xmppController = xmppController
        self.userData = userData

        self.fetchOwnFeedOnConnect = !userData.isLoggedIn

        super.init()

        self.xmppController.feedDelegate = self

        /* enable videoes to play with sound even when the phone is set to ringer mode */
        do {
           try AVAudioSession.sharedInstance().setCategory(.playback)
        } catch(let error) {
            print(error.localizedDescription)
        }

        // when app resumes, xmpp reconnects, feed should try uploading any pending again
        self.cancellableSet.insert(
            self.xmppController.didConnect.sink { _ in
                DDLogInfo("Feed: Got event for didConnect")

                if self.fetchOwnFeedOnConnect {
                    self.xmppController.retrieveFeedData(for: [ userData.userId ])
                    self.fetchOwnFeedOnConnect = false
                }
                
                self.deleteExpiredPosts()
            })
        
        self.cancellableSet.insert(
            self.userData.didLogOff.sink {
                DDLogInfo("Unloading feed data. \(self.feedDataItems.count) posts")

                self.destroyStore()
                self.fetchOwnFeedOnConnect = true
            })

        self.fetchFeedPosts()
    }

    // MARK: CoreData stack

    private class var persistentStoreURL: URL {
        get {
            return AppContext.feedStoreURL
        }
    }

    private func loadPersistentContainer() {
        let container = self.persistentContainer
        DDLogDebug("FeedData/loadPersistentStore Loaded [\(container)]")
    }

    private lazy var persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: FeedData.persistentStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
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
            try FileManager.default.removeItem(at: AppContext.mediaDirectoryURL)
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

        // Reload re-useing existing FeedDataItem.
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
            try self.fetchedResultsController.performFetch()
            if let feedPosts = self.fetchedResultsController.fetchedObjects {
                self.reloadFeedDataItems(using: feedPosts)
                DDLogInfo("FeedData/fetch/completed \(self.feedDataItems.count) posts")
            }
        }
        catch {
            DDLogError("FeedData/fetch/error [\(error)]")
            fatalError("Failed to fetch feed items \(error)")
        }

        self.feedNotifications = FeedNotifications(self.viewContext)
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
            self.feedDataItems.remove(at: index)

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

    // MARK: Updates

    private func updateFeedPost(with id: FeedPostID, block: @escaping (FeedPost) -> Void) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
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

    private func updateFeedPostComment(with id: FeedPostCommentID, block: @escaping (FeedPostComment) -> Void) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
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
        self.updateFeedPost(with: feedPostId) { (feedPost) in
            if feedPost.unreadCount != 0 {
                feedPost.unreadCount = 0
            }
        }
        self.markNotificationsAsRead(for: feedPostId)
    }

    // MARK: Process Incoming Feed Data

    @discardableResult private func process(posts xmppPosts: [XMPPFeedPost], using managedObjectContext: NSManagedObjectContext) -> [FeedPost] {
        guard !xmppPosts.isEmpty else { return [] }

        let postIds = Set(xmppPosts.map{ $0.id })
        let existingPosts = self.feedPosts(with: postIds, in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
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
            feedPost.text = xmppPost.text
            feedPost.status = .incoming
            feedPost.timestamp = xmppPost.timestamp

            // Process post media
            for (index, xmppMedia) in xmppPost.media.enumerated() {
                DDLogDebug("FeedData/process-posts/new/add-media [\(xmppMedia.url)]")
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
        self.save(managedObjectContext)

        // Only initiate downloads for feed posts received in real-time.
        // Media for older posts in the feed will be downloaded as user scrolls down.
        if newPosts.count == 1 {
            // Initiate downloads from the main thread.
            // This is done to avoid race condition with downloads initiated from FeedTableView.
            try? managedObjectContext.obtainPermanentIDs(for: newPosts)
            let postObjectIDs = newPosts.map { $0.objectID }
            DispatchQueue.main.async {
                let managedObjectContext = self.viewContext
                let feedPosts = postObjectIDs.compactMap{ try? managedObjectContext.existingObject(with: $0) as? FeedPost }
                self.downloadMedia(in: feedPosts)
            }
        }

        return newPosts
    }

    @discardableResult private func process(comments xmppComments: [XMPPComment], using managedObjectContext: NSManagedObjectContext) -> [FeedPostComment] {
        guard !xmppComments.isEmpty else { return [] }

        let feedPostIds = Set(xmppComments.map{ $0.feedPostId })
        let feedPosts = self.feedPosts(with: feedPostIds, in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
        let commentIds = Set(xmppComments.map{ $0.id }).union(Set(xmppComments.compactMap{ $0.parentId }))
        var comments = self.feedComments(with: commentIds, in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
        var ignoredCommentIds: Set<String> = []
        var xmppCommentsMutable = [XMPPComment](xmppComments)
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
                guard let feedPost = feedPosts[xmppComment.feedPostId] else {
                    DDLogError("FeedData/process-comments/missing-post [\(xmppComment.feedPostId)]")
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
                if parentComment?.isCommentRetracted ?? false {
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
        self.save(managedObjectContext)
        return newComments
    }

    func xmppController(_ xmppController: XMPPController, didReceiveFeedItems items: [XMLElement], in xmppMessage: XMPPMessage?) {
        var feedPosts: [XMPPFeedPost] = []
        var comments: [XMPPComment] = []
        for item in items {
            guard let type = item.attribute(forName: "type")?.stringValue else {
                DDLogError("Invalid item: [\(item)]")
                continue
            }
            if type == "feedpost" {
                if let feedPost = XMPPFeedPost(itemElement: item) {
                    feedPosts.append(feedPost)
                }
            } else if type == "comment" {
                if let comment = XMPPComment(itemElement: item) {
                    comments.append(comment)
                }
            } else {
                DDLogError("Invalid item type: [\(type)]")
            }
        }

        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            self.process(posts: feedPosts, using: managedObjectContext)
            let comments = self.process(comments: comments, using: managedObjectContext)
            self.generateNotifications(for: comments, using: managedObjectContext)

            if let message = xmppMessage {
                DispatchQueue.main.async {
                    xmppController.sendAck(for: message)
                }
            }
        }
    }

    // MARK: Notifications

    private func generateNotifications(for comments: [FeedPostComment], using managedObjectContext: NSManagedObjectContext) {
        guard !comments.isEmpty else { return }

        let selfId = AppContext.shared.userData.userId
        for comment in comments {
            // Step 1. Determine if comment is eligible for a notification.
            // This would be the person who posted comment.
            let authorId = comment.userId
            guard authorId != selfId else {
                DDLogError("FeedData/generateNotifications  Comment from self post=[\(comment.post.id)]  comment=[\(comment.id)]")
                continue
            }

            var event: FeedNotification.Event? = nil
            // Someone replied to your comment.
            if comment.parent != nil && comment.parent?.userId == selfId {
                event = .reply
            }
            // Someone commented on your post.
            else if comment.post.userId == selfId {
                event = .comment
            }
            guard event != nil else { continue }

            // Step 2. Add notification entry to the database.
            let notification = NSEntityDescription.insertNewObject(forEntityName: FeedNotification.entity().name!, into: managedObjectContext) as! FeedNotification
            notification.commentId = comment.id
            notification.postId = comment.post.id
            notification.event = event!
            notification.userId = authorId
            notification.timestamp = comment.timestamp
            notification.text = comment.text
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
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let notifications: [FeedNotification]
            let isNotReadPredicate = NSPredicate(format: "read = %@", NSExpression(forConstantValue: false))
            if postId != nil {
                let postIdPredicate = NSPredicate(format: "postId = %@", postId!)
                notifications = self.notifications(with: NSCompoundPredicate(andPredicateWithSubpredicates: [ isNotReadPredicate, postIdPredicate ]), in: managedObjectContext)
            } else {
                notifications = self.notifications(with: isNotReadPredicate, in: managedObjectContext)
            }
            DDLogInfo("FeedData/notifications/mark-read-all Count: \(notifications.count)")
            notifications.forEach { $0.read = true }
            self.save(managedObjectContext)
        }
    }

    // MARK: Retracts

    private func processRetract(forPostId postId: FeedPostID, completion: @escaping () -> Void) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let feedPost = self.feedPost(with: postId, in: managedObjectContext) else {
                DDLogError("FeedData/retract-post/error Missing post. [\(postId)]")
                return
            }
            guard feedPost.status != .retracted  else {
                DDLogError("FeedData/retract-post/error Already retracted. [\(postId)]")
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

            completion()
        }
    }

    private func processRetract(forCommentId commentId: FeedPostCommentID, completion: @escaping () -> Void) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let feedComment = self.feedComment(with: commentId, in: managedObjectContext) else {
                DDLogError("FeedData/retract-comment/error Missing comment. [\(commentId)]")
                return
            }
            guard feedComment.status != .retracted else {
                DDLogError("FeedData/retract-comment/error Already retracted. [\(commentId)]")
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

    func xmppController(_ xmppController: XMPPController, didReceiveFeedRetracts items: [XMLElement], in xmppMessage: XMPPMessage?) {
        /**
         Example:
         <retract timestamp="1587161372" publisher="1000000000354803885@s.halloapp.net/android" type="feedpost" id="b2d888ecfe2343d9916173f2f416f4ae"><entry xmlns="http://halloapp.com/published-entry"><feedpost/><s1>CgA=</s1></entry></retract>
         */
        let processingGroup = DispatchGroup()
        for item in items {
            guard let itemId = item.attributeStringValue(forName: "id") else {
                DDLogError("FeedData/process-retract/error Missing item id. [\(item)]")
                continue
            }
            guard let type = item.attribute(forName: "type")?.stringValue else {
                DDLogError("FeedData/process-retract/error Missing item type. [\(item)]")
                continue
            }
            if type == "feedpost" {
                processingGroup.enter()
                self.processRetract(forPostId: itemId) {
                    processingGroup.leave()
                }
            } else if type == "comment" {
                processingGroup.enter()
                self.processRetract(forCommentId: itemId) {
                    processingGroup.leave()
                }
            } else {
                DDLogError("FeedData/process-retract/error Invalid item type. [\(item)]")
            }
        }
        processingGroup.notify(queue: DispatchQueue.main) {
            if let message = xmppMessage {
                xmppController.sendAck(for: message)
            }
        }
    }

    func retract(post feedPost: FeedPost) {
        let postId = feedPost.id

        // Mark post as "being retracted"
        feedPost.status = .retracting
        self.save(self.viewContext)

        // Request to retract.
        let request = XMPPRetractItemRequest(feedItem: feedPost, feedOwnerId: feedPost.userId) { (error) in
            if error == nil {
                self.processRetract(forPostId: postId) {}
            } else {
                self.updateFeedPost(with: postId) { (post) in
                    post.status = .sent
                }
            }
        }
        self.xmppController.enqueue(request: request)
    }

    func retract(comment: FeedPostComment) {
        let commentId = comment.id

        // Mark comment as "being retracted".
        comment.status = .retracting
        self.save(self.viewContext)

        // Request to retract.
        let request = XMPPRetractItemRequest(feedItem: comment, feedOwnerId: comment.post.userId) { (error) in
            if error == nil {
                self.processRetract(forCommentId: commentId) {}
            } else {
                self.updateFeedPostComment(with: commentId) { (comment) in
                    comment.status = .sent
                }
            }
        }
        self.xmppController.enqueue(request: request)
    }

    // MARK: Read Receipts

    func xmppController(_ xmppController: XMPPController, didReceiveFeedReceipt xmppReceipt: XMPPReceipt, in xmppMessage: XMPPMessage?) {
        DDLogInfo("FeedData/seen-receipt/incoming itemId=[\(xmppReceipt.itemId)]")
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let feedPost = self.feedPost(with: xmppReceipt.itemId, in: managedObjectContext) else {
                DDLogError("FeedData/seen-receipt/missing-post [\(xmppReceipt.itemId)]")
                if let message = xmppMessage {
                    xmppController.sendAck(for: message)
                }
                return
            }
            if feedPost.info == nil {
                feedPost.info = NSEntityDescription.insertNewObject(forEntityName: FeedPostInfo.entity().name!, into: managedObjectContext) as? FeedPostInfo
            }
            var receipts = feedPost.info!.receipts ?? [:]
            if receipts[xmppReceipt.userId] == nil {
                receipts[xmppReceipt.userId] = Receipt()
            }
            receipts[xmppReceipt.userId]!.seenDate = xmppReceipt.timestamp
            DDLogInfo("FeedData/seen-receipt/update  userId=[\(xmppReceipt.userId)]  ts=[\(xmppReceipt.timestamp)]  itemId=[\(xmppReceipt.itemId)]")
            feedPost.info!.receipts = receipts

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }

            if let message = xmppMessage {
                xmppController.sendAck(for: message)
            }
        }
    }

    // MARK: Feed Media

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
            feedPost.media?.forEach { feedPostMedia in
                // Status could be "downloading" if download has previously started
                // but the app was terminated before the download has finished.
                if feedPostMedia.status == .none || feedPostMedia.status == .downloading || feedPostMedia.status == .downloadError {
                    if downloadManager.downloadMedia(for: feedPostMedia) {
                        feedPostMedia.status = .downloading
                        downloadStarted = true
                    }
                }
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
            guard let feedPostMedia = try? managedObjectContext.existingObject(with: task.feedMediaObjectId) as? FeedPostMedia else {
                DDLogError("FeedData/download-task/\(task.id)/error  Missing FeedPostMedia  objectId=[\(task.feedMediaObjectId)]")
                return
            }

            guard feedPostMedia.relativeFilePath == nil else {
                DDLogError("FeedData/download-task/\(task.id)/error File already exists media=[\(feedPostMedia)]")
                return
            }

            if task.error == nil {
                DDLogInfo("FeedData/download-task/\(task.id)/complete [\(task.fileURL!)]")
                feedPostMedia.status = .downloaded
                feedPostMedia.relativeFilePath = task.relativeFilePath
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
                self.updateMediaPreview(for: notifications, usingImageAt: AppContext.mediaDirectoryURL.appendingPathComponent(postMedia.relativeFilePath!, isDirectory: false))
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
        self.updateMediaPreview(for: [ notification ], usingImageAt: AppContext.mediaDirectoryURL.appendingPathComponent(mediaPath, isDirectory: false))
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

    func post(text: String, media: [PendingMedia]) {
        let postId: FeedPostID = UUID().uuidString

        // Create and save new FeedPost object.
        let managedObjectContext = self.persistentContainer.viewContext
        DDLogDebug("FeedData/new-post/create [\(postId)]")
        let feedPost = NSEntityDescription.insertNewObject(forEntityName: FeedPost.entity().name!, into: managedObjectContext) as! FeedPost
        feedPost.id = postId
        feedPost.userId = AppContext.shared.userData.userId
        feedPost.text = text
        feedPost.status = .sending
        feedPost.timestamp = Date()
        // Add post media.
        for (index, mediaItem) in media.enumerated() {
            DDLogDebug("FeedData/new-post/add-media [\(mediaItem.url!)]")
            let feedMedia = NSEntityDescription.insertNewObject(forEntityName: FeedPostMedia.entity().name!, into: managedObjectContext) as! FeedPostMedia
            feedMedia.type = mediaItem.type
            feedMedia.status = .uploaded // For now we're only posting when all uploads are completed.
            feedMedia.url = mediaItem.url!
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
        self.save(managedObjectContext)

        // Now send data over the wire.
        let request = XMPPPostItemRequest(feedItem: feedPost, feedOwnerId: feedPost.userId) { (timestamp, error) in
            if error != nil {
                self.updateFeedPost(with: postId) { (feedPost) in
                    feedPost.status = .sendError
                }
            } else {
                self.updateFeedPost(with: postId) { (feedPost) in
                    if timestamp != nil {
                        feedPost.timestamp = timestamp!
                    }
                    feedPost.status = .sent
                }
            }
        }
        AppContext.shared.xmppController.enqueue(request: request)
    }

    func post(comment text: String, to feedItem: FeedDataItem, replyingTo parentCommentId: FeedPostCommentID? = nil) {
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
        DDLogDebug("FeedData/new-comment/create id=[\(commentId)]  postId=[\(feedPost.id)]")
        let comment = NSEntityDescription.insertNewObject(forEntityName: FeedPostComment.entity().name!, into: managedObjectContext) as! FeedPostComment
        comment.id = commentId
        comment.userId = AppContext.shared.userData.userId
        comment.text = text
        comment.parent = parentComment
        comment.post = feedPost
        comment.status = .sending
        comment.timestamp = Date()
        self.save(managedObjectContext)

        // Now send data over the wire.
        let request = XMPPPostItemRequest(feedItem: comment, feedOwnerId: feedPost.userId) { (timestamp, error) in
            if error != nil {
                 self.updateFeedPostComment(with: commentId) { (feedComment) in
                     feedComment.status = .sendError
                 }
             } else {
                 self.updateFeedPostComment(with: commentId) { (feedComment) in
                     if timestamp != nil {
                         feedComment.timestamp = timestamp!
                     }
                     feedComment.status = .sent
                 }
             }
        }
        AppContext.shared.xmppController.enqueue(request: request)
    }

    // MARK: Debug

    func refetchEverything() {
        let userIds = AppContext.shared.contactStore.allRegisteredContactIDs()
        self.xmppController.retrieveFeedData(for: userIds)
    }

    // MARK: Deletion

    private func deleteMedia(in feedPost: FeedPost) {
        feedPost.media?.forEach { (media) in
            if media.relativeFilePath != nil {
                let fileURL = AppContext.mediaDirectoryURL.appendingPathComponent(media.relativeFilePath!, isDirectory: false)
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

    private func deleteExpiredPosts() {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let cutoffDate = Date(timeIntervalSinceNow: -Date.days(30))
            DDLogInfo("FeedData/delete-expired  date=[\(cutoffDate)]")
            let fetchRequest = NSFetchRequest<FeedPost>(entityName: FeedPost.entity().name!)
            fetchRequest.predicate = NSPredicate(format: "timestamp < %@", cutoffDate as NSDate)
            do {
                let posts = try managedObjectContext.fetch(fetchRequest)
                guard !posts.isEmpty else {
                    DDLogInfo("FeedData/delete-expired/empty")
                    return
                }
                DDLogInfo("FeedData/delete-expired/begin  count=[\(posts.count)]")
                posts.forEach {
                    self.deleteMedia(in: $0)
                    managedObjectContext.delete($0)
                }
                DDLogInfo("FeedData/delete-expired/finished")
            }
            catch {
                DDLogError("FeedData/delete-expired/error  [\(error)]")
                return
            }
            self.save(managedObjectContext)
        }
    }
}
