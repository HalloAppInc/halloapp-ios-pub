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

    private(set) var activityObserver: FeedActivityObserver?

    let didReloadStore = PassthroughSubject<Void, Never>()

    let shouldReloadView = PassthroughSubject<Void, Never>()

    let didGetRemoveHomeTabIndicator = PassthroughSubject<Void, Never>()
    
    let validMoment = CurrentValueSubject<FeedPost?, Never>(nil)
    private(set) var expiredMoments = Set<FeedPostID>()

    private struct UserDefaultsKey {
        static let persistentStoreUserID = "feed.store.userID"
    }

    private static let externalShareThumbSize: CGFloat = 800

    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.feed")
    private lazy var downloadManager: FeedDownloadManager = {
        let downloadManager = FeedDownloadManager(mediaDirectoryURL: MainAppContext.commonMediaStoreURL)
        downloadManager.delegate = self
        return downloadManager
    }()

    let mediaUploader: MediaUploader
    private let commonMediaUploader: CommonMediaUploader
    private let coreFeedData: CoreFeedData

    private var contentInFlight: Set<String> = []

    init(service: HalloService, contactStore: ContactStoreMain, mainDataStore: MainDataStore, userData: UserData, coreFeedData: CoreFeedData, mediaUploader: CommonMediaUploader) {
        self.service = service
        self.contactStore = contactStore
        self.mainDataStore = mainDataStore
        self.userData = userData
        self.commonMediaUploader = mediaUploader
        self.mediaUploader = MediaUploader(service: service)
        self.coreFeedData = coreFeedData

        super.init()

        self.service.feedDelegate = self
        // when app resumes, xmpp reconnects, feed should try uploading any pending again
        cancellableSet.insert(
            self.service.didConnect.sink {
                DDLogInfo("Feed: Got event for didConnect")

                self.deleteExpiredPosts()
                self.deleteExpiredMoments()

                self.performSeriallyOnBackgroundContext { managedObjectContext in
                    self.getArchivedPosts { [weak self] posts in
                        self?.deleteAssociatedData(for: posts, in: managedObjectContext)
                    }
                    self.deleteNotifications(olderThan: Date(timeIntervalSinceNow: -FeedPost.defaultExpiration), in: managedObjectContext)
                }
                self.resendStuckItems()
                self.resendPendingReadReceipts()
            })

        cancellableSet.insert(
            mainDataStore.didClearStore.sink {
                do {
                    DDLogInfo("FeedData/didClearStore/clear-media starting")
                    try FileManager.default.removeItem(at: MediaDirectory.media.url)
                    DDLogInfo("FeedData/didClearStore/clear-media finished")
                }
                catch {
                    DDLogError("FeedData/didClearStore/clear-media/error [\(error)]")
                }
            }
        )

        cancellableSet.insert(
            self.contactStore.didDiscoverNewUsers.sink { (userIds) in
                userIds.forEach({ self.sharePastPostsWith(userId: $0) })
            })

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification, object: nil).sink { [weak self] _ in
            // on the app's enter, we check the status of the user's moment
            self?.refreshValidMoment()
        }.store(in: &cancellableSet)

        fetchFeedPosts()
        refreshValidMoment()
    }

    private func performSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        mainDataStore.performSeriallyOnBackgroundContext(block)
    }

    var viewContext: NSManagedObjectContext {
        mainDataStore.viewContext
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

    func migrateLegacyPosts(_ legacyPosts: [FeedPostLegacy]) throws {
        try mainDataStore.saveSeriallyOnBackgroundContextAndWait { context in
            DDLogInfo("FeedData/migrateLegacyPosts/begin [\(legacyPosts.count)]")
            legacyPosts.forEach { self.migrateLegacyPost($0, in: context) }
            DDLogInfo("FeedData/migrateLegacyPosts/finished [\(legacyPosts.count)]")
        }
    }

    func migrateLegacyNotifications(_ legacyNotifications: [FeedNotification]) throws {
        try mainDataStore.saveSeriallyOnBackgroundContextAndWait { context in
            DDLogInfo("FeedData/migrateLegacyNotifications/begin [\(legacyNotifications.count)]")
            legacyNotifications.forEach { self.migrateLegacyNotification($0, in: context) }
            DDLogInfo("FeedData/migrateLegacyNotifications/finished [\(legacyNotifications.count)]")
        }
    }

    private func migrateLegacyNotification(_ legacy: FeedNotification, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("FeedData/migrateLegacyNotification/new/ [\(legacy.postId):\(legacy.event):\(legacy.userId):\(legacy.timestamp)]")
        let activity = FeedActivity(context: managedObjectContext)
        activity.event = legacy.event
        activity.commentID = legacy.commentId
        activity.mediaPreview = legacy.mediaPreview
        activity.postID = legacy.postId
        activity.userID = legacy.userId
        activity.read = legacy.read
        activity.rawText = legacy.text
        activity.timestamp = legacy.timestamp
        activity.mentions = legacy.mentions?.map { MentionData(index: $0.index, userID: $0.userID, name: $0.name) } ?? []
        activity.mediaType = legacy.mediaType
        DDLogInfo("FeedData/migrateLegacyNotification/finished/ [\(legacy.postId):\(legacy.event):\(legacy.userId):\(legacy.timestamp)]")
    }

    private func migrateLegacyPost(_ legacy: FeedPostLegacy, in managedObjectContext: NSManagedObjectContext) {
        let post: FeedPost = {
            if let post = feedPost(with: legacy.id, in: managedObjectContext, archived: true) {
                DDLogInfo("FeedData/migrateLegacyPost/existing/\(legacy.id)")
                return post
            } else {
                DDLogInfo("FeedData/migrateLegacyPost/new/\(legacy.id)")
                return FeedPost(context: managedObjectContext)
            }
        }()
        legacy.comments?.forEach { self.migrateLegacyComment($0, toPost: post, in: managedObjectContext) }
        legacy.linkPreviews?.forEach { self.migrateLegacyLinkPreview($0, toPost: post, in: managedObjectContext) }

        // Remove and recreate media
        post.media?.forEach { managedObjectContext.delete($0) }
        legacy.media?.forEach { self.migrateLegacyMedia($0, toPost: post, in: managedObjectContext) }

        if let legacyInfo = legacy.info {
            let originalReceipts = legacyInfo.receipts ?? [:]
            let info = ContentPublishInfo(context: managedObjectContext)
            info.audienceType = legacyInfo.audienceType
            info.receipts = originalReceipts.merging(post.info?.receipts ?? [:]) { r1, r2 in return r2 }
            post.info = info
        }

        for legacyAttempt in (legacy.resendAttempts ?? []) {
            if let existing = post.contentResendInfo?.first(where: { $0.userID == legacyAttempt.userID }) {
                existing.retryCount = max(existing.retryCount, legacyAttempt.retryCount)
            } else {
                let info = ContentResendInfo(context: managedObjectContext)
                info.contentID = legacyAttempt.contentID
                info.retryCount = legacyAttempt.retryCount
                info.userID = legacyAttempt.userID
                info.post = post
            }
        }

        post.mentions = legacy.mentions?.map { MentionData(index: $0.index, userID: $0.userID, name: $0.name) } ?? []
        post.userID = legacy.userId
        post.id = legacy.id
        post.rawText = legacy.text
        post.groupID = legacy.groupId
        post.timestamp = legacy.timestamp
        post.unreadCount = Int32(legacy.unreadCount)
        post.rawData = legacy.rawData
        post.statusValue = Int16(legacy.statusValue)
        post.lastUpdated = legacy.timestamp
        post.expiration = post.timestamp.addingTimeInterval(FeedPost.defaultExpiration)
        DDLogInfo("FeedData/migrateLegacyPost/finished/\(legacy.id)")
    }

    private func migrateLegacyComment(_ legacy: FeedPostCommentLegacy, toPost post: FeedPost, in managedObjectContext: NSManagedObjectContext) {
        let comment: FeedPostComment = {
            if let comment = feedComment(with: legacy.id, in: managedObjectContext) {
                DDLogInfo("FeedData/migrateLegacyComment/existing/\(legacy.id)")
                return comment
            } else {
                DDLogInfo("FeedData/migrateLegacyComment/new/\(legacy.id)")
                return FeedPostComment(context: managedObjectContext)
            }
        }()

        // Remove and recreate media
        comment.media?.forEach { managedObjectContext.delete($0) }
        legacy.media?.forEach { self.migrateLegacyMedia($0, toComment: comment, in: managedObjectContext) }

        legacy.linkPreviews?.forEach { self.migrateLegacyLinkPreview($0, toComment: comment, in: managedObjectContext) }

        comment.id = legacy.id
        comment.mentions = legacy.mentions?.map { MentionData(index: $0.index, userID: $0.userID, name: $0.name) } ?? []
        comment.rawText = legacy.text
        comment.timestamp = legacy.timestamp
        comment.userID = legacy.userId
        comment.rawData = legacy.rawData
        comment.status = legacy.status
        if let resendAttempts = legacy.resendAttempts {
            let resendInfo: [ContentResendInfo] = resendAttempts.map {
                let info = ContentResendInfo(context: managedObjectContext)
                info.contentID = $0.contentID
                info.retryCount = $0.retryCount
                info.userID = $0.userID
                // TODO: Need to fix up group history info?
                return info
            }
            comment.contentResendInfo = Set(resendInfo)
        }
        // Set parent comment if available...
        if let parentID = legacy.parent?.id, let parent = feedComment(with: parentID, in: managedObjectContext) {
            comment.parent = parent
        }
        // ... and also set replies in case the child comments have already been migrated.
        if let replyIDs = legacy.replies?.map({ $0.id }) {
            let replies = feedComments(with: Set(replyIDs), in: managedObjectContext)
            comment.replies = Set(replies).union(comment.replies ?? [])
        }
        comment.post = post
        post.lastUpdated = post.lastUpdated.flatMap { max($0, comment.timestamp) } ?? comment.timestamp
        DDLogInfo("FeedData/migrateLegacyComment/finished/\(legacy.id)")
    }

    private func migrateLegacyMedia(_ legacy: FeedPostMedia, toPost post: FeedPost? = nil, toComment comment: FeedPostComment? = nil, toLinkPreview linkPreview: CommonLinkPreview? = nil, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("FeedData/migrateLegacyMedia/new/\(legacy.id)")

        let media = CommonMedia(context: managedObjectContext)
        media.id = "\(post?.id ?? comment?.id ?? linkPreview?.id ?? UUID().uuidString)-\(legacy.order)"
        media.typeValue = legacy.typeValue
        media.relativeFilePath = legacy.relativeFilePath
        media.url = legacy.url
        media.uploadURL = legacy.uploadUrl
        media.status = legacy.status
        media.width = legacy.width
        media.height = legacy.height
        media.key = legacy.key
        media.sha256 = legacy.sha256
        media.order = legacy.order
        media.blobVersion = legacy.blobVersion
        media.chunkSize = legacy.chunkSize
        media.blobSize = legacy.blobSize
        media.mediaDirectory = .media

        media.post = post
        media.comment = comment
        media.linkPreview = linkPreview
        DDLogInfo("FeedData/migrateLegacyMedia/finished/\(legacy.id)")
    }

    private func migrateLegacyLinkPreview(_ legacy: FeedLinkPreview, toPost post: FeedPost? = nil, toComment comment: FeedPostComment? = nil, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("FeedData/migrateLegacyLinkPreview/new/\(legacy.id)")
        let linkPreview = feedLinkPreview(with: legacy.id, in: managedObjectContext) ?? CommonLinkPreview(context: managedObjectContext)
        linkPreview.id = legacy.id
        linkPreview.desc = legacy.desc
        linkPreview.title = legacy.title
        linkPreview.url = legacy.url

        // Remove and recreate media
        linkPreview.media?.forEach { managedObjectContext.delete($0) }
        legacy.media?.forEach { self.migrateLegacyMedia($0, toLinkPreview: linkPreview, in: managedObjectContext) }

        linkPreview.post = post
        linkPreview.comment = comment
        DDLogInfo("FeedData/migrateLegacyLinkPreview/finished/\(legacy.id)")
    }

    func migrateFeedPostLastUpdated() {
        try? mainDataStore.saveSeriallyOnBackgroundContextAndWait { context in
            self.feedPosts(predicate: NSPredicate(format: "lastUpdated == nil"), in: context).forEach { feedPost in
                // We make the assumption that any comment timestamp is after the feedPost timestamp
                feedPost.lastUpdated = feedPost.comments?.map(\.timestamp).max() ?? feedPost.timestamp
            }
        }
    }

    func migrateFeedPostExpiration() {
        do {
            try mainDataStore.saveSeriallyOnBackgroundContextAndWait { context in
                self.feedPosts(predicate: NSPredicate(format: "expiration == nil"), in: context).forEach { feedPost in
                    feedPost.expiration = feedPost.timestamp.addingTimeInterval(FeedPost.defaultExpiration)
                }
            }
        } catch {
            DDLogError("Failed to migrate FeedPostExpiration")
        }
    }

    // MARK: Fetched Results Controller

    private func processUnsupportedItems() {
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }

            var groupFeedElements = [GroupID: [FeedElement]]()
            var homeFeedElements = [FeedElement]()

            let postsFetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
            postsFetchRequest.predicate = NSPredicate(format: "statusValue = %d", FeedPost.Status.unsupported.rawValue)
            do {
                let unsupportedPosts = try managedObjectContext.fetch(postsFetchRequest)
                for post in unsupportedPosts {
                    guard let rawData = post.rawData else {
                        DDLogError("FeedData/processUnsupportedItems/posts/error [missing data] [\(post.id)]")
                        continue
                    }
                    // NB: Set isShared to true to avoid "New Post" banner
                    guard let postData = PostData(id: post.id,
                                                  userId: post.userId,
                                                  timestamp: post.timestamp,
                                                  expiration: post.expiration,
                                                  payload: rawData,
                                                  status: post.feedItemStatus,
                                                  isShared: true,
                                                  audience: post.audience) else {
                        DDLogError("FeedData/processUnsupportedItems/posts/error [deserialization] [\(post.id)]")
                        continue
                    }
                    switch postData.content {
                    case .album, .text, .retracted, .voiceNote, .moment:
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
                let unsupportedComments = try managedObjectContext.fetch(commentsFetchRequest)
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
                        if let groupID = comment.post.groupId {
                            var elements = groupFeedElements[groupID] ?? []
                            elements.append(.comment(commentData, publisherName: nil))
                            groupFeedElements[groupID] = elements
                        } else {
                            homeFeedElements.append(.comment(commentData, publisherName: nil))
                        }
                    case .commentReaction:
                        DDLogInfo("FeedData/processUnsupportedItems/comments/reaction/migrating [\(comment.id)]")
                        if let groupID = comment.post.groupId {
                            var elements = groupFeedElements[groupID] ?? []
                            elements.append(.comment(commentData, publisherName: nil))
                            groupFeedElements[groupID] = elements
                        } else {
                            homeFeedElements.append(.comment(commentData, publisherName: nil))
                        }
                        DDLogInfo("FeedData/processUnsupportedItems/comments/reaction/deleting tombstone [\(comment.id)]")
                        self.deleteComment(with: comment.id)
                    case .unsupported:
                        DDLogInfo("FeedData/processUnsupportedItems/comments/skipping [still unsupported] [\(comment.id)]")
                        continue
                    case .waiting:
                        DDLogInfo("FeedData/processUnsupportedItems/comments/skipping [still empty] [\(comment.id)]")
                        continue
                    }
                }
            } catch {
                DDLogError("FeedData/processUnsupportedItems/comments/error [\(error)]")
                return
            }

            DDLogInfo("FeedData/processUnsupportedItems/homeFeed [\(homeFeedElements.count)]")
            self.processIncomingFeedItems(homeFeedElements, groupID: nil, presentLocalNotifications: false, ack: nil)
            for (groupID, elements) in groupFeedElements {
                DDLogInfo("FeedData/processUnsupportedItems/groupFeed [\(groupID)] [\(elements.count)]")
                self.processIncomingFeedItems(elements, groupID: groupID, presentLocalNotifications: false, ack: nil)
            }
        }
    }

    private func resendStuckItems() {
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }

            let commentsFetchRequest: NSFetchRequest<FeedPostComment> = FeedPostComment.fetchRequest()
            commentsFetchRequest.predicate = NSPredicate(format: "statusValue = %d", FeedPostComment.Status.sending.rawValue)
            do {
                let stuckComments = try managedObjectContext.fetch(commentsFetchRequest)
                for comment in stuckComments {
                    if comment.timestamp.addingTimeInterval(Date.days(1)) < Date() {
                        DDLogInfo("FeedData/stuck-comments/\(comment.id)/canceling (too old)")
                        self.updateFeedPostComment(with: comment.id) { comment in
                            comment.status = .sendError
                        }
                    } else {
                        DDLogInfo("FeedData/stuck-comments/\(comment.id)/resending")
                        self.uploadMediaAndSend(feedComment: comment)
                    }
                }
            } catch {
                DDLogError("FeedData/stuck-comments/error [\(error)]")
            }

            let postsFetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
            postsFetchRequest.predicate = NSPredicate(format: "statusValue = %d", FeedPost.Status.sending.rawValue)
            do {
                let stuckPosts = try managedObjectContext.fetch(postsFetchRequest)
                for post in stuckPosts {
                    if post.timestamp.addingTimeInterval(Date.days(1)) < Date() {
                        DDLogInfo("FeedData/stuck-posts/\(post.id)/canceling (too old)")
                        self.updateFeedPost(with: post.id) { post in
                            post.status = .sendError
                        }
                    } else {
                        DDLogInfo("FeedData/stuck-posts/\(post.id)/resending")
                        self.beginMediaUploadAndSend(feedPost: post)
                    }
                }
            } catch {
                DDLogError("FeedData/stuck-posts/error [\(error)]")
            }
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
                    let commentsWithIncorrectTimestamp = try fetchedResultsController.managedObjectContext.fetch(commentsFetchRequest)
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
                let notificationsFetchRequest: NSFetchRequest<FeedActivity> = FeedActivity.fetchRequest()
                notificationsFetchRequest.predicate = NSPredicate(format: "timestamp > %@", cutoffDate as NSDate)
                do {
                    let notificationsWithIncorrectTimestamp = try fetchedResultsController.managedObjectContext.fetch(notificationsFetchRequest)
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

        activityObserver = FeedActivityObserver(viewContext)

        reloadGroupFeedUnreadCounts(using: viewContext)
    }
    
    private lazy var fetchedResultsController: NSFetchedResultsController<FeedPost> = newFetchedResultsController()

    private func newFetchedResultsController() -> NSFetchedResultsController<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        let fetchedResultsController = NSFetchedResultsController<FeedPost>(fetchRequest: fetchRequest, managedObjectContext: viewContext,
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
        refreshValidMoment()
        setNeedsReloadGroupFeedUnreadCounts()
    }

    // MARK: Fetching Feed Data

    public func feedHistory(for groupID: GroupID, in managedObjectContext: NSManagedObjectContext, maxNumPosts: Int = Int.max, maxCommentsPerPost: Int = Int.max) -> ([PostData], [CommentData]) {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        // Fetch all feedposts in the group that have not expired yet.
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "groupID == %@", groupID),
            NSPredicate(format: "expiration >= now() || expiration == nil")
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

    public func authoredFeedHistory(for groupID: GroupID, in managedObjectContext: NSManagedObjectContext) -> ([PostData], [CommentData]) {
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

    private func feedPosts(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext, archived: Bool = false) -> [FeedPost] {
        let fetchRequest = FeedPost.fetchRequest()
        
        if let predicate = predicate {
            if !archived {
                fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    predicate,
                    NSPredicate(format: "expiration >= now() || expiration == nil")
                ])
            } else {
                fetchRequest.predicate = predicate
            }
        } else {
            fetchRequest.predicate = NSPredicate(format: "expiration >= now() || expiration == nil")
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

    func feedPost(with id: FeedPostID, in managedObjectContext: NSManagedObjectContext, archived: Bool = false) -> FeedPost? {
        return self.feedPosts(predicate: NSPredicate(format: "id == %@", id), in: managedObjectContext, archived: archived).first
    }

    // Should always be called using the backgroundQueue.
    func fetchResendAttempt(for contentID: String, userID: UserID, in managedObjectContext: NSManagedObjectContext) -> ContentResendInfo {
        let fetchRequest: NSFetchRequest<ContentResendInfo> = ContentResendInfo.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "contentID == %@ AND userID == %@", contentID, userID)
        fetchRequest.returnsObjectsAsFaults = false
        do {
            if let result = try managedObjectContext.fetch(fetchRequest).first {
                return result
            } else {
                let result = ContentResendInfo(context: managedObjectContext)
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

    private func feedPosts(with ids: Set<FeedPostID>, sortDescriptors: [NSSortDescriptor] = [NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: true)],
                           in managedObjectContext: NSManagedObjectContext, archived: Bool = false) -> [FeedPost] {
        return feedPosts(predicate: NSPredicate(format: "id in %@", ids), sortDescriptors: sortDescriptors, in: managedObjectContext, archived: archived)
    }

    private func feedPostsToProcess(sortDescriptors: [NSSortDescriptor] = [NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: true)],
                                              in managedObjectContext: NSManagedObjectContext, archived: Bool = false) -> [FeedPost] {
        return feedPosts(predicate: NSPredicate(format: "hasBeenProcessed == NO"), sortDescriptors: sortDescriptors, in: managedObjectContext, archived: archived)
    }

    func feedLinkPreview(with id: FeedLinkPreviewID, in managedObjectContext: NSManagedObjectContext) -> CommonLinkPreview? {
        let fetchRequest: NSFetchRequest<CommonLinkPreview> = CommonLinkPreview.fetchRequest()
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

    func feedComment(with id: FeedPostCommentID, in managedObjectContext: NSManagedObjectContext) -> FeedPostComment? {
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

    private func feedComments(for feedPostId: FeedPostID,
                              sortDescriptors: [NSSortDescriptor] = [NSSortDescriptor(keyPath: \FeedPostComment.timestamp, ascending: true)],
                              in managedObjectContext: NSManagedObjectContext) -> [FeedPostComment] {
        let fetchRequest: NSFetchRequest<FeedPostComment> = FeedPostComment.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "postID == %@", feedPostId)
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

    private func feedComments(with ids: Set<FeedPostCommentID>,
                              sortDescriptors: [NSSortDescriptor] = [NSSortDescriptor(keyPath: \FeedPostComment.timestamp, ascending: true)],
                              in managedObjectContext: NSManagedObjectContext) -> [FeedPostComment] {
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

    private func feedCommentsToProcess(in managedObjectContext: NSManagedObjectContext) -> [FeedPostComment] {
        let fetchRequest: NSFetchRequest<FeedPostComment> = FeedPostComment.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "hasBeenProcessed == NO")
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
    
    private func commonReaction(with id: String, in managedObjectContext: NSManagedObjectContext) -> CommonReaction? {
        return self.commonReactions(predicate: NSPredicate(format: "id == %@", id), in: managedObjectContext).first
    }
    
    private func commonReactions(predicate: NSPredicate? = nil,
                                 sortDescriptors: [NSSortDescriptor]? = nil,
                                 limit: Int? = nil,
                                 in managedObjectContext: NSManagedObjectContext) -> [CommonReaction] {
        let fetchRequest: NSFetchRequest<CommonReaction> = CommonReaction.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        if let fetchLimit = limit { fetchRequest.fetchLimit = fetchLimit }
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let reactions = try managedObjectContext.fetch(fetchRequest)
            return reactions
        }
        catch {
            DDLogError("FeedData/fetch-reactions/error  [\(error)]")
            fatalError("Failed to fetch reactions")
        }
    }
    
    private func commonReactions(with ids: Set<CommonReactionID>,
                              sortDescriptors: [NSSortDescriptor] = [NSSortDescriptor(keyPath: \CommonReaction.timestamp, ascending: true)],
                              in managedObjectContext: NSManagedObjectContext) -> [CommonReaction] {
        let fetchRequest: NSFetchRequest<CommonReaction> = CommonReaction.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id in %@", ids)
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let reactions = try managedObjectContext.fetch(fetchRequest)
            return reactions
        }
        catch {
            DDLogError("FeedData/fetch-reactions/error  [\(error)]")
            fatalError("Failed to fetch feed post comment reactions.")
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

    private func reloadGroupFeedUnreadCounts(using context: NSManagedObjectContext) {
        var results: [GroupID: GroupFeedState] = [:]

        // Count posts in all groups.
        let countDesc = NSExpressionDescription()
        countDesc.expression = NSExpression(forFunction: "count:", arguments: [ NSExpression(forKeyPath: \FeedPost.groupID) ])
        countDesc.name = "count"
        countDesc.expressionResultType = .integer64AttributeType

        let fetchRequest: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: FeedPost.entity().name!)
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.predicate = NSPredicate(format: "groupID != nil")
        fetchRequest.propertiesToGroupBy = [ "groupID" ]
        fetchRequest.propertiesToFetch = [ "groupID", countDesc ]
        fetchRequest.resultType = .dictionaryResultType
        do {
            let fetchResults = try context.fetch(fetchRequest)
            for result in fetchResults {
                guard let groupId = result["groupID"] as? GroupID, let count = result["count"] as? Int else { continue }
                results[groupId] = .seenPosts(count)
            }
        }
        catch {
            DDLogError("FeedData/fetch-posts/error  [\(error)]")
            fatalError("Failed to fetch feed posts.")
        }

        // Count new posts in groups.
        fetchRequest.predicate = NSPredicate(format: "groupID != nil AND statusValue == %d", FeedPost.Status.incoming.rawValue)
        do {
            let fetchResults = try context.fetch(fetchRequest)
            for result in fetchResults {
                guard let groupId = result["groupID"] as? GroupID, let count = result["count"] as? Int else { continue }
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
            self.reloadGroupFeedUnreadCounts(using: self.viewContext)
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
                    if let group = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: managedObjectContext) {
                        feedPost.expiration = group.postExpirationDate(from: feedPost.timestamp)
                    } else {
                        DDLogError("FeedData/createTombstones/groupID: \(groupID) not found, setting default expiration...")
                        feedPost.expiration = feedPost.timestamp.addingTimeInterval(FeedPost.defaultExpiration)
                    }
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
                    feedPostComment.rawText = ""
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
        performSeriallyOnBackgroundContext { (managedObjectContext) in
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
    
    private func updateReaction(with id: CommonReactionID, block: @escaping (CommonReaction) -> (), performAfterSave: (() -> ())? = nil) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            defer {
                if let performAfterSave = performAfterSave {
                    performAfterSave()
                }
            }
            guard let reaction = self.commonReaction(with: id, in: managedObjectContext) else {
                DDLogError("FeedData/update-reaction/missing-reaction [\(id)]")
                return
            }
            DDLogVerbose("FeedData/update-reaction [\(id)]")
            block(reaction)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    private func updateFeedLinkPreview(with id: FeedLinkPreviewID, block: @escaping (CommonLinkPreview) -> (), performAfterSave: (() -> ())? = nil) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
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
                                            presentLocalNotifications: Bool,
                                            fromExternalShare: Bool) -> [FeedPost] {
        guard !xmppPosts.isEmpty else { return [] }

        let postIds = Set(xmppPosts.map{ $0.id })
        let existingPosts = feedPosts(with: postIds, in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
        var newPosts: [FeedPost] = []
        var sharedPosts: [FeedPostID] = []

        for xmppPost in xmppPosts {
            if let existingPost = existingPosts[xmppPost.id] {
                if fromExternalShare {
                    // Ignore any posts externally shared that are already in the app
                    DDLogInfo("FeedData/process-posts/existing [\(existingPost.id)]/skipping update from external share")
                    continue
                } else if !fromExternalShare, existingPost.fromExternalShare {
                    // Always update any existing externally shared posts
                    DDLogInfo("FeedData/process-posts/existing [\(existingPost.id)]/updating existing external share post")
                    existingPost.fromExternalShare = false
                    existingPost.groupId = groupID
                    existingPost.lastUpdated = xmppPost.timestamp
                    existingPost.expiration = xmppPost.expiration
                    newPosts.append(existingPost)
                    continue
                } else if existingPost.status == .none {
                    // If status = .none for an existing post, we need to process the newly received post.
                    DDLogInfo("FeedData/process-posts/existing [\(existingPost.id)]/status is none/need to update")
                } else if existingPost.status == .unsupported {
                    // If status = .unsupported, populate it
                    DDLogInfo("FeedData/process-posts/existing [\(existingPost.id)]/status is unsupported/need to update")
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
            case .incoming, .seen, .seenSending, .sendError, .sending, .sent, .retracted, .retracting, .expired:
                DDLogError("FeedData/process-posts/skipping [duplicate] [\(xmppPost.id)] current status: \(feedPost.status)")
                continue
            }

            feedPost.id = xmppPost.id
            feedPost.userId = xmppPost.userId
            feedPost.groupId = groupID
            feedPost.rawText = xmppPost.text
            feedPost.timestamp = xmppPost.timestamp
            feedPost.lastUpdated = xmppPost.timestamp
            feedPost.expiration = xmppPost.expiration
             // This is safe to always update as we skip processing any existing posts if fromExternalShare
            feedPost.fromExternalShare = fromExternalShare

            if case let .moment(_, unlockUID) = xmppPost.content {
                feedPost.isMoment = true
                feedPost.unlockedMomentUserID = unlockUID
            }

            switch xmppPost.content {
            case .album, .text, .voiceNote, .moment:
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
            setCachedMedia(nil, for: feedPost.id)

            feedPost.mentions = xmppPost.orderedMentions.map {
                MentionData(index: $0.index, userID: $0.userID, name: $0.name)
            }

            // Post Audience
            if let audience = xmppPost.audience {
                let feedPostInfo = ContentPublishInfo(context: managedObjectContext)
                feedPostInfo.audienceType = audience.audienceType
                feedPostInfo.receipts = audience.userIds.reduce(into: [UserID : Receipt]()) { (receipts, userId) in
                    receipts[userId] = Receipt()
                }
                feedPost.info = feedPostInfo
            }

            // Process link preview if present
            xmppPost.linkPreviewData.forEach { linkPreviewData in
                DDLogDebug("FeedData/process-posts/new/add-link-preview [\(linkPreviewData.url)]")
                let linkPreview = CommonLinkPreview(context: managedObjectContext)
                linkPreview.id = PacketID.generate()
                linkPreview.url = linkPreviewData.url
                linkPreview.title = linkPreviewData.title
                linkPreview.desc = linkPreviewData.description
                // Set preview image if present
                linkPreviewData.previewImages.enumerated().forEach { (index, previewMedia) in
                    let media = CommonMedia(context: managedObjectContext)
                    media.id = "\(linkPreview.id)-\(index)"
                    media.type = previewMedia.type
                    media.status = .none
                    media.url = previewMedia.url
                    media.size = previewMedia.size
                    media.key = previewMedia.key
                    media.sha256 = previewMedia.sha256
                    media.linkPreview = linkPreview
                    media.order = Int16(index)
                }
                linkPreview.post = feedPost
            }
            // Process post media
            for (index, xmppMedia) in xmppPost.orderedMedia.enumerated() {
                DDLogDebug("FeedData/process-posts/new/add-media [\(xmppMedia.url!)]")
                let feedMedia = CommonMedia(context: managedObjectContext)
                feedMedia.id = "\(feedPost.id)-\(index)"
                feedMedia.type = xmppMedia.type
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
            if !fromExternalShare {
                newPosts.append(feedPost)
            }

            DDLogInfo("FeedData/process-posts/post [\(xmppPost.id)] with status: \(xmppPost.status)")
        }
        DDLogInfo("FeedData/process-posts/finished \(newPosts.count) new items, \(xmppPosts.count - newPosts.count) duplicates, \(sharedPosts.count) shared (old)")
        save(managedObjectContext)

        try? managedObjectContext.obtainPermanentIDs(for: newPosts)
        let postObjectIDs = newPosts.map { $0.objectID }
        DispatchQueue.main.async {
            let managedObjectContext = self.viewContext
            let feedPosts = postObjectIDs.compactMap { try? managedObjectContext.existingObject(with: $0) as? FeedPost }

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
        let posts = feedPosts(with: feedPostIds, in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
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
                    } else if existingComment.status == .unsupported {
                        DDLogInfo("FeedData/process-comments/existing [\(existingComment.id)]/status is unsupported/need to update")
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
                } else {
                    DDLogError("FeedData/process-comments/missing-post [\(xmppComment.feedPostId)]/skip comment")
                    AppContext.shared.errorLogger?.logError(NSError(domain: "MissingPostForComment", code: 1009))
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
                        parentComment?.rawText = ""
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
                    comment = FeedPostComment(context: managedObjectContext)
                }

                comment.id = xmppComment.id
                comment.userId = xmppComment.userId
                comment.parent = parentComment
                comment.post = feedPost
                comment.timestamp = xmppComment.timestamp
                feedPost.lastUpdated = feedPost.lastUpdated.flatMap { max($0, comment.timestamp) } ?? comment.timestamp
                // Clear cached media if any.
                setCachedMedia(nil, for: feedPost.id)

                switch xmppComment.content {
                case .text(let mentionText, let linkPreviewData):
                    comment.rawText = mentionText.collapsedText
                    comment.mentions = mentionText.mentionsArray
                    // Process link preview if present
                    linkPreviewData.forEach { linkPreviewData in
                        DDLogDebug("FeedData/process-comments/new/add-link-preview [\(linkPreviewData.url)]")
                        let linkPreview = CommonLinkPreview(context: managedObjectContext)
                        linkPreview.id = PacketID.generate()
                        linkPreview.url = linkPreviewData.url
                        linkPreview.title = linkPreviewData.title
                        linkPreview.desc = linkPreviewData.description
                        // Set preview image if present
                        linkPreviewData.previewImages.enumerated().forEach { (index, previewMedia) in
                            let media = CommonMedia(context: managedObjectContext)
                            media.id = "\(linkPreview.id)-\(index)"
                            media.type = previewMedia.type
                            media.status = .none
                            media.url = previewMedia.url
                            media.size = previewMedia.size
                            media.key = previewMedia.key
                            media.sha256 = previewMedia.sha256
                            media.linkPreview = linkPreview
                            media.order = Int16(index)
                        }
                        linkPreview.comment = comment
                    }
                case .album(let mentionText, let media):
                    comment.rawText = mentionText.collapsedText
                    comment.mentions = mentionText.mentionsArray
                    // Process Comment Media
                    for (index, xmppMedia) in media.enumerated() {
                        DDLogDebug("FeedData/process-comments/new/add-comment-media [\(xmppMedia.url!)]")
                        let feedCommentMedia = CommonMedia(context: managedObjectContext)
                        feedCommentMedia.id = "\(comment.id)-\(index)"
                        feedCommentMedia.type = xmppMedia.type
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
                    comment.rawText = ""
                    comment.mentions = []

                    let feedCommentMedia = CommonMedia(context: managedObjectContext)
                    feedCommentMedia.id = "\(comment.id)-0"
                    feedCommentMedia.type = .audio
                    feedCommentMedia.status = .none
                    feedCommentMedia.url = media.url
                    feedCommentMedia.size = media.size
                    feedCommentMedia.key = media.key
                    feedCommentMedia.order = 0
                    feedCommentMedia.sha256 = media.sha256
                    feedCommentMedia.comment = comment
                case .commentReaction(let emoji):
                    comment.rawText = emoji
                case .retracted:
                    comment.rawText = ""
                case .unsupported(let data):
                    comment.rawData = data
                    comment.rawText = ""
                case .waiting:
                    comment.rawText = ""
                }

                // Set status for each comment appropriately.
                switch xmppComment.content {
                case .album, .text, .commentReaction, .voiceNote:
                    // Mark our own comments as seen in case server sends us old comments following re-registration
                    if comment.userId == userData.userId {
                        comment.status = .sent
                    } else {
                        // Set status to be rerequesting if necessary.
                        if xmppComment.status == .rerequesting {
                            comment.status = .rerequesting
                        } else {
                            comment.status = .incoming
                        }
                    }
                case .retracted:
                    DDLogError("FeedData/process-comments/incoming-retracted-comment [\(xmppComment.id)]")
                    comment.status = .retracted
                case .unsupported(let data):
                    comment.status = .unsupported
                    feedPost.rawData = data
                case .waiting:
                    comment.status = .rerequesting
                    if xmppComment.status != .rerequesting {
                        DDLogError("FeedData/process-comments/invalid content [\(xmppComment.id)] with status: \(xmppComment.status)")
                    }
                }

                comments[comment.id] = comment
                newComments.append(comment)

                // Increase unread comments counter on post.
                feedPost.lastUpdated = feedPost.lastUpdated.flatMap { max($0, comment.timestamp) } ?? comment.timestamp
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

    @discardableResult private func process(reactions xmppReactions: [CommentData],
                                            receivedIn groupID: GroupID?,
                                            using managedObjectContext: NSManagedObjectContext,
                                            presentLocalNotifications: Bool) -> [CommonReaction] {
        guard !xmppReactions.isEmpty else { return [] }

        let feedPostIds = Set(xmppReactions.map{ $0.feedPostId })
        let posts = feedPosts(with: feedPostIds, in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
        let reactionIds = Set(xmppReactions.map{ $0.id })
        var reactions = commonReactions(with: reactionIds, in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
        let commentIds = Set(xmppReactions.compactMap{ $0.parentId })
        let comments = feedComments(with: commentIds, in: managedObjectContext).reduce(into: [:]) { $0[$1.id] = $1 }
        var ignoredReactionIds: Set<String> = []
        var newReactions: [CommonReaction] = []
        
        for xmppReaction in xmppReactions {

            if let existingReaction = reactions[xmppReaction.id] {
                switch existingReaction.incomingStatus {
                case .unsupported, .none, .rerequesting:
                    DDLogInfo("FeedData/process/already-exists/updating [\(existingReaction.incomingStatus)] [\(xmppReaction.id)]")
                    break
                case .error, .incoming, .retracted:
                    DDLogError("FeedData/process/already-exists/error [\(existingReaction.incomingStatus)] [\(xmppReaction.id)]")
                    continue
                }
            }

            // Find reaction's post.
            let feedPost: FeedPost
            if let post = posts[xmppReaction.feedPostId] {
                DDLogInfo("FeedData/process-reactions/existing-post [\(xmppReaction.feedPostId)]")
                feedPost = post
            } else {
                DDLogError("FeedData/process-reactions/missing-post [\(xmppReaction.feedPostId)]/skip comment")
                AppContext.shared.errorLogger?.logError(NSError(domain: "MissingPostForReaction", code: 1011))
                ignoredReactionIds.insert(xmppReaction.id)
                continue
            }

            // Additional check: post's groupId must match groupId of the comment.
            guard feedPost.groupId == groupID else {
                DDLogError("FeedData/process-reactions/incorrect-group-id post:[\(feedPost.groupId ?? "")] comment:[\(groupID ?? "")]")
                ignoredReactionIds.insert(xmppReaction.id)
                continue
            }

            // Check if post has been retracted.
            guard !feedPost.isPostRetracted else {
                DDLogError("FeedData/process-reactions/retracted-post [\(xmppReaction.feedPostId)]")
                ignoredReactionIds.insert(xmppReaction.id)
                continue
            }

            // Check if parent comment exists
            guard let parentId = xmppReaction.parentId, let parentComment = comments[parentId] else {
                DDLogError("FeedData/process-reactions/no-parent-comment for reaction [\(xmppReaction.id)]")
                ignoredReactionIds.insert(xmppReaction.id)
                // TODO: handle reactions that arrive before corresponding comment
                continue
            }

            DDLogDebug("FeedData/process-reactions [\(xmppReaction.id)]")
            let commonReaction: CommonReaction = {
                guard let existingReaction = reactions[xmppReaction.id] else {
                    let existingTombstone = self.feedComment(with: xmppReaction.id, in: managedObjectContext)
                    if let existingTombstone = existingTombstone, existingTombstone.status == .rerequesting {
                        //Delete tombstone
                        DDLogInfo("FeedData/process-reactions/deleteTombstone [\(existingTombstone.id)]")
                        managedObjectContext.delete(existingTombstone)
                    }
                    DDLogDebug("FeedData/process-reactions/new [\(xmppReaction.id)]")
                    return CommonReaction(context: managedObjectContext)
                }
                DDLogDebug("FeedData/process-reactions/updating rerequested reaction [\(xmppReaction.id)]")
                return existingReaction
            }()

            commonReaction.id = xmppReaction.id
            commonReaction.fromUserID = xmppReaction.userId
            switch xmppReaction.content {
            case .commentReaction(let emoji):
                commonReaction.emoji = emoji
            case .album, .text, .voiceNote, .unsupported, .retracted, .waiting:
                DDLogError("FeedData/process-reaction content not reaction type")
            }
            commonReaction.comment = parentComment
            commonReaction.timestamp = xmppReaction.timestamp
            feedPost.lastUpdated = feedPost.lastUpdated.flatMap { max($0, commonReaction.timestamp) } ?? commonReaction.timestamp

            // Set status for each comment appropriately.
            switch xmppReaction.content {
            case .commentReaction:
                if commonReaction.fromUserID == userData.userId {
                    commonReaction.outgoingStatus = .sentOut
                } else {
                    // Set status to be rerequesting if necessary.
                    if xmppReaction.status == .rerequesting {
                        commonReaction.incomingStatus = .rerequesting
                    } else {
                        commonReaction.incomingStatus = .incoming
                    }
                }
            case .retracted:
                DDLogError("FeedData/process-reactions/incoming-retracted-comment [\(xmppReaction.id)]")
                commonReaction.incomingStatus = .retracted
            case .unsupported(let data):
                commonReaction.incomingStatus = .unsupported
                feedPost.rawData = data
            case .waiting:
                commonReaction.incomingStatus = .rerequesting
                if xmppReaction.status != .rerequesting {
                    DDLogError("FeedData/process-reactions/invalid content [\(xmppReaction.id)] with status: \(xmppReaction.status)")
                }
            case .text, .voiceNote, .album:
                DDLogError("FeedData/process-reactions/processing comment as reaction [\(xmppReaction.id)] with status: \(xmppReaction.status)")
            }

            reactions[commonReaction.id] = commonReaction
            newReactions.append(commonReaction)
        }

        DDLogInfo("FeedData/process-reactions/finished  \(newReactions.count) new items. \(ignoredReactionIds.count) ignored.")
        save(managedObjectContext)

        return newReactions
    }

    private func processIncomingFeedItems(_ items: [FeedElement], groupID: GroupID?, presentLocalNotifications: Bool, ack: (() -> Void)?) {
        var feedPosts = [PostData]()
        var comments = [CommentData]()
        var reactions = [CommentData]()
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
                switch comment.content {
                case .commentReaction:
                    reactions.append(comment)
                case .voiceNote, .text, .unsupported, .album, .retracted, .waiting:
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
        }

        if !contactNames.isEmpty {
            contactStore.addPushNames(contactNames)
        }
        
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            let posts = self.process(posts: feedPosts,
                                     receivedIn: groupID,
                                     using: managedObjectContext,
                                     presentLocalNotifications: presentLocalNotifications,
                                     fromExternalShare: false)
            self.generateNotifications(for: posts, using: managedObjectContext, markAsRead: !presentLocalNotifications)

            let comments = self.process(comments: comments, receivedIn: groupID, using: managedObjectContext, presentLocalNotifications: presentLocalNotifications)
            self.generateNotifications(for: comments, using: managedObjectContext, markAsRead: !presentLocalNotifications)
            
            self.process(reactions: reactions, receivedIn: groupID, using: managedObjectContext, presentLocalNotifications: presentLocalNotifications)

            if let ack = ack {
                DispatchQueue.main.async {
                    ack()
                }
            }
        }
    }

    // MARK: Notifications

    private func notificationEvent(for post: FeedPost) -> FeedActivity.Event? {
        let selfId = userData.userId

        // Dont show posts from blocked users in activity center.
        if AppContext.shared.privacySettings.blocked.userIds.contains(post.userID) {
            return nil
        }

        if post.mentions.contains(where: { $0.userID == selfId}) {
            return .mentionPost
        }

        return nil
    }

    private func notificationEvent(for comment: FeedPostComment) -> FeedActivity.Event? {
        let selfId = userData.userId

        // This would be the person who posted comment.
        let authorId = comment.userId
        guard authorId != selfId else { return nil }

        // Dont show comments from blocked users in activity center.
        if AppContext.shared.privacySettings.blocked.userIds.contains(authorId) {
            return nil
        }

        // Someone replied to your comment.
        if comment.parent != nil && comment.parent?.userId == selfId {
            return .reply
        }

        // Someone commented on your post.
        else if comment.post.userId == selfId {
            return .comment
        }

        // Someone mentioned you in a comment
        else if comment.mentions.contains(where: { $0.userID == selfId }) {
            return .mentionComment
        }

        // Someone commented on the post you've commented before.
        if comment.post.comments?.contains(where: { $0.userId == selfId }) ?? false {
            return .otherComment
        }

        // Notify group comments by contacts on group posts
        var isKnownPublisher = false
        AppContext.shared.contactStore.performOnBackgroundContextAndWait { managedObjectContext in
            isKnownPublisher = AppContext.shared.contactStore.isContactInAddressBook(userId: comment.userId, in: managedObjectContext)
        }

        let isGroupComment = comment.post.groupId != nil
        if ServerProperties.isGroupCommentNotificationsEnabled  && isGroupComment && isKnownPublisher {
            return .groupComment
        }

        // Notify comments on home feed from contacts.
        if ServerProperties.isHomeCommentNotificationsEnabled && isKnownPublisher {
            return .homeFeedComment
        }

        return nil
    }

    private func generateNotifications(for posts: [FeedPost], using managedObjectContext: NSManagedObjectContext, markAsRead: Bool = false) {
        guard !posts.isEmpty else { return }

        for post in posts {
            // Step 1. Determine if post is eligible for a notification.
            guard let event = notificationEvent(for: post) else { continue }

            // Step 2. Add notification entry to the database.
            let notification = FeedActivity(context: managedObjectContext)
            notification.commentID = nil
            notification.postID = post.id
            notification.event = event
            notification.userID = post.userId
            notification.timestamp = post.timestamp
            notification.rawText = post.rawText
            notification.mentions = post.mentions

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
            notification.read = markAsRead
            DDLogInfo("FeedData/generateNotifications  New notification [\(notification)]")

            // Step 3. Generate media preview for the notification.
            // TODO Nandini check if media preview needs to be updated for media comments
            self.generateMediaPreview(for: [ notification ], feedPost: post, using: managedObjectContext)
        }
        if managedObjectContext.hasChanges {
            self.save(managedObjectContext)
        }
    }

    private func generateNotifications(for comments: [FeedPostComment], using managedObjectContext: NSManagedObjectContext, markAsRead: Bool = false) {
        guard !comments.isEmpty else { return }

        for comment in comments {
            // Step 1. Determine if comment is eligible for a notification.
            guard let event = notificationEvent(for: comment) else { continue }

            // Step 2. Add notification entry to the database.
            let notification = FeedActivity(context: managedObjectContext)
            notification.commentID = comment.id
            notification.postID = comment.post.id
            notification.event = event
            notification.userID = comment.userId
            notification.timestamp = comment.timestamp
            notification.rawText = comment.rawText
            notification.mentions = comment.mentions

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
            notification.read = markAsRead
            DDLogInfo("FeedData/generateNotifications  New notification [\(notification)]")

            // Step 3. Generate media preview for the notification.
            self.generateMediaPreview(for: [ notification ], feedPost: comment.post, using: managedObjectContext)
        }
        if managedObjectContext.hasChanges {
            self.save(managedObjectContext)
        }
    }

    func markNotificationsAsRead(for postId: FeedPostID? = nil) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            let notifications: [FeedActivity]
            let isNotReadPredicate = NSPredicate(format: "read = %@", NSExpression(forConstantValue: false))
            // Set of reaction ids to mark as read.
            var reactionIds = [CommonReactionID]()
            if let feedPostId = postId {
                let postIdPredicate = NSPredicate(format: "postID = %@", feedPostId)
                notifications = self.coreFeedData.notifications(with: NSCompoundPredicate(andPredicateWithSubpredicates: [ isNotReadPredicate, postIdPredicate ]), in: managedObjectContext)

                // Fetch reactions.
                let comments = self.feedComments(for: feedPostId, in: managedObjectContext)
                comments.forEach { comment in
                    reactionIds.append(contentsOf: comment.sortedReactionsList.compactMap { $0.id })
                }
            } else {
                notifications = self.coreFeedData.notifications(with: isNotReadPredicate, in: managedObjectContext)
            }
            DDLogInfo("FeedData/notifications/mark-read-all Count: \(notifications.count)")
            guard !notifications.isEmpty else { return }
            notifications.forEach {
                $0.read = true
            }
            self.save(managedObjectContext)
            // remove all notifications for comments.
            UNUserNotificationCenter.current().removeDeliveredCommentNotifications(commentIds: notifications.compactMap({ $0.commentID }))
            // remove all notifications for comment reactions.
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: reactionIds)
        }
    }

    // MARK: Local Notifications

    private func isCommentEligibleForLocalNotification(_ comment: FeedPostComment) -> Bool {
        let selfId = userData.userId

        // Dont show notifications for comments from blocked users.
        if AppContext.shared.privacySettings.blocked.userIds.contains(comment.userID) {
            return false
        }

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
        let isUserMentioned = comment.mentions.contains(where: { mention in
            mention.userID == selfId
        })
        if isUserMentioned == true {
            return true
        }

        // Notify group comments by contacts on group posts
        var isKnownPublisher = false
        AppContext.shared.contactStore.performOnBackgroundContextAndWait { managedObjectContext in
            isKnownPublisher = AppContext.shared.contactStore.isContactInAddressBook(userId: comment.userId, in: managedObjectContext)
        }
        let isGroupComment = comment.post.groupId != nil
        if ServerProperties.isGroupCommentNotificationsEnabled  && isGroupComment && isKnownPublisher {
            return true
        }

        // Notify group comments on group posts after user has commented on it.
        let interestedPosts = AppContext.shared.userDefaults.value(forKey: AppContext.commentedGroupPostsKey) as? [FeedPostID] ?? []
        if Set(interestedPosts).contains(comment.post.id) {
            return true
        }

        // Notify comments on home feed from contacts.
        if ServerProperties.isHomeCommentNotificationsEnabled && isKnownPublisher {
            return true
        }

        // Do not notify about all other comments.
        return false
    }

    private func presentLocalNotifications(forComments comments: [FeedPostComment]) {
        // present local notifications when applicationState is either .background or .inactive
        guard UIApplication.shared.applicationState != .active else { return }

        let commentIDs = comments.map(\.id)
        UNUserNotificationCenter.current().getFeedCommentIdsForDeliveredNotifications { [weak self] commentIdsToFilterOut in
            guard let self = self else { return }

            self.performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
                guard let self = self else {
                    return
                }
                let comments = self.feedComments(with: Set(commentIDs), in: managedObjectContext)
                comments.filter { !commentIdsToFilterOut.contains($0.id) && self.isCommentEligibleForLocalNotification($0) }.forEach { comment in
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
                       let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: managedObjectContext) {
                        metadata.groupId = group.id
                        metadata.groupName = group.name
                    }

                    DispatchQueue.main.async {
                        // create and add a notification to the notification center.
                        NotificationRequest.createAndShow(from: metadata)
                    }
                }
            }
        }
    }

    private func presentLocalNotifications(forFeedPosts feedPosts: [FeedPost]) {
        // present local notifications when applicationState is either .background or .inactive
        guard UIApplication.shared.applicationState != .active else { return }

        // Present moment notifications if any.
        NotificationRequest.updateMomentNotifications()

        UNUserNotificationCenter.current().getFeedPostIdsForDeliveredNotifications { [weak self] postIdsToFilterOut in
            guard let self = self else { return }

            let feedPostObjectIDs = feedPosts.map(\.objectID)
            self.performSeriallyOnBackgroundContext { managedObjectContext in
                let feedPosts = feedPostObjectIDs.compactMap { managedObjectContext.object(with: $0) as? FeedPost }
                let blockedUserIDSet = Set(AppContext.shared.privacySettings.blocked.userIds)

                // We filter feedposts which are already presented, which are from blocked users (could be group feed posts)
                // We also filter out moments here since they have their own batching logic.
                let filteredFeedPosts = feedPosts.filter {
                    !postIdsToFilterOut.contains($0.id) && !blockedUserIDSet.contains($0.userId) && !$0.isMoment
                }
                filteredFeedPosts.forEach { feedPost in
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
                       let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: managedObjectContext) {
                        metadata.groupId = group.id
                        metadata.groupName = group.name
                    }

                    DispatchQueue.main.async {
                        // create and add a notification to the notification center.
                        NotificationRequest.createAndShow(from: metadata)
                    }
                }
            }
        }
    }

    private func presentLocalNotificationsForScreenshot(receipt: HalloReceipt) async {
        guard await UIApplication.shared.applicationState != .active else {
            return
        }

        if await UNUserNotificationCenter.current().getScreenshotIdsForDeliveredNotifications().contains(receipt.itemId) {
            DDLogInfo("FeedData/presentLocalNotificationsForScreenshot/already delivered notification for \(receipt.itemId)")
            return
        }

        let metadata = NotificationMetadata(contentId: receipt.itemId,
                                            contentType: .screenshot,
                                            fromId: receipt.userId,
                                            timestamp: receipt.timestamp,
                                            data: nil,
                                            messageId: nil)

        DispatchQueue.main.async {
            NotificationRequest.createAndShow(from: metadata)
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
                // TODO: it would be better to leave a tombstone and avoid using this everywhere else.
                managedObjectContext.delete($0)
            }

            // 3. Delete all notifications for this post.
            let notifications = self.coreFeedData.notifications(for: postId, in: managedObjectContext)
            notifications.forEach { managedObjectContext.delete($0)}

            // 4. Reset post data and mark post as deleted.
            feedPost.rawText = nil
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
            feedComment.rawText = ""
            feedComment.status = .retracted

            // 2. Delete comment media
            self.deleteMedia(feedPostComment: feedComment)

            // 3. Reset comment text copied over to notifications.
            let notifications = self.coreFeedData.notifications(for: feedComment.post.id, commentId: feedComment.id, in: managedObjectContext)
            notifications.forEach { (notification) in
                notification.event = .retractedComment
                notification.rawText = nil
            }

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }

            completion()
        }
    }
    
    private func processReactionRetract(_ reactionId: CommonReactionID, completion: @escaping () -> Void) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let reaction = self.commonReaction(with: reactionId, in: managedObjectContext) else {
                DDLogError("FeedData/retract-reaction/error Missing reaction. [\(reactionId)]")
                completion()
                return
            }
            guard reaction.incomingStatus != .retracted else {
                DDLogError("FeedData/retract-reaction/error Already retracted. [\(reactionId)]")
                completion()
                return
            }
            DDLogInfo("FeedData/retract-reaction [\(reactionId)]")
            guard let parentComment = reaction.comment else {
                DDLogError("FeedData/retract-reaction/no parent comment")
                return
            }
            if let reactionToDelete = parentComment.sortedReactionsList.filter({ $0.id == reaction.id }).last {
                managedObjectContext.delete(reactionToDelete)
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
                performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                    guard let self = self else { return }
                    if self.commonReaction(with: commentID, in: managedObjectContext) != nil {
                        self.processReactionRetract(commentID) {
                            processingGroup.leave()
                        }
                    } else {
                        self.processCommentRetract(commentID) {
                            processingGroup.leave()
                        }
                    }
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
                if let context = feedPost.managedObjectContext {
                    self.save(context)
                }

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
        if let context = comment.managedObjectContext {
            save(context)
        }

        // Request to retract.
        service.retractComment(id: comment.id, postID: comment.post.id, in: comment.post.groupId) { result in
            switch result {
            case .success:
                self.processCommentRetract(commentId) {}

            case .failure(_):
                // TODO: Retry retractions on next connection
                self.updateFeedPostComment(with: commentId) { (comment) in
                    comment.status = .sent
                }
            }
        }
    }
    
    func retract(reaction: CommonReaction) {
        DDLogInfo("FeedData/retract-reaction/reactionID: [\(reaction.id)]")
        guard let parentComment = reaction.comment else {
            DDLogError("FeedData/retract-reaction/no parent comment")
            return
        }
        let reactionId = reaction.id

        // Mark reaction as "being retracted".
        reaction.outgoingStatus = .retracting
        if let context = reaction.managedObjectContext {
            save(context)
        }

        // Request to retract.
        service.retractComment(id: reaction.id, postID: parentComment.post.id, in: parentComment.post.groupId) { result in
            switch result {
            case .success:
                self.processReactionRetract(reactionId) {}
            case .failure(_):
                // TODO: Retry retractions on next connection
                DDLogError("FeedData/retract-reaction/failed to retract reaction [\(reactionId)]")
                self.updateReaction(with: reactionId) { (reaction) in
                    reaction.outgoingStatus = .sentOut
                }
            }
        }
    }

    // MARK: Read Receipts

    private func resendPendingReadReceipts() {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
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
        guard !feedPost.fromExternalShare else { return }

        let postId = feedPost.id
        let postStatus = feedPost.status
        updateFeedPost(with: postId) { [weak self] (post) in
            guard let self = self else { return }
            // Check status again in case one of these blocks was already queued
            guard post.status == .incoming || postStatus == .rerequesting else { return }
            self.internalSendSeenReceipt(for: post)
            self.checkForUnreadFeed()
        }
    }

    func sendScreenshotReceipt(for feedPost: FeedPost) {
        guard feedPost.isMoment, feedPost.userId != userData.userId else {
            DDLogError("FeedData/sendScreenshotReceipt/tried to send a screenshot receipt for a normal feed post")
            return
        }

        DDLogInfo("FeedData/sendScreenshotReceipt postID: [\(feedPost.id)]")
        service.sendReceipt(itemID: feedPost.id,
                            thread: .feed,
                              type: .screenshot,
                        fromUserID: userData.userId,
                          toUserID: feedPost.userId)
    }

    func sendSavedReceipt(for feedPost: FeedPost) {
        guard feedPost.userId != userData.userId else {
            return
        }

        DDLogInfo("FeedData/sendSavedReceipt postID: [\(feedPost.id)]")
        service.sendReceipt(itemID: feedPost.id,
                            thread: .feed,
                              type: .saved,
                        fromUserID: userData.userId,
                          toUserID: feedPost.userId)
    }

    func seenReceipts(for feedPost: FeedPost) -> [FeedPostReceipt] {
        guard let seenReceipts = feedPost.info?.receipts else {
            return []
        }

        var receipts = [FeedPostReceipt]()

        contactStore.performOnBackgroundContextAndWait { managedObjectContext in
            let contacts = contactStore.contacts(withUserIds: Array(seenReceipts.keys), in: managedObjectContext)
            let contactsMap = contacts.reduce(into: [UserID: ABContact]()) { (map, contact) in
                if let userID = contact.userId {
                    map[userID] = contact
                }
            }

            for (userId, receipt) in seenReceipts {
                guard let seenDate = receipt.seenDate else { continue }

                var contactName: String?, phoneNumber: String?
                if let contact = contactsMap[userId] {
                    contactName = contact.fullName
                    phoneNumber = contact.phoneNumber?.formattedPhoneNumber
                }
                if contactName == nil {
                    contactName = contactStore.fullName(for: userId, in: managedObjectContext)
                }

                receipts.append(FeedPostReceipt(userId: userId,
                                                  type: .seen,
                                           contactName: contactName!,
                                           phoneNumber: phoneNumber,
                                             timestamp: seenDate,
                                        savedTimestamp: receipt.savedDate,
                                   screenshotTimestamp: receipt.screenshotDate))
            }
            receipts.sort(by: { $0.timestamp > $1.timestamp })
        }

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
        if let cachedMedia = cachedMedia(for: post.id) {
            return cachedMedia
        } else {
            let media = (post.media ?? []).sorted(by: { $0.order < $1.order }).map{ FeedMedia($0) }
            setCachedMedia(media, for: post.id)
            return media
        }
    }

    func media(postID: FeedPostID, in managedObjectContext: NSManagedObjectContext) -> [FeedMedia]? {
        if let cachedMedia = cachedMedia(for: postID) {
            return cachedMedia
        } else if let post = MainAppContext.shared.feedData.feedPost(with: postID, in: managedObjectContext) {
            return media(for: post)
        } else {
            return nil
        }
    }
    
    func media(for comment: FeedPostComment) -> [FeedMedia] {
        if let cachedMedia = cachedMedia(for: comment.id) {
            return cachedMedia
        } else {
            let media = (comment.media ?? []).sorted(by: { $0.order < $1.order }).map{ FeedMedia($0) }
            setCachedMedia(media, for: comment.id)
            return media
        }
    }

    func media(commentID: FeedPostCommentID, in managedObjectContext: NSManagedObjectContext) -> [FeedMedia]? {
        if let cachedMedia = cachedMedia(for: commentID) {
            return cachedMedia
        } else if let comment = MainAppContext.shared.feedData.feedComment(with: commentID, in: managedObjectContext) {
            let media = (comment.media ?? []).sorted(by: { $0.order < $1.order }).map{ FeedMedia($0) }
            setCachedMedia(media, for: commentID)
            return media
        } else {
            return nil
        }
    }

    func media(feedLinkPreviewID: FeedLinkPreviewID, in managedObjectContext: NSManagedObjectContext) -> [FeedMedia]? {
        if let cachedMedia = cachedMedia(for: feedLinkPreviewID) {
            return cachedMedia
        } else if let linkPreview = MainAppContext.shared.feedData.feedLinkPreview(with: feedLinkPreviewID, in: managedObjectContext) {
            let media = (linkPreview.media ?? []).sorted(by: { $0.order < $1.order }).map{ FeedMedia($0) }
            setCachedMedia(media, for: feedLinkPreviewID)
            return media
        } else {
            return nil
        }
    }

    func loadImages(postID: FeedPostID) {
        mainDataStore.performSeriallyOnBackgroundContext { managedObjectContext in
            guard let media = self.media(postID: postID, in: managedObjectContext) else { return }
            media.forEach { $0.loadImage() }
        }
    }
    
    func loadImages(commentID: FeedPostCommentID) {
        mainDataStore.performSeriallyOnBackgroundContext { managedObjectContext in
            guard let media = self.media(commentID: commentID, in: managedObjectContext) else { return }
            media.forEach { $0.loadImage() }
        }
    }

    func loadImages(feedLinkPreviewID: FeedLinkPreviewID) {
        mainDataStore.performSeriallyOnBackgroundContext { managedObjectContext in
            guard let media = self.media(feedLinkPreviewID: feedLinkPreviewID, in: managedObjectContext) else { return }
            media.forEach { $0.loadImage() }
        }
    }

    // TODO: Refactor FeedMedia to allow unloading images from memory (for now we can't clear cache)
    private var cachedMedia1 = [FeedPostID: [FeedMedia]]()
    private var cachedMediaQueue = DispatchQueue(label: "CachedMediaAccessQueue")

    // Thread-safe Accessors

    private func cachedMedia(for id: String) -> [FeedMedia]? {
        var media: [FeedMedia]?
        cachedMediaQueue.sync {
            media = cachedMedia1[id]
        }
        return media
    }

    private func setCachedMedia(_ media: [FeedMedia]?, for id: String) {
        cachedMediaQueue.sync {
            cachedMedia1[id] = media
        }
    }

    func downloadTask(for mediaItem: FeedMedia, using managedObjectContext: NSManagedObjectContext) -> FeedDownloadManager.Task? {
        switch mediaItem.feedElementId {
        case .post(let postId):
            guard let feedPost = feedPost(with: postId, in: managedObjectContext) else { return nil }
            guard let feedPostMedia = feedPost.media?.first(where: { $0.order == mediaItem.order }) else { return nil }
            return downloadManager.currentTask(for: feedPostMedia)
        case .comment(let commentId):
            guard let feedComment = feedComment(with: commentId, in: managedObjectContext) else { return nil }
            guard let feedPostCommentMedia = feedComment.media?.first(where: { $0.order == mediaItem.order }) else { return nil }
            return downloadManager.currentTask(for: feedPostCommentMedia)
        case .linkPreview(let linkPreviewId):
            guard let feedLinkPreview = feedLinkPreview(with: linkPreviewId, in: managedObjectContext) else { return nil }
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
        mainDataStore.performSeriallyOnBackgroundContext { managedObjectContext in
            var pendingPostIds: Set<FeedPostID> = []
            var pendingCommentIds: Set<FeedPostCommentID> = []

            // Iterate through all the suspendedMediaObjectIds and download media for those posts.
            self.downloadManager.suspendedMediaObjectIds.forEach { feedMediaObjectId in
                // Fetch FeedPostMedia
                guard let feedPostMedia = try? managedObjectContext.existingObject(with: feedMediaObjectId) as? CommonMedia else {
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

            self.downloadManager.suspendedMediaObjectIds.removeAll()
            // Download media for all these posts and comments
            self.downloadMedia(in: self.feedPosts(with: pendingPostIds, in: managedObjectContext))
            self.downloadMedia(in: self.feedComments(with: pendingCommentIds, in: managedObjectContext))
        }
    }

    func downloadMediaInMoments() {
        let moments = fetchAllIncomingMoments()
        downloadMedia(in: moments)
    }

    func downloadMedia(in feedPosts: [FeedPost]) {
        guard !feedPosts.isEmpty else { return }

        let feedPostObjectIds = feedPosts.map(\.objectID)
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }
            let feedPosts = feedPostObjectIds.compactMap { try? managedObjectContext.existingObject(with: $0) as? FeedPost }
            feedPosts.forEach { feedPost in
                // Download media items.
                self.downloadFeedMedia(mediaItems: feedPost.media, contentID: feedPost.id)
                // Download link previews if any.
                feedPost.linkPreviews?.forEach { linkPreview in
                    self.downloadFeedMedia(mediaItems: linkPreview.media, contentID: linkPreview.id)
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
            feedPostComments.forEach { feedComment in
                // Download media items.
                self.downloadFeedMedia(mediaItems: feedComment.media, contentID: feedComment.id)
                // Download link previews if any.
                feedComment.linkPreviews?.forEach { linkPreview in
                    self.downloadFeedMedia(mediaItems: linkPreview.media, contentID: linkPreview.id)
                }
            }
        }
    }

    func downloadFeedMedia(mediaItems: Set<CommonMedia>?, contentID: String) {
        guard let mediaItems = mediaItems,
              !mediaItems.isEmpty else {
            return
        }
        DDLogInfo("FeedData/downloadFeedMedia/contentID: \(contentID)")

        var mediaIndexToReload = [Int]()
        var downloadStarted = false
        let sortedMedia = mediaItems.sorted(by: { $0.order < $1.order })
        for mediaItem in sortedMedia {

            let order = mediaItem.order
            DDLogInfo("FeedData/downloadFeedMedia/contentID: \(contentID)/order: \(order)/status: \(mediaItem.status)")
            let mediaDownloadGroup = DispatchGroup()
            var startTime: Date?
            var photosDownloaded = 0
            var videosDownloaded = 0
            var audiosDownloaded = 0
            var totalDownloadSize = 0

            guard mediaItem.url != nil else { continue }
            guard [.none, .downloading, .downloadError].contains(mediaItem.status) else { continue }

            let (taskAdded, task) = self.downloadManager.downloadMedia(for: mediaItem)
            if taskAdded {
                switch mediaItem.type {
                case .image: photosDownloaded += 1
                case .video: videosDownloaded += 1
                case .audio: audiosDownloaded += 1
                }
                if startTime == nil {
                    startTime = Date()
                    DDLogInfo("FeedData/downloadFeedMedia/contentID: \(contentID)/order: \(order)/starting")
                }
                mediaDownloadGroup.enter()
                var isDownloadInProgress = true
                let index = Int(mediaItem.order)
                self.cancellableSet.insert(task.downloadProgress.sink() { progress in
                    if isDownloadInProgress && progress == 1 {
                        totalDownloadSize += task.fileSize ?? 0
                        mediaDownloadGroup.leave()
                        isDownloadInProgress = false
                    }
                    mediaIndexToReload.append(index)
                })
                downloadStarted = true
                task.feedMediaObjectId = mediaItem.objectID
                mediaItem.status = .downloading
                mediaItem.numTries += 1
            }

            mediaDownloadGroup.notify(queue: .main) {
                guard photosDownloaded > 0 || videosDownloaded > 0 || audiosDownloaded > 0 else { return }
                guard let startTime = startTime else {
                    DDLogError("FeedData/downloadFeedMedia/contentID: \(contentID)/error start time not set")
                    return
                }
                let duration = Date().timeIntervalSince(startTime)
                DDLogInfo("FeedData/downloadFeedMedia/contentID: \(contentID)/finished [photos: \(photosDownloaded)] [videos: \(videosDownloaded)] [audios: \(audiosDownloaded)] [t: \(duration)] [bytes: \(totalDownloadSize)]")
                AppContext.shared.eventMonitor.observe(
                    .mediaDownload(
                        postID: contentID,
                        duration: duration,
                        numPhotos: photosDownloaded,
                        numVideos: videosDownloaded,
                        totalSize: totalDownloadSize))
            }
        }

        // Using `downloadStarted` to prevent any recursive saves.
        if downloadStarted,
           let context = mediaItems.first?.managedObjectContext,
           context.hasChanges {
            DDLogInfo("FeedData/downloadFeedMedia/contentID: \(contentID)/downloadStarted: \(downloadStarted)")
            self.save(context)

            if (mediaItems.first?.post) != nil {
                DispatchQueue.main.async {
                    mediaIndexToReload.forEach{ order in
                        self.reloadMedia(feedPostId: contentID, order: order)
                    }
                }
            } else if (mediaItems.first?.comment) != nil {
                DispatchQueue.main.async {
                    mediaIndexToReload.forEach{ order in
                        self.reloadMedia(feedCommentID: contentID, order: order)
                    }
                }
            } else if (mediaItems.first?.linkPreview) != nil {
                DispatchQueue.main.async {
                    mediaIndexToReload.forEach{ order in
                        self.reloadMedia(feedLinkPreviewID: contentID, order: order)
                    }
                }
            }
        }
    }

    func reloadMedia(feedPostId: FeedPostID, order: Int) {
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            DDLogInfo("FeedData/reloadMedia/postId:\(feedPostId), order/\(order)")
            guard let self = self,
                  let coreDataPost = self.feedPost(with: feedPostId, in: managedObjectContext),
                  let coreDataMedia = coreDataPost.media?.first(where: { $0.order == order }),
                  let cachedMedia = self.media(postID: feedPostId, in: managedObjectContext)?.first(where: { $0.order == order }) else
            {
                return
            }
            DDLogInfo("FeedData/reloadMedia/postID: cache reload")
            cachedMedia.reload(from: coreDataMedia)
        }
    }

    func reloadMedia(feedCommentID: FeedPostCommentID, order: Int) {
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            DDLogInfo("FeedData/reloadMedia/commentId:\(feedCommentID), order/\(order)")
            guard let self = self,
                  let coreDataComment = self.feedComment(with: feedCommentID, in: managedObjectContext),
                  let coreDataMedia = coreDataComment.media?.first(where: { $0.order == order }),
                  let cachedMedia = self.media(commentID: feedCommentID, in: managedObjectContext)?.first(where: { $0.order == order }) else
            {
                DDLogInfo("FeedData/reloadMedia/commentId: \(feedCommentID) not reloading media cache")
                return
            }
            DDLogInfo("FeedData/reloadMedia/commentId: \(feedCommentID) cache reload")
            cachedMedia.reload(from: coreDataMedia)
        }
    }

    func reloadMedia(feedLinkPreviewID: FeedLinkPreviewID, order: Int) {
        DDLogInfo("FeedData/reloadMedia/feedLinkPreviewID:\(feedLinkPreviewID), order/\(order)")

        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self,
                  let feedLinkPreview = self.feedLinkPreview(with: feedLinkPreviewID, in: managedObjectContext),
                  let coreDataMedia = feedLinkPreview.media?.first(where: { $0.order == order }),
                  let cachedMedia = self.media(feedLinkPreviewID: feedLinkPreviewID, in: managedObjectContext)?.first(where: { $0.order == order }) else
            {
                DDLogInfo("FeedData/reloadMedia/feedLinkPreviewID: \(feedLinkPreviewID) not reloading media cache")
                return
            }
            DDLogInfo("FeedData/reloadMedia/feedLinkPreviewID: \(feedLinkPreviewID) cache reload")

            cachedMedia.reload(from: coreDataMedia)
        }
    }

    func feedDownloadManager(_ manager: FeedDownloadManager, didFinishTask task: FeedDownloadManager.Task) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            // Step 1: Update FeedPostMedia
            guard let objectID = task.feedMediaObjectId, let feedPostMedia = try? managedObjectContext.existingObject(with: objectID) as? CommonMedia else {
                DDLogError("FeedData/download-task/\(task.id)/error  Missing CommonMedia  taskId=[\(task.id)]  objectId=[\(task.feedMediaObjectId?.uriRepresentation().absoluteString ?? "nil")))]")
                return
            }

            guard feedPostMedia.relativeFilePath == nil else {
                DDLogError("FeedData/download-task/\(task.id)/error File already exists media=[\(feedPostMedia)]")
                self.refreshUIwithMedia(feedMedia: feedPostMedia)
                return
            }

            if let error = task.error {
                DDLogError("FeedData/download-task/\(task.id)/error [\(task.error!)]")
                feedPostMedia.status = .downloadError

                // TODO: Do an exponential backoff on the client for 1 day and then show a manual retry button for the user.
                // Mark as permanent failure if we encounter hashMismatch or MACMismatch.
                switch error {
                case .macMismatch, .hashMismatch, .decryptionFailed:
                    DDLogInfo("FeedData/download-task/\(task.id)/error [\(task.error!) - fail permanently]")
                    feedPostMedia.status = .downloadFailure
                    AppContext.shared.errorLogger?.logError(error)
                default:
                    break
                }
            } else {
                DDLogInfo("FeedData/download-task/\(task.id)/complete [\(task.decryptedFilePath!)]")
                feedPostMedia.status = task.isPartialChunkedDownload ? .downloadedPartial : .downloaded
                feedPostMedia.relativeFilePath = task.decryptedFilePath
                feedPostMedia.mediaDirectory = .commonMedia
                if task.isPartialChunkedDownload, let chunkSet = task.downloadedChunkSet {
                    DDLogDebug("FeedData/download-task/\(task.id)/feedDownloadManager chunkSet=[\(chunkSet)]")
                    feedPostMedia.chunkSet = chunkSet.data
                }


            }

            self.save(managedObjectContext)

            // Step 2: Update media preview for all notifications for the given post.
            if [.downloaded, .downloadedPartial].contains(feedPostMedia.status) && feedPostMedia.order == 0 {
                self.updateNotificationMediaPreview(with: feedPostMedia, using: managedObjectContext)
                if managedObjectContext.hasChanges {
                    self.save(managedObjectContext)
                }
            }

            // Step 3: Notify UI about finished download.
            self.refreshUIwithMedia(feedMedia: feedPostMedia)

            // Step 4: Update upload data to avoid duplicate uploads
            // TODO Nandini : check this for comment media
            if let fileUrl = feedPostMedia.mediaURL, let downloadUrl = feedPostMedia.url {
                MainAppContext.shared.mediaHashStore.update(url: fileUrl, blobVersion: feedPostMedia.blobVersion, key: feedPostMedia.key, sha256: feedPostMedia.sha256, downloadURL: downloadUrl)
            }
        }
    }

    private func refreshUIwithMedia(feedMedia: CommonMedia) {
        if let  feedPost = feedMedia.post {
            let feedPostId = feedPost.id
            let mediaOrder = Int(feedMedia.order)
            DispatchQueue.main.async {
                self.reloadMedia(feedPostId: feedPostId, order: mediaOrder)
            }
        } else if let  feedComment = feedMedia.comment {
            let feedCommentId = feedComment.id
            let mediaOrder = Int(feedMedia.order)
            DispatchQueue.main.async {
                self.reloadMedia(feedCommentID: feedCommentId, order: mediaOrder)
            }
        } else if let feedLinkPreview = feedMedia.linkPreview {
            let feedLinkPreviewId = feedLinkPreview.id
            let mediaOrder = Int(feedMedia.order)
            DispatchQueue.main.async {
                self.reloadMedia(feedLinkPreviewID: feedLinkPreviewId, order: mediaOrder)
            }
        }
    }

    public func markStreamingMediaAsDownloaded(feedPostID: FeedPostID, order: Int16) {
        mainDataStore.saveSeriallyOnBackgroundContext({ [weak self] managedObjectContext in
            guard let self = self else { return }
            guard let feedPost = self.feedPost(with: feedPostID, in: managedObjectContext),
                  let feedPostMedia = feedPost.media?.first(where: { $0.order == order }) else {
                DDLogError("FeedData/markStreamingMediaAsDownloaded/error No media with feedPostID=[\(feedPostID)] order=[\(order)]")
                return
            }
            feedPostMedia.status = .downloaded
        }, completion: { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                DispatchQueue.main.async {
                    self.reloadMedia(feedPostId: feedPostID, order: Int(order))
                }
            case .failure(let error):
                DDLogError("FeedData/markStreamingMediaAsDownloaded/error Could not save context \(error)")
            }
        })
    }

    public func updateStreamingMediaChunks(feedPostID: FeedPostID, order: Int16, chunkSetData: Data) {
        mainDataStore.saveSeriallyOnBackgroundContext{ [weak self] managedObjectContext in
            guard let self = self else { return }
            guard let feedPost = self.feedPost(with: feedPostID, in: managedObjectContext),
                  let feedPostMedia = feedPost.media?.first(where: { $0.order == order }) else {
                DDLogError("FeedData/updateStreamingMediaChunks/error No media with feedPostID=[\(feedPostID)] order=[\(order)]")
                return
            }
            feedPostMedia.chunkSet = chunkSetData
        }
    }

    private func updateNotificationMediaPreview(with postMedia: CommonMedia, using managedObjectContext: NSManagedObjectContext) {
        guard postMedia.relativeFilePath != nil else { return }
        if let feedPost = postMedia.post {
            let feedPostId = feedPost.id

            // Fetch all associated notifications.
            let fetchRequest: NSFetchRequest<FeedActivity> = FeedActivity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "postID == %@", feedPostId)
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

    private func generateMediaPreview(for notifications: [FeedActivity], feedPost: FeedPost, using managedObjectContext: NSManagedObjectContext) {
        guard let postMedia = feedPost.orderedMedia.first as? CommonMedia else { return }
        guard let mediaURL = postMedia.mediaURL else { return }

        DDLogInfo("FeedData/generateMediaPreview/feedPost \(feedPost.id), mediaType: \(postMedia.type)")
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

    private func updateMediaPreview(for notifications: [FeedActivity], usingImageAt url: URL) {
        guard let image = UIImage(contentsOfFile: url.path) else {
            DDLogError("FeedData/notification/preview/error  Failed to load image at [\(url)]")
            return
        }
        updateMediaPreview(for: notifications, using: image)
    }

    private func updateMediaPreview(for notifications: [FeedActivity], using image: UIImage) {
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

    func post(text: MentionText, media: [PendingMedia], linkPreviewData: LinkPreviewData?, linkPreviewMedia : PendingMedia?, to destination: ShareDestination, momentContext: MomentContext? = nil) {
        if ServerProperties.enableNewMediaUploader {
            coreFeedData.post(text: text, media: media, linkPreviewData: linkPreviewData, linkPreviewMedia: linkPreviewMedia, to: destination, momentContext: momentContext)
            return
        }

        let managedObjectContext = viewContext
        let postId: FeedPostID = PacketID.generate()

        // Create and save new FeedPost object.
        DDLogDebug("FeedData/new-post/create [\(postId)]")

        let timestamp = Date()

        let feedPost = FeedPost(context: managedObjectContext)
        feedPost.id = postId
        feedPost.userId = AppContext.shared.userData.userId
        if case .group(let groupID, _) = destination {
            feedPost.groupId = groupID
            if let group = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: managedObjectContext) {
                feedPost.expiration = group.postExpirationDate(from: timestamp)
            } else {
                DDLogError("FeedData/createTombstones/groupID: \(groupID) not found, setting default expiration...")
                feedPost.expiration = timestamp.addingTimeInterval(ServerProperties.enableGroupExpiry ? TimeInterval(Int64.thirtyDays) : FeedPost.defaultExpiration)
            }
        } else {
            feedPost.expiration = timestamp.addingTimeInterval(FeedPost.defaultExpiration)
        }
        feedPost.rawText = text.collapsedText
        feedPost.status = .sending
        feedPost.timestamp = timestamp
        feedPost.lastUpdated = timestamp

        switch momentContext {
        case .unlock(let unlockedPost):
            feedPost.unlockedMomentUserID = unlockedPost.userId
            fallthrough
        case .normal:
            feedPost.isMoment = true
        case .none:
            feedPost.isMoment = false
        }

        // Add mentions
        feedPost.mentions = text.mentionsArray.map {
            return MentionData(
                index: $0.index,
                userID: $0.userID,
                name: self.contactStore.pushNames[$0.userID] ?? $0.name)
        }
        feedPost.mentions.filter { $0.name == "" }.forEach {
            DDLogError("FeedData/new-post/mention/\($0.userID) missing push name")
        }

        let shouldStreamFeedVideo = ServerProperties.streamingSendingEnabled || ChunkedMediaTestConstants.STREAMING_FEED_GROUP_IDS.contains(feedPost.groupId ?? "")

        // Add post media.
        for (index, mediaItem) in media.enumerated() {
            DDLogDebug("FeedData/new-post/add-media [\(mediaItem.fileURL!)]")
            let feedMedia = CommonMedia(context: managedObjectContext)
            feedMedia.id = "\(feedPost.id)-\(index)"
            feedMedia.type = mediaItem.type
            feedMedia.status = .readyToUpload
            feedMedia.url = mediaItem.url
            feedMedia.size = mediaItem.size!
            feedMedia.key = ""
            feedMedia.sha256 = ""
            feedMedia.order = Int16(index)
            feedMedia.blobVersion = (mediaItem.type == .video && shouldStreamFeedVideo) ? .chunked : .default
            feedMedia.post = feedPost
            feedMedia.mediaDirectory = .commonMedia

            if let url = mediaItem.fileURL {
                ImageServer.shared.attach(for: url, id: postId, index: index)
            }

            // Copying depends on all data fields being set, so do this last.
            do {
                try self.downloadManager.copyMedia(from: mediaItem, to: feedMedia)
            }
            catch {
                DDLogError("FeedData/new-post/copy-media/error [\(error)]")
            }
        }

        // Add feed link preview if any
        var linkPreview: CommonLinkPreview?
        if let linkPreviewData = linkPreviewData {
            linkPreview = CommonLinkPreview(context: managedObjectContext)
            linkPreview?.id = PacketID.generate()
            linkPreview?.url = linkPreviewData.url
            linkPreview?.title = linkPreviewData.title
            linkPreview?.desc = linkPreviewData.description
            // Set preview image if present
            if let linkPreviewMedia = linkPreviewMedia {
                let previewMedia = CommonMedia(context: managedObjectContext)
                previewMedia.id = "\(linkPreview?.id ?? UUID().uuidString)-0"
                previewMedia.type = linkPreviewMedia.type
                previewMedia.status = .readyToUpload
                previewMedia.url = linkPreviewMedia.url
                previewMedia.size = linkPreviewMedia.size!
                previewMedia.key = ""
                previewMedia.sha256 = ""
                previewMedia.order = 0
                previewMedia.linkPreview = linkPreview
                previewMedia.mediaDirectory = .commonMedia

                // Copying depends on all data fields being set, so do this last.
                do {
                    try self.downloadManager.copyMedia(from: linkPreviewMedia, to: previewMedia)
                }
                catch {
                    DDLogError("FeedData/new-post/copy-likePreviewmedia/error [\(error)]")
                }
            }
            linkPreview?.post = feedPost
        }

        switch destination {
        case .feed(let privacyListType):
            guard let postAudience = try? MainAppContext.shared.privacySettings.feedAudience(for: privacyListType) else { return }

            let feedPostInfo = ContentPublishInfo(context: managedObjectContext)
            let receipts = postAudience.userIds.reduce(into: [UserID : Receipt]()) { (receipts, userId) in
                receipts[userId] = Receipt()
            }
            feedPostInfo.receipts = receipts
            feedPostInfo.audienceType = postAudience.audienceType
            feedPost.info = feedPostInfo
        case .group(let groupId, _):
            guard let chatGroup = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: managedObjectContext) else {
                return
            }
            let feedPostInfo = ContentPublishInfo(context: managedObjectContext)
            var receipts = [UserID : Receipt]()
            chatGroup.members?.forEach({ member in
                receipts[member.userID] = Receipt()
            })
            feedPostInfo.receipts = receipts
            feedPostInfo.audienceType = .group
            feedPost.info = feedPostInfo
        case .contact:
            // ChatData is responsible for this case
            break
        }

        self.save(managedObjectContext)

        self.beginMediaUploadAndSend(feedPost: feedPost)

        if feedPost.groupId != nil {
            self.didSendGroupFeedPost.send(feedPost)
        }
    }

    func post(comment: MentionText, media: [PendingMedia], linkPreviewData: LinkPreviewData?, linkPreviewMedia : PendingMedia?, to feedPostID: FeedPostID, replyingTo parentCommentId: FeedPostCommentID? = nil) {
        performSeriallyOnBackgroundContext { managedObjectContext in
            let commentId: FeedPostCommentID = PacketID.generate()

            // Create and save FeedPostComment
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

            DDLogDebug("FeedData/new-comment/create id=[\(commentId)]  postId=[\(feedPost.id)]")
            let feedComment = NSEntityDescription.insertNewObject(forEntityName: FeedPostComment.entity().name!, into: managedObjectContext) as! FeedPostComment
            feedComment.id = commentId
            feedComment.userId = AppContext.shared.userData.userId
            feedComment.rawText = comment.collapsedText
            feedComment.parent = parentComment
            feedComment.post = feedPost
            feedComment.status = .sending
            feedComment.timestamp = Date()
            feedPost.lastUpdated = feedPost.lastUpdated.flatMap { max($0, feedComment.timestamp) } ?? feedComment.timestamp
            feedComment.mentions = comment.mentions.map { (index, user) in
                return MentionData(
                    index: index,
                    userID: user.userID,
                    name: self.contactStore.pushNames[user.userID] ?? user.pushName ?? "")
            }
            feedPost.mentions.filter { $0.name == "" }.forEach {
                DDLogError("FeedData/new-comment/mention/\($0.userID) missing push name")
            }


            // Add post comment media.
            for (index, mediaItem) in media.enumerated() {
                DDLogDebug("FeedData/new-comment/add-media [\(mediaItem.fileURL!)]")

                let feedMedia = CommonMedia(context: managedObjectContext)
                feedMedia.id = "\(feedComment.id)-\(index)"
                feedMedia.type = mediaItem.type
                feedMedia.status = .readyToUpload
                feedMedia.url = mediaItem.url
                feedMedia.size = mediaItem.size!
                feedMedia.key = ""
                feedMedia.sha256 = ""
                feedMedia.order = Int16(index)
                feedMedia.comment = feedComment
                feedMedia.mediaDirectory = .commonMedia

                // Copying depends on all data fields being set, so do this last.
                do {
                    try self.downloadManager.copyMedia(from: mediaItem, to: feedMedia)
                }
                catch {
                    DDLogError("FeedData/new-comment/copy-media/error [\(error)]")
                }
            }

            // Add feed link preview if any
            var linkPreview: CommonLinkPreview?
            if let linkPreviewData = linkPreviewData {
                linkPreview = CommonLinkPreview(context: managedObjectContext)
                linkPreview?.id = PacketID.generate()
                linkPreview?.url = linkPreviewData.url
                linkPreview?.title = linkPreviewData.title
                linkPreview?.desc = linkPreviewData.description
                // Set preview image if present
                if let linkPreviewMedia = linkPreviewMedia {
                    let previewMedia = CommonMedia(context: managedObjectContext)
                    previewMedia.id = "\(linkPreview?.id ?? UUID().uuidString)-0"
                    previewMedia.type = linkPreviewMedia.type
                    previewMedia.status = .readyToUpload
                    previewMedia.url = linkPreviewMedia.url
                    previewMedia.size = linkPreviewMedia.size!
                    previewMedia.key = ""
                    previewMedia.sha256 = ""
                    previewMedia.order = 0
                    previewMedia.linkPreview = linkPreview
                    previewMedia.mediaDirectory = .commonMedia

                    // Copying depends on all data fields being set, so do this last.
                    do {
                        try self.downloadManager.copyMedia(from: linkPreviewMedia, to: previewMedia)
                    }
                    catch {
                        DDLogError("FeedData/new-comment/copy-likePreviewmedia/error [\(error)]")
                    }
                }
                linkPreview?.comment = feedComment
            }

            self.save(managedObjectContext)

            if let linkPreview = linkPreview {
                // upload link preview media followed by comment media and send over the wire
                self.uploadMediaAndSend(feedLinkPreview: linkPreview)
            } else {
                // upload comment media if any and send data over the wire.
                self.uploadMediaAndSend(feedComment: feedComment)
            }
        }
    }
    
    func sendReaction(reaction: String, replyingTo parentCommentId: FeedPostCommentID) {
        performSeriallyOnBackgroundContext { managedObjectContext in
            let reactionId: CommonReactionID = PacketID.generate()

            // Create and save CommonReaction
            var parentComment: FeedPostComment?
            parentComment = self.feedComment(with: parentCommentId, in: managedObjectContext)
            guard let parentComment = parentComment else {
                DDLogError("FeedData/new-reaction/error  Missing parent comment with id=[\(parentCommentId)]")
                return
            }

            DDLogDebug("FeedData/new-reaction/create id=[\(reactionId)]")
            let commonReaction = CommonReaction(context: managedObjectContext)
            commonReaction.id = reactionId
            commonReaction.fromUserID = self.userData.userId
            commonReaction.emoji = reaction
            commonReaction.comment = parentComment
            commonReaction.incomingStatus = .none
            commonReaction.outgoingStatus = .pending
            commonReaction.timestamp = Date()

            self.save(managedObjectContext)

            self.send(reaction: commonReaction)
        }
    }

    func retryPosting(postId: FeedPostID) {
        performSeriallyOnBackgroundContext { managedObjectContext in
            DDLogInfo("FeedData/retryPosting/postId: \(postId)")

            guard let feedPost = self.feedPost(with: postId, in: managedObjectContext) else { return }
            guard feedPost.status == .sendError else { return }

            // Change status to "sending" and start sending / uploading.
            feedPost.status = .sending
            self.save(managedObjectContext)
            self.beginMediaUploadAndSend(feedPost: feedPost)
        }
    }

    func resend(commentWithId commentId: FeedPostCommentID) {
        performSeriallyOnBackgroundContext { managedObjectContext in
            DDLogInfo("FeedData/resend/commentWithId: \(commentId)")

            guard let comment = self.feedComment(with: commentId, in: managedObjectContext) else { return }
            guard comment.status == .sendError else { return }

            // Change status to "sending" and send.
            comment.status = .sending
            self.save(managedObjectContext)

            self.send(comment: comment)
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
                DDLogInfo("FeedData/send-comment/commentID: \(commentId) success")
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
                DDLogError("FeedData/send-comment/commentID: \(commentId) error \(error)")
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
    
    private func send(reaction: CommonReaction) {
        DDLogInfo("FeedData/send-reaction/reactionID: \(reaction.id)")
        guard let parentComment = reaction.comment else {
            DDLogError("FeedData/send-reaction/no parent comment")
            return
        }
        let reactionId = reaction.id
        let groupId = parentComment.post.groupId
        let postId = parentComment.post.id

        guard !contentInFlight.contains(reactionId) else {
            DDLogInfo("FeedData/send-reaction/reactionID: \(parentComment.id) already-in-flight")
            return
        }
        DDLogInfo("FeedData/send-reaction/reactionID: \(parentComment.id) begin")
        contentInFlight.insert(reactionId)
        
        var content: CommentContent
        content = .commentReaction(reaction.emoji)
        let commentData = CommentData(id: reaction.id, userId: reaction.fromUserID, timestamp: reaction.timestamp, feedPostId: parentComment.post.id, parentId: parentComment.id, content: content, status: FeedItemStatus.sent)
        
        service.publishComment(commentData, groupId: groupId) { result in
            switch result {
            case .success(let timestamp):
                DDLogInfo("FeedData/send-reaction/reactionID: \(reactionId) success")
                self.contentInFlight.remove(reactionId)
                self.updateReaction(with: reactionId) { (reaction) in
                    reaction.timestamp = timestamp
                    reaction.outgoingStatus = .sentOut

                    MainAppContext.shared.endBackgroundTask(reaction.id)
                }
                if groupId != nil {
                    var interestedPosts = AppContext.shared.userDefaults.value(forKey: AppContext.commentedGroupPostsKey) as? [FeedPostID] ?? []
                    interestedPosts.append(postId)
                    AppContext.shared.userDefaults.set(Array(Set(interestedPosts)), forKey: AppContext.commentedGroupPostsKey)
                }

            case .failure(let error):
                DDLogError("FeedData/send-reaction/reactionID: \(reactionId) error \(error)")
                self.contentInFlight.remove(reactionId)
                // TODO: Track this state more precisely. Even if this attempt was a definite failure, a previous attempt may have succeeded.
                if error.isKnownFailure {
                    self.updateReaction(with: reactionId) { (reaction) in
                        reaction.outgoingStatus = .error
                        MainAppContext.shared.endBackgroundTask(reaction.id)
                    }
                }
            }
        }
    }

    // DEPRECATED - Use coreFeedData.send once the new uploader is enabled everywhere
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

        let predicate = NSPredicate(format: "statusValue == %d AND groupID == nil AND timestamp > %@", FeedPost.Status.sent.rawValue, NSDate(timeIntervalSinceNow: -Date.days(7)))
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

    public func uploadProgressPublisher(for post: FeedPost) -> AnyPublisher<Float, Never> {
        if ServerProperties.enableNewMediaUploader {
            return coreFeedData.uploadProgressPublisher(for: post)
        } else {
            let postID = post.id
            let mediaCount = post.mediaCount
            guard mediaCount > 0 else {
                return Just(Float(1)).eraseToAnyPublisher()
            }
            // Send PostID to handle initial progress population
            return Publishers.Merge3(ImageServer.shared.progress, MainAppContext.shared.feedData.mediaUploader.uploadProgressDidChange, Just(postID))
                .filter { $0 == postID }
                .map { _ -> Float in
                    var (processingCount, processingProgress) = ImageServer.shared.progress(for: postID)
                    var (uploadCount, uploadProgress) = MainAppContext.shared.feedData.mediaUploader.uploadProgress(forGroupId: postID)

                    processingProgress = processingProgress * Float(processingCount) / Float(mediaCount)
                    uploadProgress = uploadProgress * Float(uploadCount) / Float(mediaCount)
                    return (processingProgress + uploadProgress) / 2.0
                }
                .eraseToAnyPublisher()
        }
    }

    private func beginMediaUploadAndSend(feedPost: FeedPost) {
        if ServerProperties.enableNewMediaUploader {
            coreFeedData.beginMediaUploadAndSend(feedPost: feedPost)
        } else {
            if let linkPreview = feedPost.linkPreviews?.first {
                // upload link preview media followed by comment media and send over the wire
                uploadMediaAndSend(feedLinkPreview: linkPreview)
            } else {
                // upload comment media if any and send data over the wire.
                uploadMediaAndSend(feedPost: feedPost)
            }
        }
    }

    private func uploadMediaAndSend(feedPost: FeedPost) {
        let postId = feedPost.id

        MainAppContext.shared.beginBackgroundTask(postId)

        // Either all media has already been uploaded or post does not contain media.
        guard let mediaItemsToUpload = feedPost.media?.filter({ [.none, .readyToUpload, .processedForUpload, .uploading, .uploadError].contains($0.status) }), !mediaItemsToUpload.isEmpty else {
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

            if let url = mediaItem.mediaURL, mediaItem.sha256.isEmpty, mediaItem.key.isEmpty {
                DDLogDebug("FeedData/process-mediaItem/feedPost: \(postId)/\(mediaIndex)/url: \(url)")
                let output = url.deletingLastPathComponent().appendingPathComponent(outputFileID, isDirectory: false).appendingPathExtension("processed").appendingPathExtension(url.pathExtension)

                ImageServer.shared.prepare(mediaItem.type, url: url, for: postId, index: Int(mediaIndex), shouldStreamVideo: mediaItem.blobVersion == .chunked) { [weak self] in
                    guard let self = self else { return }
                    DDLogDebug("FeedData/process-mediaItem/\(postId)/\(mediaIndex)/result: \($0)")
                    switch $0 {
                    case .success(let result):
                        guard result.copy(to: output) else {
                            break
                        }
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
                        return
                    case .failure(_):
                        break
                    }
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
                }
            }

            let numPhotos = mediaItemsToUpload.filter { $0.type == .image }.count
            let numVideos = mediaItemsToUpload.filter { $0.type == .video }.count
            AppContext.shared.eventMonitor.observe(
                .mediaUpload(
                    postID: postId,
                    duration: Date().timeIntervalSince(startTime),
                    numPhotos: numPhotos,
                    numVideos: numVideos,
                    totalSize: totalUploadSize,
                    status: numberOfFailedUploads == 0 ? .ok : .fail))
        }
    }

    private func uploadMediaAndSend(feedLinkPreview: CommonLinkPreview) {
        let linkPreviewID = feedLinkPreview.id
        let commentID = feedLinkPreview.comment?.id
        let postID = feedLinkPreview.post?.id

        guard let mediaItemsToUpload = feedLinkPreview.media?.filter({ [.none, .readyToUpload, .processedForUpload, .uploading].contains($0.status) }), !mediaItemsToUpload.isEmpty else {
            // no link preview media.. upload
            performSeriallyOnBackgroundContext { managedObjectContext in
                // Comment link preview
                if let commentID = commentID, let feedComment = self.feedComment(with: commentID, in: managedObjectContext) {
                    self.uploadMediaAndSend(feedComment: feedComment)
                    return
                }
                // Post link preview
                if let postID = postID, let feedPost = self.feedPost(with: postID, in: managedObjectContext) {
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

            if let url = mediaItemToUpload.mediaURL, mediaItemToUpload.sha256.isEmpty, mediaItemToUpload.key.isEmpty {
                DDLogDebug("FeedData/process-mediaItem/feedLinkPreview: \(feedLinkPreview.id)/\(mediaIndex)/url: \(url)")
                let output = url.deletingLastPathComponent().appendingPathComponent(outputFileID, isDirectory: false).appendingPathExtension("processed").appendingPathExtension(url.pathExtension)

                ImageServer.shared.prepare(mediaItemToUpload.type, url: url, for: feedLinkPreview.id, index: Int(mediaIndex), shouldStreamVideo: false) { [weak self] in
                    guard let self = self else { return }
                    switch $0 {
                    case .success(let result):
                        guard result.copy(to: output) else {
                            break
                        }
                        if result.url != url {
                            result.clear()
                        }

                        let path = self.downloadManager.relativePath(from: output)
                        DDLogDebug("FeedData/process-feedLinkPreview-mediaItem/success: \(linkPreviewID)/ index: \(mediaIndex)")
                        self.updateFeedLinkPreview(with: linkPreviewID, block: { (feedLinkPreview) in
                            if let media = feedLinkPreview.media?.first(where: { $0.order == mediaIndex }) {
                                media.size = result.size
                                media.key = result.key
                                media.sha256 = result.sha256
                                media.relativeFilePath = path
                            }
                        }) {
                            self.uploadFeedLinkPreview(feedLinkPreviewId: linkPreviewID, mediaIndex: mediaIndex, completion: uploadCompletion)
                        }
                        return
                    case .failure(_):
                        break
                    }
                    DDLogDebug("FeedData/process-feedLinkPreview-mediaItem/failure: feedLinkPreview \(linkPreviewID)/\(mediaIndex) url\(url) output \(output)")
                    numberOfFailedUploads += 1

                    self.updateFeedLinkPreview(with: linkPreviewID, block: { (feedLinkPreview) in
                        if let media = feedLinkPreview.media?.first(where: { $0.order == mediaIndex }){
                            media.status = .uploadError
                        }
                    }) {
                        uploadGroup.leave()
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
                    if let commentID = commentID, let feedComment = self.feedComment(with: commentID, in: managedObjectContext) {
                        self.uploadMediaAndSend(feedComment: feedComment)
                        return
                    }
                    // Post link preview
                    if let postID = postID, let feedPost = self.feedPost(with: postID, in: managedObjectContext) {
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
            let commentID = feedComment.id
            let postID = feedComment.post.id

            guard let mediaItemsToUpload = feedComment.media?.filter({ [.none, .readyToUpload, .processedForUpload, .uploading, .uploadError].contains($0.status) }), !mediaItemsToUpload.isEmpty else {
                performSeriallyOnBackgroundContext { managedObjectContext in
                    guard let feedComment = self.feedComment(with: commentID, in: managedObjectContext) else {
                        DDLogError("FeedData/missing-comment [\(commentID)]")
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


                if let url = mediaItemToUpload.mediaURL, mediaItemToUpload.sha256.isEmpty && mediaItemToUpload.key.isEmpty {
                    DDLogDebug("FeedData/process-mediaItem/comment: \(feedComment.id)/\(mediaIndex)/url: \(url)")
                    let output = url.deletingLastPathComponent().appendingPathComponent(outputFileID, isDirectory: false).appendingPathExtension("processed").appendingPathExtension(url.pathExtension)

                    ImageServer.shared.prepare(mediaItemToUpload.type, url: url, for: feedComment.id, index: Int(mediaIndex), shouldStreamVideo: mediaItemToUpload.blobVersion == .chunked) { [weak self] in
                        guard let self = self else { return }
                        switch $0 {
                        case .success(let result):
                            guard result.copy(to: output) else {
                                break
                            }
                            if result.url != url {
                                result.clear()
                            }

                            let path = self.downloadManager.relativePath(from: output)
                            DDLogDebug("FeedData/process-comment-mediaItem/success: comment \(commentID)/ commment:\(commentID)\(mediaIndex)")
                            self.updateFeedPostComment(with: commentID, block: { (feedPostComment) in
                                if let media = feedPostComment.media?.first(where: { $0.order == mediaIndex }) {
                                    media.size = result.size
                                    media.key = result.key
                                    media.sha256 = result.sha256
                                    media.chunkSize = result.chunkSize
                                    media.blobSize = result.blobSize
                                    media.relativeFilePath = path
                                }
                            }) {
                                self.uploadCommentMedia(postId: postID, commentId: commentID, mediaIndex: mediaIndex, completion: uploadCompletion)
                            }
                            return
                        case .failure(_):
                            break
                        }
                        DDLogDebug("FeedData/process-comment-mediaItem/failure: comment \(commentID)/\(mediaIndex) url\(url) output \(output)")
                        numberOfFailedUploads += 1

                        self.updateFeedPostComment(with: commentID, block: { (feedComment) in
                            if let media = feedComment.media?.first(where: { $0.order == mediaIndex }){
                                media.status = .uploadError
                            }
                        }) {
                            uploadGroup.leave()
                        }
                    }
                } else {
                    DDLogDebug("FeedData/process-comment-mediaItem/processed already: comment \(feedComment.id)/\(mediaIndex)")
                    self.uploadCommentMedia(postId: postID, commentId: commentID, mediaIndex: mediaIndex, completion: uploadCompletion)
                }
            }

        uploadGroup.notify(queue: .main) {
            DDLogInfo("FeedData/upload-comment-media/\(commentID)/all/finished [\(totalUploads-numberOfFailedUploads)/\(totalUploads)]")
            ImageServer.shared.clearAllTasks(for: commentID)
            self.mediaUploader.clearTasks(withGroupID: commentID)
            if numberOfFailedUploads > 0 {
                self.updateFeedPostComment(with: commentID, block: { (feedComment) in
                    feedComment.status = .sendError
                })
            } else {
                // TODO(murali@): one way to avoid looking up the object from the database is to keep an updated in-memory version of the comment.
                self.performSeriallyOnBackgroundContext { (managedObjectContext) in
                    guard let feedComment = self.feedComment(with: commentID, in: managedObjectContext) else {
                        DDLogError("FeedData/missing-comment [\(feedComment.id)]")
                        return
                    }
                    self.send(comment: feedComment)
                    // TODO dini update this with commentid
    //                AppContext.shared.eventMonitor.observe(
    //                    .mediaUpload(
    //                        postID: postID,
    //                        duration: Date().timeIntervalSince(startTime),
    //                        numPhotos: mediaItemsToUpload.filter { $0.type == .image }.count,
    //                        numVideos: mediaItemsToUpload.filter { $0.type == .video }.count,
    //                        totalSize: totalUploadSize))
                }
            }
        }
    }

    private func upload(postId: FeedPostID, mediaIndex: Int16, completion: @escaping (Result<Int, Error>) -> Void) {
        performSeriallyOnBackgroundContext { managedObjectContext in
            guard let post = self.feedPost(with: postId, in: managedObjectContext),
                  let postMedia = post.media?.first(where: { $0.order == mediaIndex }) else {
                DDLogError("FeedData/upload/fetch post and media \(postId)/\(mediaIndex) - missing")
                return
            }

            DDLogDebug("FeedData/upload/media \(postId)/\(postMedia.order), index:\(mediaIndex)")
            guard let processed = postMedia.mediaURL else {
                DDLogError("FeedData/upload-media/\(postId)/\(mediaIndex) missing file path")
                return completion(.failure(MediaUploadError.invalidUrls))
            }

            MainAppContext.shared.mediaHashStore.fetch(url: processed, blobVersion: postMedia.blobVersion) { [weak self] upload in
                guard let self = self else { return }

                self.performSeriallyOnBackgroundContext { managedObjectContext in
                    // Lookup object from coredata again instead of passing around the object across threads.
                    DDLogInfo("FeedData/upload/fetch upload hash \(postId)/\(mediaIndex)")
                    guard let post = self.feedPost(with: postId, in: managedObjectContext),
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
        }
    }

    private func uploadCommentMedia(postId: FeedPostID, commentId: FeedPostCommentID, mediaIndex: Int16, completion: @escaping (Result<Int, Error>) -> Void) {
        performSeriallyOnBackgroundContext { managedObjectContext in
            guard let comment = self.feedComment(with: commentId, in: managedObjectContext), let postCommentMedia = comment.media?.first(where: { $0.order == mediaIndex }) else {
                DDLogError("FeedData/upload/fetch post, comment and media \(postId)/\(commentId)/\(mediaIndex) - missing")
                return
            }

            DDLogDebug("FeedData/upload/media/coment postid: \(postId)/ commentid: \(commentId)/ order: \(postCommentMedia), index:\(mediaIndex)")
            guard let processed = postCommentMedia.mediaURL else {
                DDLogError("FeedData/upload-media/comment postid: \(postId)/ commentid: \(commentId)/\(mediaIndex) missing file path")
                return completion(.failure(MediaUploadError.invalidUrls))
            }

            MainAppContext.shared.mediaHashStore.fetch(url: processed, blobVersion: postCommentMedia.blobVersion) { [weak self] upload in
                guard let self = self else { return }

                self.performSeriallyOnBackgroundContext { managedObjectContext in
                    // Lookup object from coredata again instead of passing around the object across threads.
                    DDLogInfo("FeedData/upload/fetch upload hash comment \(commentId)/\(mediaIndex)")
                    guard let comment = self.feedComment(with: commentId, in: managedObjectContext),
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
        }
    }
    
    private func uploadFeedLinkPreview(feedLinkPreviewId: FeedLinkPreviewID, mediaIndex: Int16, completion: @escaping (Result<Int, Error>) -> Void) {
        performSeriallyOnBackgroundContext { managedObjectContext in
            guard let feedLinkPreview = self.feedLinkPreview(with: feedLinkPreviewId, in: managedObjectContext),
                  let feedLinkPreviewMedia = feedLinkPreview.media?.first(where: { $0.order == mediaIndex }) else {
                DDLogError("FeedData/upload/fetch feedLinkPreviewID media \(feedLinkPreviewId)/\(mediaIndex) - missing")
                return
            }

            DDLogDebug("FeedData/upload/media/feedLinkPreviewID \(feedLinkPreviewId)/ order: \(feedLinkPreviewMedia), index:\(mediaIndex)")
            guard let processed = feedLinkPreviewMedia.mediaURL else {
                DDLogError("FeedData/upload-media/feedLinkPreview \(feedLinkPreviewId)/\(mediaIndex) missing file path")
                return completion(.failure(MediaUploadError.invalidUrls))
            }

            MainAppContext.shared.mediaHashStore.fetch(url: processed, blobVersion: feedLinkPreviewMedia.blobVersion) { [weak self] upload in
                guard let self = self else { return }

                self.performSeriallyOnBackgroundContext { managedObjectContext in
                    // Lookup object from coredata again instead of passing around the object across threads.
                    DDLogInfo("FeedData/upload/fetch upload hash FeedLinkPreview \(feedLinkPreviewId)/\(mediaIndex)")
                    guard let feedLinkPreview = self.feedLinkPreview(with: feedLinkPreviewId, in: managedObjectContext),
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
        }
    }

    func cancelMediaUpload(postId: FeedPostID) {
        DDLogInfo("FeedData/upload-media/cancel/\(postId)")
        mediaUploader.cancelUpload(groupId: postId)

        performSeriallyOnBackgroundContext { [weak self] context in
            guard let self = self else {
                return
            }
            self.feedPost(with: postId, in: context)?.media?.forEach { media in
                self.commonMediaUploader.cancelUpload(mediaID: media.id)
            }
        }
    }

    // MARK: Clean Up Media Upload Data

    // cleans up old upload data since for now we do not remove the originals right after uploading
    public func cleanUpOldUploadData(directoryURL: URL) {
        // Create our own context so we don't block the main queue, this can be a lengthy operation
        let context = mainDataStore.persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.perform {
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

                if let media = MainAppContext.shared.mainDataStore.commonMediaItem(id: fileNameWithIndex, in: context), media.status == .uploaded {
                    DDLogVerbose("FeedData/cleanUpOldUploadData/clean up existing media upload data: \(media.relativeFilePath ?? "")")
                    ImageServer.cleanUpUploadData(directoryURL: directoryURL, relativePath: media.relativeFilePath)
                } else if let feedPost = MainAppContext.shared.feedData.feedPost(with: contentID, in: context) {
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
                } else if let feedPostComment = MainAppContext.shared.feedData.feedComment(with: contentID, in: context) {
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
                } else if let feedLinkPreview = MainAppContext.shared.feedData.feedLinkPreview(with: contentID, in: context) {
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
    }

    // MARK: Deletion

    func deleteUnsentPost(postID: FeedPostID) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
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
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            let feedFetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
            feedFetchRequest.predicate = NSPredicate(format: "groupID == %@", groupId)
            do {
                let groupFeeds = try managedObjectContext.fetch(feedFetchRequest)
                
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
            cancelDownloadAndDeleteMedia(mediaItem: media)
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

        setCachedMedia(nil, for: feedPost.id)
    }
    
    private func deleteMedia(feedPostComment: FeedPostComment) {
        feedPostComment.media?.forEach { (media) in
            cancelDownloadAndDeleteMedia(mediaItem: media)
        }

        feedPostComment.linkPreviews?.forEach {
            // Delete link previews if any
            self.deleteMedia(feedLinkPreview: $0)
            feedPostComment.managedObjectContext?.delete($0)
        }
    }

    private func deleteMedia(feedLinkPreview: CommonLinkPreview) {
        feedLinkPreview.media?.forEach { (media) in
            // cancel any pending tasks for this media
            DDLogInfo("FeedData/deleteMedia/feedLinkPreview-id \(feedLinkPreview.id), media-id: \(media.id)")
            cancelDownloadAndDeleteMedia(mediaItem: media)
        }
    }

    private func cancelDownloadAndDeleteMedia(mediaItem: CommonMedia) {
        // cancel any pending tasks for this media
        DDLogInfo("FeedData/deleteMedia/id: \(mediaItem.id)")
        if let currentTask = downloadManager.currentTask(for: mediaItem) {
            DDLogInfo("FeedData/deleteMedia/cancelTask/task: \(currentTask.id)")
            currentTask.downloadRequest?.cancel(producingResumeData : false)
        }
        commonMediaUploader.cancelUpload(mediaID: mediaItem.id)
        // Delete media files.
        coreFeedData.deleteMedia(mediaItem: mediaItem)
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
        let fetchRequest = FeedActivity.fetchRequest()
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
        let fetchRequest = FeedActivity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "postID IN %@", postIDs)
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
    
    static var momentCutoffDate: Date {
        let momentExpiryTimeInterval = -Date.days(1)
        return Date(timeIntervalSinceNow: momentExpiryTimeInterval)
    }

    private func deleteExpiredPosts() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            DDLogInfo("FeedData/delete-expired")
            let expiredPosts = self.feedPosts(predicate: NSPredicate(format: "expiration < now()"), in: managedObjectContext)

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
            self.reloadGroupFeedUnreadCounts(using: managedObjectContext)
        }
    }

    private func deleteExpiredMoments() {
        performSeriallyOnBackgroundContext { [weak self] context in
            guard let self = self else {
                return
            }

            let cutoff = Self.momentCutoffDate
            DDLogInfo("FeedData/delete-expired-moments  date=[\(cutoff)]")

            let request = FeedPost.fetchRequest()
            request.predicate = NSCompoundPredicate(type: .and, subpredicates: [
                NSPredicate(format: "timestamp < %@", cutoff as NSDate),
                NSPredicate(format: "userID != %@", MainAppContext.shared.userData.userId),
                NSPredicate(format: "isMoment == YES"),
            ])

            let results = try? context.fetch(request)
            let expiredMomentIDs = (results ?? []).map { $0.id }

            self.deleteAssociatedData(for: expiredMomentIDs, in: context)
            results?.forEach { post in
                // TODO: use the `.expired` status for normal feed posts vs deleting them entirely?
                self.deleteMedia(feedPost: post)
                post.status = .expired
            }

            self.save(context)
        }
    }
    
    /// Gets expired posts that were posted by the user.
    /// - Parameter completion: Callback function that returns the array of feed post ids
    func getArchivedPosts(completion: @escaping ([FeedPostID]) -> ()) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            DDLogInfo("FeedData/get-archived")
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "expiration < now()"),
                NSPredicate(format: "userID == %@", MainAppContext.shared.userData.userId),
            ])
            completion(self.feedPosts(predicate: predicate, in: managedObjectContext).map(\.id))
        }
    }
    
    /// Delete data that is no longer relevant for archived posts. Data deleted includes notifications and post comment drafts.
    /// - Parameter posts: Posts to delete related data from.
    func deleteAssociatedData(for posts: [FeedPostID], in managedObjectContext: NSManagedObjectContext) {
        performSeriallyOnBackgroundContext { managedObjectContext in
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
            MainAppContext.shared.feedData.feedPost(with: id, in: managedObjectContext)
        }.flatMap { post in
            post.comments ?? []
        }.forEach({ comment in
            managedObjectContext.delete(comment)
        })
    }
    
    public func deleteComment(with id: FeedPostCommentID) {
        DDLogDebug("FeedData/deleteComment/message \(id)")

        performSeriallyOnBackgroundContext { [weak self] context in
            guard let self = self, let comment = self.feedComment(with: id, in: context) else {
                return
            }
            context.delete(comment)

            if context.hasChanges {
                self.save(context)
            }
        }
    }
    
    /// Deletes drafts of comments in `userDefaults` that meet the condition argument.
    /// - Parameter condition: Should return true when the draft passed in needs to be removed. Returns false otherwise.
    static func deletePostCommentDrafts(when condition: (CommentDraft) -> Bool) {
        var draftsArray: [CommentDraft] = []
        
        if let draftsDecoded: [CommentDraft] = try? AppContext.shared.userDefaults.codable(forKey: FlatCommentsViewController.postCommentDraftKey) {
            draftsArray = draftsDecoded
        }
        
        draftsArray.removeAll(where: condition)
        
        try? AppContext.shared.userDefaults.setCodable(draftsArray, forKey: FlatCommentsViewController.postCommentDraftKey)
    }

    // MARK: - External Share

    func externalShareUrl(for postID: FeedPostID, completion: @escaping (Result<URL, Error>) -> Void) {
        if let url = Self.externalShareInfo(for: postID, in: mainDataStore.viewContext)?.externalShareURL {
            completion(.success(url))
        } else {
            guard let post = feedPost(with: postID, in: mainDataStore.viewContext) else {
                DDLogError("FeedData/externalShareUrl/could not find post with id \(postID)")
                completion(.failure(RequestError.aborted))
                return
            }

            let postData = post.postData
            let expiry = post.expiration ?? post.timestamp.addingTimeInterval(FeedPost.defaultExpiration)
            var blob = postData.clientPostContainerBlob
            // Populate groupID, which is not available on PostData
            if let groupID = post.groupId {
                blob.groupID = groupID
            }

            let encryptedBlob: Data
            let key: Data
            do {
                (encryptedBlob, key) = try ExternalSharePost.encypt(blob: blob)
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

            let image: UIImage = {
                let image = externalShareThumbnail(for: post)
                // return light mode version if from our asset catalog
                return image.imageAsset?.image(with: UITraitCollection(userInterfaceStyle: .light)) ?? image
            }()
            let relativePath = "externalsharethumb-\(UUID().uuidString).jpg"
            let uploadFileURL = MainAppContext.commonMediaStoreURL.appendingPathComponent(relativePath)
            if image.save(to: uploadFileURL) {
                let imageSize = image.size
                let groupID = "\(post.id)-external"
                mediaUploader.upload(media: SimpleMediaUploadable(type: .image, encryptedFileURL: uploadFileURL),
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
            } else {
                uploadPostForExternalShare(nil, nil)
            }
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

    func externalSharePost(with blobID: String, key: Data, completion: @escaping (Result<FeedPost, Error>) -> Void) {
        let mainQueueCompletion: (Result<FeedPost, Error>) -> Void = { [viewContext] result in
            DispatchQueue.main.async {
                // Redispatch with object in correct context
                switch result {
                case .success(let feedPost):
                    completion(.success(viewContext.object(with: feedPost.objectID) as! FeedPost))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
        let transform: (Server_ExternalSharePostContainer) -> Void = { externalSharePostContainer in
            self.performSeriallyOnBackgroundContext { [weak self] context in
                guard let self = self else {
                    mainQueueCompletion(.failure(RequestError.malformedResponse))
                    return
                }
                do {
                    let postContainerBlob = try ExternalSharePost.decrypt(encryptedBlob: externalSharePostContainer.blob, key: key)
                    let expiration = Date(timeIntervalSince1970: TimeInterval(postContainerBlob.timestamp)).addingTimeInterval(FeedPost.defaultExpiration)
                    guard let postData = PostData(blob: postContainerBlob, expiration: expiration) else {
                        mainQueueCompletion(.failure(RequestError.malformedResponse))
                        return
                    }

                    // Add push name and avatar if from external user
                    let userID = String(externalSharePostContainer.uid)
                    var isContact = false
                    self.contactStore.performOnBackgroundContextAndWait { [weak self] context in
                        isContact = self?.contactStore.isContactInAddressBook(userId: userID, in: context) ?? false
                    }

                    if !isContact {
                        self.contactStore.addPushNames([userID: externalSharePostContainer.name])
                        if !externalSharePostContainer.avatarID.isEmpty {
                            MainAppContext.shared.avatarStore.addAvatar(id: externalSharePostContainer.avatarID, for: userID)
                        }
                    }

                    self.process(posts: [postData],
                                 receivedIn: postContainerBlob.groupID,
                                 using: context,
                                 presentLocalNotifications: false,
                                 fromExternalShare: true)
                    guard let post = self.feedPost(with: postData.id, in: context) else {
                        mainQueueCompletion(.failure(RequestError.malformedResponse))
                        return
                    }
                    mainQueueCompletion(.success(post))
                } catch {
                    DDLogError("FeedData/externalSharePost/decryptionError: \(error)")
                    mainQueueCompletion(.failure(error))
                }

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

    func externalShareThumbnail(for post: FeedPost) -> UIImage {
        let media = media(for: post)

        var thumbnailMedia = media
            .filter { [.image, .video].contains($0.type) }
            .sorted { $0.order < $1.order }

        if let linkPreviewMedia = post.linkPreview?.feedMedia {
            thumbnailMedia.append(linkPreviewMedia)
        }

        // Display a thumb from the first image or video, if available
        if let thumbnailMedia = thumbnailMedia.first(where: { $0.fileURL != nil }), let fileURL = thumbnailMedia.fileURL {
            switch thumbnailMedia.type {
            case .image:
                if let thumb = UIImage.thumbnail(contentsOf: fileURL, maxPixelSize: Self.externalShareThumbSize) {
                    return thumb
                }
            case .video:
                if let thumb = VideoUtils.videoPreviewImage(url: fileURL, size: CGSize(width: Self.externalShareThumbSize,
                                                                                       height: Self.externalShareThumbSize)) {
                    return thumb
                }
            case .audio:
                // Audio is filtered out
                break
            }
        }

        // Display an audio icon for audio posts
        if media.contains(where: { $0.type == .audio }) {
            return UIImage(named: "ExternalShareAudioPostThumb")!
        }

        // Display a generic icon for text posts / if creating a thumb failed
        return UIImage(named: "ExternalShareTextPostThumb")!
    }
    
    // MARK: - Moments

    func refreshValidMoment() {
        if let validMoment = validMoment.value, validMoment.status != .retracted, !validMoment.isDeleted, validMoment.timestamp > Self.momentCutoffDate {
            DDLogInfo("FeedData/refreshValidMoment/existing moment still valid")
            return
        }

        // this moment is accessed in views & controllers, viewContext is required
        let moment = fetchLatestMoment(using: viewContext)
        if moment?.id != validMoment.value?.id {
            DDLogInfo("FeedData/refreshValidMoment/sending \(moment?.id ?? "nil")")
            validMoment.send(moment)
        }
    }
    
    func fetchLatestMoment(using context: NSManagedObjectContext) -> FeedPost? {
        let request = FeedPost.fetchRequest()

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userID == %@", userData.userId),
            NSPredicate(format: "isMoment == YES"),
            NSPredicate(format: "statusValue != %d", FeedPost.Status.retracted.rawValue),
            NSPredicate(format: "timestamp > %@", Self.momentCutoffDate as NSDate),
        ])
        
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func momentWasViewed(_ moment: FeedPost) {
        guard moment.userId != userData.userId else {
            return
        }

        DDLogInfo("FeedData/momentWasViewed/starting update block id: [\(moment.id)]")
        expiredMoments.insert(moment.id)

        updateFeedPost(with: moment.id) { [weak self] moment in
            self?.internalSendSeenReceipt(for: moment)
            guard let context = moment.managedObjectContext else {
                DDLogError("FeedData/momentWasViewed/post in update block has no moc")
                return
            }

            self?.deleteMedia(feedPost: moment)
            self?.deleteAssociatedData(for: [moment.id], in: context)
            moment.status = .expired

            DDLogInfo("FeedData/momentWasViewed/finished update: \(moment.id) status: \(moment.status)")
        }
    }

    /// - Returns: All of the valid, unexpired moments from other users (sorted).
    func fetchAllIncomingMoments() -> [FeedPost] {
        let request = FeedPost.fetchRequest()

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userID != %@", userData.userId),
            NSPredicate(format: "isMoment == YES"),
            NSPredicate(format: "statusValue != %d", FeedPost.Status.retracted.rawValue),
            NSPredicate(format: "statusValue != %d", FeedPost.Status.expired.rawValue),
            NSPredicate(format: "timestamp > %@", Self.momentCutoffDate as NSDate),
        ])

        request.sortDescriptors = [NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false)]

        return (try? viewContext.fetch(request)) ?? []
    }

    // MARK: - Notifications

    func updateFavoritesPromoNotification() {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            let notifications = AppContext.shared.coreFeedData.notifications(for: "favorites", in: managedObjectContext)
            if notifications.count > 0 {
                notifications.forEach {
                    if $0.timestamp < Date(timeIntervalSinceNow: -FeedPost.defaultExpiration) {
                        managedObjectContext.delete($0)
                    }
                }
                return
            }
            if !AppContext.shared.userDefaults.bool(forKey: "hasFavoritesNotificationBeenSent") {
                AppContext.shared.userDefaults.set(true, forKey: "hasFavoritesNotificationBeenSent")
                let userId = self.userData.userId
                let notification = FeedActivity(context: managedObjectContext)
                notification.postID = String("favorites")
                notification.event = .favoritesPromo
                notification.timestamp = Date()
                notification.userID = userId
                self.save(managedObjectContext)
            }
        }
    }

    // MARK: Merge Data
    
    let didMergeFeedPost = PassthroughSubject<FeedPostID, Never>()

    func mergeData(from sharedDataStore: SharedDataStore, completion: @escaping () -> ()) {
        DDLogInfo("FeedData/mergeData - \(sharedDataStore.source)/begin")
        sharedDataStore.performSeriallyOnBackgroundContext { context in
            let posts = sharedDataStore.posts(in: context)
            let comments = sharedDataStore.comments(in: context)
            self.performSeriallyOnBackgroundContext { managedObjectContext in
                self.merge(posts: posts, comments: comments, from: sharedDataStore, using: managedObjectContext)
            }

            let sharedPostIds = sharedDataStore.postIds()
            let sharedCommentIds = sharedDataStore.commentIds()
            DDLogInfo("FeedData/mergeData/sharedPostIds: \(sharedPostIds)/sharedCommentIds: \(sharedCommentIds)")

            self.mainDataStore.saveSeriallyOnBackgroundContext ({ managedObjectContext in
                // TODO: murali@: we dont need the following merge in the future - leaving it in for now.
                self.mergeMediaItems(from: sharedDataStore, using: managedObjectContext)
            }) { [self] result in
                switch result {
                case .success:
                    mainDataStore.saveSeriallyOnBackgroundContext { [self] context in
                        // Posts
                        let sharedFeedPosts = feedPosts(with: Set(sharedPostIds), in: context, archived: false)
                        var mergedFeedPosts = feedPostsToProcess(in: context)
                        mergedFeedPosts.append(contentsOf: sharedFeedPosts)

                        let postIds = mergedFeedPosts.map { $0.id }
                        generateNotifications(for: mergedFeedPosts, using: context)
                        // Notify about new posts all interested parties.
                        mergedFeedPosts.forEach({ feedPost in
                            /*
                             Do not invalidate cachedMedia. Anything currently bound to the existing media
                             will no longer receive load callbacks, as they are not reloaded as the posts are
                             not changing (as in the other places where this is set).

                             The cache may still contain previous media data if the post is changed or deleted,
                             but the UI state should still be consistent, as we've already sent change notifications
                             to all of our contexts.
                             */
                            //cachedMedia[$0.id] = nil

                            // Try and reload cached media. It is possible that we have an old media item in cache and
                            // nse just finished downloading the media and the transaction is merged afterwards.
                            feedPost.media?.forEach { mediaItem in
                                refreshUIwithMedia(feedMedia: mediaItem)
                            }
                            didMergeFeedPost.send(feedPost.id)
                            feedPost.hasBeenProcessed = true
                        })

                        // Comments
                        let sharedfeedPostComments = feedComments(with: Set(sharedCommentIds), in: context)
                        var mergedfeedPostComments = feedCommentsToProcess(in: context)
                        mergedfeedPostComments.append(contentsOf: sharedfeedPostComments)

                        let commentIds = mergedfeedPostComments.map { $0.id }
                        generateNotifications(for: mergedfeedPostComments, using: context)
                        // Notify about new comments all interested parties.
                        mergedfeedPostComments.forEach({ feedPostComment in
                            /*
                             Do not invalidate cachedMedia. Anything currently bound to the existing media
                             will no longer receive load callbacks, as they are not reloaded as the posts are
                             not changing (as in the other places where this is set).

                             The cache may still contain previous media data if the post is changed or deleted,
                             but the UI state should still be consistent, as we've already sent change notifications
                             to all of our contexts.
                             */

                            // Try and reload cached media. It is possible that we have an old media item in cache and
                            // nse just finished downloading the media and the transaction is merged afterwards.
                            feedPostComment.media?.forEach { mediaItem in
                                refreshUIwithMedia(feedMedia: mediaItem)
                            }
                            didReceiveFeedPostComment.send(feedPostComment)
                            feedPostComment.hasBeenProcessed = true
                        })
                        DDLogInfo("FeedData/mergeData/postIds: \(postIds)/commentIds: \(commentIds)")
                    }

                    sharedDataStore.clearPostIds()
                    sharedDataStore.clearCommentIds()
                case .failure(let error):
                    DDLogDebug("FeedData/mergeData/error: \(error)")
                }
                DDLogInfo("FeedData/mergeData - \(sharedDataStore.source)/done")
                checkForUnreadFeed()
                completion()
            }
        }
    }

    private func merge(posts: [SharedFeedPost], comments: [SharedFeedComment], from sharedDataStore: SharedDataStore, using managedObjectContext: NSManagedObjectContext) {
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
            feedPost.rawText = post.text
            feedPost.status = {
                switch post.status {
                case .received, .acked: return .incoming
                case .sent: return .sent
                case .none, .sendError: return .sendError
                case .decryptionError, .rerequesting: return .rerequesting
                }
            }()
            feedPost.timestamp = post.timestamp
            feedPost.lastUpdated = post.timestamp
            if let rawData = post.rawData {
                feedPost.rawData = rawData
                feedPost.status = .unsupported
            }
            feedPost.isMoment = post.isMoment

            // Clear cached media if any.
            setCachedMedia(nil, for: feedPost.id)

            // Mentions
            feedPost.mentions = post.mentions?.map { MentionData(index: $0.index, userID: $0.userID, name: $0.name) } ?? []

            // Post Audience
            if let audience = post.audience {
                let feedPostInfo = ContentPublishInfo(context: managedObjectContext)
                feedPostInfo.audienceType = audience.audienceType
                feedPostInfo.receipts = audience.userIds.reduce(into: [UserID : Receipt]()) { (receipts, userId) in
                    receipts[userId] = Receipt()
                }
                feedPost.info = feedPostInfo
            }

            // Process link preview if present
            post.linkPreviews?.forEach { linkPreviewData in
                DDLogDebug("FeedData/merge-data/post/\(postId)/add-link-preview [\(String(describing: linkPreviewData.url))]")
                let linkPreview = CommonLinkPreview(context: managedObjectContext)
                linkPreview.id = PacketID.generate()
                linkPreview.url = linkPreviewData.url
                linkPreview.title = linkPreviewData.title
                linkPreview.desc = linkPreviewData.desc
                // Set preview image if present
                linkPreviewData.media?.enumerated().forEach { (index, previewMedia) in
                    let media = CommonMedia(context: managedObjectContext)
                    media.id = "\(linkPreview.id)-\(index)"
                    media.type = previewMedia.type
                    media.status = .none
                    media.url = previewMedia.url
                    media.size = previewMedia.size
                    media.key = previewMedia.key
                    media.sha256 = previewMedia.sha256
                    media.linkPreview = linkPreview
                    media.mediaDirectory = .commonMedia
                    media.order = Int16(index)

                    // Copy media if there'a a local copy (outgoing posts or incoming posts with downloaded media).
                    if let relativeFilePath = previewMedia.relativeFilePath {
                        let pendingMedia = PendingMedia(type: media.type)
                        pendingMedia.fileURL = sharedDataStore.legacyFileURL(forRelativeFilePath: relativeFilePath)
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

                let feedMedia = CommonMedia(context: managedObjectContext)
                feedMedia.id = "\(feedPost.id)-\(media.order)"
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
                feedMedia.mediaDirectory = .commonMedia

                // Copy media if there'a a local copy (outgoing posts or incoming posts with downloaded media).
                if let relativeFilePath = media.relativeFilePath {
                    let pendingMedia = PendingMedia(type: feedMedia.type)
                    pendingMedia.fileURL = sharedDataStore.legacyFileURL(forRelativeFilePath: relativeFilePath)
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

        // Process link preview if present
        var linkPreviews = Set<CommonLinkPreview>()
        sharedComment.linkPreviews?.forEach { sharedLinkPreviewData in
            DDLogDebug("FeedData/process-comments/new/add-link-preview [\(String(describing: sharedLinkPreviewData.url))]")

            let linkPreview = CommonLinkPreview(context: managedObjectContext)
            linkPreview.id = PacketID.generate()
            linkPreview.url = sharedLinkPreviewData.url
            linkPreview.title = sharedLinkPreviewData.title
            linkPreview.desc = sharedLinkPreviewData.desc
            // Set preview image if present
            sharedLinkPreviewData.media?.enumerated().forEach { (index, sharedPreviewMedia) in
                let media = CommonMedia(context: managedObjectContext)
                media.id = "\(linkPreview.id)-\(index)"
                media.type = sharedPreviewMedia.type
                media.status = .none
                media.url = sharedPreviewMedia.url
                media.size = sharedPreviewMedia.size
                media.key = sharedPreviewMedia.key
                media.sha256 = sharedPreviewMedia.sha256
                media.linkPreview = linkPreview
                media.order = Int16(index)
            }
            linkPreviews.insert(linkPreview)
        }

        // Add media
        var mediaItems = Set<CommonMedia>()
        sharedComment.media?.forEach({ mediaItem in
            let feedCommentMedia = CommonMedia(context: managedObjectContext)
            feedCommentMedia.id = "\(commentId)-\(mediaItem.order)"
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
        feedComment.rawText = sharedComment.text
        feedComment.mentions = sharedComment.mentions?.map {
            if $0.name.isEmpty {
                DDLogError("FeedData/merge/comment/mention/\($0.userID) missing push name")
            }
            return MentionData(index: $0.index, userID: $0.userID, name: $0.name)
        } ?? []
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
        setCachedMedia(nil, for: feedComment.id)

        if let rawData = sharedComment.rawData {
            feedComment.rawData = rawData
            feedComment.status = .unsupported
        }
        // Increase unread comments counter on post.
        feedPost.lastUpdated = feedPost.lastUpdated.flatMap { max($0, feedComment.timestamp) } ?? feedComment.timestamp
        feedPost.unreadCount += 1

        return feedComment
    }

    private func mergeMediaItems(from sharedDataStore: SharedDataStore, using managedObjectContext: NSManagedObjectContext) {
        let mediaDirectory = sharedDataStore.oldMediaDirectory
        DDLogInfo("FeedData/mergeMediaItems from \(mediaDirectory)/begin")

        let mediaPredicate = NSPredicate(format: "mediaDirectoryValue == \(mediaDirectory.rawValue)")
        let extensionMediaItems = mainDataStore.commonMediaItems(predicate: mediaPredicate, in: managedObjectContext)
        DDLogInfo("FeedData/mergeMediaItems/extensionMediaItems: \(extensionMediaItems.count)")
        extensionMediaItems.forEach { media in
            // Copy only posts/comments/linkPreviews to posts and comments.
            // Ideally - we should just have the extension write to a common media directory and we use that everywhere.
            // Will do that separately - since that will need some more changes.
            if media.post != nil || media.comment != nil || media.linkPreview?.post != nil || media.linkPreview?.comment != nil {
                DDLogDebug("FeedData/mergeMediaItems/media: \(String(describing: media.relativeFilePath))")
                copyMediaItem(from: media, sharedDataStore: sharedDataStore)
            }
        }
        DDLogInfo("FeedData/mergeMediaItems from \(mediaDirectory)/done")
    }

    private func copyMediaItem(from media: CommonMedia, sharedDataStore: SharedDataStore) {
        // Copy media if there's a local copy (outgoing posts or incoming posts with downloaded media).
        if let relativeFilePath = media.relativeFilePath {

            // current media URL
            let extensionMediaURL = sharedDataStore.fileURL(forRelativeFilePath: relativeFilePath)
            let extensionEncryptedMediaURL = extensionMediaURL.appendingPathExtension("enc")

            // final media URL
            let mainappMediaURL = self.downloadManager.fileURL(forRelativeFilePath: relativeFilePath)
            let mainappEncryptedMediaURL = mainappMediaURL.appendingPathExtension("enc")
            DDLogInfo("FeedData/copyMediaItem/extension: \(extensionMediaURL)/mainapp: \(mainappMediaURL)")

            do {
                // create directories if necessary
                try FileManager.default.createDirectory(at: mainappMediaURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                if media.status == .uploadError {
                    try FileManager.default.copyItem(at: extensionEncryptedMediaURL, to: mainappEncryptedMediaURL)
                    return
                }
                // copy unencrypted file
                try FileManager.default.copyItem(at: extensionMediaURL, to: mainappMediaURL)
            } catch {
                DDLogError("FeedData/copy-media-error [\(error)]")
            }

            // Set mediaDirectory properly
            media.mediaDirectory = .commonMedia
        }
    }
}

extension FeedData: HalloFeedDelegate {

    func halloService(_ halloService: HalloService, didRerequestHomeFeedItem contentID: String, contentType: HomeFeedRerequestContentType, from userID: UserID, ack: (() -> Void)?) {
        DDLogDebug("FeedData/didRerequestHomeFeedItem [\(contentID)] - [\(contentType)] - from: \(userID)")
        AppContext.shared.coreFeedData.handleRerequest(for: contentID, contentType: contentType, from: userID, ack: ack)
    }

    func halloService(_ halloService: HalloService, didRerequestGroupFeedItem contentID: String, contentType: GroupFeedRerequestContentType, from userID: UserID, ack: (() -> Void)?) {
        DDLogDebug("FeedData/didRerequestGroupFeedItem [\(contentID)] - [\(contentType)] - from: \(userID)")
        AppContext.shared.coreFeedData.handleRerequest(for: contentID, contentType: contentType, from: userID, ack: ack)
    }

    func halloService(_ halloService: HalloService, didRerequestGroupFeedHistory contentID: String, from userID: UserID, ack: (() -> Void)?) {
        DDLogDebug("FeedData/didRerequestGroupFeedHistory [\(contentID)] - from: \(userID)")
        AppContext.shared.coreFeedData.handleGroupFeedHistoryRerequest(for: contentID, from: userID, ack: ack)
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
                feedPost.info = ContentPublishInfo(context: managedObjectContext)
            }
            var receipts = feedPost.info!.receipts ?? [:]
            if receipts[receipt.userId] == nil {
                receipts[receipt.userId] = Receipt()
            }

            var postReceipt = receipts[receipt.userId]!
            switch receipt.type {
            case .screenshot:
                postReceipt.screenshotDate = receipt.timestamp
                Task { await self.presentLocalNotificationsForScreenshot(receipt: receipt) }
                DDLogInfo("FeedData/screenshot-receipt/update  userId=[\(receipt.userId)]  ts=[\(receipt.timestamp!)]  itemId=[\(receipt.itemId)]")

            case .saved:
                postReceipt.savedDate = receipt.timestamp
                DDLogInfo("FeedData/saved-receipt/update  userId=[\(receipt.userId)]  ts=[\(receipt.timestamp!)]  itemId=[\(receipt.itemId)]")

            default:
                postReceipt.seenDate = receipt.timestamp
                DDLogInfo("FeedData/seen-receipt/update  userId=[\(receipt.userId)]  ts=[\(receipt.timestamp!)]  itemId=[\(receipt.itemId)]")
            }

            receipts[receipt.userId] = postReceipt
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
            // Dont mark the status to be seen if the post is retracted, rerequested, or expired.
            if !feedPost.isPostRetracted && !feedPost.isRerequested && !feedPost.isExpired {
                feedPost.status = .seen
            }
        }
    }
}
