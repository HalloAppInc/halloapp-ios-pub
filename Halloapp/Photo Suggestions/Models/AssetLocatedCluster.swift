//
//  AssetLocatedCluster.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 11/9/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import Core
import CoreData
import CoreLocation

@objc(AssetLocatedCluster)
class AssetLocatedCluster: NSManagedObject {

    var assetRecordsAsSet: Set<AssetRecord> {
        return assetRecords as? Set<AssetRecord> ?? []
    }

    enum LocationStatus: Int16 {
        case pending = 0
        case located = 1
        case failed = 2
        case noLocation = 3
    }

    var locationStatus: LocationStatus {
        get {
            return LocationStatus(rawValue: rawLocationStatus) ?? .pending
        }
        set {
            rawLocationStatus = newValue.rawValue
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
            if let newValue {
                latitude = newValue.coordinate.latitude
                longitude = newValue.coordinate.longitude
            } else {
                latitude = 0
                longitude = 0
            }
        }
    }

    var geocodedLocation: CLLocation? {
        get {
            guard geocodedLatitude != 0 || geocodedLongitude != 0 else {
                return nil
            }
            return CLLocation(latitude: geocodedLatitude, longitude: geocodedLongitude)
        }
        set {
            if let newValue {
                geocodedLatitude = newValue.coordinate.latitude
                geocodedLongitude = newValue.coordinate.longitude
            } else {
                geocodedLatitude = 0
                geocodedLongitude = 0
            }
        }
    }

    private func recomputeDates() {
        var startDate: Date?
        var endDate: Date?
        assetRecordsAsSet.forEach { asset in
            guard let creationDate = asset.creationDate else {
                return
            }
            startDate = min(creationDate, startDate ?? .distantFuture)
            endDate = max(creationDate, endDate ?? .distantPast)
        }
        if self.startDate != startDate {
            self.startDate = startDate
        }
        if self.endDate != endDate {
            self.endDate = endDate
        }
    }

    override func willSave() {
        super.willSave()

        if id?.isEmpty ?? true {
            id = UUID().uuidString
        }

        recomputeDates()
    }
}

extension AssetLocatedCluster: IdentifiableManagedObject {

    static var identifierKeyPath: WritableKeyPath<AssetLocatedCluster, String?> {
        return \.id
    }
}
