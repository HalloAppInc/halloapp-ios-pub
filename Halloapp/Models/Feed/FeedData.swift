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
import Foundation
import SwiftUI
import XMPPFramework


class FeedData: NSObject, ObservableObject, FeedDownloadManagerDelegate, NSFetchedResultsControllerDelegate, XMPPControllerFeedDelegate {

    private var userData: UserData
    private var contactStore: ContactStoreMain
    private var xmppController: XMPPControllerMain

    private var cancellableSet: Set<AnyCancellable> = []

    private(set) var feedNotifications: FeedNotifications?

    let willDestroyStore = PassthroughSubject<Void, Never>()
    let didReloadStore = PassthroughSubject<Void, Never>()

    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.feed")
    private lazy var downloadManager: FeedDownloadManager = {
        let downloadManager = FeedDownloadManager(mediaDirectoryURL: MainAppContext.mediaDirectoryURL)
        downloadManager.delegate = self
        return downloadManager
    }()

    let mediaUploader: MediaUploader

    init(xmppController: XMPPControllerMain, contactStore: ContactStoreMain, userData: UserData) {
        self.xmppController = xmppController
        self.contactStore = contactStore
        self.userData = userData
        self.mediaUploader = MediaUploader(xmppController: xmppController)

        super.init()

        self.xmppController.feedDelegate = self
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
        self.cancellableSet.insert(
            self.xmppController.didConnect.sink {
                DDLogInfo("Feed: Got event for didConnect")

                self.deleteExpiredPosts()

                self.resendPendingReadReceipts()
            })
        
        self.cancellableSet.insert(
            self.userData.didLogOff.sink {
                DDLogInfo("Unloading feed data. \(self.feedDataItems.count) posts")

                self.destroyStore()
            })

        self.fetchFeedPosts()
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
            try self.fetchedResultsController.performFetch()
            if let feedPosts = self.fetchedResultsController.fetchedObjects {
                self.reloadFeedDataItems(using: feedPosts)
                DDLogInfo("FeedData/fetch/completed \(self.feedDataItems.count) posts")

                // Turn tasks stuck in "sending" state into "sendError".
                let idsOfTasksInProgress = mediaUploader.activeTaskGroupIdentifiers()
                let stuckPosts = feedPosts.filter({ $0.status == .sending }).filter({ !idsOfTasksInProgress.contains($0.id) })
                if !stuckPosts.isEmpty {
                    stuckPosts.forEach({ $0.status = .sendError })
                    save(fetchedResultsController.managedObjectContext)
                }
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

    let didReceiveFeedPost = PassthroughSubject<FeedPost, Never>()

    let didReceiveFeedPostComment = PassthroughSubject<FeedPostComment, Never>()

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
            feedPost.timestamp = xmppPost.timestamp
            
            if feedPost.userId == userData.userId {
                // This only happens when the user re-register,
                // and the server sends us old posts.
                feedPost.status = .seen
            } else {
                feedPost.status = .incoming
            }

            var mentions = Set<FeedMention>()
            for xmppMention in xmppPost.mentions {
                let mention = NSEntityDescription.insertNewObject(forEntityName: FeedMention.entity().name!, into: managedObjectContext) as! FeedMention
                mention.index = xmppMention.index
                mention.userID = xmppMention.userID
                mention.name = xmppMention.name
                mentions.insert(mention)
            }
            feedPost.mentions = mentions

            // Process post media
            for (index, xmppMedia) in xmppPost.media.enumerated() {
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
        self.save(managedObjectContext)

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
            self.presentLocalNotifications(forFeedPosts: feedPosts)

            // Notify about new posts all interested parties.
            feedPosts.forEach({ self.didReceiveFeedPost.send($0) })
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
                for xmppMention in xmppComment.mentions {
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
        self.save(managedObjectContext)

        try? managedObjectContext.obtainPermanentIDs(for: newComments)
        let commentObjectIDs = newComments.map { $0.objectID }
        DispatchQueue.main.async {
            let managedObjectContext = self.viewContext
            let feedPostComments = commentObjectIDs.compactMap{ try? managedObjectContext.existingObject(with: $0) as? FeedPostComment }

            // Show local notifications.
            self.presentLocalNotifications(forComments: feedPostComments)

            // Notify about new comments all interested parties.
            feedPostComments.forEach({ self.didReceiveFeedPostComment.send($0) })
        }

        return newComments
    }

    func xmppController(_ xmppController: XMPPController, didReceiveFeedItems items: [XMLElement], in xmppMessage: XMPPMessage?) {
        var feedPosts: [XMPPFeedPost] = []
        var comments: [XMPPComment] = []
        var contactNames: [UserID:String] = [:]
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

                    if let contactName = item.attributeStringValue(forName: "publisher_name") {
                        contactNames[comment.userId] = contactName
                    }
                }
            } else {
                DDLogError("Invalid item type: [\(type)]")
            }
        }

        if !contactNames.isEmpty {
            self.contactStore.addPushNames(contactNames)
        }
        
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let posts = self.process(posts: feedPosts, using: managedObjectContext)
            self.generateNotifications(for: posts, using: managedObjectContext)

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
            guard !notifications.isEmpty else { return }
            notifications.forEach {
                $0.read = true
                
                if let commentId = $0.commentId {
                    NotificationUtility.removeDelivered(forType: .comment, withContentId: commentId)
                }
            }
            self.save(managedObjectContext)
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
        NotificationUtility.getContentIdsForDeliveredNotifications(ofType: .comment) { (commentIds) in
            commentIdsToFilterOut = commentIds
            dispatchGroup.leave()
        }

        dispatchGroup.notify(queue: .main) {
            var notifications: [UNMutableNotificationContent] = []
            comments.filter{ !commentIdsToFilterOut.contains($0.id) && self.isCommentEligibleForLocalNotification($0) }.forEach { (comment) in
                let protoContainer = comment.protoContainer(withData: true)
                let protobufData = try? protoContainer.serializedData()
                let metadata = NotificationUtility.Metadata(contentId: comment.id, contentType: .comment, data: protobufData, fromId: comment.userId)

                let notification = UNMutableNotificationContent()
                notification.title = contactNames[comment.userId] ?? "Unknown Contact"
                NotificationUtility.populate(
                    notification: notification,
                    withDataFrom: protoContainer,
                    mentionNameProvider: { userID in
                        self.contactStore.mentionName(
                            for: userID,
                            pushedName: protoContainer.mentionPushName(for: userID)) })
                notification.userInfo[NotificationUtility.Metadata.userInfoKey] = metadata.rawData

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
        NotificationUtility.getContentIdsForDeliveredNotifications(ofType: .feedpost) { (feedPostIds) in
            postIdsToFilterOut = feedPostIds
            dispatchGroup.leave()
        }

        dispatchGroup.notify(queue: .main) {
            var notifications: [UNMutableNotificationContent] = []
            feedPosts.filter({ !postIdsToFilterOut.contains($0.id) }).forEach { (feedPost) in
                let protoContainer = feedPost.protoContainer(withData: true)
                let protobufData = try? protoContainer.serializedData()
                let metadata = NotificationUtility.Metadata(contentId: feedPost.id, contentType: .feedpost, data: protobufData, fromId: feedPost.userId)

                let notification = UNMutableNotificationContent()
                notification.title = contactNames[feedPost.userId] ?? "Unknown Contact"
                NotificationUtility.populate(
                    notification: notification,
                    withDataFrom: protoContainer,
                    mentionNameProvider: { userID in
                        self.contactStore.mentionName(
                            for: userID,
                            pushedName: protoContainer.mentionPushName(for: userID)) })

                notification.userInfo[NotificationUtility.Metadata.userInfoKey] = metadata.rawData

                notifications.append(notification)
            }

            let notificationCenter = UNUserNotificationCenter.current()
            notifications.forEach { (notificationContent) in
                notificationCenter.add(UNNotificationRequest(identifier: UUID().uuidString, content: notificationContent, trigger: nil))
            }
        }
    }

    // MARK: Retracts

    private func processRetract(forPostId postId: FeedPostID, completion: @escaping () -> Void) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
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

            completion()
        }
    }

