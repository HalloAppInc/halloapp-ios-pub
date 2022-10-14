//
//  CryptoData.swift
//  HalloApp
//
//  Created by Garrett on 3/17/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CoreCommon
import CocoaLumberjackSwift
import CoreData
import Foundation

public enum CryptoResult {
    case success
    case failure
}

public final class CryptoData {
    public init(persistentStoreURL: URL) {
        self.persistentStoreURL = persistentStoreURL
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
    }

    public func update(messageID: String, timestamp: Date, result: String, rerequestCount: Int, sender: UserAgent, contentType: DecryptionReportContentType) {
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }
            guard let messageDecryption = self.fetchMessageDecryption(id: messageID, in: managedObjectContext) ??
                    self.createMessageDecryption(id: messageID, timestamp: timestamp, sender: sender, in: managedObjectContext) else
            {
                DDLogError("CryptoData/update/\(messageID)/error could not find or create decryption report")
                return
            }
            guard !messageDecryption.hasBeenReported else {
                DDLogInfo("CryptoData/update/\(messageID)/skipping already reported")
                return
            }
            guard !messageDecryption.isSuccess() else {
                DDLogInfo("CryptoData/update/\(messageID)/skipping already decrypted")
                return
            }
            guard !messageDecryption.isMissingFromAuthor() else {
                DDLogInfo("CryptoData/update/\(messageID)/skipping already missing from author")
                return
            }
            guard let timeReceived = messageDecryption.timeReceived, timeReceived.timeIntervalSinceNow > -self.deadline else {
                DDLogInfo("CryptoData/update/\(messageID)/skipping past deadline")
                return
            }
            messageDecryption.rerequestCount = Int32(rerequestCount)
            messageDecryption.decryptionResult = result
            messageDecryption.timeDecrypted = result == "success" ? Date() : nil
            // TODO: Delete this field from coredata
            messageDecryption.isSilent = false
            messageDecryption.contentType = contentType.rawValue

