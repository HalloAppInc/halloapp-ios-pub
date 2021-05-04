//
//  SharedDataStore.swift
//  Shared Extension
//
//  Created by Alan Luo on 7/17/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import CoreData

open class SharedDataStore {

    public enum PostOrMessage {
        case post(SharedFeedPost)
        case message(SharedChatMessage)
    }

    // MARK: Customization Points
    class var persistentStoreURL: URL {
        fatalError("Must implement in a subclass")
    }
    
    class var dataDirectoryURL: URL {
        fatalError("Must implement in a subclass")
    }

    public final lazy var persistentContainer: NSPersistentContainer! = {
        let storeDescription = NSPersistentStoreDescription(url: Self.persistentStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
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
    
    public final func fileURL(forRelativeFilePath relativePath: String) -> URL {
        return Self.dataDirectoryURL.appendingPathComponent(relativePath)
    }

    public final class func relativeFilePath(forFilename filename: String, mediaType: FeedMediaType) -> String {
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
            try managedObjectContext.save()
            DDLogInfo("SharedDataStore/did-save")
        } catch {
            DDLogError("SharedDataStore/save-error error=[\(error)]")
        }
    }

    private lazy var bgContext: NSManagedObjectContext = { persistentContainer.newBackgroundContext() }()
    
    public func performSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        self.backgroundProcessingQueue.async {
            self.bgContext.performAndWait { block(self.bgContext) }
        }
    }

    // MARK: Fetching Data
    
    public final func posts() -> [SharedFeedPost] {
        let managedObjectContext = persistentContainer.viewContext
        let fetchRequest: NSFetchRequest<SharedFeedPost> = SharedFeedPost.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SharedFeedPost.timestamp, ascending: false)]
        
        do {
            let posts = try managedObjectContext.fetch(fetchRequest)
            return posts
        } catch {
            DDLogError("SharedDataStore/posts/error  [\(error)]")
            fatalError("Failed to fetch shared posts.")
        }
    }
    
    public final func comments() -> [SharedFeedComment] {
        let managedObjectContext = persistentContainer.viewContext
        let fetchRequest: NSFetchRequest<SharedFeedComment> = SharedFeedComment.fetchRequest()
        // Important to fetch these in ascending order - since there could be replies to comments.
        // We fetch the parent comment using parentId and use it to store a reference in our entity.
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SharedFeedComment.timestamp, ascending: true)]
        
        do {
            let comments = try managedObjectContext.fetch(fetchRequest)
            return comments
        } catch {
            DDLogError("SharedDataStore/posts/error  [\(error)]")
            fatalError("Failed to fetch shared posts.")
        }
    }
    
    public final func messages() -> [SharedChatMessage] {
        let managedObjectContext = persistentContainer.viewContext
        let fetchRequest: NSFetchRequest<SharedChatMessage> = SharedChatMessage.fetchRequest()
        // Important to fetch these in ascending order - since there could be quoted content referencing previous messages
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SharedChatMessage.timestamp, ascending: true)]
        
        do {
            let messages = try managedObjectContext.fetch(fetchRequest)
            return messages
        } catch {
            DDLogError("SharedDataStore/messages/error  [\(error)]")
            fatalError("Failed to fetch shared messages.")
        }
    }

    public final func serverMessages() -> [SharedServerMessage] {
        let managedObjectContext = persistentContainer.viewContext
        let fetchRequest: NSFetchRequest<SharedServerMessage> = SharedServerMessage.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SharedServerMessage.timestamp, ascending: false)]
        
        do {
            let messages = try managedObjectContext.fetch(fetchRequest)
            return messages
        } catch {
            DDLogError("SharedDataStore/serverMessages/error  [\(error)]")
            fatalError("Failed to fetch shared serverMessages.")
        }
    }

    // MARK: Deleting Data

    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.data-store")

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
}

open class ShareExtensionDataStore: SharedDataStore {

    override class var persistentStoreURL: URL {
        AppContext.sharedDirectoryURL.appendingPathComponent("share-extension.sqlite")
    }

    override class var dataDirectoryURL: URL {
        AppContext.sharedDirectoryURL.appendingPathComponent("ShareExtension")
    }

    public override init() {}
}

open class NotificationServiceExtensionDataStore: SharedDataStore {

    override class var persistentStoreURL: URL {
        AppContext.sharedDirectoryURL.appendingPathComponent("notification-service-extension.sqlite")
    }

    override class var dataDirectoryURL: URL {
        AppContext.sharedDirectoryURL.appendingPathComponent("NotificationServiceExtension")
    }

    public override init() {}
}