    private func processRetract(forCommentId commentId: FeedPostCommentID, completion: @escaping () -> Void) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
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
        let request = XMPPRetractItemRequest(feedItem: feedPost, feedOwnerId: feedPost.userId) { (result) in
            switch result {
            case .success:
                self.processRetract(forPostId: postId) {}

            case .failure(_):
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
        let request = XMPPRetractItemRequest(feedItem: comment, feedOwnerId: comment.post.userId) { (result) in
            switch result {
            case .success:
                self.processRetract(forCommentId: commentId) {}

            case .failure(_):
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
            feedPost.willChangeValue(forKey: "info")
            if feedPost.info == nil {
                feedPost.info = NSEntityDescription.insertNewObject(forEntityName: FeedPostInfo.entity().name!, into: managedObjectContext) as? FeedPostInfo
            }
            var receipts = feedPost.info!.receipts ?? [:]
            if receipts[xmppReceipt.userId] == nil {
                receipts[xmppReceipt.userId] = Receipt()
            }
            receipts[xmppReceipt.userId]!.seenDate = xmppReceipt.timestamp
            DDLogInfo("FeedData/seen-receipt/update  userId=[\(xmppReceipt.userId)]  ts=[\(xmppReceipt.timestamp!)]  itemId=[\(xmppReceipt.itemId)]")
            feedPost.info!.receipts = receipts
            feedPost.didChangeValue(forKey: "info")

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }

            if let message = xmppMessage {
                xmppController.sendAck(for: message)
            }
        }
    }

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
        guard feedPost.status == .incoming else {
            DDLogWarn("FeedData/seen-receipt/ignore Incorrect post status: \(feedPost.status)")
            return
        }
        feedPost.status = .seenSending
        self.xmppController.sendSeenReceipt(XMPPReceipt.seenReceipt(for: feedPost), to: feedPost.userId)
    }

