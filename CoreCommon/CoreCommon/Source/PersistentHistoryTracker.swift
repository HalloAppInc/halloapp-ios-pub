//
//  PersistentHistoryTracker.swift
//  Core
//
//  Created by Murali Balusu on 5/11/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//
// [Reference: https://www.avanderlee.com/swift/persistent-history-tracking-core-data/]

import Foundation
import CoreData
import CocoaLumberjackSwift

public enum AppTarget: String, CaseIterable {
    case mainApp
    case shareExtension
    case notificationExtension
}

public enum DataStore: String {
    case mainDataStore
    case keyStore
    case notificationStore
}


extension UserDefaults {

    func lastHistoryTransactionTimestamp(for target: AppTarget, dataStore: DataStore) -> Date? {
        let key = "lastHistoryTransactionTimeStamp-\(dataStore.rawValue)-\(target.rawValue)"
        return object(forKey: key) as? Date
    }

    public func updateLastHistoryTransactionTimestamp(for target: AppTarget, dataStore: DataStore, to newValue: Date?) {
        let key = "lastHistoryTransactionTimeStamp-\(dataStore.rawValue)-\(target.rawValue)"
        set(newValue, forKey: key)
    }

    func lastCommonTransactionTimestamp(in targets: [AppTarget], dataStore: DataStore) -> Date? {
        let timestamp = targets
            .map { lastHistoryTransactionTimestamp(for: $0, dataStore: dataStore) ?? .distantPast }
            .min() ?? .distantPast
        return timestamp > .distantPast ? timestamp : nil
    }
}

public struct PersistentHistoryMerger {

    let backgroundContext: NSManagedObjectContext
    let currentTarget: AppTarget
    let dataStore: DataStore
    let viewContext: NSManagedObjectContext
    let userDefaults: UserDefaults

    public init(backgroundContext: NSManagedObjectContext, viewContext: NSManagedObjectContext, dataStore: DataStore, userDefaults: UserDefaults, currentTarget: AppTarget) {
        self.backgroundContext = backgroundContext
        self.currentTarget = currentTarget
        self.dataStore = dataStore
        self.viewContext = viewContext
        self.userDefaults = userDefaults
    }

    public func merge() throws -> Bool {
        let fromDate = userDefaults.lastHistoryTransactionTimestamp(for: currentTarget, dataStore: dataStore) ?? .distantPast
        let fetcher = PersistentHistoryFetcher(context: backgroundContext, fromDate: fromDate)
        let history = try fetcher.fetch()

        guard !history.isEmpty else {
            DDLogInfo("PersistentHistoryMerger/dataStore: \(dataStore)/No history transactions found to merge for target \(currentTarget)")
            return false
        }
        DDLogInfo("PersistentHistoryMerger/dataStore: \(dataStore)/Merging \(history.count) transactions for target \(currentTarget)")
        // Merges the current collection of history transactions into the managed object context.
        history.forEach { transaction in
            guard let userInfo = transaction.objectIDNotification().userInfo else { return }
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: userInfo, into: [backgroundContext, viewContext])
        }

        guard let lastTimestamp = history.last?.timestamp else { return false }
        userDefaults.updateLastHistoryTransactionTimestamp(for: currentTarget, dataStore: dataStore, to: lastTimestamp)
        return true
    }
}

struct PersistentHistoryFetcher {

    enum Error: Swift.Error {
        // In case that the fetched history transactions couldn't be converted into the expected type.
        case historyTransactionConversionFailed
    }

    let context: NSManagedObjectContext
    let fromDate: Date

    func fetch() throws -> [NSPersistentHistoryTransaction] {
        let fetchRequest = createFetchRequest()

        guard let historyResult = try context.execute(fetchRequest) as? NSPersistentHistoryResult, let history = historyResult.result as? [NSPersistentHistoryTransaction] else {
            throw Error.historyTransactionConversionFailed
        }
        return history
    }

    func createFetchRequest() -> NSPersistentHistoryChangeRequest {
        let historyFetchRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: fromDate)

        if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
            var predicates: [NSPredicate] = []
            if let transactionAuthor = context.transactionAuthor {
                // Only look at transactions created by other targets.
                predicates.append(NSPredicate(format: "%K != %@", #keyPath(NSPersistentHistoryTransaction.author), transactionAuthor))
            }
            if let contextName = context.name {
                // Only look at transactions not from our current context.
                predicates.append(NSPredicate(format: "%K != %@", #keyPath(NSPersistentHistoryTransaction.contextName), contextName))
            }
            fetchRequest.predicate = NSCompoundPredicate(type: .and, subpredicates: predicates)
            historyFetchRequest.fetchRequest = fetchRequest
        }
        return historyFetchRequest
    }
}

public struct PersistentHistoryCleaner {

    let context: NSManagedObjectContext
    let targets: [AppTarget]
    let dataStore: DataStore
    let userDefaults: UserDefaults

    public init(context: NSManagedObjectContext, targets: [AppTarget], dataStore: DataStore, userDefaults: UserDefaults) {
        self.context = context
        self.targets = targets
        self.dataStore = dataStore
        self.userDefaults = userDefaults
    }

    // Cleans up the persistent history by deleting the transactions that have been merged into each target.
    public func clean() throws {
        guard let timestamp = userDefaults.lastCommonTransactionTimestamp(in: targets, dataStore: dataStore) else {
            DDLogInfo("PersistentHistoryCleaner/dataStore: \(dataStore)/Cancelling deletions as there is no common transaction timestamp")
            return
        }

        let deleteHistoryRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: timestamp)
        DDLogInfo("PersistentHistoryCleaner/dataStore: \(dataStore)/Deleting persistent history using common timestamp \(timestamp)")
        try context.execute(deleteHistoryRequest)

        targets.forEach { target in
            // Reset the dates as we would otherwise end up in an infinite loop.
            userDefaults.updateLastHistoryTransactionTimestamp(for: target, dataStore: dataStore, to: nil)
        }
    }
}
