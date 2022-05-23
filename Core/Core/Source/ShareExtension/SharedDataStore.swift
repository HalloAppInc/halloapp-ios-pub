//
//  SharedDataStore.swift
//  Shared Extension
//
//  Created by Alan Luo on 7/17/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import CoreData
import CoreCommon

open class SharedDataStore {

    public enum PostOrMessageOrLinkPreview {
        case post(FeedPost)
        case message(ChatMessage)
        case linkPreview(CommonLinkPreview)
    }

    // MARK: Customization Points
    class var persistentStoreURL: URL {
        fatalError("Must implement in a subclass")
    }

    class var dataDirectoryURL: URL {
        fatalError("Must implement in a subclass")
    }

    class var mediaDirectoryURL: URL {
        fatalError("Must implement in a subclass")
    }

    public var source: AppTarget {
        fatalError("Must implement in a subclass")
    }

    public var oldMediaDirectory: MediaDirectory {
        fatalError("Must implement in a subclass")
    }

    public final lazy var persistentContainer: NSPersistentContainer! = {
        let storeDescription = NSPersistentStoreDescription(url: Self.persistentStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let modelURL = Bundle(for: SharedMedia.self).url(forResource: "SharedData", withExtension: "momd")!
        let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL)
        let container = NSPersistentContainer(name: "SharedData", managedObjectModel: managedObjectModel!)
        container.persistentStoreDescriptions = [storeDescription]
        container.loadPersistentStores { (description, error) in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        return container
    }()

    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.shared-data-store")

    public final func legacyFileURL(forRelativeFilePath relativePath: String) -> URL {
        return Self.dataDirectoryURL.appendingPathComponent(relativePath)
    }

    public final func fileURL(forRelativeFilePath relativePath: String) -> URL {
        return Self.mediaDirectoryURL.appendingPathComponent(relativePath)
    }

    public final class func relativeFilePath(forFilename filename: String, mediaType: CommonMediaType) -> String {
        // No intermediate directories needed.
        let fileExtension = FeedDownloadManager.fileExtension(forMediaType: mediaType)
        return "\(filename).\(fileExtension)"
    }

    public final class func preparePathForWriting(_ fileURL: URL) {
        let directoryURL = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        }
        catch {
            DDLogError("SharedDataStore/prepare-path/error \(error)")
        }
    }

    public final func save(_ managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("SharedDataStore/will-save")
        do {
            managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            try managedObjectContext.save()
            DDLogInfo("SharedDataStore/did-save")
        } catch {
            DDLogError("SharedDataStore/save-error error=[\(error)]")
        }
    }