            if managedObjectContext.hasChanges {
                do {
                    try managedObjectContext.save()
                    DDLogInfo("CryptoData/update/\(messageID)/saved [\(result)]")
                } catch {
                    DDLogError("CryptoData/update/\(messageID)/save/error [\(error)]")
                }
            }
        }
    }

    public func resetFeedHistory(groupID: String, timestamp: Date, numExpected: Int) {
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }
            guard let groupFeedHistoryDecryption = self.fetchGroupFeedHistoryDecryption(groupID: groupID, in: managedObjectContext) ??
                    self.createGroupFeedHistoryDecryption(groupID: groupID, timestamp: timestamp, in: managedObjectContext) else
            {
                DDLogError("CryptoData/resetFeedHistory/\(groupID)/error could not find or create decryption report")
                return
            }
            groupFeedHistoryDecryption.groupID = groupID
            groupFeedHistoryDecryption.timeReceived = timestamp
            groupFeedHistoryDecryption.userAgentReceiver = AppContext.userAgent
            groupFeedHistoryDecryption.hasBeenReported = false
            groupFeedHistoryDecryption.numExpected = Int32(numExpected)
            groupFeedHistoryDecryption.numDecrypted = 0
            groupFeedHistoryDecryption.timeLastUpdated = Date()
            if managedObjectContext.hasChanges {
                do {
                    try managedObjectContext.save()
                    DDLogInfo("CryptoData/resetFeedHistory/\(groupID)/saved numExpected: [\(numExpected)]")
                } catch {
                    DDLogError("CryptoData/resetFeedHistory/\(groupID)/save/error [\(error)]")
                }
            }
        }
    }

    public func receivedFeedHistoryItems(groupID: String, timestamp: Date, newlyDecrypted: Int, newRerequests: Int) {
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }
            guard let groupFeedHistoryDecryption = self.fetchGroupFeedHistoryDecryption(groupID: groupID, in: managedObjectContext) ??
                    self.createGroupFeedHistoryDecryption(groupID: groupID, timestamp: timestamp, in: managedObjectContext) else
            {
                DDLogError("CryptoData/receivedFeedHistoryItems/\(groupID)/error could not find or create decryption report")
                return
            }
            let totalNumDecrypted = groupFeedHistoryDecryption.numDecrypted + Int32(newlyDecrypted)
            let totalRerequestCount = groupFeedHistoryDecryption.rerequestCount + Int32(newRerequests)
            guard totalNumDecrypted > groupFeedHistoryDecryption.numDecrypted || totalRerequestCount > groupFeedHistoryDecryption.rerequestCount  else {
                DDLogInfo("CryptoData/receivedFeedHistoryItems/\(groupID)/skipping no change in numDecrypted -or- totalRerequestCount")
                return
            }
            groupFeedHistoryDecryption.groupID = groupID
            groupFeedHistoryDecryption.userAgentReceiver = AppContext.userAgent
            groupFeedHistoryDecryption.hasBeenReported = false
            groupFeedHistoryDecryption.numDecrypted = totalNumDecrypted
            groupFeedHistoryDecryption.rerequestCount = totalRerequestCount
            groupFeedHistoryDecryption.timeLastUpdated = timestamp
            if managedObjectContext.hasChanges {
                do {
                    try managedObjectContext.save()
                    DDLogInfo("CryptoData/receivedFeedHistoryItems/\(groupID)/saved numDecrypted: [\(totalNumDecrypted)]")
                } catch {
                    DDLogError("CryptoData/receivedFeedHistoryItems/\(groupID)/save/error [\(error)]")
                }
            }
        }
    }

    public func update(contentID: String, contentType: GroupDecryptionReportContentType, groupID: GroupID, timestamp: Date, error: String, sender: UserAgent?, rerequestCount: Int) {
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }

            let isItemAlreadyDecrypted: Bool
            let isItemMissingFromAuthor: Bool
            if let itemResult = self.fetchGroupFeedItemDecryption(id: contentID, in: managedObjectContext) {
                isItemAlreadyDecrypted = itemResult.isSuccess()
                isItemMissingFromAuthor = itemResult.isMissingFromAuthor()
            } else {
                isItemAlreadyDecrypted = false
                isItemMissingFromAuthor = false
            }
            guard let groupFeedItemDecryption = self.fetchGroupFeedItemDecryption(id: contentID, in: managedObjectContext) ??
                    self.createGroupFeedItemDecryption(id: contentID, contentType: contentType, groupID: groupID, timestamp: timestamp, sender: sender, in: managedObjectContext) else
            {
                DDLogError("CryptoData/update/\(contentID)/group/\(groupID)/error could not find or create decryption report")
                return
            }
            guard !isItemAlreadyDecrypted else {
                DDLogInfo("CryptoData/update/\(contentID)/group/\(groupID)/skipping already decrypted")
                return
            }
            guard !isItemMissingFromAuthor else {
                DDLogInfo("CryptoData/update/\(contentID)/group/\(groupID)/skipping already missing from author")
                return
            }
            groupFeedItemDecryption.rerequestCount = Int32(rerequestCount)
            groupFeedItemDecryption.decryptionError = error
            groupFeedItemDecryption.timeDecrypted = error == "" ? Date() : nil
            // If error is empty - then mark the item as not reported, so that client reports this stat to server again.
            if error.isEmpty {
                groupFeedItemDecryption.hasBeenReported = false
            }
            if managedObjectContext.hasChanges {
                do {
                    try managedObjectContext.save()
                    DDLogInfo("CryptoData/update/\(contentID)/group/\(groupID)/saved [\(error)]")
                } catch {
                    DDLogError("CryptoData/update/\(contentID)/group/\(groupID)/save/error [\(error)]")
                }
            }
        }
    }

    public func update(contentID: String, contentType: HomeDecryptionReportContentType, audienceType: HomeDecryptionReportAudienceType, timestamp: Date, error: String, sender: UserAgent?, rerequestCount: Int) {
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }

            let isItemAlreadyDecrypted: Bool
            let isItemMissingFromAuthor: Bool
            if let itemResult = self.fetchHomeFeedItemDecryption(id: contentID, in: managedObjectContext) {
                isItemAlreadyDecrypted = itemResult.isSuccess()
                isItemMissingFromAuthor = itemResult.isMissingFromAuthor()
            } else {
                isItemAlreadyDecrypted = false
                isItemMissingFromAuthor = false
            }
            guard let homeFeedItemDecryption = self.fetchHomeFeedItemDecryption(id: contentID, in: managedObjectContext) ??
                    self.createHomeFeedItemDecryption(id: contentID, contentType: contentType, audienceType: audienceType, timestamp: timestamp, sender: sender, in: managedObjectContext) else
            {
                DDLogError("CryptoData/update/\(contentID)/audienceType: \(audienceType)/error could not find or create decryption report")
                return
            }
            guard !isItemAlreadyDecrypted else {
                DDLogInfo("CryptoData/update/\(contentID)/audienceType: \(audienceType)/skipping already decrypted")
                return
            }
            guard !isItemMissingFromAuthor else {
                DDLogInfo("CryptoData/update/\(contentID)/audienceType: \(audienceType)/skipping already missing from author")
                return
            }
            homeFeedItemDecryption.rerequestCount = Int32(rerequestCount)
            homeFeedItemDecryption.decryptionError = error
            homeFeedItemDecryption.timeDecrypted = error == "" ? Date() : nil
            // If error is empty - then mark the item as not reported, so that client reports this stat to server again.
            if error.isEmpty {
                homeFeedItemDecryption.hasBeenReported = false
            }
            if managedObjectContext.hasChanges {
                do {
                    try managedObjectContext.save()
                    DDLogInfo("CryptoData/update/\(contentID)/audienceType: \(audienceType)/saved [\(error)]")
                } catch {
                    DDLogError("CryptoData/update/\(contentID)/audienceType: \(audienceType)/save/error [\(error)]")
                }
            }
        }
    }

    public func generateReport(markEventsReported: Bool = true, using managedObjectContext: NSManagedObjectContext) -> [DiscreteEvent] {
        let messageFetchRequest: NSFetchRequest<MessageDecryption> = MessageDecryption.fetchRequest()
        messageFetchRequest.predicate = NSPredicate(format: "hasBeenReported == false")
        messageFetchRequest.returnsObjectsAsFaults = false

        let groupFeedItemFetchRequest: NSFetchRequest<GroupFeedItemDecryption> = GroupFeedItemDecryption.fetchRequest()
        groupFeedItemFetchRequest.predicate = NSPredicate(format: "hasBeenReported == false")
        groupFeedItemFetchRequest.returnsObjectsAsFaults = false

        let homeFeedItemFetchRequest: NSFetchRequest<HomeFeedItemDecryption> = HomeFeedItemDecryption.fetchRequest()
        homeFeedItemFetchRequest.predicate = NSPredicate(format: "hasBeenReported == false")
        homeFeedItemFetchRequest.returnsObjectsAsFaults = false

        let groupFeedHistoryFetchRequest: NSFetchRequest<GroupFeedHistoryDecryption> = GroupFeedHistoryDecryption.fetchRequest()
        groupFeedHistoryFetchRequest.predicate = NSPredicate(format: "hasBeenReported == false")
        groupFeedHistoryFetchRequest.returnsObjectsAsFaults = false

        do {

            // Message decryption events.
            let messageUnreportedEvents = try managedObjectContext.fetch(messageFetchRequest)
            let messageReadyEvents = messageUnreportedEvents.filter { $0.isReadyToBeReported(withDeadline: deadline) }
            DDLogInfo("CryptoData/generateReport-message [\(messageReadyEvents.count) ready of \(messageUnreportedEvents.count) unreported]")

            // GroupFeedItem decryption events.
            let groupUnreportedEvents = try managedObjectContext.fetch(groupFeedItemFetchRequest)
            let groupReadyEvents = groupUnreportedEvents.filter { $0.isReadyToBeReported(withDeadline: deadline) }
            DDLogInfo("CryptoData/generateReport-group [\(groupReadyEvents.count) ready of \(groupUnreportedEvents.count) unreported]")

            // GroupHistory report decryption events.
            let groupHistoryUnreportedEvents = try managedObjectContext.fetch(groupFeedHistoryFetchRequest)
            let groupHistoryReadyEvents = groupHistoryUnreportedEvents.filter { $0.isReadyToBeReported(withDeadline: deadline) }
            DDLogInfo("CryptoData/generateReport-groupHistory [\(groupHistoryReadyEvents.count) ready of \(groupHistoryUnreportedEvents.count) unreported]")

            // HomeFeed decryption events.
            let homeFeedUnreportedEvents = try managedObjectContext.fetch(homeFeedItemFetchRequest)
            let homeFeedReadyEvents = homeFeedUnreportedEvents.filter { $0.isReadyToBeReported(withDeadline: deadline) }
            DDLogInfo("CryptoData/generateReport-home [\(homeFeedReadyEvents.count) ready of \(homeFeedUnreportedEvents.count) unreported]")

            if markEventsReported {
                if !messageReadyEvents.isEmpty {
                    markDecryptionsAsReported(messageReadyEvents.map { $0.objectID })
                }
                if !groupReadyEvents.isEmpty {
                    markGroupDecryptionsAsReported(groupReadyEvents.map { $0.objectID })
                }
                if !groupHistoryReadyEvents.isEmpty {
                    markGroupFeedHistoryDecryptionsAsReported(groupHistoryReadyEvents.map { $0.objectID })
                }
                if !homeFeedReadyEvents.isEmpty {
                    markHomeDecryptionsAsReported(homeFeedReadyEvents.map { $0.objectID })
                }
            }

            return messageReadyEvents.compactMap { $0.report(deadline: deadline) } + groupReadyEvents.compactMap { $0.report(deadline: deadline) } + homeFeedReadyEvents.compactMap { $0.report(deadline: deadline) }
        }
        catch {
            DDLogError("CryptoData/generateReport/error \(error)")
            return []
        }
    }

    public func startReporting(interval: TimeInterval, reportEvents: @escaping ([DiscreteEvent]) -> Void) {
        guard reportTimer == nil else {
            DDLogError("CryptoData/startReporting/error already-reporting")
            return
        }
        DDLogInfo("CryptoData/startReporting/starting [interval=\(interval)]")
        reportTimer = DispatchSource.makeTimerSource(flags: [], queue: .main)
        reportTimer?.setEventHandler(handler: { [weak self] in
            guard let self = self else { return }
            let events = self.generateReport(using: self.viewContext)
            if events.isEmpty {
                DDLogInfo("CryptoData/reportTimer/skipping [no events]")
            } else {
                DDLogInfo("CryptoData/reportTimer/reporting [\(events.count) events]")
                reportEvents(events)
            }
        })
        reportTimer?.schedule(deadline: .now(), repeating: interval)
        reportTimer?.resume()
    }

    // TODO: we should make this result an enum.
    public func result(for messageID: String, in managedObjectContext: NSManagedObjectContext) -> String? {
        return fetchMessageDecryption(id: messageID, in: managedObjectContext)?.decryptionResult
    }

    public func cryptoResult(for contentID: String, in managedObjectContext: NSManagedObjectContext) -> CryptoResult? {
        if let error = fetchGroupFeedItemDecryption(id: contentID, in: managedObjectContext)?.decryptionError {
            return error.isEmpty ? .success : .failure
        } else if let error = fetchHomeFeedItemDecryption(id: contentID, in: managedObjectContext)?.decryptionError {
            return error.isEmpty ? .success : .failure
        } else {
            return nil
        }
    }

    public func details(for messageID: String, dateFormatter: DateFormatter, in managedObjectContext: NSManagedObjectContext) -> String? {
        guard let decryption = fetchMessageDecryption(id: messageID, in: managedObjectContext) else {
            DDLogInfo("CryptoData/details/\(messageID)/not-found")
            return nil
        }

        var lines = ["Decryption Info [Internal]"]
        if let result = decryption.decryptionResult {
            lines.append("Result: \(result)")
        }
        lines.append("Rerequests: \(decryption.rerequestCount)")
        if let timeReceived = decryption.timeReceived {
            lines.append("Received: \(dateFormatter.string(from: timeReceived))")
        }
        if let timeDecrypted = decryption.timeDecrypted {
            lines.append("Decrypted: \(dateFormatter.string(from: timeDecrypted))")
        }
        // NB: A bug in 1.4.108 caused messages to be prematurely marked as reported
        lines.append("Reported: \(decryption.hasBeenReported)")

        return lines.joined(separator: "\n")
    }

    // Used to migrate old database from main app storage into shared container.
    public func integrateEarlierResults(from oldDatabase: CryptoData, completion: (() -> Void)? = nil) {
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }

            var oldDecryptions: [MessageDecryption] = []
            oldDatabase.performOnBackgroundContextAndWait { oldManagedObjectContext in
                oldDecryptions = oldDatabase.fetchAllMessageDecryptions(in: oldManagedObjectContext)
            }

            for oldDecryption in oldDecryptions {
                let messageID = oldDecryption.messageID
                if let newDecryption = self.fetchMessageDecryption(id: messageID, in: managedObjectContext) {
                    DDLogInfo("CryptoData/integrateEarlierResults/\(messageID)/updating")
                    // Prefer original decryption timestamp and user agent
                    newDecryption.timeReceived = oldDecryption.timeReceived ?? newDecryption.timeReceived
                    newDecryption.userAgentSender = oldDecryption.userAgentSender ?? newDecryption.userAgentSender
                    newDecryption.userAgentReceiver = oldDecryption.userAgentSender ?? newDecryption.userAgentReceiver

                    // Mark hasBeenReported if either has been reported
                    newDecryption.hasBeenReported = oldDecryption.hasBeenReported || newDecryption.hasBeenReported
                } else if let newDecryption = NSEntityDescription.insertNewObject(forEntityName: "MessageDecryption", into: managedObjectContext) as? MessageDecryption {
                    DDLogInfo("CryptoData/integrateEarlierResults/\(messageID)/copying")
                    // Copy all values from original decryption
                    newDecryption.messageID = oldDecryption.messageID
                    newDecryption.timeReceived = oldDecryption.timeReceived
                    newDecryption.userAgentSender = oldDecryption.userAgentSender
                    newDecryption.userAgentReceiver = oldDecryption.userAgentReceiver
                    newDecryption.hasBeenReported = oldDecryption.hasBeenReported
                    newDecryption.decryptionResult = oldDecryption.decryptionResult
                    newDecryption.rerequestCount = oldDecryption.rerequestCount
                    newDecryption.timeDecrypted = oldDecryption.timeDecrypted
                    newDecryption.isSilent = oldDecryption.isSilent
                } else {
                    DDLogError("CryptoData/integrateEarlierResults/\(messageID)/error [copy failure]")
                }
            }
            if managedObjectContext.hasChanges {
                do {
                    try managedObjectContext.save()
                    DDLogInfo("CryptoData/integrateEarlierResults/saved [\(oldDecryptions.count)]")
                } catch {
                    DDLogError("CryptoData/integrateEarlierResults/save/error [\(error)]")
                }
            } else {
                DDLogInfo("CryptoData/integrateEarlierResults/no-updates")
            }
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    public func destroyStore() {
        let coordinator = self.persistentContainer.persistentStoreCoordinator
        do {
            let stores = coordinator.persistentStores
            stores.forEach { (store) in
                do {
                    try coordinator.remove(store)
                    DDLogError("CryptoData/destroy/remove-store/finished [\(store)]")
                }
                catch {
                    DDLogError("CryptoData/destroy/remove-store/error [\(error)]")
                }
            }

            try coordinator.destroyPersistentStore(at: persistentStoreURL, ofType: NSSQLiteStoreType, options: nil)
            try FileManager.default.removeItem(at: persistentStoreURL)
            DDLogInfo("CryptoData/destroy/delete-store/complete")
        }
        catch {
            DDLogError("CryptoData/destroy/delete-store/error [\(error)]")
        }
    }

    // MARK: Private

    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.crypto-stats")
    private let persistentStoreURL: URL
    private let deadline = TimeInterval(86400) // 24*60*60, 24 hour deadline

    private var reportTimer: DispatchSourceTimer?

    public var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    private lazy var persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: persistentStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let modelURL = Bundle(for: KeyStore.self).url(forResource: "CryptoStats", withExtension: "momd")!
        let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL)
        let container = NSPersistentContainer(name: "CryptoStats", managedObjectModel: managedObjectModel!)
        container.persistentStoreDescriptions = [ storeDescription ]
        container.loadPersistentStores(completionHandler: { (description, error) in
            if let error = error {
                DDLogError("Failed to load persistent store: \(error)")
                fatalError("Unable to load persistent store: \(error)")
            } else {
                DDLogInfo("CryptoData/load-store/completed [\(description)]")
            }
        })
        return container
    }()

    private func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return context
    }

    public func performSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        backgroundProcessingQueue.async { [weak self] in
            guard let self = self else { return }

            let context = self.newBackgroundContext()
            context.performAndWait {
                block(context)
            }
        }
    }

    public func performOnBackgroundContextAndWait(_ block: (NSManagedObjectContext) -> Void) {
        backgroundProcessingQueue.sync {
            let context = self.newBackgroundContext()
            context.performAndWait {
                block(context)
            }
        }
    }

    public func fetchMessageDecryption(id: String, in context: NSManagedObjectContext) -> MessageDecryption? {
        let fetchRequest: NSFetchRequest<MessageDecryption> = MessageDecryption.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "messageID == %@", id)
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let results = try context.fetch(fetchRequest)
            if results.count > 1 {
                DDLogError("CryptoData/fetch/\(id)/error multiple-results [\(results.count) found]")
            }
            return results.first
        }
        catch {
            DDLogError("CryptoData/fetch/\(id)/error \(error)")
            return nil
        }
    }

    public func fetchHomeFeedItemDecryption(id: String, in context: NSManagedObjectContext) -> HomeFeedItemDecryption? {
        let fetchRequest: NSFetchRequest<HomeFeedItemDecryption> = HomeFeedItemDecryption.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "contentID == %@", id)
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let results = try context.fetch(fetchRequest)
            if results.count > 1 {
                DDLogError("CryptoData/fetchHomeFeedItemDecryption/\(id)/error multiple-results [\(results.count) found]")
            }
            return results.first
        }
        catch {
            DDLogError("CryptoData/fetchHomeFeedItemDecryption/\(id)/error \(error)")
            return nil
        }
    }

    public func fetchGroupFeedItemDecryption(id: String, in context: NSManagedObjectContext) -> GroupFeedItemDecryption? {
        let fetchRequest: NSFetchRequest<GroupFeedItemDecryption> = GroupFeedItemDecryption.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "contentID == %@", id)
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let results = try context.fetch(fetchRequest)
            if results.count > 1 {
                DDLogError("CryptoData/fetchGroupFeedItemDecryption/\(id)/error multiple-results [\(results.count) found]")
            }
            return results.first
        }
        catch {
            DDLogError("CryptoData/fetchGroupFeedItemDecryption/\(id)/error \(error)")
            return nil
        }
    }

    public func fetchGroupFeedHistoryDecryption(groupID: String, in context: NSManagedObjectContext) -> GroupFeedHistoryDecryption? {
        let fetchRequest: NSFetchRequest<GroupFeedHistoryDecryption> = GroupFeedHistoryDecryption.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "groupID == %@", groupID)
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let results = try context.fetch(fetchRequest)
            if results.count > 1 {
                DDLogError("CryptoData/fetchGroupFeedHistoryDecryption/\(groupID)/error multiple-results [\(results.count) found]")
            }
            return results.first
        }
        catch {
            DDLogError("CryptoData/fetchGroupFeedHistoryDecryption/\(groupID)/error \(error)")
            return nil
        }
    }

    private func fetchAllMessageDecryptions(in context: NSManagedObjectContext) -> [MessageDecryption] {
        let fetchRequest: NSFetchRequest<MessageDecryption> = MessageDecryption.fetchRequest()
        fetchRequest.returnsObjectsAsFaults = false

        do {
            return try context.fetch(fetchRequest)
        }
        catch {
            DDLogError("CryptoData/fetchAll/error \(error)")
            return []
        }
    }

    private func createHomeFeedItemDecryption(id: String, contentType: HomeDecryptionReportContentType, audienceType: HomeDecryptionReportAudienceType, timestamp: Date, sender: UserAgent?, in context: NSManagedObjectContext) -> HomeFeedItemDecryption? {
        let decryption = HomeFeedItemDecryption(context: context)
        decryption.contentID = id
        decryption.contentType = contentType.rawValue
        decryption.audienceType = audienceType.rawValue
        decryption.timeReceived = timestamp
        decryption.userAgentSender = sender?.description ?? ""
        decryption.userAgentReceiver = AppContext.userAgent
        decryption.hasBeenReported = false
        return decryption
    }

    private func createGroupFeedItemDecryption(id: String, contentType: GroupDecryptionReportContentType, groupID: GroupID, timestamp: Date, sender: UserAgent?, in context: NSManagedObjectContext) -> GroupFeedItemDecryption? {
        let decryption = GroupFeedItemDecryption(context: context)
        decryption.contentID = id
        decryption.contentType = contentType.rawValue
        decryption.groupID = groupID
        decryption.timeReceived = timestamp
        decryption.userAgentSender = sender?.description ?? ""
        decryption.userAgentReceiver = AppContext.userAgent
        decryption.hasBeenReported = false
        return decryption
    }

    private func createMessageDecryption(id: String, timestamp: Date, sender: UserAgent, in context: NSManagedObjectContext) -> MessageDecryption? {
        guard let name = MessageDecryption.entity().name,
              let decryption = NSEntityDescription.insertNewObject(forEntityName: name, into: context) as? MessageDecryption else
        {
            DDLogError("CryptoData/create/error unable to create decryption entity")
            return nil
        }
        decryption.messageID = id
        decryption.timeReceived = timestamp
        decryption.userAgentSender = sender.description
        decryption.userAgentReceiver = AppContext.userAgent
        return decryption
    }

    private func createGroupFeedHistoryDecryption(groupID: String, timestamp: Date, in context: NSManagedObjectContext) -> GroupFeedHistoryDecryption? {
        let decryption = GroupFeedHistoryDecryption(context: context)
        decryption.groupID = groupID
        decryption.timeReceived = timestamp
        decryption.userAgentReceiver = AppContext.userAgent
        decryption.hasBeenReported = false
        decryption.numExpected = 0
        decryption.numDecrypted = 0
        decryption.rerequestCount = 0
        return decryption
    }

    private func markDecryptionsAsReported(_ managedObjectIDs: [NSManagedObjectID]) {
        performSeriallyOnBackgroundContext { managedObjectContext in
            for id in managedObjectIDs {
                guard let messageDecryption = try? managedObjectContext.existingObject(with: id) as? MessageDecryption else {
                    DDLogError("CryptoData/markDecryptionsAsReported/\(id)/error could not find row to update")
                    continue
                }
                messageDecryption.hasBeenReported = true
            }
            if managedObjectContext.hasChanges {
                do {
                    try managedObjectContext.save()
                } catch {
                    DDLogError("CryptoData/markDecryptionsAsReported/save/error [\(error)]")
                }
            }
        }
    }

    private func markGroupDecryptionsAsReported(_ managedObjectIDs: [NSManagedObjectID]) {
        performSeriallyOnBackgroundContext { managedObjectContext in
            for id in managedObjectIDs {
                guard let groupFeedItemDecryption = try? managedObjectContext.existingObject(with: id) as? GroupFeedItemDecryption else {
                    DDLogError("CryptoData/markGroupDecryptionsAsReported/\(id)/error could not find row to update")
                    continue
                }
                groupFeedItemDecryption.hasBeenReported = true
            }
            if managedObjectContext.hasChanges {
                do {
                    try managedObjectContext.save()
                } catch {
                    DDLogError("CryptoData/markGroupDecryptionsAsReported/save/error [\(error)]")
                }
            }
        }
    }

    private func markGroupFeedHistoryDecryptionsAsReported(_ managedObjectIDs: [NSManagedObjectID]) {
        performSeriallyOnBackgroundContext { managedObjectContext in
            for id in managedObjectIDs {
                guard let groupFeedHistoryDecryption = try? managedObjectContext.existingObject(with: id) as? GroupFeedHistoryDecryption else {
                    DDLogError("CryptoData/markGroupFeedHistoryDecryptionsAsReported/\(id)/error could not find row to update")
                    continue
                }
                groupFeedHistoryDecryption.hasBeenReported = true
            }
            if managedObjectContext.hasChanges {
                do {
                    try managedObjectContext.save()
                } catch {
                    DDLogError("CryptoData/markGroupFeedHistoryDecryptionsAsReported/save/error [\(error)]")
                }
            }
        }
    }

    private func markHomeDecryptionsAsReported(_ managedObjectIDs: [NSManagedObjectID]) {
        performSeriallyOnBackgroundContext { managedObjectContext in
            for id in managedObjectIDs {
                guard let homeFeedItemDecryption = try? managedObjectContext.existingObject(with: id) as? HomeFeedItemDecryption else {
                    DDLogError("CryptoData/markHomeDecryptionsAsReported/\(id)/error could not find row to update")
                    continue
                }
                homeFeedItemDecryption.hasBeenReported = true
            }
            if managedObjectContext.hasChanges {
                do {
                    try managedObjectContext.save()
                } catch {
                    DDLogError("CryptoData/markDecryptionsAsReported/save/error [\(error)]")
                }
            }
        }
    }
}

