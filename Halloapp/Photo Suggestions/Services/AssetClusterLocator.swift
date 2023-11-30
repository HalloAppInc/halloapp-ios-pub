//
//  AssetClusterLocator.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 11/9/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import CoreData
import CoreLocation
import Foundation

/*
 Given a macrocluster, further divide it into located clusters by dividing based on mean shifting photo locations
 */
final class AssetClusterLocator {

    enum AssetClusterLocatorError: Error {
        case macroClusterNotFound
    }

    private struct Constants {
        static let meanShiftDistanceNormalizationFactor: CLLocationDistance = 100
        static let convergenceThreshold: CLLocationDistance = 5
    }

    private init() {}

    class func locateCluster(macroCluster: AssetMacroCluster) {
        guard let context = macroCluster.managedObjectContext else {
            DDLogError("Attempting to locate cluster with invalid ManagedObjectContext, aborting...")
            return
        }

        var unclusteredAssetRecords: Set<AssetRecord> = []
        var assetsWithLocation: [(location: CLLocation, assetRecord: AssetRecord)] = []

        for assetRecord in macroCluster.assetRecordsAsSet {
            if let location = assetRecord.location {
                assetsWithLocation.append((location, assetRecord))
            } else {
                unclusteredAssetRecords.insert(assetRecord)
            }
        }

        // Group into clusters by mean shifting locations to send to geocoder

        var locatedClusters: [(normalizedLocation: CLLocation?, assetRecords: Set<AssetRecord>)]

        if assetsWithLocation.isEmpty {
            // No location - cluster all assets as a single cluster without location
            locatedClusters = [(nil, unclusteredAssetRecords)]
        } else {
            let normalizedLocations = Self.meanShiftCluster(locations: assetsWithLocation.map(\.location))
            let normalizedAssetsWithLocation = zip(assetsWithLocation, normalizedLocations)
                .map { (assetWithLocation, normalizedLocation) in
                    (normalizedLocation: normalizedLocation, assetRecord: assetWithLocation.assetRecord)
                }

            var clusteredNormalizedAssetRecordLocations: [[(normalizedLocation: CLLocation, assetRecord: AssetRecord)]] = []
            for normalizedAssetWithLocation in normalizedAssetsWithLocation {
                let clusterIndex = clusteredNormalizedAssetRecordLocations.firstIndex { cluster in
                    cluster.contains {
                        $0.normalizedLocation.distance(from: normalizedAssetWithLocation.normalizedLocation) <= 2 * Constants.convergenceThreshold
                    }
                }
                if let clusterIndex {
                    clusteredNormalizedAssetRecordLocations[clusterIndex].append(normalizedAssetWithLocation)
                } else {
                    clusteredNormalizedAssetRecordLocations.append([normalizedAssetWithLocation])
                }
            }

            // Filter out any clusters with < minClusterableAssetCount locations, appends assets to unclusteredAssetRecords
            clusteredNormalizedAssetRecordLocations = clusteredNormalizedAssetRecordLocations.filter { cluster in
                if cluster.count >= PhotoSuggestionsUtilities.Constants.minClusterableAssetCount {
                    return true
                } else {
                    unclusteredAssetRecords.formUnion(cluster.map(\.assetRecord))
                    return false
                }
            }

            if clusteredNormalizedAssetRecordLocations.isEmpty {
                // If we don't have any convergence into clusters, use the average location from any located assets and append all unlocated assets
                let location = Self.averageLocation(unclusteredAssetRecords.compactMap(\.location))
                locatedClusters = [(location, unclusteredAssetRecords)]
            } else {
                var clusters = clusteredNormalizedAssetRecordLocations.map {
                    (normalizedLocation: Self.averageLocation($0.map(\.normalizedLocation)), assetRecords: Set($0.map(\.assetRecord)))
                }

                for unclusteredAssetRecord in unclusteredAssetRecords {
                    var minDistanceClusterIndex: Int?
                    var minDistance: Double = .greatestFiniteMagnitude
                    for (index, cluster) in clusters.enumerated() {
                        for asset in cluster.assetRecords {
                            let distance = PhotoSuggestionsUtilities.distance(unclusteredAssetRecord, asset)
                            if distance < minDistance {
                                minDistanceClusterIndex = index
                                minDistance = distance
                            }
                        }
                    }

                    if let minDistanceClusterIndex, minDistance <= PhotoSuggestionsUtilities.Constants.maxDistance {
                        clusters[minDistanceClusterIndex].assetRecords.insert(unclusteredAssetRecord)
                    }
                }

                locatedClusters = clusters
            }
        }

        // Merge assets back into locatedClusters

        var existingLocatedClusters = Array(macroCluster.locatedClustersAsSet)
        var pendingLocatedClusters = locatedClusters

        // Map existing clusters to new ones to minimize churn.
        // We define distance as the total number of assets already part of the set (ie, the count of the intersection of elements)
        // Use a greedy algorithm as the sizes shouldn't be too large.

