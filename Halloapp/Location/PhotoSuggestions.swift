//
//  PhotoSuggestions.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 7/11/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import MapKit
import Photos

class PhotoSuggestions: NSObject {

    enum PhotoSuggestionsError: Error {
        case noPhotoLocations
        case noPhotos
    }

    private struct Constants {
        // dbscan macroclustering
        static let maxTimeIntervalForClustering: TimeInterval = 12 * 60 * 60 // 12 hours
        static let minClusterableAssetCount = 3
        static let maxDistance: Double = 2
        static let timeNormalizationFactor: TimeInterval = 3 * 60 * 60 // 3 hours
        static let distanceNormalizationFactor: CLLocationDistance = 1000

        // mean shift location clustering
        static let maxMacroclusters = 20
        static let meanShiftDistanceNormalizationFactor: CLLocationDistance = 75
        static let convergenceThreshold: CLLocationDistance = 10
    }

    func generateSuggestions() async throws -> [PhotoCluster] {
        var visitedAssetIdentifiers: Set<String> = []
        var macroClusters: [[PHAsset]] = []

        let recentAssets = Self.queryAssets(start: Date().advanced(by: -30 * 24 * 60 * 60), limit: 1000)

        // Sanity checks on photos
        if recentAssets.count == 0 {
            throw PhotoSuggestionsError.noPhotos
        }

        // DBSCAN to create macroclusters
        for recentAssetIndex in 0..<recentAssets.count {
            let asset = recentAssets[recentAssetIndex]

            guard !visitedAssetIdentifiers.contains(asset.localIdentifier) else {
                continue
            }

            var clusterableAssets = Set(Self.clusterableAssets(for: asset, in: recentAssets))

            guard clusterableAssets.count >= Constants.minClusterableAssetCount else {
                continue
            }

            var cluster = [asset]
            visitedAssetIdentifiers.insert(asset.localIdentifier)

            while let clusterableAsset = clusterableAssets.popFirst() {
                guard !visitedAssetIdentifiers.contains(clusterableAsset.localIdentifier) else {
                    continue
                }

                cluster.append(clusterableAsset)
                visitedAssetIdentifiers.insert(clusterableAsset.localIdentifier)

                let clusterableAssetNeighbors = Self.clusterableAssets(for: clusterableAsset, in: recentAssets)
                if clusterableAssetNeighbors.count > Constants.minClusterableAssetCount {
                    clusterableAssets.formUnion(clusterableAssetNeighbors)
                }
            }

            macroClusters.append(cluster)
        }

        // Parallelize clustering and geocoding each macrocluster
        return try await withThrowingTaskGroup(of: Array<PhotoCluster>.self) { taskGroup in
            for assets in macroClusters.prefix(Constants.maxMacroclusters) {
                taskGroup.addTask {
                    var assetsWithLocation: [PHAsset] = []
                    var assetLocations: [CLLocation] = []
                    var unclusteredAssets: [PHAsset] = []

                    for asset in assets {
                        if let location = asset.location {
                            assetsWithLocation.append(asset)
                            assetLocations.append(location)
                        } else {
                            unclusteredAssets.append(asset)
                        }
                    }

                    // If we don't have any assets with location, just use the macrocluster
                    guard !assetsWithLocation.isEmpty else {
                        return [PhotoCluster(assets: unclusteredAssets)]
                    }

                    // Group into clusters by mean shifting locations to send to geocoder
                    var clusteredAssetsWithNormalizedLocation: [[(asset: PHAsset, normalizedLocation: CLLocation)]] = []
                    for (asset, normalizedLocation) in zip(assetsWithLocation, Self.meanShiftCluster(locations: assetLocations)) {
                        let idx = clusteredAssetsWithNormalizedLocation.firstIndex { cluster in
                            cluster.contains {
                                $0.normalizedLocation.distance(from: normalizedLocation) <= Constants.convergenceThreshold
                            }
                        }
                        if let idx {
                            clusteredAssetsWithNormalizedLocation[idx].append((asset, normalizedLocation))
                        } else {
                            clusteredAssetsWithNormalizedLocation.append([(asset, normalizedLocation)])
                        }
                    }

                    // Geocode clusters
                    var locatedClusters: [PhotoClusterLocation: [PHAsset]] = [:]
                    for cluster in clusteredAssetsWithNormalizedLocation {
                        guard cluster.count >= Constants.minClusterableAssetCount else {
                            unclusteredAssets.append(contentsOf: cluster.map(\.asset))
                            continue
                        }

                        let clusterLocation = Self.averageLocation(cluster.map(\.normalizedLocation))

                        let reverseGeocodeLocation = try? await AppleGeocoder.shared.reverseGeocode(location: clusterLocation)

                        if let reverseGeocodeLocation {
                            locatedClusters[reverseGeocodeLocation] = cluster.map(\.asset)
                        } else {
                            unclusteredAssets.append(contentsOf: cluster.map(\.asset))
                        }
                    }

                    // Unable to find a location, just return the macrocluster
                    guard !locatedClusters.isEmpty else {
                        return [PhotoCluster(assets: unclusteredAssets)]
                    }

                    // Group in unclustered assets
                    let locationsByAssetCreationDate = locatedClusters.reduce(into: [:]) { partialResult, element in
                        element.value.compactMap(\.creationDate).forEach {
                            partialResult[$0] = element.key
                        }
                    }

                    for asset in unclusteredAssets {
                        let closestLocation: PhotoClusterLocation?

                        if let location = asset.location {
                            // if the asset has a location, group into the closest located cluster
                            closestLocation = locatedClusters.keys.min {
                                location.distance(from: $0.location) < location.distance(from: $1.location)
                            }
                        } else if let creationDate = asset.creationDate {
                            // asset only has a time, group into cluster containing the closest asset by time
                            closestLocation = locationsByAssetCreationDate.min {
                                abs($0.key.timeIntervalSince(creationDate)) <= abs($1.key.timeIntervalSince(creationDate))
                            }?.value
                        } else {
                            closestLocation = nil
                        }

                        if let closestLocation {
                            locatedClusters[closestLocation]?.append(asset)
                        }
                    }

                    return locatedClusters.map { (location, assets) in
                        let photoCluster = PhotoCluster(assets: assets)
                        photoCluster.locationName = location.name
                        return photoCluster
                    }
                }
            }

            var clusters: [PhotoCluster] = []
            for try await subcluster in taskGroup {
                clusters.append(contentsOf: subcluster)
            }
            return clusters
        }
    }

