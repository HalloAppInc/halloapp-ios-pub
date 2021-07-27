//
//  MediaPickerSnapshotManager.swift
//  HalloApp
//
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import Photos
import UIKit

class MediaPickerSnapshotManager {
    private var assets: PHFetchResult<PHAsset>?
    private var snapshot = NSDiffableDataSourceSnapshot<Int, PHAsset>()
    private var nextIndex = 0
    
    private let pageSize = 400
    private let filter: MediaPickerFilter
    
    init(filter: MediaPickerFilter = .all) {
        self.filter = filter
        snapshot.appendSections([0])
    }
    
    func reset(with assets: PHFetchResult<PHAsset>) {
        snapshot.deleteAllItems()

        snapshot = NSDiffableDataSourceSnapshot<Int, PHAsset>()
        snapshot.appendSections([0])
        nextIndex = 0

        self.assets = assets
    }

    func update(change: PHChange) -> NSDiffableDataSourceSnapshot<Int, PHAsset>? {
        guard let assets = assets else { return nil }
        guard let details = change.changeDetails(for: assets) else { return nil }

        // try keeping at least as many elements in the snapshot as there are now, to avoid scroll jumping
        let limit = max(nextIndex, pageSize)
        reset(with: details.fetchResultAfterChanges)

        return next(limit: limit)
    }
    
    func next(limit: Int? = nil) -> NSDiffableDataSourceSnapshot<Int, PHAsset> {
        guard let assets = assets, assets.count > 0 else { return snapshot }

        let limit = min(limit ?? (nextIndex + pageSize), assets.count)
        for i in nextIndex..<limit {
            guard assets[i].creationDate != nil else { continue }
            guard filter != .image || assets[i].mediaType == .image else { continue }
            guard filter != .video || assets[i].mediaType == .video else { continue }
            snapshot.appendItems([assets[i]])
        }
        
        nextIndex = limit
        
        return snapshot
    }
}