        var maxOverlap = Int.min
        while !existingLocatedClusters.isEmpty, !pendingLocatedClusters.isEmpty, maxOverlap > 0 {
            maxOverlap = Int.min
            var existingCluster: AssetLocatedCluster?
            var existingClusterIndex: Int?
            var pendingCluster: (normalizedLocation: CLLocation?, assetRecords: Set<AssetRecord>)?
            var pendingClusterIndex: Int?

            for (existingLocatedClusterIndex, existingLocatedCluster) in existingLocatedClusters.enumerated() {
                for (pendingLocatedClusterIndex, pendingLocatedCluster) in pendingLocatedClusters.enumerated() {
                    let overlap = pendingLocatedCluster.assetRecords.intersection(existingLocatedCluster.assetRecordsAsSet).count
                    if overlap > maxOverlap {
                        maxOverlap = overlap
                        existingCluster = existingLocatedCluster
                        existingClusterIndex = existingLocatedClusterIndex
                        pendingCluster = pendingLocatedCluster
                        pendingClusterIndex = pendingLocatedClusterIndex
                    }
                }
            }

            if let existingCluster, let existingClusterIndex, let pendingCluster, let pendingClusterIndex {
                existingLocatedClusters.remove(at: existingClusterIndex)
                pendingLocatedClusters.remove(at: pendingClusterIndex)


                // Reset location status if we've moved the cluster past Constants.locationInvalidationDistance
                switch (existingCluster.location, pendingCluster.normalizedLocation) {
                case (.some(let existingLocation), .some(let pendingLocation)):
                    if existingLocation.distance(from: pendingLocation) >= PhotoSuggestionsUtilities.Constants.locationInvalidationDistance {
                        existingCluster.locationStatus = .pending
                    }
                case (.none, .some), (.some, .none):
                    existingCluster.locationStatus = .pending
                default:
                    break
                }

                existingCluster.location = pendingCluster.normalizedLocation
                // remove any existing assets no longer part of cluster
                existingCluster.assetRecordsAsSet
                    .filter { !pendingCluster.assetRecords.contains($0) }
                    .forEach {
                        DDLogInfo("AssetClusterLocator/locateAssets/Removing \($0.localIdentifier ?? "<unknown>") from located cluster \(existingCluster.id ?? "<unknown>")")
                        $0.locatedCluster = nil
                    }
                // add any new assets to locatedCluster
                pendingCluster.assetRecords
                    .forEach {
                        if $0.locatedCluster != existingCluster {
                            DDLogInfo("AssetClusterLocator/locateAssets/Adding \($0.localIdentifier ?? "<unknown>") to located cluster \(existingCluster.id ?? "<unknown>")")
                            $0.locatedCluster = existingCluster
                        }
                    }
            }
        }

        // We're not using any of the remaining clusters, delete
        for existingLocatedCluster in existingLocatedClusters {
            DDLogInfo("AssetClusterLocator/locateAssets/Removing located cluster \(existingLocatedCluster.id ?? "<unknown>")")
            context.delete(existingLocatedCluster)
        }

        // If we don't have a matching locatedCluster, create one
        for pendingLocatedCluster in pendingLocatedClusters {
            let cluster = AssetLocatedCluster(context: context)
            cluster.id = UUID().uuidString
            cluster.location = pendingLocatedCluster.normalizedLocation
            pendingLocatedCluster.assetRecords
                .forEach { $0.locatedCluster = cluster }
            cluster.macroCluster = macroCluster
            DDLogInfo("AssetClusterLocator/locateAssets/Creating located cluster \(cluster.id ?? "<unknown>") with assets \(pendingLocatedCluster.assetRecords.compactMap(\.localIdentifier).joined(separator: ", "))")
        }

        macroCluster.locatedClusterStatus = .located
        DDLogInfo("AssetClusterLocator/locateAssets/Marking macrocluster \(macroCluster.id ?? "<unknown>") as located")
    }

    private class func meanShiftCluster(locations: [CLLocation]) -> [CLLocation] {
        var shiftedLocations = locations
        while true {
            var updatedLocations: [CLLocation] = []
            for shiftedLocation in shiftedLocations {
                var numeratorSum = CLLocation(latitude: 0, longitude: 0)
                var denominatorSum: CLLocationDistance = 0

                for originalLocation in locations {
                    let distance = originalLocation.distance(from: shiftedLocation)
                    let weight = exp(-0.5 * pow(distance / Constants.meanShiftDistanceNormalizationFactor, 2))

                    numeratorSum = CLLocation(latitude: numeratorSum.coordinate.latitude + originalLocation.coordinate.latitude * weight,
                                              longitude: numeratorSum.coordinate.longitude + originalLocation.coordinate.longitude * weight)
                    denominatorSum += weight
                }

                // Compute the mean shift vector
                let meanShiftVector = CLLocation(latitude: numeratorSum.coordinate.latitude / denominatorSum,
                                                 longitude: numeratorSum.coordinate.longitude / denominatorSum)
                updatedLocations.append(meanShiftVector)
            }
            // Check for convergence
            var hasConverged = true
            for (point, updatedPoint) in zip(shiftedLocations, updatedLocations) {
                if point.distance(from: updatedPoint) >= Constants.convergenceThreshold {
                    hasConverged = false
                    break
                }
            }

            if hasConverged {
                break
            }

            shiftedLocations = updatedLocations
        }

        return shiftedLocations
    }

    private class func averageLocation(_ locations: [CLLocation]) -> CLLocation {
        let coordinate = locations
            .map(\.coordinate)
            .enumerated()
            .reduce(CLLocationCoordinate2D(latitude: 0, longitude: 0)) { avgCoordinate, i in
                let (idx, coordinate) = i
                return .init(latitude: avgCoordinate.latitude + (coordinate.latitude - avgCoordinate.latitude) / CLLocationDegrees(idx + 1),
                             longitude: avgCoordinate.longitude + (coordinate.longitude - avgCoordinate.longitude) / CLLocationDegrees(idx + 1))
            }
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
