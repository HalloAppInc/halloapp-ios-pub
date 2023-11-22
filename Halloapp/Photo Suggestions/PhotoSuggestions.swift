//
//  PhotoSuggestions.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 7/11/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Contacts
import Core
import CoreCommon
import MapKit
import Photos

class PhotoSuggestions: NSObject {

    class var suggestionsDidChange: Notification.Name {
        return Notification.Name(rawValue: "photoSuggestionsChanged")
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
        static let meanShiftDistanceNormalizationFactor: CLLocationDistance = 100
        static let convergenceThreshold: CLLocationDistance = 5
    }

    private var recentAssets: PHFetchResult<PHAsset> = PHFetchResult()

    private var previousPersistentChangeToken: AnyObject?

    private var cachedSuggestions: [PhotoCluster]?

    private var currentTask: Task<[PhotoCluster], Error>?

    private var cancellables = Set<AnyCancellable>()

    private var hasRegisteredChangeObserver = false

    override init() {
        super.init()

        NotificationCenter.default.publisher(for: PhotoPermissionsHelper.photoAuthorizationDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                registerChangeObserverIfNeeded()
                resetFetchedPhotos()
                
            }
            .store(in: &cancellables)

        registerChangeObserverIfNeeded()
        resetFetchedPhotos()
    }

    private func registerChangeObserverIfNeeded() {
        let shouldRegister = PhotoPermissionsHelper.authorizationStatus(for: .readWrite).hasAnyAuthorization

        guard shouldRegister != hasRegisteredChangeObserver else {
            return
        }

        if shouldRegister {
            PHPhotoLibrary.shared().register(self)
        } else {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }

        hasRegisteredChangeObserver = shouldRegister
    }

    var hasLocationsForPhotos: Bool {
        var hasLocation = false
        var hasAnyAsset = false
        recentAssets.enumerateObjects { asset, _, stop in
            guard Self.isValidAsset(asset) else {
                return
            }
            hasAnyAsset = true
            if asset.location != nil {
                hasLocation = true
                stop.pointee = true
            }
        }
        return hasAnyAsset && hasLocation
    }

    func resetFetchedPhotos() {
        guard PhotoPermissionsHelper.authorizationStatus(for: .readWrite).hasAnyAuthorization else {
            let hadCachedSuggestions = cachedSuggestions != nil
            cachedSuggestions = nil
            recentAssets = PHFetchResult()
            if hadCachedSuggestions {
                NotificationCenter.default.post(name: Self.suggestionsDidChange, object: self)
            }
            return
        }

        let updatedAssets = PhotoSuggestions.queryAssets(start: Date().advanced(by: -90 * 24 * 60 * 60), limit: 1000)

        var currentAssetIDs: Set<String> = []
        var previousAssetIDs: Set<String> = []
        recentAssets.enumerateObjects { asset, _, _ in
            previousAssetIDs.insert(asset.localIdentifier)
        }
        updatedAssets.enumerateObjects { asset, _, _ in
            currentAssetIDs.insert(asset.localIdentifier)
        }

        guard currentAssetIDs != previousAssetIDs else {
            return
        }

        self.cachedSuggestions = nil
        recentAssets = updatedAssets

        NotificationCenter.default.post(name: Self.suggestionsDidChange, object: self)
    }

    func generateSuggestions() async throws -> [PhotoCluster] {
        // Dedup requests
        if let currentTask {
            return try await currentTask.value
        } else {
            let task = Task {
                try await generateSuggestionsInternal()
            }
            currentTask = task
            let result = try await task.value
            currentTask = nil
            return result
        }
    }

