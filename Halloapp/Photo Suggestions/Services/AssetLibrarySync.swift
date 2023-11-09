//
//  AssetLibrarySync.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/5/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Photos

/*
 Syncs the system PHPhotoLibrary to our asset database.
 On iOS 16+, we keep track of a changeToken, and sync all changes that occurred after that token
 On iOS 15, we re-do the initial sync each time (but expect few updates) we see a change from the photo library.
 Only one sync task can be running at any given time, and pending tasks are coalesced into a single next task.
 Since both iOS 15 and 16 mechanisms will sync all changes since the last sync, this allows us to deduplicate requests
 and effectively loop until there are no more changes.
 */
final class AssetLibrarySync {

    private struct Constants {
        static let fullSyncBatchSize = 500
    }

    private init() {}

    private class func sync(with photoSuggestionsData: PhotoSuggestionsData, changeTokenSynchronizer: ChangeTokenSynchronizer) async throws {
        if #available(iOS 16, *) {
            let currentChangeToken = PHPhotoLibrary.shared().currentChangeToken
            if let lastSyncedChangeToken = changeTokenSynchronizer.lastSyncedChangeToken {
                if currentChangeToken == lastSyncedChangeToken {
                    DDLogInfo("AssetLibrarySync/Skipping (same change token)")
                } else {
                    DDLogInfo("AssetLibrarySync/Begin/diff")
                    try await syncChanges(since: lastSyncedChangeToken, with: photoSuggestionsData)
                    DDLogInfo("AssetLibrarySync/Complete/diff")
                }
            } else {
                DDLogInfo("AssetLibrarySync/Begin/Initial Sync")
                try await performInitialSync(with: photoSuggestionsData)
                DDLogInfo("AssetLibrarySync/Complete/Initial Sync")
            }
            changeTokenSynchronizer.lastSyncedChangeToken = currentChangeToken
        } else {
            DDLogInfo("AssetLibrarySync/Begin/Full Sync")
            try await performInitialSync(with: photoSuggestionsData)
            DDLogInfo("AssetLibrarySync/Complete/Full Sync")
        }
    }

    private class func performInitialSync(with photoSuggestionsData: PhotoSuggestionsData) async throws {
        let options = PHFetchOptions()
        options.wantsIncrementalChangeDetails = false
        options.sortDescriptors = [
            NSSortDescriptor(keyPath: \PHAsset.creationDate, ascending: false)
        ]

        let results = PHAsset.fetchAssets(with: options)

        // Divide assets into batches for faster processing
        for startIndex in stride(from: 0, to: results.count, by: Constants.fullSyncBatchSize) {
            let batchedAssets = (startIndex..<min(startIndex + Constants.fullSyncBatchSize, results.count)).map { results.object(at: $0) }
            try await photoSuggestionsData.saveOnBackgroundContext { context in
                let existingRecordsByID = AssetRecord.find(ids: batchedAssets.map(\.localIdentifier), in: context)
                    .reduce(into: [String: AssetRecord]()) { partialResult, record in
                        if let localIdentifier = record.localIdentifier {
                            partialResult[localIdentifier] = record
                        }
                    }

                for asset in batchedAssets {
                    let record: AssetRecord
                    if let existingRecord = existingRecordsByID[asset.localIdentifier] {
                        DDLogInfo("AssetLibrarySync/performInitialSync/Found existing asset with id \(asset.localIdentifier), updating")
                        record = existingRecord
                    } else {
                        DDLogInfo("AssetLibrarySync/performInitialSync/Creating new asset with id \(asset.localIdentifier)")
                        record = AssetRecord(context: context)
                        record.macroClusterStatus = .pending
                    }
                    record.update(asset: asset)

                    if !Self.isValidAsset(asset) {
                        DDLogInfo("AssetLibrarySync/performInitialSync/Marking \(asset.localIdentifier) as invalid")
                        record.macroClusterStatus = .invalidAssetForClustering
                    }
                }
            }

            DDLogInfo("AssetLibrarySync/Sync \(min(startIndex + Constants.fullSyncBatchSize, results.count)) / \(results.count)")
        }
    }

    @available(iOS 16, *)
    private class func syncChanges(since token: PHPersistentChangeToken, with photoSuggestionsData: PhotoSuggestionsData) async throws {
        let changes = try PHPhotoLibrary.shared().fetchPersistentChanges(since: token)

        for change in changes {
            try await photoSuggestionsData.saveOnBackgroundContext { context in
                let details = try change.changeDetails(for: .asset)

                let allChangedIdentifiers = details.insertedLocalIdentifiers.union(details.deletedLocalIdentifiers).union(details.updatedLocalIdentifiers)
                let existingRecordsByID = AssetRecord.find(ids: allChangedIdentifiers, in: context)
                    .reduce(into: [String: AssetRecord]()) { partialResult, record in
                        if let localIdentifier = record.localIdentifier {
                            partialResult[localIdentifier] = record
                        }
                    }

                let options = PHFetchOptions()
                options.wantsIncrementalChangeDetails = false
                let insertedOrUpdatedIdentifiers = details.insertedLocalIdentifiers.union(details.updatedLocalIdentifiers)
                let insertedOrUpdatedAssets = PHAsset.fetchAssets(withLocalIdentifiers: Array(insertedOrUpdatedIdentifiers), options: options)
                var insertedOrUpdatedAssetsByID: [String: PHAsset] = [:]
                insertedOrUpdatedAssets.enumerateObjects { asset, _, _ in
                    insertedOrUpdatedAssetsByID[asset.localIdentifier] = asset
                }

                insertedOrUpdatedIdentifiers.forEach {
                    guard let asset = insertedOrUpdatedAssetsByID[$0] else {
                        DDLogError("AssetLibrarySync/syncChanges/Could not fetch asset for inserted or deleted asset with identifier: \($0)")
                        return
                    }
                    let record: AssetRecord
                    if let existingRecord = existingRecordsByID[$0] {
                        DDLogInfo("AssetLibrarySync/syncChanges/Found existing asset with id \(asset.localIdentifier), updating")
                        record = existingRecord
                    } else {
                        DDLogInfo("AssetLibrarySync/syncChanges/Creating new asset with id \(asset.localIdentifier)")
                        record = AssetRecord(context: context)
                        record.macroClusterStatus = .pending
                    }
                    record.update(asset: asset)

                    if !Self.isValidAsset(asset) {
                        DDLogInfo("AssetLibrarySync/syncChanges/Marking \(asset.localIdentifier) as invalid")
                        record.macroClusterStatus = .invalidAssetForClustering
                    }
                }

                details.deletedLocalIdentifiers.forEach {
                    guard let existingRecord = existingRecordsByID[$0] else {
                        DDLogError("AssetLibrarySync/syncChanges/Could not find record for deleted asset with identifier: \($0)")
                        return
                    }

                    DDLogInfo("AssetLibrarySync/syncChanges/Marking asset for deletion with identifier \($0)")
                    existingRecord.macroClusterStatus = .deletePending
                }
            }
        }
    }

    private class func isValidAsset(_ asset: PHAsset) -> Bool {
        // PHAsset fetches do not accurately query mediaSubtypes, filter after the fetch
        return asset.mediaSubtypes != [] && asset.mediaSubtypes.isDisjoint(with: [.photoScreenshot, .photoAnimated, .videoScreenRecording])
    }
}

