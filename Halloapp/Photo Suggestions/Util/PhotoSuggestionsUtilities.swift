//
//  AssetClusterUtilities.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 11/16/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import Core
import CoreLocation
import Photos

class PhotoSuggestionsUtilities {

    struct Constants {
        static let minClusterableAssetCount = 3

        // dbscan macroclustering
        static let maxDistance: Double = 2
        static let timeNormalizationFactor: TimeInterval = 3 * 60 * 60 // 3 hours
        static let distanceNormalizationFactor: CLLocationDistance = 1000

        static let locationInvalidationDistance: CLLocationDistance = 5
    }

    static func distance(_ assetRepresentationA: AssetRecord, _ assetRepresentationB: AssetRecord) -> Double {
        guard let creationDateA = assetRepresentationA.creationDate, let creationDateB = assetRepresentationB.creationDate else {
            return .greatestFiniteMagnitude
        }

        let normalizedTimeDistance = abs(creationDateA.timeIntervalSince(creationDateB)) / Constants.timeNormalizationFactor

        if let locationA = assetRepresentationA.location, let locationB = assetRepresentationB.location {
            let normalizedLocationDistance = locationA.distance(from: locationB) / Constants.distanceNormalizationFactor
            return sqrt(normalizedTimeDistance * normalizedTimeDistance + normalizedLocationDistance * normalizedLocationDistance)
        } else {
            return normalizedTimeDistance
        }
    }

    static func assets(with localIdentifiers: [String], options: PHFetchOptions? = nil) -> [PHAsset] {
        var assets: [PHAsset] = []
        PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: options).enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    static func newPostState(assetLocalIdentifiers: [String], postText: String?, albumTitle: String) async -> NewPostState {
        let assets = Self.assets(with: assetLocalIdentifiers)
        let (scoreSortedAssets, mediaAssetInfo) = await BurstAwareHighlightSelector().selectHighlights(10, from: Array(assets))
        let selectedMedia = scoreSortedAssets.prefix(ServerProperties.maxPostMediaItems).compactMap { PendingMedia(asset: $0) }
        let createdAtSortedAssets = assets.sorted { $0.creationDate ?? .distantFuture < $1.creationDate ?? .distantFuture }
        let highlightedAssetCollection = PHAssetCollection.transientAssetCollection(with: createdAtSortedAssets, title: albumTitle)
        return NewPostState(pendingMedia: selectedMedia,
                            mediaSource: .library,
                            pendingInput: MentionInput(text: postText ?? "", mentions: MentionRangeMap(), selectedRange: NSRange()),
                            highlightedAssetCollection: highlightedAssetCollection,
                            mediaAssetInfo: mediaAssetInfo)


    }
}