    func sendSeenReceiptIfNecessary(for feedPost: FeedPost) {
        guard feedPost.status == .incoming else { return }

        let postId = feedPost.id
        self.updateFeedPost(with: postId) { (post) in
            self.internalSendSeenReceipt(for: post)
        }
    }

    func xmppController(_ xmppController: XMPPController, didSendFeedReceipt receipt: XMPPReceipt) {
        self.updateFeedPost(with: receipt.itemId) { (feedPost) in
            if !feedPost.isPostRetracted {
                feedPost.status = .seen
            }
        }
    }
    
    func seenByUsers(for feedPost: FeedPost) -> [SeenByUser] {
        let allContacts = contactStore.allRegisteredContacts(sorted: true)
        
        // Contacts that have seen the post go into the first section.
        var users: [SeenByUser] = []
        
        if let seenReceipts = feedPost.info?.receipts {
            for (userId, receipt) in seenReceipts {
                var contactName: String?
                if let contactIndex = allContacts.firstIndex(where: { $0.userId == userId }) {
                    contactName = allContacts[contactIndex].fullName
                }
                if contactName == nil {
                    contactName = contactStore.fullName(for: userId)
                }
                users.append(SeenByUser(userId: userId, postStatus: .seen, contactName: contactName!, timestamp: receipt.seenDate!))
            }
        }
        users.sort(by: { $0.timestamp > $1.timestamp })

        return users
    }

    // MARK: Feed Media

