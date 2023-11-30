//
//  AssetClusterer.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/10/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import CoreData
import CoreLocation

/*
 For each invalidated or new asset, attempt to cluster it with its neighbors  This is an iterative version of the DBSCAN algorithm.
 After clustering assets, re-resolve all subclusters that may have changed.
 */
final class AssetClusterer {

    enum AssetClustererError: Error {
        case assetNotFound
    }

    private init() {}

    private class func clusterAsset(localIdentifier: String, with photoSuggestionsData: PhotoSuggestionsData) async throws {
        try await photoSuggestionsData.saveOnBackgroundContext { context in
            guard let asset = AssetRecord.find(id: localIdentifier, in: context) else {
                throw AssetClustererError.assetNotFound
            }

            switch asset.macroClusterStatus {
            case .pending:
                try Self.processPendingAsset(asset, in: context)
            case .deletePending:
                try Self.processDeletedAsset(asset, in: context)
            default:
                DDLogInfo("AssetClusterer/clusterAsset/attempted to cluster already clustered asset with id \(localIdentifier), ignoring")
            }

            // Process all cluster changes
            locateChangedClusters(in: context)
        }
    }

    private class func processPendingAsset(_ assetRecord: AssetRecord, in context: NSManagedObjectContext) throws {
        guard assetRecord.macroClusterStatus == .pending else {
            DDLogInfo("AssetClusterer/processPendingAsset/attempted to cluster already clustered asset")
            return
        }

        DDLogInfo("AssetClusterer/processPendingAsset/processing asset \(assetRecord.localIdentifier ?? "(null)")")

        let sortedClusterableAssets = try Self.sortedClusterableAssetRecords(for: assetRecord, in: context)

        let isCorePoint = sortedClusterableAssets.count >= PhotoSuggestionsUtilities.Constants.minClusterableAssetCount
        var cluster = assetRecord.macroCluster

        for clusterableAsset in sortedClusterableAssets {
            switch clusterableAsset.macroClusterStatus {
            case .pending:
                continue
            case .core:
                guard let existingCluster = clusterableAsset.macroCluster else {
                    DDLogInfo("AssetClusterer/processPendingAsset/Core asset with id \(clusterableAsset.localIdentifier ?? "(null)") does not have associated cluster")
                    continue
                }

                if cluster == nil {
                    cluster = existingCluster
                } else if let cluster, cluster != existingCluster {
                    DDLogInfo("AssetClusterer/processPendingAsset/Merging clusters \(cluster.id ?? "(null)") and \(existingCluster.id ?? "(null)")")

                    // Merge clusters
                    let clusterSize = cluster.assetRecords?.count ?? 0
                    let existingClusterSize = cluster.assetRecords?.count ?? 0

                    let clusterToMergeInto: AssetMacroCluster
                    let clusterToRemove: AssetMacroCluster

                    if clusterSize >= existingClusterSize {
                        clusterToMergeInto = cluster
                        clusterToRemove = existingCluster
                    } else {
                        clusterToMergeInto = existingCluster
                        clusterToRemove = cluster
                    }

                    clusterToRemove.assetRecordsAsSet.forEach {
                        $0.macroCluster = clusterToMergeInto
                    }

                    clusterToMergeInto.locatedClusterStatus = .pending

                    context.delete(clusterToRemove)
                }
            case .edge:
                let clusterableAssetSurroundingAssetCount = try Self.sortedClusterableAssetRecords(for: clusterableAsset, in: context).count
                if clusterableAssetSurroundingAssetCount >= PhotoSuggestionsUtilities.Constants.minClusterableAssetCount {
                    DDLogInfo("AssetClusterer/processPendingAsset/marking \(clusterableAsset.localIdentifier ?? "(null)") as pending as it may be a core point")
                    clusterableAsset.macroClusterStatus = .pending
                }
            case .orphan:
                if isCorePoint {
                    DDLogInfo("AssetClusterer/processPendingAsset/marking \(clusterableAsset.localIdentifier ?? "(null)") as pending as it it is adjacent to a core point")
                    clusterableAsset.macroClusterStatus = .pending
                }
            case .deletePending, .invalidAssetForClustering:
                DDLogInfo("AssetClusterer/processPendingAsset/Invalid asset status for clustering for \(clusterableAsset.localIdentifier ?? "(null)")")
                // do nothing, should be filtered by sortedClusterableAssets
                continue
            }
        }


