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
import CocoaLumberjack

public enum AppTarget: String, CaseIterable {
    case mainApp
    case shareExtension
    case notificationExtension
}


extension UserDefaults {

    func lastHistoryTransactionTimestamp(for target: AppTarget) -> Date? {
        let key = "lastHistoryTransactionTimeStamp-\(target.rawValue)"
        return object(forKey: key) as? Date
    }

    func updateLastHistoryTransactionTimestamp(for target: AppTarget, to newValue: Date?) {
        let key = "lastHistoryTransactionTimeStamp-\(target.rawValue)"
        set(newValue, forKey: key)
    }

    func lastCommonTransactionTimestamp(in targets: [AppTarget]) -> Date? {
        let timestamp = targets
            .map { lastHistoryTransactionTimestamp(for: $0) ?? .distantPast }
            .min() ?? .distantPast
        return timestamp > .distantPast ? timestamp : nil
    }
}

struct PersistentHistoryMerger {

    let backgroundContext: NSManagedObjectContext
    let currentTarget: AppTarget

    func merge() throws -> Bool {
        let fromDate = UserDefaults.shared.lastHistoryTransactionTimestamp(for: currentTarget) ?? .distantPast
        let fetcher = PersistentHistoryFetcher(context: backgroundContext, fromDate: fromDate)
        let history = try fetcher.fetch()

        guard !history.isEmpty else {
            DDLogInfo("PersistentHistoryMerger/No history transactions found to merge for target \(currentTarget)")
            return false
        }
        DDLogInfo("PersistentHistoryMerger/Merging \(history.count) transactions for target \(currentTarget)")
        // Merges the current collection of history transactions into the managed object context.
        history.forEach { transaction in
            guard let userInfo = transaction.objectIDNotification().userInfo else { return }
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: userInfo, into: [backgroundContext])
        }

        guard let lastTimestamp = history.last?.timestamp else { return false }
        UserDefaults.shared.updateLastHistoryTransactionTimestamp(for: currentTarget, to: lastTimestamp)
        return true
    }
}

struct PersistentHistoryFetcher {

    enum Error: Swift.Error {
        // In case that the fetched history transactions couldn't be converted into the expected type.
        case historyTransactionConvertionFailed
    }

    let context: NSManagedObjectContext
    let fromDate: Date

    func fetch() throws -> [NSPersistentHistoryTransaction] {
        let fetchRequest = createFetchRequest()

        guard let historyResult = try context.execute(fetchRequest) as? NSPersistentHistoryResult, let history = historyResult.result as? [NSPersistentHistoryTransaction] else {
            throw Error.historyTransactionConvertionFailed
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

struct PersistentHistoryCleaner {

    let context: NSManagedObjectContext
    let targets: [AppTarget]

    // Cleans up the persistent history by deleting the transactions that have been merged into each target.
    func clean() throws {
        guard let timestamp = UserDefaults.shared.lastCommonTransactionTimestamp(in: targets) else {
            DDLogInfo("PersistentHistoryCleaner/Cancelling deletions as there is no common transaction timestamp")
            return
        }

        let deleteHistoryRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: timestamp)
        DDLogInfo("PersistentHistoryCleaner/Deleting persistent history using common timestamp \(timestamp)")
        try context.execute(deleteHistoryRequest)

        targets.forEach { target in
            // Reset the dates as we would otherwise end up in an infinite loop.
            UserDefaults.shared.updateLastHistoryTransactionTimestamp(for: target, to: nil)
        }
    }
}
