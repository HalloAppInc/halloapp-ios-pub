//
//  AssetRecord.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/31/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import Core
import CoreData
import CoreLocation
import Photos

@objc(AssetRecord)
class AssetRecord: NSManagedObject {

    enum MacroClusterStatus: Int16 {
        case pending = 0
        case core = 1
        case edge = 2
        case orphan = 3
        case deletePending = 4
        case invalidAssetForClustering = 5
    }

    var macroClusterStatus: MacroClusterStatus {
        get {
            return MacroClusterStatus(rawValue: rawMacroClusterStatus) ?? .pending
        }
        set {
            rawMacroClusterStatus = newValue.rawValue
        }
    }

    var mediaType: PHAssetMediaType {
        get {
            return PHAssetMediaType(rawValue: Int(rawMediaType)) ?? .unknown
        }
        set {
            rawMediaType = Int32(newValue.rawValue)
        }
    }

    var mediaSubtypes: PHAssetMediaSubtype {
        get {
            return PHAssetMediaSubtype(rawValue: UInt(rawMediaSubtypes))
        }
        set  {
            rawMediaSubtypes = Int32(newValue.rawValue)
        }
    }

    var location: CLLocation? {
        get {
            guard latitude != 0 || longitude != 0 else {
                return nil
            }
            return CLLocation(latitude: latitude, longitude: longitude)
        }
        set {
            latitude = newValue?.coordinate.latitude ?? 0
            longitude = newValue?.coordinate.longitude ?? 0
        }
    }

    // Try to use batched requests vs this property if querying many assets
    var asset: PHAsset? {
        return localIdentifier.flatMap {
            PHAsset.fetchAssets(withLocalIdentifiers: [$0], options: nil).firstObject
        }
    }

    func update(asset: PHAsset) {
        if creationDate != asset.creationDate {
            creationDate = asset.creationDate
        }
        if localIdentifier != asset.localIdentifier {
            localIdentifier = asset.localIdentifier
        }
        if location != asset.location {
            location = asset.location
        }
        if mediaType != asset.mediaType {
            mediaType = asset.mediaType
        }
        if mediaSubtypes != asset.mediaSubtypes {
            mediaSubtypes = asset.mediaSubtypes
        }
    }
}

extension AssetRecord: IdentifiableManagedObject {

    public static var identifierKeyPath: WritableKeyPath<AssetRecord, String?> {
        return \Self.localIdentifier
    }
}