        if isCorePoint, cluster == nil {
            DDLogInfo("AssetClusterer/processPendingAsset/creating new cluster (\(cluster?.id ?? "(null)"))")
            cluster = AssetMacroCluster(context: context)
            cluster?.id = UUID().uuidString
        }

        DDLogInfo("AssetClusterer/processPendingAsset/adding \(assetRecord.localIdentifier ?? "(null)") to cluster \(cluster?.id ?? "(null)")")
        assetRecord.macroCluster = cluster
        cluster?.locatedClusterStatus = .pending

        if cluster != nil {
            if isCorePoint {
                DDLogInfo("AssetClusterer/processPendingAsset/Complete, marking \(assetRecord.localIdentifier ?? "(null)") as core")
                assetRecord.macroClusterStatus = .core
            } else {
                DDLogInfo("AssetClusterer/processPendingAsset/Complete, marking \(assetRecord.localIdentifier ?? "(null)") as edge")
                assetRecord.macroClusterStatus = .edge
            }
        } else {
            DDLogInfo("AssetClusterer/processPendingAsset/Complete, marking \(assetRecord.localIdentifier ?? "(null)")) as orphan")
            assetRecord.macroClusterStatus = .orphan
        }
    }

    private class func processDeletedAsset(_ assetRecord: AssetRecord, in context: NSManagedObjectContext) throws {
        guard assetRecord.macroClusterStatus == .deletePending else {
            DDLogInfo("AssetClusterer/processDeletedAsset/attempted to delete already clustered asset")
            return
        }

        DDLogInfo("AssetClusterer/processDeletedAsset/processing \(assetRecord.localIdentifier ?? "(null)")")

        // Only worry about reclustering if part of a cluster, else we can just delete the assetRecord
        guard let existingCluster = assetRecord.macroCluster else {
            DDLogInfo("AssetClusterer/processDeletedAsset/no cluster found, deleting asset \(assetRecord.localIdentifier ?? "(null)")")
            context.delete(assetRecord)
            return
        }

        let existingClusterAssets = existingCluster.assetRecordsAsSet

        var unassignedAssetRecords = existingClusterAssets

        var distinctClusters: [Set<AssetRecord>] = []

        // BFS to see if assetRecords are still connected as a cluster.
        while let initialUnassignedAssetRecord = unassignedAssetRecords.first {
            var visitedAssetRecords: Set<AssetRecord> = []
            var queue: [AssetRecord] = [initialUnassignedAssetRecord]

            while let unassignedAssetRecord = queue.popLast() {
                guard !visitedAssetRecords.contains(unassignedAssetRecord) else {
                    continue
                }

                let adjacentAssets = try Self.sortedClusterableAssetRecords(for: unassignedAssetRecord, in: context)
                let macroClusterStatus: AssetRecord.MacroClusterStatus

                if adjacentAssets.count >= PhotoSuggestionsUtilities.Constants.minClusterableAssetCount {
                    macroClusterStatus = .core
                    queue.append(contentsOf: adjacentAssets)
                } else {
                    macroClusterStatus = .edge
                }
                // Patch macroClusterStatus, which may have changed with the deleted node
                if unassignedAssetRecord.macroClusterStatus != .deletePending, macroClusterStatus != unassignedAssetRecord.macroClusterStatus {
                    DDLogInfo("AssetClusterer/processDeletedAsset/patching asset \(unassignedAssetRecord.localIdentifier ?? "(null)") status to \(macroClusterStatus)")
                    unassignedAssetRecord.macroClusterStatus = macroClusterStatus
                }

                visitedAssetRecords.insert(unassignedAssetRecord)
            }

            distinctClusters.append(visitedAssetRecords)
            unassignedAssetRecords.subtract(visitedAssetRecords)
        }

        let largestDistinctCluster = distinctClusters.max { $0.count > $1.count }
        let largestDistinctClusterHasCoreNode = largestDistinctCluster?.contains { $0.macroClusterStatus == .core } ?? false

        guard let largestDistinctCluster, largestDistinctClusterHasCoreNode else {
            DDLogInfo("AssetClusterer/processDeletedAsset/cluster no longer has core node, deleting cluster \(existingCluster.id ?? "(null)")")
            existingCluster.locatedClustersAsSet.forEach { context.delete($0) }
            context.delete(existingCluster)
            existingClusterAssets
                .filter { $0.macroClusterStatus != .deletePending }
                .forEach { $0.macroClusterStatus = .orphan }
            return
        }

