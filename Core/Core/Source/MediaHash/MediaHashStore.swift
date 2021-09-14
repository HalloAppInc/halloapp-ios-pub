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
    private let backgroundQueue = DispatchQueue(label: "com.halloapp.mediahash-data")
    private let persistentStoreURL: URL
    public init(persistentStoreURL: URL) {
        self.persistentStoreURL = persistentStoreURL
    }

    // MARK: CoreData stack

    private lazy var persistentContainer: NSPersistentContainer = {
        let description = NSPersistentStoreDescription(url: self.persistentStoreURL)
        description.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(NSNumber(booleanLiteral: false), forKey: NSInferMappingModelAutomaticallyOption)
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

    private var viewContext: NSManagedObjectContext {
        get {
            persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
            return persistentContainer.viewContext
        }
    }

    private lazy var backgroundContext: NSManagedObjectContext = {
        return self.persistentContainer.newBackgroundContext()
    } ()

    private func performSeriallyOnBackgroundContext(_ action: @escaping (NSManagedObjectContext) -> Void) {
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            self.backgroundContext.performAndWait { action(self.backgroundContext) }
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

    public func fetch(url: URL, completion: @escaping (MediaHash?) -> Void) {
        guard let hash = try? MediaCrypter.hash(url: url).base64EncodedString() else {
            DDLogError("MediaHashStore/get/error unable to hash file=[\(url)]")
            return completion(nil)
        }

        fetch(hash: hash, completion: completion)
    }

    public func fetch(data: Data, completion: @escaping (MediaHash?) -> Void) {
        fetch(hash: MediaCrypter.hash(data: data).base64EncodedString(), completion: completion)
    }

    public func fetch(hash: String, completion: @escaping (MediaHash?) -> Void) {
        performSeriallyOnBackgroundContext { context in
            let mediaHash = self.fetch(hash: hash, in: context)
            completion(mediaHash)
        }
    }

    // should always run on background queue.
    private func fetch(hash: String, in context: NSManagedObjectContext) -> MediaHash? {
        let request: NSFetchRequest<MediaHash> = MediaHash.fetchRequest()
        request.returnsObjectsAsFaults = false
        request.predicate = NSPredicate(format: "dataHash = %@", hash)
        do {
            return try context.fetch(request).first
        } catch {
            DDLogError("MediaHashStore/fetch-mediaHash/error  [\(error)]")
            return nil
        }
    }

    // MARK: Updating

    public func update(url: URL, key: String, sha256: String, downloadURL: URL) {
        guard let hash = try? MediaCrypter.hash(url: url).base64EncodedString() else {
            DDLogError("MediaHashStore/insert/error unable to hash file=[\(url)]")
            return
        }

        update(hash: hash, key: key, sha256: sha256, downloadURL: downloadURL)
    }

    public func update(data: Data, key: String, sha256: String, downloadURL: URL) {
        update(hash: MediaCrypter.hash(data: data).base64EncodedString(), key: key, sha256: sha256, downloadURL: downloadURL)
    }

    public func update(hash: String, key: String, sha256: String, downloadURL: URL) {
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