    private class func clusterableAssets(for asset: PHAsset, in fetchResult: PHFetchResult<PHAsset>) -> [PHAsset] {
        var clusterableAssets: [PHAsset] = []
        fetchResult.enumerateObjects { nearbyAsset, _, _ in
            if nearbyAsset != asset, shouldCluster(asset, nearbyAsset) {
                clusterableAssets.append(nearbyAsset)
            }
        }

        return clusterableAssets
    }

    private class func shouldCluster(_ assetA: PHAsset, _ assetB: PHAsset) -> Bool {
        guard let creationDateA = assetA.creationDate, let creationDateB = assetB.creationDate else {
            return false
        }

        let normalizedTimeDistance = abs(creationDateA.timeIntervalSince(creationDateB)) / Constants.timeNormalizationFactor

        if let locationA = assetA.location, let locationB = assetB.location {
            let normalizedLocationDistance = locationA.distance(from: locationB) / Constants.distanceNormalizationFactor
            return sqrt(normalizedTimeDistance * normalizedTimeDistance + normalizedLocationDistance * normalizedLocationDistance) <= Constants.maxDistance
        } else {
            return normalizedTimeDistance <= Constants.maxDistance
        }
    }

    private class func queryAssets(start: Date? = nil, end: Date? = nil, limit: Int? = nil) -> PHFetchResult<PHAsset> {
        var subpredicates: [NSPredicate] = [
            NSPredicate(format: "mediaSubtype != %ld", PHAssetMediaSubtype.photoScreenshot.rawValue),
            NSPredicate(format: "mediaSubtype != %ld", PHAssetMediaSubtype.photoAnimated.rawValue),
            NSPredicate(format: "mediaSubtype != %ld", PHAssetMediaSubtype.videoScreenRecording.rawValue),
        ]
        if let start {
            subpredicates.append(NSPredicate(format: "creationDate >= %@", start as NSDate))
        }
        if let end {
            subpredicates.append(NSPredicate(format: "creationDate <= %@", end as NSDate))
        }

