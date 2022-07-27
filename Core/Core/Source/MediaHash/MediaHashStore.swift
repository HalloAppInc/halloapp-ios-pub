//
//  MediaHashStore.swift
//  Core
//
//  Created by Murali Balusu on 9/13/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import CoreData
import Foundation

public class MediaHashStore {

    let willDestroyStore = PassthroughSubject<Void, Never>()
    let didReloadStore = PassthroughSubject<Void, Never>()

    private var cancellableSet: Set<AnyCancellable> = []
    private let persistentStoreURL: URL
    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.mediahash-data")

    public init(persistentStoreURL: URL) {
        self.persistentStoreURL = persistentStoreURL
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
    }

    // MARK: CoreData stack

    private lazy var persistentContainer: NSPersistentContainer = {
        let description = NSPersistentStoreDescription(url: self.persistentStoreURL)
        description.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
        description.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        description.setValue(NSString("1"), forPragmaNamed: "secure_delete")

        let modelURL = Bundle(for: MediaHash.self).url(forResource: "MediaHash", withExtension: "momd")!
        let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL)
        let container = NSPersistentContainer(name: "MediaHash", managedObjectModel: managedObjectModel!)

        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { (description, error) in
            if let error = error {
                DDLogError("Failed to load persistent store: \(error)")
                DDLogError("Deleting persistent store at [\(self.persistentStoreURL.absoluteString)]")

                try? FileManager.default.removeItem(at: self.persistentStoreURL)

                DDLogError("Unable to load persistent store: \(error)")
            } else {
                DDLogInfo("MediaHash/load-store/completed [\(description)]")
            }
        }

        return container
    }()

    public var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
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

    private func save(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }

        DDLogVerbose("MediaHashStore/will-save")
        do {
            try context.save()
            DDLogVerbose("MediaHashStore/did-save")
        } catch {
            DDLogError("MediaHashStore/save-error error=[\(error)]")
        }
    }

    // MARK: Fetching

    public func fetch(url: URL, blobVersion: BlobVersion) async -> (url: URL?, key: String?, sha256: String?)? {
        return await withCheckedContinuation { continuation in
            fetch(url: url, blobVersion: blobVersion) { upload in
                continuation.resume(returning: upload)
            }
        }
    }

    public func fetch(url: URL, blobVersion: BlobVersion, completion: @escaping ((url: URL?, key: String?, sha256: String?)?) -> Void) {
        guard let hash = try? MediaCrypter.hash(url: url).base64EncodedString() else {
            DDLogError("MediaHashStore/get/error unable to hash file=[\(url)]")
            return completion(nil)
        }

        fetch(hash: hash, blobVersion: blobVersion, completion: completion)
    }

    public func fetch(data: Data, blobVersion: BlobVersion, completion: @escaping ((url: URL?, key: String?, sha256: String?)?) -> Void) {
        fetch(hash: MediaCrypter.hash(data: data).base64EncodedString(), blobVersion: blobVersion, completion: completion)
    }

    public func fetch(hash: String, blobVersion: BlobVersion, completion: @escaping ((url: URL?, key: String?, sha256: String?)?) -> Void) {
        performSeriallyOnBackgroundContext { context in
            completion(self.fetch(hash: hash, blobVersion: blobVersion, in: context))
        }
    }

    // should always run on background queue.
    private func fetch(hash: String, blobVersion: BlobVersion, in context: NSManagedObjectContext) -> (url: URL?, key: String?, sha256: String?)? {
        let request: NSFetchRequest<MediaHash> = MediaHash.fetchRequest()
        request.returnsObjectsAsFaults = false
        request.predicate = NSPredicate(format: "dataHash = %@ AND blobVersionValue = %d", hash, blobVersion.rawValue)
        do {
            // avoid accesssing the MediaHash managed object on another thread
            if let hash = try context.fetch(request).first {
                return (url: hash.url, key: hash.key, sha256: hash.sha256)
            } else {
                return nil
            }
        } catch {
            DDLogError("MediaHashStore/fetch-mediaHash/error  [\(error)]")
            return nil
        }
    }

    // MARK: Updating

    public func update(url: URL, blobVersion: BlobVersion, key: String, sha256: String, downloadURL: URL) {
        guard let hash = try? MediaCrypter.hash(url: url).base64EncodedString() else {
            DDLogError("MediaHashStore/insert/error unable to hash file=[\(url)]")
            return
        }

        update(hash: hash, blobVersion: blobVersion, key: key, sha256: sha256, downloadURL: downloadURL)
    }

    public func update(data: Data, blobVersion: BlobVersion, key: String, sha256: String, downloadURL: URL) {
        update(hash: MediaCrypter.hash(data: data).base64EncodedString(), blobVersion: blobVersion, key: key, sha256: sha256, downloadURL: downloadURL)
    }

    public func update(hash: String, blobVersion: BlobVersion, key: String, sha256: String, downloadURL: URL) {
        DDLogInfo("MediaHashStore/update hash=[\(hash)] from=[\(downloadURL)]")

        performSeriallyOnBackgroundContext { context in
            let request: NSFetchRequest<MediaHash> = MediaHash.fetchRequest()
            request.returnsObjectsAsFaults = false
            request.predicate = NSPredicate(format: "dataHash = %@", hash)

            let mediaHash: MediaHash
            do {
                mediaHash = (try context.fetch(request).first) ?? MediaHash(context: context)
            } catch {
                return DDLogError("MediaHashStore/fetch-mediahash/error  [\(error)]")
            }

            mediaHash.dataHash = hash
            mediaHash.blobVersionValue = Int16(blobVersion.rawValue)
            mediaHash.key = key
            mediaHash.sha256 = sha256
            mediaHash.timestamp = Date()
            mediaHash.url = downloadURL

            self.save(context)
        }
    }

    public func updateAll(mediaHashItemList: [(String, String, String, URL)]) {
        performSeriallyOnBackgroundContext { context in
            for (dataHash, sha256, key, url) in mediaHashItemList {
                let request: NSFetchRequest<MediaHash> = MediaHash.fetchRequest()
                request.returnsObjectsAsFaults = false
                request.predicate = NSPredicate(format: "dataHash = %@", dataHash)

                let mediaHash: MediaHash
                do {
                    mediaHash = (try context.fetch(request).first) ?? MediaHash(context: context)
                } catch {
                    return DDLogError("MediaHashStore/fetch-mediahash/error  [\(error)]")
                }

                mediaHash.dataHash = dataHash
                mediaHash.key = key
                mediaHash.sha256 = sha256
                mediaHash.timestamp = Date()
                mediaHash.url = url
            }
            self.save(context)
        }
    }

}
