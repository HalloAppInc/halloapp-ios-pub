//
//  UploadsData.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import Foundation

class UploadData {

    let willDestroyStore = PassthroughSubject<Void, Never>()
    let didReloadStore = PassthroughSubject<Void, Never>()

    private var cancellableSet: Set<AnyCancellable> = []
    private let backgroundQueue = DispatchQueue(label: "com.halloapp.uploads-data")

    // MARK: CoreData stack

    private class var persistentStoreURL: URL {
        get {
            return MainAppContext.uploadStoreURL
        }
    }

    private lazy var persistentContainer: NSPersistentContainer = {
        let description = NSPersistentStoreDescription(url: UploadData.persistentStoreURL)
        description.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(NSNumber(booleanLiteral: false), forKey: NSInferMappingModelAutomaticallyOption)
        description.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        description.setValue(NSString("1"), forPragmaNamed: "secure_delete")

        let container = NSPersistentContainer(name: "Upload")
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { (description, error) in
            if let error = error {
                DDLogError("Failed to load persistent store: \(error)")
                DDLogError("Deleting persistent store at [\(UploadData.persistentStoreURL.absoluteString)]")

                try? FileManager.default.removeItem(at: UploadData.persistentStoreURL)

                DDLogError("Unable to load persistent store: \(error)")
            } else {
                DDLogInfo("UploadsData/load-store/completed [\(description)]")
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

        DDLogVerbose("UploadsData/will-save")
        do {
            try context.save()
            DDLogVerbose("UploadsData/did-save")
        } catch {
            DDLogError("UploadsData/save-error error=[\(error)]")
        }
    }

    // MARK: Fetching

    func fetch(upload url: URL, completion: @escaping (Upload?) -> Void) {
        guard let hash = try? MediaCrypter.hash(url: url).base64EncodedString() else {
            DDLogError("UploadsData/get/error unable to hash file=[\(url)]")
            return completion(nil)
        }

        fetch(upload: hash, completion: completion)
    }

    func fetch(upload data: Data, completion: @escaping (Upload?) -> Void) {
        fetch(upload: MediaCrypter.hash(data: data).base64EncodedString(), completion: completion)
    }

    func fetch(upload hash: String, completion: @escaping (Upload?) -> Void) {
        performSeriallyOnBackgroundContext { context in
            let request: NSFetchRequest<Upload> = Upload.fetchRequest()
            request.returnsObjectsAsFaults = false
            request.predicate = NSPredicate(format: "dataHash = %@", hash)

            do {
                completion(try context.fetch(request).first)
            } catch {
                DDLogError("UploadsData/fetch-upload/error  [\(error)]")
            }
        }
    }

    // MARK: Updating

    func update(upload fileURL: URL, key: String, sha256: String, downloadURL: URL) {
        guard let hash = try? MediaCrypter.hash(url: fileURL).base64EncodedString() else {
            DDLogError("UploadsData/insert/error unable to hash file=[\(fileURL)]")
            return
        }

        update(hash: hash, key: key, sha256: sha256, downloadURL: downloadURL)
    }

    func update(upload data: Data, key: String, sha256: String, downloadURL: URL) {
        update(hash: MediaCrypter.hash(data: data).base64EncodedString(), key: key, sha256: sha256, downloadURL: downloadURL)
    }

    func update(hash: String, key: String, sha256: String, downloadURL: URL) {
        DDLogInfo("UploadsData/update hash=[\(hash)] from=[\(downloadURL)]")

        performSeriallyOnBackgroundContext { context in
            let request: NSFetchRequest<Upload> = Upload.fetchRequest()
            request.returnsObjectsAsFaults = false
            request.predicate = NSPredicate(format: "dataHash = %@", hash)

            let upload: Upload
            do {
                upload = (try context.fetch(request).first) ?? Upload(context: context)
            } catch {
                return DDLogError("UploadsData/fetch-upload/error  [\(error)]")
            }

            upload.dataHash = hash
            upload.key = key
            upload.sha256 = sha256
            upload.timestamp = Date()
            upload.url = downloadURL

            self.save(context)
        }
    }
}