        // Remove assets disjoint from our largest cluster and mark for reclustering
        for assetRecordToUncluster in existingClusterAssets.subtracting(largestDistinctCluster) {
            DDLogInfo("AssetClusterer/processDeletedAsset/asset \(assetRecordToUncluster.localIdentifier ?? "(null)") is removed from cluster and set to pending")
            assetRecordToUncluster.macroClusterStatus = .pending
            assetRecordToUncluster.macroCluster = nil
        }

        existingCluster.locatedClusterStatus = .pending

        DDLogInfo("AssetClusterer/processDeletedAsset/Complete, deleting asset \(assetRecord.localIdentifier ?? "(null)")")
        context.delete(assetRecord)
    }

    private static func sortedClusterableAssetRecords(for assetRecord: AssetRecord, in context: NSManagedObjectContext) throws -> [AssetRecord] {
        guard let creationDate = assetRecord.creationDate else {
            return []
        }

        let maxTimeIntervalForClustering = PhotoSuggestionsUtilities.Constants.maxDistance * PhotoSuggestionsUtilities.Constants.timeNormalizationFactor
        let minDate = creationDate.addingTimeInterval(-maxTimeIntervalForClustering)
        let maxDate = creationDate.addingTimeInterval(maxTimeIntervalForClustering)

        let fetchRequest = AssetRecord.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "%K BETWEEN {%@,%@}", #keyPath(AssetRecord.creationDate), minDate as NSDate, maxDate as NSDate),
            NSPredicate(format: "%K != %ld", #keyPath(AssetRecord.rawMacroClusterStatus), AssetRecord.MacroClusterStatus.deletePending.rawValue),
            NSPredicate(format: "%K != %ld", #keyPath(AssetRecord.rawMacroClusterStatus), AssetRecord.MacroClusterStatus.invalidAssetForClustering.rawValue),
        ])
        fetchRequest.relationshipKeyPathsForPrefetching = [
            #keyPath(AssetRecord.macroCluster)
        ]
        fetchRequest.returnsObjectsAsFaults = false

        let results: [AssetRecord]
        do {
            results = try context.fetch(fetchRequest)
        } catch {
            DDLogError("AssetClusterer/Failed to fetch clusterable assets: \(error)")
            throw error
        }

        // Return all assetRecords within maxDistance, sorted by distance
        return results
            .map { (assetRecord: $0, distance: PhotoSuggestionsUtilities.distance(assetRecord, $0)) }
            .filter { $0.distance < PhotoSuggestionsUtilities.Constants.maxDistance }
            .sorted { $0.distance < $1.distance }
            .map { $0.assetRecord }
    }

    private static func locateChangedClusters(in context: NSManagedObjectContext) {
        let predicate = NSPredicate(format: "%K == %ld", #keyPath(AssetMacroCluster.rawLocatedClusterStatus), AssetMacroCluster.LocatedClusterStatus.pending.rawValue)
        AssetMacroCluster.find(predicate: predicate, in: context).forEach { macroCluster in
            AssetClusterLocator.locateCluster(macroCluster: macroCluster)
        }
    }
}

extension AssetClusterer {

    static func makeService(photoSuggestionsData: PhotoSuggestionsData) -> PhotoSuggestionsService {
        return PhotoSuggestionsSerialService {
            let fetchRequest = AssetRecord.fetchRequest()
            fetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "%K == %ld", #keyPath(AssetRecord.rawMacroClusterStatus), AssetRecord.MacroClusterStatus.pending.rawValue),
                NSPredicate(format: "%K == %ld", #keyPath(AssetRecord.rawMacroClusterStatus), AssetRecord.MacroClusterStatus.deletePending.rawValue),
            ])
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \AssetRecord.creationDate, ascending: false),
            ]
            return PhotoSuggestionsFetchedResultsControllerAsyncSequence(fetchRequest: fetchRequest, photoSuggestionsData: photoSuggestionsData)
        } task: { localIdentifier in
            try? await Self.clusterAsset(localIdentifier: localIdentifier, with: photoSuggestionsData)
        }
    }
}