extension MessageDecryption {
    func isReadyToBeReported(withDeadline deadline: TimeInterval) -> Bool {
        guard let timeReceived = timeReceived else { return false }
        return timeReceived.timeIntervalSinceNow < -deadline
    }

    func report(deadline: TimeInterval) -> DiscreteEvent? {
        guard
            let result = decryptionResult,
            let clientVersion = UserAgent(string: userAgentReceiver ?? "")?.version,
            let sender = UserAgent(string: userAgentSender ?? ""),
            let timeReceived = timeReceived
            else
        {
            return nil
        }
        let contentTypeValue = DecryptionReportContentType(rawValue: contentType) ?? .chat

        guard isReadyToBeReported(withDeadline: deadline) else {
            return nil
        }

        let timeTaken: TimeInterval = {
            if let timeDecrypted = timeDecrypted {
                return timeDecrypted.timeIntervalSince(timeReceived)
            } else {
                return deadline
            }
        }()

        return .decryptionReport(
            id: messageID,
            contentType: contentTypeValue,
            result: result,
            clientVersion: clientVersion,
            sender: sender,
            rerequestCount: Int(rerequestCount),
            timeTaken: timeTaken,
            isSilent: isSilent)
    }

    public func isSuccess() -> Bool {
        return decryptionResult == "success"
    }