    private func generateSuggestionsInternal() async throws -> [PhotoCluster] {
        if let cachedSuggestions {
            DDLogInfo("PhotoSuggestions/generateSuggestions/returning from cache")
            return cachedSuggestions
        }

        let generateSuggestionsStartDate = Date()

        var visitedAssetIdentifiers: Set<String> = []
        var macroClusters: [[PHAsset]] = []

        var filteredAssets: [PHAsset] = []
        recentAssets.enumerateObjects { asset, _, _ in
            if Self.isValidAsset(asset) {
                filteredAssets.append(asset)
            }
        }

        DDLogInfo("PhotoSuggestions/generateSuggestions/Clustering \(filteredAssets.count) photos...")

        // Sanity checks on photos
        guard !filteredAssets.isEmpty else {
            return []
        }

        // DBSCAN to create macroclusters
        for asset in filteredAssets {
            guard !visitedAssetIdentifiers.contains(asset.localIdentifier) else {
                continue
            }

            var clusterableAssets = Set(Self.clusterableAssets(for: asset, in: filteredAssets))

            guard clusterableAssets.count >= Constants.minClusterableAssetCount - 1 else {
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

                let clusterableAssetNeighbors = Self.clusterableAssets(for: clusterableAsset, in: filteredAssets)
                if clusterableAssetNeighbors.count >= Constants.minClusterableAssetCount - 1 {
                    clusterableAssets.formUnion(clusterableAssetNeighbors)
                }
            }

            macroClusters.append(cluster)
        }

        DDLogInfo("PhotoSuggestions/generateSuggestions/Found \(macroClusters.count) macroClusters (max \(Constants.maxMacroclusters))")

        // Parallelize clustering and geocoding each macrocluster
        let clusters = try await withThrowingTaskGroup(of: Array<PhotoCluster>.self) { taskGroup in
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
                                $0.normalizedLocation.distance(from: normalizedLocation) <= 2 * Constants.convergenceThreshold
                            }
                        }
                        if let idx {
                            clusteredAssetsWithNormalizedLocation[idx].append((asset, normalizedLocation))
                        } else {
                            clusteredAssetsWithNormalizedLocation.append([(asset, normalizedLocation)])
                        }
                    }

                    // Geocode clusters
                    var locatedClusters: [(location: PhotoClusterLocation?, assets: [PHAsset])] = []
                    for cluster in clusteredAssetsWithNormalizedLocation {
                        guard cluster.count >= Constants.minClusterableAssetCount else {
                            unclusteredAssets.append(contentsOf: cluster.map(\.asset))
                            continue
                        }

                        let clusterLocation = Self.averageLocation(cluster.map(\.normalizedLocation))

                        do {
                            let reverseGeocodeLocation = try await MainAppContext.shared.geocoder.reverseGeocode(location: clusterLocation)
                            locatedClusters.append((reverseGeocodeLocation, cluster.map(\.asset)))
                        } catch {
                            DDLogError("PhotoSuggestions/generateSuggestions/error geocoding cluster: \(error)")
                            locatedClusters.append((nil, cluster.map(\.asset)))
                        }
                    }

                    DDLogInfo("PhotoSuggestions/generateSuggestions/Found \(locatedClusters.count) located clusters, \(unclusteredAssets.count) remaining assets")

                    // Unable to find a location, just return the macrocluster
                    guard !locatedClusters.isEmpty else {
                        return [PhotoCluster(assets: unclusteredAssets)]
                    }

                    for unclusteredAsset in unclusteredAssets {
                        var minDistanceClusterIndex: Int?
                        var minDistance: Double = .greatestFiniteMagnitude
                        for (index, locatedCluster) in locatedClusters.enumerated() {
                            for asset in locatedCluster.assets {
                                let distance = Self.distance(unclusteredAsset, asset)
                                if distance < minDistance {
                                    minDistanceClusterIndex = index
                                    minDistance = distance
                                }
                            }
                        }

                        if let minDistanceClusterIndex, minDistance <= Constants.maxDistance {
                            locatedClusters[minDistanceClusterIndex].assets.append(unclusteredAsset)
                        }
                    }

                    return locatedClusters.map { (location, assets) in
                        let photoCluster = PhotoCluster(assets: assets)
                        photoCluster.location = location
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

        DDLogInfo("PhotoSuggestions/generateSuggestions/Completed with \(clusters.count) clusters in \(-generateSuggestionsStartDate.timeIntervalSinceNow) sec")

        cachedSuggestions = clusters

        return clusters
    }

    private class func clusterableAssets(for asset: PHAsset, in assets: [PHAsset]) -> [PHAsset] {
        return assets.filter { nearbyAsset in
            return nearbyAsset != asset && shouldCluster(asset, nearbyAsset)
        }
    }

    private class func distance(_ assetA: PHAsset, _ assetB: PHAsset) -> Double {
        guard let creationDateA = assetA.creationDate, let creationDateB = assetB.creationDate else {
            return .greatestFiniteMagnitude
        }

        let normalizedTimeDistance = abs(creationDateA.timeIntervalSince(creationDateB)) / Constants.timeNormalizationFactor

        if let locationA = assetA.location, let locationB = assetB.location {
            let normalizedLocationDistance = locationA.distance(from: locationB) / Constants.distanceNormalizationFactor
            return sqrt(normalizedTimeDistance * normalizedTimeDistance + normalizedLocationDistance * normalizedLocationDistance)
        } else {
            return normalizedTimeDistance
        }
    }

    private class func shouldCluster(_ assetA: PHAsset, _ assetB: PHAsset) -> Bool {
        return distance(assetA, assetB) <= Constants.maxDistance
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

    private class func isValidAsset(_ asset: PHAsset) -> Bool {
        // PHAsset fetches do not accurately query mediaSubtypes, filter after the fetch
        return asset.mediaSubtypes != [] && asset.mediaSubtypes.isDisjoint(with: [.photoScreenshot, .photoAnimated, .videoScreenRecording])
    }
}

