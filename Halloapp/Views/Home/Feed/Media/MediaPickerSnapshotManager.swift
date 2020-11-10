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
    private var snapshot = NSDiffableDataSourceSnapshot<Int, PickerItem>()
    
    private let pageSize = 400
    private let formatDay = DateFormatter()
    private let formatDayYear = DateFormatter()
    private let formatMonth = DateFormatter()
    private let formatMonthYear = DateFormatter()
    private let filter: MediaPickerFilter
    
    private var nextIndex = 0
    private var thisYear = Calendar.current.component(.year, from: Date())
    private var currentYear = -1
    private var currentDay = -1
    private var currentMonth = -1
    private var itemsInMonth = 0
    private var itemsInDay = 0
    
    init(filter: MediaPickerFilter = .all) {
        self.filter = filter

        formatDay.locale = Locale.current
        formatDay.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        formatDayYear.locale = Locale.current
        formatDayYear.setLocalizedDateFormatFromTemplate("EEEE, MMM d, YYYY")
        formatMonth.locale = Locale.current
        formatMonth.setLocalizedDateFormatFromTemplate("MMMM")
        formatMonthYear.locale = Locale.current
        formatMonthYear.setLocalizedDateFormatFromTemplate("MMMM YYYY")
        
        snapshot.appendSections([0])
    }
    
    func reset(with assets: PHFetchResult<PHAsset>) {
        snapshot.deleteAllItems()
        snapshot.appendSections([0])
        
        self.assets = assets
        
        nextIndex = 0
        thisYear = Calendar.current.component(.year, from: Date())
        currentYear = -1
        currentDay = -1
        currentMonth = -1
        itemsInMonth = 0
        itemsInDay = 0
    }

    func update(change: PHChange) -> NSDiffableDataSourceSnapshot<Int, PickerItem>? {
        guard let assets = assets else { return nil }
        guard let details = change.changeDetails(for: assets) else { return nil }

        let limit = nextIndex
        reset(with: details.fetchResultAfterChanges)

        return next(limit: limit)
    }
    
    func next(limit: Int? = nil) -> NSDiffableDataSourceSnapshot<Int, PickerItem> {
        guard let assets = assets, assets.count > 0 else { return snapshot }

        let limit = min(limit ?? (nextIndex + pageSize), assets.count)
        for i in nextIndex..<limit {
            guard let date = assets[i].creationDate else { continue }
            guard filter != .image || assets[i].mediaType == .image else { continue }
            guard filter != .video || assets[i].mediaType == .video else { continue }
            
            let year = Calendar.current.component(.year, from: date)
            let month = Calendar.current.component(.month, from: date)
            let day = Calendar.current.component(.day, from: date)
            
            if year != currentYear || month != currentMonth {
                appendDayPlaceholders()
                appendMonthPlaceholders()
                
                itemsInMonth = 0
                itemsInDay = 0
                
                appendMonthLabel(date: date)
                appendDayLabel(date: date)
            } else if day != currentDay {
                appendDayPlaceholders()
                appendDayLargePlaceholders()
                
                itemsInDay = 0
                
                appendDayLabel(date: date)
            }

            snapshot.appendItems([PickerItem(asset: assets[i], indexInMonth: itemsInMonth, indexInDay: itemsInDay)])
            itemsInMonth += 1
            itemsInDay += 1
            
            currentYear = year
            currentMonth = month
            currentDay = day
        }
        
        nextIndex = limit
        
        return snapshot
    }
    
    private func appendMonthLabel(date: Date) {
        if thisYear == currentYear {
            snapshot.appendItems([PickerItem(type: .month, label: formatMonth.string(from: date))])
        } else {
            snapshot.appendItems([PickerItem(type: .month, label: formatMonthYear.string(from: date))])
        }
    }
    
    private func appendDayLabel(date: Date) {
        if thisYear == currentYear {
            snapshot.appendItems([PickerItem(type: .day, label: formatDay.string(from: date))])
        } else {
            snapshot.appendItems([PickerItem(type: .day, label: formatDayYear.string(from: date))])
        }
    }
    
    private func appendDayLargePlaceholders() {
        let itemsInLastBlock = itemsInDay % 5
        if itemsInLastBlock == 1 {
            snapshot.appendItems(makeHolders(type: .placeholderDayLarge, count: 1, indexInMonth: itemsInMonth, indexInDay: itemsInDay))
        } else if 2 < itemsInLastBlock {
            snapshot.appendItems(makeHolders(type: .placeholderDayLarge, count: 5 - itemsInLastBlock, indexInMonth: itemsInMonth, indexInDay: itemsInDay))
        }
    }
    
    private func appendDayPlaceholders() {
        if (itemsInDay % 4) > 0 {
            snapshot.appendItems(makeHolders(type: .placeholderDay, count: 4 - itemsInDay % 4, indexInMonth: itemsInMonth, indexInDay: itemsInDay))
        }
    }
    
    private func appendMonthPlaceholders() {
        if (itemsInMonth % 5) > 0 {
            snapshot.appendItems(makeHolders(type: .placeholderMonth, count: 5 - itemsInMonth % 5, indexInMonth: itemsInMonth, indexInDay: itemsInDay))
        }
    }
    
    private func makeHolders(type: PickerItemType, count: Int, indexInMonth: Int, indexInDay: Int) -> [PickerItem] {
        var result = [PickerItem]()
        
        for j in 0..<count {
            result.append(PickerItem(type: type, indexInMonth: indexInMonth + j, indexInDay: indexInDay + j))
        }
        
        return result
    }
}
