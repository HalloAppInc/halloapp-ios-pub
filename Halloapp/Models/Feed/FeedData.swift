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

class FeedData: ObservableObject {
    @Published var feedDataItems : [FeedDataItem] = []
    @Published var feedCommentItems : [FeedComment] = []

    private var userData: UserData
    private var xmppController: XMPPController
    private var cancellableSet: Set<AnyCancellable> = []

    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.feed")

    init(xmppController: XMPPController, userData: UserData) {
        self.xmppController = xmppController
        self.userData = userData

        self.feedDataItems = FeedItemCore.getAll()
        self.feedCommentItems = FeedCommentCore.getAll()
        
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
                
                self.processExpires()
            })
        
        self.cancellableSet.insert(
            self.userData.didLogOff.sink {
                DDLogInfo("Unloading feed data. \(self.feedDataItems.count) posts. \(self.feedCommentItems.count) comments")
                
                self.feedCommentItems.removeAll()
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

    // MARK: Fetching Feed Data

    private func feedPost(with id: FeedPost.ID, in managedObjectContext: NSManagedObjectContext) -> FeedPost? {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let posts = try managedObjectContext.fetch(fetchRequest)
            return posts.first
        }
        catch {
            DDLogError("FeedData/fetch-posts/error  [\(error)]")
            fatalError("Failed to fetch feed posts.")
        }
    }

    private func feedPosts(with ids: Set<FeedPost.ID>, in managedObjectContext: NSManagedObjectContext) -> [FeedPost] {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id in %@", ids)
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

    private func updateFeedPost(with id: FeedPost.ID, block: @escaping (FeedPost) -> Void) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let feedPost = self.feedPost(with: id, in: managedObjectContext) else {
                DDLogError("FeedData/update-post/missing-post [\(id)]")
                return
            }
            DDLogVerbose("FeedData/update-post [\(id)]")
            block(feedPost)
            self.save(managedObjectContext)
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
            self.save(managedObjectContext)
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
            for xmppMedia in xmppPost.media {
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
                feedMedia.post = feedPost
            }

            newPosts.append(feedPost)
        }
        DDLogInfo("FeedData/process-posts/finished  \(newPosts.count) new items.  \(xmppPosts.count - newPosts.count) duplicates.")
        self.save(managedObjectContext)
        return newPosts
    }

    @discardableResult private func process(comments xmppComments: [XMPPComment], using managedObjectContext: NSManagedObjectContext) -> [FeedPostComment] {
        guard !xmppComments.isEmpty else { return [] }

        let feedPostIds = Set(xmppComments.map{ $0.feedPostId })
        let feedPosts = self.feedPosts(with: feedPostIds, in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
        var comments = self.feedComments(with: Set(xmppComments.compactMap{ $0.parentId }), in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
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

        let feedDataItems = feedPosts.map { FeedDataItem($0) }
        for item in feedDataItems.sorted(by: { $0.timestamp > $1.timestamp }) {
            self.pushItem(item: item)
        }

        // TODO: do bulk processing here
        let feedComments = comments.map { FeedComment($0) }
        for item in feedComments {
            self.insertComment(item: item)
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
        for xmppMedia in xmppPost.media {
            DDLogDebug("FeedData/new-post/add-media [\(xmppMedia.url)]")
            let feedMedia = NSEntityDescription.insertNewObject(forEntityName: FeedPostMedia.entity().name!, into: managedObjectContext) as! FeedPostMedia
            switch xmppMedia.type {
            case .image:
                feedMedia.type = .image
            case .video:
                feedMedia.type = .video
            }
            feedMedia.status = .uploaded // For now we're only posting when all uploads are completed.
            // TODO: set path.
            feedMedia.url = xmppMedia.url
            feedMedia.post = feedPost
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

            let feedItem = FeedDataItem(xmppPost)
            if timestamp != nil {
                // TODO: probably not need to use server timestamp here?
                feedItem.timestamp = Date(timeIntervalSince1970: timestamp!)
            }
            feedItem.media = media.map{ FeedMedia($0, feedItemId: feedPost.id) }
            // TODO: save post to the local db before request finishes and allow to retry later.
            self.pushItem(item: feedItem)
            // TODO: write media data to db
        }
        AppContext.shared.xmppController.enqueue(request: request)
    }

    func post(comment text: String, to feedItem: FeedDataItem, replyingTo parentCommentId: String? = nil) {
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
        let request = XMPPPostCommentRequest(xmppComment: xmppComment, postAuthor: feedItem.username) { (timestamp, error) in
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

            var feedComment = FeedComment(xmppComment)
            if timestamp != nil {
                // TODO: probably not need to use server timestamp here?
                feedComment.timestamp = Date(timeIntervalSince1970: timestamp!)
            }
            // TODO: comment should be saved to local db before it is posted.
            self.insertComment(item: feedComment)
        }
        AppContext.shared.xmppController.enqueue(request: request)
    }

    func getItemMedia(_ itemId: String) {
        if let feedItem = self.feedDataItems.first(where: { $0.itemId == itemId }) {
            if feedItem.media.isEmpty {
                feedItem.media = FeedMediaCore.get(feedItemId: itemId)

                DDLogDebug("FeedData/getItemMedia item=[\(itemId)] count=[\(feedItem.media.count)]")

                /* ideally we should have the images in core data by now */
                /* todo: scan for unloaded images during init */
                feedItem.loadMedia()
            }
        }
    }

    func calHeight(media: [FeedMedia]) -> Int? {
        guard !media.isEmpty else { return nil }

        var maxHeight: CGFloat = 0
        var width: CGFloat = 0

        media.forEach { media in
            if media.size.height > maxHeight {
                maxHeight = media.size.height
                width = media.size.width
            }
        }

        if maxHeight < 1 {
            return nil
        }

        let desiredAspectRatio: Float = 5/4 // 1.25 for portrait

        // can be customized for different devices
        let desiredViewWidth = Float(UIScreen.main.bounds.width) - 20 // account for padding on left and right

        let desiredTallness = desiredAspectRatio * desiredViewWidth

        let ratio = Float(maxHeight)/Float(width) // image ratio

        let actualTallness = ratio * desiredViewWidth

        let resultHeight = actualTallness >= desiredTallness ? desiredTallness : actualTallness + 10
        return Int(resultHeight.rounded())
    }

    func pushItem(item: FeedDataItem) {
        guard !self.feedDataItems.contains(where: { $0.itemId == item.itemId }) else { return }
        guard !FeedItemCore.isPresent(itemId: item.itemId) else { return }

        item.mediaHeight = self.calHeight(media: item.media)
        self.feedDataItems.insert(item, at: 0)
        self.feedDataItems.sort {
            return $0.timestamp > $1.timestamp
        }

        FeedItemCore.create(item: item)
        item.media.forEach { FeedMediaCore.create(item: $0) }

        item.loadMedia()
    }

    func insertComment(item: FeedComment) {
        guard !self.feedCommentItems.contains(where: { $0.id == item.id }) else { return }

        self.feedCommentItems.insert(item, at: 0)

        if (item.username != self.userData.phone) {
            self.increaseFeedItemUnreadComments(feedItemId: item.feedItemId, by: 1)
        }

        FeedCommentCore.create(item: item)
    }

    func increaseFeedItemUnreadComments(feedItemId: String, by number: Int) {
        guard let feedDataItem = self.feedDataItems.first(where: { $0.itemId == feedItemId }) else { return }
        feedDataItem.unreadComments += number
        FeedItemCore.update(item: feedDataItem)
    }

    func markFeedItemUnreadComments(feedItemId: String) {
        guard let feedDataItem = self.feedDataItems.first(where: { $0.itemId == feedItemId }) else { return }
        if feedDataItem.unreadComments > 0 {
            feedDataItem.unreadComments = 0
            FeedItemCore.update(item: feedDataItem)
        }
    }
    
    func feedDataItem(with itemId: String) -> FeedDataItem? {
        return self.feedDataItems.first(where: { $0.itemId == itemId })
    }
    
    func processExpires() {
        let current = Date().timeIntervalSince1970
        let month = Date.days(30)

        for (i, item) in feedDataItems.enumerated().reversed() {
            let diff = current - item.timestamp.timeIntervalSince1970
            if diff > month {
                if (item.username != self.userData.phone) {
                    // TODO: bulk delete
                    FeedItemCore.delete(itemId: item.itemId)
                    feedDataItems.remove(at: i)
                }
            }
        }
    }
}