    public func isMissingFromAuthor() -> Bool {
        return (decryptionResult ?? "") == "missingContent"
    }
}

extension HomeFeedItemDecryption {
    func isReadyToBeReported(withDeadline deadline: TimeInterval) -> Bool {
        guard let timeReceived = timeReceived else { return false }
        return timeReceived.timeIntervalSinceNow < -deadline
    }

    func report(deadline: TimeInterval) -> DiscreteEvent? {
        guard
            let clientVersion = UserAgent(string: userAgentReceiver ?? "")?.version,
            let timeReceived = timeReceived,
            let contentID = contentID,
            let contentType = contentType,
            let audienceType = audienceType,
            let userAgentSender = userAgentSender
            else
        {
            return nil
        }
        let audienceTypeValue = HomeDecryptionReportAudienceType(rawValue: audienceType) ?? .all
        let contentTypeValue = HomeDecryptionReportContentType(rawValue: contentType) ?? .post

        guard isReadyToBeReported(withDeadline: deadline) else {
            return nil
        }

        let timeTaken: TimeInterval = {
            if let timeDecrypted = timeDecrypted {
                return timeDecrypted.timeIntervalSince(timeReceived)
            } else {
                return deadline
            }
        }()

        return .homeDecryptionReport(id: contentID,
                                     audienceType: audienceTypeValue,
                                     contentType: contentTypeValue,
                                     error: decryptionError ?? "",
                                     clientVersion: clientVersion,
                                     sender: UserAgent(string: userAgentSender),
                                     rerequestCount: Int(rerequestCount),
                                     timeTaken: timeTaken)
    }