extension AssetLibrarySync {

    static func makeService(photoSuggestionsData: PhotoSuggestionsData, userDefaults: UserDefaults) -> PhotoSuggestionsService {
        let changeTokenSynchronizer = ChangeTokenSynchronizer(userDefaults: userDefaults)

        return PhotoSuggestionsSerialService {
            AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
                let assetLibraryChangeObserver = AssetLibraryChangeObserver {
                    continuation.yield()
                }
                continuation.onTermination = { _ in
                    assetLibraryChangeObserver.stop()
                }
                assetLibraryChangeObserver.start()
                // Always assume there's been changes if we've just started to observer them
                continuation.yield()
            }
        } task: {
            try? await Self.sync(with: photoSuggestionsData, changeTokenSynchronizer: changeTokenSynchronizer)
        } reset: {
            changeTokenSynchronizer.reset()
        }
    }
}

// MARK: - AssetLibraryChangeObserver

extension AssetLibrarySync {

    private final class AssetLibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver, Sendable {

        let onChange: @Sendable () -> Void

        init(onChange: @escaping @Sendable () -> Void) {
            self.onChange = onChange
        }

        func start() {
            PHPhotoLibrary.shared().register(self)
            onChange()
        }

        func stop() {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }

        func photoLibraryDidChange(_ changeInstance: PHChange) {
            onChange()
        }
    }
}

extension AssetLibrarySync {

    // UserDefaults is not sendable, wrap it to share across tasks
    class ChangeTokenSynchronizer: @unchecked Sendable {

        private static let changeTokenUserDefaultsKey = "AssetLibrarySync.lastSyncedChangeToken"

        private let userDefaults: UserDefaults

        init(userDefaults: UserDefaults) {
            self.userDefaults = userDefaults
        }

        @available(iOS 16, *)
        var lastSyncedChangeToken: PHPersistentChangeToken? {
            get {
                let data = userDefaults.data(forKey: Self.changeTokenUserDefaultsKey)
                return data.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: $0) }
            }
            set {
                let data = newValue.flatMap { try? NSKeyedArchiver.archivedData(withRootObject:$0, requiringSecureCoding: true) }
                userDefaults.set(data, forKey: Self.changeTokenUserDefaultsKey)
            }
        }

        func reset() {
            userDefaults.removeObject(forKey: Self.changeTokenUserDefaultsKey)
        }
    }
}
