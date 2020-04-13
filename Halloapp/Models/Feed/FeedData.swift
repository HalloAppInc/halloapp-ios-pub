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

class FeedData: NSObject, ObservableObject, FeedDownloadManagerDelegate, NSFetchedResultsControllerDelegate {

    private var userData: UserData
    private var xmppController: XMPPController
    private var cancellableSet: Set<AnyCancellable> = []

    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.feed")
    private lazy var downloadManager: FeedDownloadManager = {
        let manager = FeedDownloadManager()
        manager.delegate = self
        return manager
    }()

    init(xmppController: XMPPController, userData: UserData) {
        self.xmppController = xmppController
        self.userData = userData

        super.init()

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
                
                self.deleteExpiredPosts()
            })
        
        self.cancellableSet.insert(
            self.userData.didLogOff.sink {
                DDLogInfo("Unloading feed data. \(self.feedDataItems.count) posts")

                // TODO: disable NSFetchedResultsController?
                self.feedDataItems.removeAll()
            })
        
        /* getting new items, usually one */
        self.cancellableSet.insert(
            xmppController.didGetNewFeedItem.sink { [weak self] xmppMessage in
                if let items = xmppMessage.element(forName: "event")?.element(forName: "items") {
                    DDLogInfo("Feed: new item \(items)")
                    guard let self = self else { return }
                    self.processIncomingFeedItems(items)
                }
            })
        
        /* getting the entire list of items back */
        self.cancellableSet.insert(
            xmppController.didGetFeedItems.sink { [weak self] xmppIQ in
                if let items = xmppIQ.element(forName: "pubsub")?.element(forName: "items") {
                    DDLogInfo("Feed: fetched items \(items)")
                    guard let self = self else { return }
                    self.processIncomingFeedItems(items)
               }
            })
        
        /* retract item */
        self.cancellableSet.insert(
            xmppController.didGetRetractItem.sink { xmppMessage in
                DDLogInfo("Feed: Retract Item \(xmppMessage)")
                
                //todo: handle retracted items
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
        container.loadPersistentStores { description, error in
            if let error = error {
                DDLogError("Failed to load persistent store: \(error)")
                DDLogError("Deleting persistent store at [\(FeedData.persistentStoreURL.absoluteString)]")
                try! FileManager.default.removeItem(at: FeedData.persistentStoreURL)
                fatalError("Unable to load persistent store: \(error)")
            }
        }
        return container
    }()

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

    // MARK: Fetched Results Controller

    @Published var isFeedEmpty: Bool = false

    var feedDataItems : [FeedDataItem] = []

    private func fetchFeedPosts() {
        do {
            try self.fetchedResultsController.performFetch()
            if let feedPosts = self.fetchedResultsController.fetchedObjects {
                self.feedDataItems = feedPosts .map { FeedDataItem($0) }
                DDLogInfo("FeedData/fetch/completed \(self.feedDataItems.count) posts")
            }
        }
        catch {
            DDLogError("FeedData/fetch/error [\(error)]")
            fatalError("Failed to fetch feed items \(error)")
        }
        self.isFeedEmpty = self.feedDataItems.isEmpty
    }

    lazy var fetchedResultsController: NSFetchedResultsController<FeedPost> = {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        let fetchedResultsController = NSFetchedResultsController<FeedPost>(fetchRequest: fetchRequest, managedObjectContext: self.viewContext,
                                                                            sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }()

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
                self.feedDataItems = feedPosts .map { FeedDataItem($0) }
                DDLogInfo("FeedData/frc/full-reload \(self.feedDataItems.count) posts")
            }
        }
        self.isFeedEmpty = self.feedDataItems.isEmpty
    }

    // MARK: Fetching Feed Data

    func feedDataItem(with itemId: String) -> FeedDataItem? {
        return self.feedDataItems.first(where: { $0.itemId == itemId })
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

    func feedPost(with id: FeedPost.ID, in managedObjectContext: NSManagedObjectContext? = nil) -> FeedPost? {
        return self.feedPosts(predicate: NSPredicate(format: "id == %@", id), in: managedObjectContext).first
    }

    private func feedPosts(with ids: Set<FeedPost.ID>, in managedObjectContext: NSManagedObjectContext? = nil) -> [FeedPost] {
        return feedPosts(predicate: NSPredicate(format: "id in %@", ids), in: managedObjectContext)
    }

    private func feedComment(with id: FeedPostComment.ID, in managedObjectContext: NSManagedObjectContext) -> FeedPostComment? {
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

    private func feedComments(with ids: Set<FeedPostComment.ID>, in managedObjectContext: NSManagedObjectContext) -> [FeedPostComment] {
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

    private func updateFeedPost(with id: FeedPost.ID, block: @escaping (FeedPost) -> Void) {
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

    private func updateFeedPostComment(with id: FeedPostComment.ID, block: @escaping (FeedPostComment) -> Void) {
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

    func markCommentsAsRead(feedPostId: FeedPost.ID) {
        self.updateFeedPost(with: feedPostId) { (feedPost) in
            if feedPost.unreadCount != 0 {
                feedPost.unreadCount = 0
            }
        }
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
            feedPost.userId = xmppPost.userPhoneNumber
            feedPost.text = xmppPost.text
            feedPost.status = .incoming
            if let ts = xmppPost.timestamp {
                feedPost.timestamp = Date(timeIntervalSince1970: ts)
            } else {
                feedPost.timestamp = Date()
            }

            // Process post media
            for (index, xmppMedia) in xmppPost.media.enumerated() {
                guard xmppMedia.key != nil && xmppMedia.sha256 != nil else {
                    DDLogError("FeedData/process-posts/media-unencrypted [\(xmppMedia.url)]")
                    continue
                }
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
                feedMedia.key = xmppMedia.key!
                feedMedia.order = Int16(index)
                feedMedia.sha256 = xmppMedia.sha256!
                feedMedia.post = feedPost
            }

            newPosts.append(feedPost)
        }
        DDLogInfo("FeedData/process-posts/finished  \(newPosts.count) new items.  \(xmppPosts.count - newPosts.count) duplicates.")
        self.save(managedObjectContext)

        // Initiate downloads from the main thread.
        // This is done to avoid race condition with downloads initiated from FeedTableView.
        try? managedObjectContext.obtainPermanentIDs(for: newPosts)
        let postObjectIDs = newPosts.map { $0.objectID }
        DispatchQueue.main.async {
            let managedObjectContext = self.viewContext
            let feedPosts = postObjectIDs.compactMap{ try? managedObjectContext.existingObject(with: $0) as? FeedPost }
            self.downloadMedia(in: feedPosts)
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
                comment.userId = xmppComment.userPhoneNumber
                comment.text = xmppComment.text
                comment.parent = parentComment
                comment.post = feedPost
                comment.status = .incoming
                if let ts = xmppComment.timestamp {
                    comment.timestamp = Date(timeIntervalSince1970: ts)
                } else {
                    comment.timestamp = Date()
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
        self.save(managedObjectContext)
        return newComments
    }

    private func processIncomingFeedItems(_ itemsElement: XMLElement) {
        var feedPosts: [XMPPFeedPost] = []
        var comments: [XMPPComment] = []
        let items = itemsElement.elements(forName: "item")
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

            // TODO: Send acks now
        }
    }

    private func generateNotifications(for comments: [FeedPostComment], using managedObjectContext: NSManagedObjectContext) {
        guard !comments.isEmpty else { return }

        let selfId = AppContext.shared.userData.phone
        for comment in comments {
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

            let notification = NSEntityDescription.insertNewObject(forEntityName: FeedNotification.entity().name!, into: managedObjectContext) as! FeedNotification
            notification.commentId = comment.id
            notification.postId = comment.post.id
            notification.event = event!
            notification.userId = authorId
            notification.timestamp = comment.timestamp
            notification.text = comment.text
            if let media = comment.post.media?.anyObject() as? FeedPostMedia {
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
        }
        if managedObjectContext.hasChanges {
            self.save(managedObjectContext)
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
            feedPost.orderedMedia.forEach { feedPostMedia in
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

    func reloadMedia(feedPostId: FeedPost.ID, order: Int) {
        guard let feedDataItem = self.feedDataItem(with: feedPostId) else { return }
        guard let feedPost = self.feedPost(with: feedPostId) else { return }
        feedDataItem.reloadMedia(from: feedPost, order: order)
    }

    func feedDownloadManager(_ manager: FeedDownloadManager, didFinishTask task: FeedDownloadManager.Task) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
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

            let feedPostId = feedPostMedia.post.id
            let mediaOrder = Int(feedPostMedia.order)
            DispatchQueue.main.async {
                self.reloadMedia(feedPostId: feedPostId, order: mediaOrder)
            }

            // TODO: update media preview for notifications for this post
        }
    }

    // MARK: Posting

    func post(text: String, media: [PendingMedia]) {
        let xmppPost = XMPPFeedPost(text: text, media: media)

        // Create and save new FeedPost object.
        let managedObjectContext = self.persistentContainer.viewContext
        DDLogDebug("FeedData/new-post/create [\(xmppPost.id)]")
        let feedPost = NSEntityDescription.insertNewObject(forEntityName: FeedPost.entity().name!, into: managedObjectContext) as! FeedPost
        feedPost.id = xmppPost.id
        feedPost.userId = xmppPost.userPhoneNumber
        feedPost.text = xmppPost.text
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
        let request = XMPPPostItemRequest(xmppFeedPost: xmppPost) { (timestamp, error) in
            if error != nil {
                self.updateFeedPost(with: xmppPost.id) { (feedPost) in
                    feedPost.status = .sendError
                }
            } else {
                self.updateFeedPost(with: xmppPost.id) { (feedPost) in
                    if timestamp != nil {
                        feedPost.timestamp = Date(timeIntervalSince1970: timestamp!)
                    }
                    feedPost.status = .sent
                }
            }
        }
        AppContext.shared.xmppController.enqueue(request: request)
    }

    func post(comment text: String, to feedItem: FeedDataItem, replyingTo parentCommentId: FeedPostComment.ID? = nil) {
        let xmppComment = XMPPComment(text: text, feedPostId: feedItem.itemId, parentCommentId: parentCommentId)

        // Create and save FeedPostComment
        let managedObjectContext = self.persistentContainer.viewContext
        guard let feedPost = self.feedPost(with: feedItem.itemId, in: managedObjectContext) else {
            DDLogError("FeedData/new-comment/error  Missing FeedPost with id [\(feedItem.itemId)]")
            fatalError("Unable to find FeedPost")
        }
        var parentComment: FeedPostComment?
        if parentCommentId != nil {
            parentComment = self.feedComment(with: parentCommentId!, in: managedObjectContext)
            if parentComment == nil {
                DDLogError("FeedData/new-comment/error  Missing parent comment with id=[\(parentCommentId!)]")
            }
        }
        DDLogDebug("FeedData/new-comment/create id=[\(xmppComment.id)]  postId=[\(feedPost.id)]")
        let comment = NSEntityDescription.insertNewObject(forEntityName: FeedPostComment.entity().name!, into: managedObjectContext) as! FeedPostComment
        comment.id = xmppComment.id
        comment.userId = xmppComment.userPhoneNumber
        comment.text = xmppComment.text
        comment.parent = parentComment
        comment.post = feedPost
        comment.status = .sending
        comment.timestamp = Date()
        self.save(managedObjectContext)

        // Now send data over the wire.
        let request = XMPPPostCommentRequest(xmppComment: xmppComment, postAuthor: feedPost.userId) { (timestamp, error) in
            if error != nil {
                 self.updateFeedPostComment(with: xmppComment.id) { (feedComment) in
                     feedComment.status = .sendError
                 }
             } else {
                 self.updateFeedPostComment(with: xmppComment.id) { (feedComment) in
                     if timestamp != nil {
                         feedComment.timestamp = Date(timeIntervalSince1970: timestamp!)
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
        let postMedia = feedPost.media as! Set<FeedPostMedia>
        for media in postMedia {
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