    public func isSuccess() -> Bool {
        return (decryptionError ?? "").isEmpty
    }

    public func isMissingFromAuthor() -> Bool {
        return (decryptionError ?? "" == "missingContent") || (decryptionError ?? "" == "postNotFound")
    }
}

extension GroupFeedItemDecryption {
    func isReadyToBeReported(withDeadline deadline: TimeInterval) -> Bool {
        guard let timeReceived = timeReceived else { return false }
        return timeReceived.timeIntervalSinceNow < -deadline
    }

    func report(deadline: TimeInterval) -> DiscreteEvent? {
        guard
            let clientVersion = UserAgent(string: userAgentReceiver ?? "")?.version,
            let timeReceived = timeReceived,
            let contentID = contentID,
            let contentType = contentType,
            let groupID = groupID,
            let userAgentSender = userAgentSender
            else
        {
            return nil
        }
        let contentTypeValue = GroupDecryptionReportContentType(rawValue: contentType) ?? .post

        guard isReadyToBeReported(withDeadline: deadline) else {
            return nil
        }

        let timeTaken: TimeInterval = {
            if let timeDecrypted = timeDecrypted {
                return timeDecrypted.timeIntervalSince(timeReceived)
            } else {
                return deadline
            }
        }()

        return .groupDecryptionReport(id: contentID,
                                      gid: groupID,
                                      contentType: contentTypeValue,
                                      error: decryptionError ?? "",
                                      clientVersion: clientVersion,
                                      sender: UserAgent(string: userAgentSender),
                                      rerequestCount: Int(rerequestCount),
                                      timeTaken: timeTaken)
    }

    public func isSuccess() -> Bool {
        return (decryptionError ?? "").isEmpty
    }

    public func isMissingFromAuthor() -> Bool {
        return (decryptionError ?? "" == "missingContent") || (decryptionError ?? "" == "postNotFound")
    }
}

extension GroupFeedHistoryDecryption {
    func isReadyToBeReported(withDeadline deadline: TimeInterval) -> Bool {
        return timeReceived.timeIntervalSinceNow < -deadline
    }

    func report(deadline: TimeInterval) -> DiscreteEvent? {
        guard let clientVersion = UserAgent(string: userAgentReceiver)?.version else {
            return nil
        }

        guard isReadyToBeReported(withDeadline: deadline) else {
            return nil
        }

        let timeTaken: TimeInterval = {
            return timeLastUpdated.timeIntervalSince(timeReceived)
        }()

        return .groupHistoryReport(gid: groupID,
                                   numExpected: numExpected,
                                   numDecrypted: numDecrypted,
                                   clientVersion: clientVersion,
                                   rerequestCount: rerequestCount,
                                   timeTaken: timeTaken)
    }

    public func isSuccess() -> Bool {
        return numExpected == numDecrypted
    }
}