    private func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return context
    }

    public func performSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        backgroundProcessingQueue.async { [weak self] in
            guard let self = self else { return }

            let context = self.newBackgroundContext()
            context.performAndWait {
                block(context)
            }
        }
    }

    public func performOnBackgroundContextAndWait(_ block: (NSManagedObjectContext) -> Void) {
        backgroundProcessingQueue.sync {
            let context = self.newBackgroundContext()
            context.performAndWait {
                block(context)
            }
        }
    }

    // MARK: Fetching Data

    private var postsUserDefaultsKey: String? {
        switch source {
        case .mainApp:
            return nil
        case .shareExtension:
            return AppContext.shareExtensionPostsKey
        case .notificationExtension:
            return AppContext.nsePostsKey
        }
    }

    private var commentsUserDefaultsKey: String? {
        switch source {
        case .mainApp:
            return nil
        case .shareExtension:
            return nil
        case .notificationExtension:
            return AppContext.nseCommentsKey
        }
    }

    private var messagesUserDefaultsKey: String? {
        switch source {
        case .mainApp:
            return nil
        case .shareExtension:
            return AppContext.shareExtensionMessagesKey
        case .notificationExtension:
            return AppContext.nseMessagesKey
        }
    }

    // MARK: Fetching Data
    public final func postIds() -> [FeedPostID] {
        guard let postsUserDefaultsKey = postsUserDefaultsKey else {
            DDLogError("SharedDataStore/postsUserDefaultsKey is missing")
            return []
        }
        return AppContext.shared.userDefaults.value(forKey: postsUserDefaultsKey) as? [FeedPostID] ?? []
    }

    public final func commentIds() -> [FeedPostCommentID] {
        guard let commentsUserDefaultsKey = commentsUserDefaultsKey else {
            DDLogError("SharedDataStore/commentsUserDefaultsKey is missing")
            return []
        }
        return AppContext.shared.userDefaults.value(forKey: commentsUserDefaultsKey) as? [FeedPostCommentID] ?? []
    }

    public final func chatMessageIds() -> [ChatMessageID] {
        guard let messagesUserDefaultsKey = messagesUserDefaultsKey else {
            DDLogError("SharedDataStore/messagesUserDefaultsKey is missing")
            return []
        }
        return AppContext.shared.userDefaults.value(forKey: messagesUserDefaultsKey) as? [FeedPostCommentID] ?? []
    }

    public final func posts(in context: NSManagedObjectContext) -> [SharedFeedPost] {
        let fetchRequest = SharedFeedPost.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SharedFeedPost.timestamp, ascending: true)]

        do {
            let posts = try context.fetch(fetchRequest)
            return posts
        } catch {
            DDLogError("SharedDataStore/posts/error  [\(error)]")
            fatalError("Failed to fetch shared posts.")
        }
    }

    public final func comments(in context: NSManagedObjectContext) -> [SharedFeedComment] {
        let fetchRequest = SharedFeedComment.fetchRequest()
        // Important to fetch these in ascending order - since there could be replies to comments.
        // We fetch the parent comment using parentId and use it to store a reference in our entity.
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SharedFeedComment.timestamp, ascending: true)]

        do {
            let comments = try context.fetch(fetchRequest)
            return comments
        } catch {
            DDLogError("SharedDataStore/posts/error  [\(error)]")
            fatalError("Failed to fetch shared posts.")
        }
    }

    public final func messages(in context: NSManagedObjectContext) -> [SharedChatMessage] {
        let fetchRequest: NSFetchRequest<SharedChatMessage> = SharedChatMessage.fetchRequest()
        // Important to fetch these in ascending order - since there could be quoted content referencing previous messages
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SharedChatMessage.timestamp, ascending: true)]

        do {
            let messages = try context.fetch(fetchRequest)
            return messages
        } catch {
            DDLogError("SharedDataStore/messages/error  [\(error)]")
            fatalError("Failed to fetch shared messages.")
        }
    }

    public final func sharedChatMessage(for msgId: String, in managedObjectContext: NSManagedObjectContext) -> SharedChatMessage? {
        let fetchRequest: NSFetchRequest<SharedChatMessage> = SharedChatMessage.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", msgId)
        do {
            let messages = try managedObjectContext.fetch(fetchRequest)
            return messages.first
        } catch {
            DDLogError("SharedDataStore/messages/error  [\(error)]")
            fatalError("Failed to fetch shared messages.")
        }
    }

    public final func sharedFeedPost(for contentID: String, in managedObjectContext: NSManagedObjectContext) -> SharedFeedPost? {
        let fetchRequest: NSFetchRequest<SharedFeedPost> = SharedFeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", contentID)
        do {
            let feedPosts = try managedObjectContext.fetch(fetchRequest)
            return feedPosts.first
        } catch {
            DDLogError("SharedDataStore/feedPosts/error  [\(error)]")
            fatalError("Failed to fetch shared feedPosts.")
        }
    }

    public final func sharedFeedComment(for contentID: String, in managedObjectContext: NSManagedObjectContext) -> SharedFeedComment? {
        let fetchRequest: NSFetchRequest<SharedFeedComment> = SharedFeedComment.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", contentID)
        do {
            let feedComments = try managedObjectContext.fetch(fetchRequest)
            return feedComments.first
        } catch {
            DDLogError("SharedDataStore/feedComments/error  [\(error)]")
            fatalError("Failed to fetch shared feedComments.")
        }
    }

    public final func serverMessages(in context: NSManagedObjectContext) -> [SharedServerMessage] {
        let fetchRequest: NSFetchRequest<SharedServerMessage> = SharedServerMessage.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SharedServerMessage.timestamp, ascending: true)]

        do {
            let messages = try context.fetch(fetchRequest)
            return messages
        } catch {
            DDLogError("SharedDataStore/serverMessages/error  [\(error)]")
            fatalError("Failed to fetch shared serverMessages.")
        }
    }

    // MARK: Deleting Data

    public final func clearPostIds() {
        guard let postsUserDefaultsKey = postsUserDefaultsKey else {
            DDLogError("SharedDataStore/postsUserDefaultsKey is missing")
            return
        }
        AppContext.shared.userDefaults.removeObject(forKey: postsUserDefaultsKey)
    }

    public final func clearCommentIds() {
        guard let commentsUserDefaultsKey = commentsUserDefaultsKey else {
            DDLogError("SharedDataStore/commentsUserDefaultsKey is missing")
            return
        }
        AppContext.shared.userDefaults.removeObject(forKey: commentsUserDefaultsKey)
    }

    public final func clearChatMessageIds() {
        guard let messagesUserDefaultsKey = messagesUserDefaultsKey else {
            DDLogError("SharedDataStore/messagesUserDefaultsKey is missing")
            return
        }
        AppContext.shared.userDefaults.removeObject(forKey: messagesUserDefaultsKey)
    }

    public final func delete(posts: [SharedFeedPost], comments: [SharedFeedComment], completion: @escaping (() -> Void)) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            let posts = posts.compactMap({ managedObjectContext.object(with: $0.objectID) as? SharedFeedPost })
            let comments = comments.compactMap({ managedObjectContext.object(with: $0.objectID) as? SharedFeedComment })

            // Delete posts
            for post in posts {
                if let media = post.media, !media.isEmpty {
                    self.deleteFiles(forMedia: Array(media))
                }
                managedObjectContext.delete(post)
            }

            // Delete comments
            for comment in comments {
                managedObjectContext.delete(comment)
            }

            self.save(managedObjectContext)

            DispatchQueue.main.async {
                completion()
            }
        }
    }

    public final func delete(messages: [SharedChatMessage], completion: @escaping (() -> Void)) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            let messages = messages.compactMap({ managedObjectContext.object(with: $0.objectID) as? SharedChatMessage })

            for message in messages {
                if let media = message.media, !media.isEmpty {
                    self.deleteFiles(forMedia: Array(media))
                }
                managedObjectContext.delete(message)
            }

            self.save(managedObjectContext)

            DispatchQueue.main.async {
                completion()
            }
        }
    }

    public final func delete(serverMessages: [SharedServerMessage], completion: @escaping (() -> Void)) {
        let messageObjectIDs = serverMessages.map { $0.objectID }
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            let messages = messageObjectIDs.compactMap { managedObjectContext.object(with: $0) as? SharedServerMessage }
            for message in messages {
                managedObjectContext.delete(message)
            }
            self.save(managedObjectContext)
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    public final func delete(serverMessageObjectID: NSManagedObjectID, completion: @escaping (() -> Void)) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            if let message = managedObjectContext.object(with: serverMessageObjectID) as? SharedServerMessage {
                managedObjectContext.delete(message)
                self.save(managedObjectContext)
            }
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    private func deleteFiles(forMedia mediaItems: [SharedMedia]) {
        for mediaItem in mediaItems {
            guard let relativePath = mediaItem.relativeFilePath else { continue }

            let fileUrl = fileURL(forRelativeFilePath: relativePath)
            do {
                try FileManager.default.removeItem(at: fileUrl)
                DDLogInfo("SharedDataStore/delete-media [\(fileUrl)]")
            } catch { }
            do {
                let encFileUrl = fileUrl.appendingPathExtension("enc")
                try FileManager.default.removeItem(at: encFileUrl)
                DDLogInfo("SharedDataStore/delete-media [\(encFileUrl)]")
            } catch {}
        }
    }

    public final func deleteAllContent() {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            do {
                let chatRequest = SharedChatMessage.fetchRequest()
                let chatMessages = try managedObjectContext.fetch(chatRequest)
                for chatMessage in chatMessages {
                    managedObjectContext.delete(chatMessage)
                }

                let sharedCommentRequest = SharedFeedComment.fetchRequest()
                let sharedComments = try managedObjectContext.fetch(sharedCommentRequest)
                for sharedComment in sharedComments {
                    managedObjectContext.delete(sharedComment)
                }

                let sharedPostRequest = SharedFeedPost.fetchRequest()
                let sharedPosts = try managedObjectContext.fetch(sharedPostRequest)
                for sharedPost in sharedPosts {
                    managedObjectContext.delete(sharedPost)
                }

                let serverMessageRequest = SharedServerMessage.fetchRequest()
                let sharedServerMessages = try managedObjectContext.fetch(serverMessageRequest)
                for sharedServerMessage in sharedServerMessages {
                    managedObjectContext.delete(sharedServerMessage)
                }

                self.save(managedObjectContext)
            } catch {
                DDLogError("SharedDataStore/deleteAllContent/error  [\(error)]")
                fatalError("Failed to delete all shared content.")
            }
        }
    }
}

