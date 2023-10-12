//
//  AssetMacroCluster.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/31/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import Core
import CoreData

@objc(AssetMacroCluster)
class AssetMacroCluster: NSManagedObject {

    var assetRecordsAsSet: Set<AssetRecord> {
        return assetRecords as? Set<AssetRecord> ?? []
    }

    var assetRecordCount: Int {
        return assetRecords?.count ?? 0
    }

    func recomputeDates() {
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

extension AssetMacroCluster: IdentifiableManagedObject {

    public static var identifierKeyPath: WritableKeyPath<AssetMacroCluster, String?> {
        return \Self.id
    }
}