extension PhotoSuggestions: PHPhotoLibraryChangeObserver {
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let changeDetails = changeInstance.changeDetails(for: recentAssets) else {
            return
        }

        var currentAssetIDs: Set<String> = []
        var previousAssetIDs: Set<String> = []
        changeDetails.fetchResultBeforeChanges.enumerateObjects { asset, _, _ in
            previousAssetIDs.insert(asset.localIdentifier)
        }
        changeDetails.fetchResultAfterChanges.enumerateObjects { asset, _, _ in
            currentAssetIDs.insert(asset.localIdentifier)
        }

        if currentAssetIDs != previousAssetIDs {
            recentAssets = changeDetails.fetchResultAfterChanges
            cachedSuggestions = nil
            NotificationCenter.default.post(name: Self.suggestionsDidChange, object: self)
        }
    }
}

extension PhotoSuggestions {

    class PhotoCluster: Hashable {

        private(set) var start: Date
        private(set) var end: Date
        private(set) var assets: Set<PHAsset>
        fileprivate(set) var location: PhotoClusterLocation?

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

        var newPostState: NewPostState {
            get async {
                let (scoreSortedAssets, assetInfo) = await BurstAwareHighlightSelector().selectHighlights(10, from: Array(assets))
                let selectedMedia = scoreSortedAssets.prefix(ServerProperties.maxPostMediaItems).compactMap { PendingMedia(asset: $0) }
                let createdAtSortedAssets = assets.sorted { $0.creationDate ?? .distantFuture < $1.creationDate ?? .distantFuture }
                let albumTitle = location?.name ?? location?.address ?? Localizations.suggestionAlbumTitle
                let highlightedAssetCollection = PHAssetCollection.transientAssetCollection(with: createdAtSortedAssets, title: albumTitle)
                return NewPostState(pendingMedia: selectedMedia,
                                    mediaSource: .library,
                                    pendingInput: MentionInput(text: location?.name ?? "", mentions: MentionRangeMap(), selectedRange: NSRange()),
                                    highlightedAssetCollection: highlightedAssetCollection,
                                    mediaAssetInfo: assetInfo)
            }
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

struct PhotoClusterLocation: Hashable {
    let location: CLLocation
    let name: String
    let address: String?

    init(name: String, location: CLLocation, address: String?) {
        self.location = location
        self.name = name
        self.address = address
    }

    init?(placemark: CLPlacemark) {
        guard let name = placemark.name, let location = placemark.location else {
            return nil
        }
        self.name = name
        self.location = location
        self.address = placemark.postalAddress.flatMap { CNPostalAddressFormatter.string(from: $0, style: .mailingAddress) }
    }

    init?(mapItem: MKMapItem) {
        guard let name = mapItem.name, let location = mapItem.placemark.location else {
            return nil
        }
        self.name = name
        self.location = location
        self.address = mapItem.placemark.postalAddress.flatMap { CNPostalAddressFormatter.string(from: $0, style: .mailingAddress) }
    }
}

extension Localizations {

    static var suggestionAlbumTitle: String {
        NSLocalizedString("photoSuggestions.album.title", value: "Suggested", comment: "fallback title for suggested photo album")
    }
}