    func downloadTask(for mediaItem: FeedMedia) -> FeedDownloadManager.Task? {
        guard let feedPost = feedPost(with: mediaItem.feedPostId) else { return nil }
        guard let feedPostMedia = feedPost.media?.first(where: { $0.order == mediaItem.order }) else { return nil }
        return downloadManager.currentTask(for: feedPostMedia)
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
            feedPost.media?.forEach { feedPostMedia in
                // Status could be "downloading" if download has previously started
                // but the app was terminated before the download has finished.
                if feedPostMedia.url != nil && (feedPostMedia.status == .none || feedPostMedia.status == .downloading || feedPostMedia.status == .downloadError) {
                    let (taskAdded, task) = downloadManager.downloadMedia(for: feedPostMedia)
                    if taskAdded {
                        task.feedMediaObjectId = feedPostMedia.objectID
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

    func post(text: MentionText, media: [PendingMedia]) {
        let postId: FeedPostID = UUID().uuidString

        // Create and save new FeedPost object.
        let managedObjectContext = persistentContainer.viewContext
        DDLogDebug("FeedData/new-post/create [\(postId)]")
        let feedPost = NSEntityDescription.insertNewObject(forEntityName: FeedPost.entity().name!, into: managedObjectContext) as! FeedPost
        feedPost.id = postId
        feedPost.userId = AppContext.shared.userData.userId
        feedPost.text = text.collapsedText
        feedPost.status = .sending
        feedPost.timestamp = Date()

        // Add mentions
        var mentionSet = Set<FeedMention>()
        for (index, userID) in text.mentions {
            let feedMention = NSEntityDescription.insertNewObject(forEntityName: FeedMention.entity().name!, into: managedObjectContext) as! FeedMention
            feedMention.index = index
            feedMention.userID = userID
            feedMention.name = MainAppContext.shared.contactStore.pushNames[userID] ?? ""
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
        save(managedObjectContext)

        uploadMediaAndSend(feedPost: feedPost)
    }

    func post(comment: MentionText, to feedItem: FeedDataItem, replyingTo parentCommentId: FeedPostCommentID? = nil) {
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
            feedMention.name = MainAppContext.shared.contactStore.pushNames[userID] ?? ""
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
        self.send(comment: feedComment)
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
        self.save(managedObjectContext)

        self.send(comment: comment)
    }

    private func send(comment: FeedPostComment) {
        let commentId = comment.id
        let request = XMPPPostItemRequest(feedItem: comment, feedOwnerId: comment.post.userId) { (result) in
            switch result {
            case .success(let timestamp):
                self.updateFeedPostComment(with: commentId) { (feedComment) in
                    if timestamp != nil {
                        feedComment.timestamp = timestamp!
                    }
                    feedComment.status = .sent
                }

            case .failure(_):
                self.updateFeedPostComment(with: commentId) { (feedComment) in
                    feedComment.status = .sendError
                }
            }
        }
        // Request will fail immediately if we're not connected, therefore delay sending until connected.
        ///TODO: add option of canceling posting.
        xmppController.execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.xmppController.enqueue(request: request)
        }
    }

    private func send(post: FeedPost) {
        let postId = post.id
        let request = XMPPPostItemRequest(feedItem: post, feedOwnerId: post.userId) { (result) in
            switch result {
            case .success(let timestamp):
                self.updateFeedPost(with: postId) { (feedPost) in
                    if timestamp != nil {
                        feedPost.timestamp = timestamp!
                    }
                    feedPost.status = .sent
                }

            case .failure(_):
                self.updateFeedPost(with: postId) { (feedPost) in
                    feedPost.status = .sendError
                }
            }
        }
        // Request will fail immediately if we're not connected, therefore delay sending until connected.
        ///TODO: add option of canceling posting.
        xmppController.execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.xmppController.enqueue(request: request)
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
                        media.uploadUrl = mediaURLs.put
                        media.url = mediaURLs.get
                    }
                }
            }) { (uploadResult) in
                DDLogInfo("FeedData/upload-media/\(postId)/\(mediaIndex)/finished result=[\(uploadResult)]")

                // Save URLs acquired during upload to the database.
                self.updateFeedPost(with: postId) { (feedPost) in
                    if let media = feedPost.media?.first(where: { $0.order == mediaIndex }) {
                        switch uploadResult {
                        case .success(_):
                            media.status = .uploaded

                        case .failure(_):
                            numberOfFailedUploads += 1
                            media.status = .uploadError
                        }
                    }

                    uploadGroup.leave()
                }
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
            }
        }
    }

    func cancelMediaUpload(postId: FeedPostID) {
        DDLogInfo("FeedData/upload-media/cancel/\(postId)")
        mediaUploader.cancelUpload(groupId: postId)
    }

    // MARK: Debug

    func refetchEverything() {
        let userIds = self.contactStore.allRegisteredContactIDs()
        self.xmppController.retrieveFeedData(for: userIds)
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
    
    // MARK: Merge Data
    
    func mergeSharedData(using sharedDataStore: SharedDataStore, completion: @escaping () -> ()) {
        let posts = sharedDataStore.posts()
        
        guard !posts.isEmpty else {
            completion()
            return
        }
        
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let postIds = Set(posts.map{ $0.id })
            let existingPosts = self.feedPosts(with: postIds, in: managedObjectContext).reduce(into: [FeedPostID : FeedPost]()) { $0[$1.id] = $1 }
            
            for post in posts {
                guard existingPosts[post.id] == nil else {
                    DDLogError("FeedData/mergeSharedData/duplicate [\(post.id)]")
                    continue
                }

                let postId = post.id

                DDLogDebug("FeedData/mergeSharedData/post/\(postId)")
                let feedPost = NSEntityDescription.insertNewObject(forEntityName: FeedPost.entity().name!, into: managedObjectContext) as! FeedPost
                feedPost.id = post.id
                feedPost.userId = post.userId
                feedPost.text = post.text
                feedPost.status = post.status == .sent ? .sent : .sendError
                feedPost.timestamp = post.timestamp
                
                post.media?.forEach { (media) in
                    DDLogDebug("FeedData/mergeSharedData/post/\(postId)/add-media [\(media)]")

                    let feedMedia = NSEntityDescription.insertNewObject(forEntityName: FeedPostMedia.entity().name!, into: managedObjectContext) as! FeedPostMedia
                    feedMedia.type = {
                        switch media.type {
                        case .image: return .image
                        case .video: return .video
                        }
                    }()
                    feedMedia.status = {
                        switch media.status {
                            ///TODO: treatment of "none" as "uploaded" is a temporary workaround to migrate media created without status attribute. safe to remove this case after 09/14/2020.
                        case .none, .uploaded: return .uploaded
                        default: return .uploadError
                        }
                    }()
                    feedMedia.url = media.url
                    feedMedia.uploadUrl = media.uploadUrl
                    feedMedia.size = media.size
                    feedMedia.key = media.key
                    feedMedia.order = media.order
                    feedMedia.sha256 = media.sha256
                    feedMedia.post = feedPost

                    let pendingMedia = PendingMedia(type: feedMedia.type)
                    pendingMedia.fileURL = SharedDataStore.fileURL(forRelativeFilePath: media.relativeFilePath)
                    if feedMedia.status != .uploaded {
                        // Only copy encrypted file if media failed to upload so that upload could be retried.
                        pendingMedia.encryptedFileUrl = pendingMedia.fileURL!.appendingPathExtension("enc")
                    }
                    do {
                        try self.downloadManager.copyMedia(from: pendingMedia, to: feedMedia)
                    }
                    catch {
                        DDLogError("FeedData/mergeSharedData/post/\(postId)/copy-media-error [\(error)]")
                    }
                }
            }

            self.save(managedObjectContext)
            
            DDLogInfo("FeedData/mergeSharedData/finished")
            
            sharedDataStore.delete(posts: posts) {
                completion()
            }
        }
    }
}