open class ShareExtensionDataStore: SharedDataStore {

    override class var persistentStoreURL: URL {
        AppContext.sharedDirectoryURL.appendingPathComponent("share-extension.sqlite")
    }

    public override class var dataDirectoryURL: URL {
        AppContext.sharedDirectoryURL.appendingPathComponent("ShareExtension")
    }

    public override class var mediaDirectoryURL: URL {
        AppContext.commonMediaStoreURL
    }

    public override var source: AppTarget {
        return .shareExtension
    }

    public override var oldMediaDirectory: MediaDirectory {
        return .shareExtensionMedia
    }

    public override init() {}
}

open class NotificationServiceExtensionDataStore: SharedDataStore {

    override class var persistentStoreURL: URL {
        AppContext.sharedDirectoryURL.appendingPathComponent("notification-service-extension.sqlite")
    }

    public override class var dataDirectoryURL: URL {
        AppContext.sharedDirectoryURL.appendingPathComponent("NotificationServiceExtension")
    }

    public override class var mediaDirectoryURL: URL {
        AppContext.commonMediaStoreURL
    }

    public override var source: AppTarget {
        return .notificationExtension
    }

    public override var oldMediaDirectory: MediaDirectory {
        return .notificationExtensionMedia
    }

    public override init() {}
}
