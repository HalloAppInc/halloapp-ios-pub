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
    
    public static func fileURL(forFileName fileName: String, withFileType fileType: FeedMediaType) -> URL {
        switch fileType {
        case .image:
            return Self.dataDirectoryURL.appendingPathComponent(fileName).appendingPathExtension("jpeg")
        case .video:
            return Self.dataDirectoryURL.appendingPathComponent(fileName).appendingPathExtension("mp4")
        }
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
    
    public func save(_ media: PendingMedia, index: Int, to target: PostOrMessage, using managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("SharedDataStore/save/add new media with [\(media.url!)]")
        
        let feedMedia = NSEntityDescription.insertNewObject(forEntityName: SharedMedia.entity().name!, into: managedObjectContext) as! SharedMedia
        feedMedia.type = media.type
        feedMedia.url = media.url!
        feedMedia.size = media.size!
        feedMedia.key = media.key!
        feedMedia.sha256 = media.sha256!
        feedMedia.order = Int16(index)
        
        switch target {
        case .post(let feedPost):
            feedMedia.post = feedPost
        case .message(let chatMessage):
            feedMedia.message = chatMessage
        }
        
        let mediaFilename = UUID().uuidString
        let destinationFileURL = Self.fileURL(forFileName: mediaFilename, withFileType: feedMedia.type)
        feedMedia.relativeFilePath = destinationFileURL.lastPathComponent
        
        do {
            try FileManager.default.createDirectory(at: Self.dataDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.copyItem(at: media.fileURL!, to: destinationFileURL)
        } catch {
            DDLogError("SharedDataStore/save/copy-media/error [\(error)]")
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
    
    public func delete(_ objects: [NSManagedObject], completion: @escaping (() -> Void)) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            for object in objects {
                managedObjectContext.delete(managedObjectContext.object(with: object.objectID))
            }
            
            self.save(managedObjectContext)
            
            DispatchQueue.main.async {
                completion()
            }
        }
    }
}