        let options = PHFetchOptions()
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        options.sortDescriptors = [NSSortDescriptor(keyPath: \PHAsset.creationDate, ascending: false)]

        if let limit {
            options.fetchLimit = limit
        }

        return PHAsset.fetchAssets(with: options)
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

extension PhotoSuggestions {

    class PhotoCluster: Hashable {

        private(set) var start: Date
        private(set) var end: Date
        private(set) var assets: Set<PHAsset>
        fileprivate(set) var locationName: String?

        var center: CLLocation {
            let coordinate = assets
                .compactMap(\.location)
                .map(\.coordinate)
                .enumerated()
                .reduce(CLLocationCoordinate2D(latitude: 0, longitude: 0)) { avgCoordinate, i in
                    let (idx, coordinate) = i
                    return .init(latitude: avgCoordinate.latitude + (coordinate.latitude - avgCoordinate.latitude) / CLLocationDegrees(idx + 1),
                                 longitude: avgCoordinate.longitude + (coordinate.longitude - avgCoordinate.longitude) / CLLocationDegrees(idx + 1))
                }
            return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }

        var coordinateRegion: MKCoordinateRegion? {
            let rect: MKMapRect? = assets
                .compactMap(\.location)
                .reduce(nil) { partialResult, location in
                    let locationRegion = MKCoordinateRegion(center: location.coordinate,
                                                            latitudinalMeters: location.verticalAccuracy,
                                                            longitudinalMeters: location.horizontalAccuracy)
                    if let partialResult {
                        return partialResult.union(locationRegion.mapRect)
                    } else {
                        return locationRegion.mapRect
                    }
                }

            return rect.flatMap { MKCoordinateRegion($0) }
        }

        fileprivate init(asset: PHAsset) {
            start = asset.creationDate ?? .distantFuture
            end = asset.creationDate ?? .distantPast
            assets = [asset]
        }

        fileprivate init(assets: any Sequence<PHAsset>) {
            start = assets.compactMap(\.creationDate).min() ?? .distantFuture
            end =  assets.compactMap(\.creationDate).max() ?? .distantPast
            self.assets = Set(assets)
        }

        fileprivate func add(_ asset: PHAsset) {
            if let creationDate = asset.creationDate {
                start = min(start, creationDate)
                end = max(end, creationDate)
            }
            assets.insert(asset)
        }

        static func == (lhs: PhotoSuggestions.PhotoCluster, rhs: PhotoSuggestions.PhotoCluster) -> Bool {
            return lhs.assets == rhs.assets
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(assets)
        }
    }
}

extension CLCircularRegion {

    func contains(_ location: CLLocation) -> Bool {
        let regionLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return regionLocation.distance(from: location) < radius + sqrt(pow(location.horizontalAccuracy, 2) + pow(location.verticalAccuracy, 2)) + 100
    }
}

extension MKCoordinateRegion {

    var mapRect: MKMapRect {
        let topLeft = MKMapPoint(.init(latitude: center.latitude + span.latitudeDelta / 2, longitude: center.longitude - span.longitudeDelta / 2))
        let bottomRight = MKMapPoint(.init(latitude: center.latitude - span.latitudeDelta / 2, longitude: center.longitude + span.longitudeDelta / 2))
        return MKMapRect(origin: topLeft, size: MKMapSize(width: fabs(bottomRight.x - topLeft.x), height: fabs(bottomRight.y - topLeft.y)))
    }
}

extension PHAssetMediaSubtype {
    static let photoAnimated = PHAssetMediaSubtype(rawValue: 1 << 6)
    static let videoScreenRecording = PHAssetMediaSubtype(rawValue: 1 << 15)
}

struct PhotoClusterLocation: Hashable {
    var location: CLLocation
    var name: String

    init?(placemark: CLPlacemark) {
        guard let name = placemark.name, let location = placemark.location else {
            return nil
        }
        self.name = name
        self.location = location
    }

    init?(mapItem: MKMapItem) {
        guard let name = mapItem.name, let location = mapItem.placemark.location else {
            return nil
        }
        self.name = name
        self.location = location
    }
}
