//
//  SharedDataStore.swift
//  Shared Extension
//
//  Created by Alan Luo on 7/17/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import CoreData
import UIKit
import XMPPFramework

public enum MediaType: Int {
    case image = 0
    case video = 1
}

open class SharedDataStore {

    public enum PostOrMessage {
        case post(SharedFeedPost)
        case message(SharedChatMessage)
    }
    
    private class var persistentStoreURL: URL {
        get {
            return AppContext.sharedDirectoryURL.appendingPathComponent("share-extension.sqlite")
        }
    }
    
    public class var dataDirectoryURL: URL {
        get {
            return AppContext.sharedDirectoryURL.appendingPathComponent("ShareExtension")
        }
    }
    
    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.share-extension")
    
    public let persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: SharedDataStore.persistentStoreURL)
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
    
    public static func fileURL(forRelativeFilePath relativePath: String) -> URL {
        return Self.dataDirectoryURL.appendingPathComponent(relativePath)
    }

    public static func relativeFilePath(forFilename filename: String, mediaType: FeedMediaType) -> String {
        // No intermediate directories needed.
        let fileExtension = FeedDownloadManager.fileExtension(forMediaType: mediaType)
        return "\(filename).\(fileExtension)"
    }

    public init() {}
    
    public func save(_ managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("SharedDataStore/will-save")
        do {
            try managedObjectContext.save()
            DDLogInfo("SharedDataStore/did-save")
        } catch {
            DDLogError("SharedDataStore/save-error error=[\(error)]")
        }
    }
    
    public func attach(media: PendingMedia, to target: PostOrMessage, using managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("SharedDataStore/attach-media [\(media.fileURL!)]")
        
        let feedMedia = NSEntityDescription.insertNewObject(forEntityName: SharedMedia.entity().name!, into: managedObjectContext) as! SharedMedia
        feedMedia.type = media.type
        feedMedia.url = media.url
        feedMedia.uploadUrl = media.uploadUrl
        feedMedia.size = media.size!
        feedMedia.key = media.key!
        feedMedia.sha256 = media.sha256!
        feedMedia.order = Int16(media.order)
        
        switch target {
        case .post(let feedPost):
            feedMedia.post = feedPost
        case .message(let chatMessage):
            feedMedia.message = chatMessage
        }
        
        let relativeFilePath = Self.relativeFilePath(forFilename: UUID().uuidString, mediaType: media.type)

        do {
            let destinationUrl = Self.fileURL(forRelativeFilePath: relativeFilePath)

            // Copy unencrypted media file.
            if let sourceUrl = media.fileURL {
                try FileManager.default.createDirectory(at: Self.dataDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                try FileManager.default.copyItem(at: sourceUrl, to: destinationUrl)
                DDLogDebug("SharedDataStore/attach-media/ copied [\(sourceUrl)] to [\(destinationUrl)]")

                feedMedia.relativeFilePath = relativeFilePath
            }

            // Copy encrypted media file.
            // Encrypted media would be saved at the same file path with an additional ".enc" appended.
            if let sourceUrl = media.encryptedFileUrl {
                let encryptedDestinationUrl = destinationUrl.appendingPathExtension("enc")
                try FileManager.default.copyItem(at: sourceUrl, to: encryptedDestinationUrl)
                DDLogDebug("SharedDataStore/attach-media/ copied [\(sourceUrl)] to [\(encryptedDestinationUrl)]")
            }
        } catch {
            DDLogError("SharedDataStore/attach-media/error [\(error)]")
        }
    }
    
    private func performSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        self.backgroundProcessingQueue.async {
            let managedObjectContext = self.persistentContainer.newBackgroundContext()
            managedObjectContext.performAndWait { block(managedObjectContext) }
        }
    }
    
    public func posts() -> [SharedFeedPost] {
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
    
    public func messages() -> [SharedChatMessage] {
        let managedObjectContext = persistentContainer.viewContext
        let fetchRequest: NSFetchRequest<SharedChatMessage> = SharedChatMessage.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SharedChatMessage.timestamp, ascending: false)]
        
        do {
            let messages = try managedObjectContext.fetch(fetchRequest)
            return messages
        } catch {
            DDLogError("SharedDataStore/messages/error  [\(error)]")
            fatalError("Failed to fetch shared messages.")
        }
    }
    
    public func delete(posts: [SharedFeedPost], completion: @escaping (() -> Void)) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            let posts = posts.compactMap({ managedObjectContext.object(with: $0.objectID) as? SharedFeedPost })

            for post in posts {
                if let media = post.media, !media.isEmpty {
                    self.deleteFiles(forMedia: Array(media))
                }
                managedObjectContext.delete(post)
            }
            
            self.save(managedObjectContext)
            
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    public func delete(messages: [SharedChatMessage], completion: @escaping (() -> Void)) {
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

    private func deleteFiles(forMedia mediaItems: [SharedMedia]) {
        mediaItems.forEach { (mediaItem) in
            let fileUrl = Self.fileURL(forRelativeFilePath: mediaItem.relativeFilePath)
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
