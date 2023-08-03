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

    private struct Constants {
        static let maxTimeIntervalForClustering: TimeInterval = 12 * 60 * 60 // 12 hours
        static let minClusterableAssetCount = 3
        static let maxDistance: Double = 2
        static let timeNormalizationFactor: TimeInterval = 3 * 60 * 60 // 3 hours
        static let distanceNormalizationFactor: CLLocationDistance = 1000

        // mean shift
        static let meanShiftDistanceNormalizationFactor: CLLocationDistance = 100
        static let convergenceThreshold: CLLocationDistance = 10
    }

    func generateSuggestions() async throws -> [PhotoCluster] {
        var visitedAssetIdentifiers: Set<String> = []
        var clusters: [PhotoCluster] = []

        let recentAssets = Self.queryAssets(start: Date().advanced(by: -30 * 24 * 60 * 60), limit: 1000)

        for recentAssetIndex in 0..<recentAssets.count {
            let asset = recentAssets[recentAssetIndex]

            guard !visitedAssetIdentifiers.contains(asset.localIdentifier) else {
                continue
            }

            var clusterableAssets = Set(Self.clusterableAssets(for: asset, in: recentAssets))

            guard clusterableAssets.count >= Constants.minClusterableAssetCount else {
                continue
            }

            let cluster = PhotoCluster(asset: asset)
            clusters.append(cluster)
            visitedAssetIdentifiers.insert(asset.localIdentifier)

            while let clusterableAsset = clusterableAssets.popFirst() {
                guard !visitedAssetIdentifiers.contains(clusterableAsset.localIdentifier) else {
                    continue
                }

                cluster.add(clusterableAsset)
                visitedAssetIdentifiers.insert(clusterableAsset.localIdentifier)

                let clusterableAssetNeighbors = Self.clusterableAssets(for: clusterableAsset, in: recentAssets)
                if clusterableAssetNeighbors.count > Constants.minClusterableAssetCount {
                    clusterableAssets.formUnion(clusterableAssetNeighbors)
                }
            }
        }

        let locatedClusters = Array(clusters.prefix(20))



        if #available(iOS 14.0, *) {
            return try await withThrowingTaskGroup(of: Array<PhotoCluster>.self) { taskGroup in
                locatedClusters.forEach { cluster in
                    taskGroup.addTask {

                        var clusterMapItems = Set<MKMapItem>()
                        var locatedAssets: [MKMapItem: Set<PHAsset>] = [:]

                        let orderedAssets = Array(cluster.assets.filter { $0.location != nil })

                        let normalizedAssetLocations = Self.meanShiftCluster(locations: orderedAssets.compactMap(\.location))

                        var clusters: [[(PHAsset, CLLocation)]] = []

                        for clusterAsset in zip(orderedAssets, normalizedAssetLocations) {
                            var didCluster = false
                            for i in 0..<clusters.count {
                                var clusteredAssets = clusters[i]
                                if clusteredAssets.contains(where: { $0.1.distance(from: clusterAsset.1) <= Constants.convergenceThreshold }) {
                                    clusteredAssets.append(clusterAsset)
                                    clusters[i] = clusteredAssets
                                    didCluster = true
                                    break
                                }
                            }
                            if !didCluster {
                                clusters.append([clusterAsset])
                            }
                        }

                        var locatedClusters: [MKMapItem: [PHAsset]] = [:]

                        var unmatchedAssets: [PHAsset] = []

                        for cluster in clusters {
                            let clusterCenterCoordinate = cluster
                                .map(\.1.coordinate)
                                .enumerated()
                                .reduce(CLLocationCoordinate2D(latitude: 0, longitude: 0)) { avgCoordinate, i in
                                    let (idx, coordinate) = i
                                    return .init(latitude: avgCoordinate.latitude + (coordinate.latitude - avgCoordinate.latitude) / CLLocationDegrees(idx + 1),
                                                 longitude: avgCoordinate.longitude + (coordinate.longitude - avgCoordinate.longitude) / CLLocationDegrees(idx + 1))
                                }
                            let clusterCenterLocation = CLLocation(latitude: clusterCenterCoordinate.latitude, longitude: clusterCenterCoordinate.longitude)

                            guard cluster.count >= Constants.minClusterableAssetCount else {
                                unmatchedAssets.append(contentsOf: cluster.map(\.0))
                                continue
                            }

                            let existingMapItem = clusterMapItems.min { mapItemA, mapItemB in
                                let locationA = CLLocation(latitude: mapItemA.placemark.coordinate.latitude, longitude: mapItemA.placemark.coordinate.longitude)
                                let locationB = CLLocation(latitude: mapItemB.placemark.coordinate.latitude, longitude: mapItemB.placemark.coordinate.longitude)
                                return locationA.distance(from: clusterCenterLocation) < locationB.distance(from: clusterCenterLocation)
                            }

                            if let existingMapItem, let region = existingMapItem.placemark.region as? CLCircularRegion {
                                let regionLocation = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)

                                if clusterCenterLocation.distance(from: regionLocation) < region.radius * 2 {
                                //if region.contains(clusterCenterLocation) {

                                    var a = locatedClusters[existingMapItem, default: []]
                                    a.append(contentsOf: cluster.map(\.0))
                                    locatedClusters[existingMapItem] = a
                                    continue
                                }
                            }

                            let request = MKLocalPointsOfInterestRequest(center: clusterCenterLocation.coordinate, radius: 200)
                            request.pointOfInterestFilter = MKPointOfInterestFilter(excluding: [.atm, .parking, .evCharger, .restroom])
                            let localSearch = MKLocalSearch(request: request)
                            let response: MKLocalSearch.Response

                            do {
                                response = try await localSearch.start()
                            } catch {
                                print(error)
                                continue
                            }

                            clusterMapItems.formUnion(response.mapItems)

                            let newMapItem = response.mapItems.min { mapItemA, mapItemB in
                                let locationA = CLLocation(latitude: mapItemA.placemark.coordinate.latitude, longitude: mapItemA.placemark.coordinate.longitude)
                                let locationB = CLLocation(latitude: mapItemB.placemark.coordinate.latitude, longitude: mapItemB.placemark.coordinate.longitude)
                                return locationA.distance(from: clusterCenterLocation) < locationB.distance(from: clusterCenterLocation)
                            }

                            if let newMapItem, let region = newMapItem.placemark.region as? CLCircularRegion {
                                let regionLocation = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)

                                if clusterCenterLocation.distance(from: regionLocation) < region.radius * 2 {
                                //if region.contains(clusterCenterLocation) {
                                    var a = locatedClusters[newMapItem, default: []]
                                    a.append(contentsOf: cluster.map(\.0))
                                    locatedClusters[newMapItem] = a
                                    continue
                                }
                            }

                            unmatchedAssets.append(contentsOf: cluster.map(\.0))
                        }

                        // group in unmatched assets

                        unmatchedAssets.forEach { asset in
                            guard let assetLocation = asset.location else {
                                return
                            }

                            let closestMapItem = locatedClusters.keys.min { mapItemA, mapItemB in
                                let locationA = CLLocation(latitude: mapItemA.placemark.coordinate.latitude, longitude: mapItemA.placemark.coordinate.longitude)
                                let locationB = CLLocation(latitude: mapItemB.placemark.coordinate.latitude, longitude: mapItemB.placemark.coordinate.longitude)
                                return locationA.distance(from: assetLocation) < locationB.distance(from: assetLocation)
                            }

                            if let closestMapItem {
                                let distance = assetLocation.distance(from: CLLocation(latitude: closestMapItem.placemark.coordinate.latitude,
                                                                                       longitude: closestMapItem.placemark.coordinate.longitude))

                                if distance < 500 {
                                    var a = locatedClusters[closestMapItem, default: []]
                                    a.append(asset)
                                    locatedClusters[closestMapItem] = a
                                }
                            }
                        }




                        return locatedClusters.map { (mapItem, assets) in
                            let cluster = PhotoCluster(assets: assets)
                            cluster.locationName = mapItem.name
                            return cluster
                        }

                    }
                }
                var clusters: [PhotoCluster] = []
                for try await subcluster in taskGroup {
                    clusters.append(contentsOf: subcluster)
                }
                return clusters
                //try await taskGroup.waitForAll()
            }
        }

        return locatedClusters
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
        guard let creationDateA = assetA.creationDate,
              let creationDateB = assetB.creationDate,
              let locationA = assetA.location,
              let locationB = assetB.location else {
            return false
        }

        let normalizedTimeDistance = abs(creationDateA.timeIntervalSince(creationDateB)) / Constants.timeNormalizationFactor
        let normalizedLocationDistance = locationA.distance(from: locationB) / Constants.distanceNormalizationFactor

        return sqrt(normalizedTimeDistance * normalizedTimeDistance + normalizedLocationDistance * normalizedLocationDistance) <= Constants.maxDistance
    }

    private class func queryAssets(start: Date? = nil, end: Date? = nil, limit: Int? = nil) -> PHFetchResult<PHAsset> {
        var subpredicates: [NSPredicate] = []
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

    private class func averageDistance(mapItem: MKMapItem, assets: any Sequence<PHAsset>) -> CLLocationDistance {
        let assetLocations = assets.compactMap(\.location)
        guard !assetLocations.isEmpty else {
            return .greatestFiniteMagnitude
        }

        let mapItemLocation = CLLocation(latitude: mapItem.placemark.coordinate.latitude, longitude: mapItem.placemark.coordinate.longitude)

        var averageDistance: CLLocationDistance = 0
        for (idx, assetLocation) in assetLocations.enumerated() {
            averageDistance = averageDistance + (mapItemLocation.distance(from: assetLocation) - averageDistance) / CLLocationDistance(idx + 1)
        }

        return averageDistance
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
                let updatedLocation = CLLocation(latitude: shiftedLocation.coordinate.latitude + meanShiftVector.coordinate.latitude,
                                              longitude: shiftedLocation.coordinate.longitude + meanShiftVector.coordinate.longitude)
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
