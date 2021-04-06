//
//  CryptoData.swift
//  HalloApp
//
//  Created by Garrett on 3/17/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import CoreData
import Foundation

final class CryptoData {
    init() {
        self.persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
        self.viewContext = persistentContainer.viewContext
        self.bgContext = persistentContainer.newBackgroundContext()
    }

    func update(messageID: String, timestamp: Date, result: String, rerequestCount: Int, sender: UserAgent, isSilent: Bool) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let messageDecryption = self.fetchMessageDecryption(id: messageID, in: self.bgContext) ??
                    self.createMessageDecryption(id: messageID, timestamp: timestamp, sender: sender, in: self.bgContext) else
            {
                DDLogError("CryptoData/update/\(messageID)/error could not find or create decryption report")
                return
            }
            guard !messageDecryption.hasBeenReported else {
                DDLogInfo("CryptoData/update/\(messageID)/skipping already reported")
                return
            }
            guard messageDecryption.decryptionResult != "success" else {
                DDLogInfo("CryptoData/update/\(messageID)/skipping already decrypted")
                return
            }
            guard let timeReceived = messageDecryption.timeReceived, timeReceived.timeIntervalSinceNow > -self.deadline else {
                DDLogInfo("CryptoData/update/\(messageID)/skipping past deadline")
                return
            }
            messageDecryption.rerequestCount = Int32(rerequestCount)
            messageDecryption.decryptionResult = result
            messageDecryption.timeDecrypted = result == "success" ? Date() : nil
            messageDecryption.isSilent = isSilent
            if self.bgContext.hasChanges {
                do {
                    try self.bgContext.save()
                    DDLogInfo("CryptoData/update/\(messageID)/saved [\(result)]")
                } catch {
                    DDLogError("CryptoData/update/\(messageID)/save/error [\(error)]")
                }
            }
        }
    }

    func generateReport(markEventsReported: Bool = true) -> [DiscreteEvent] {
        let fetchRequest: NSFetchRequest<MessageDecryption> = MessageDecryption.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "hasBeenReported == false")
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let unreportedEvents = try viewContext.fetch(fetchRequest)
            let readyEvents = unreportedEvents.filter { $0.isReadyToBeReported(withDeadline: deadline) }

            DDLogInfo("CryptoData/generateReport [\(readyEvents.count) ready of \(unreportedEvents.count) unreported]")

            if markEventsReported && !readyEvents.isEmpty {
                markDecryptionsAsReported(readyEvents.map { $0.objectID })
            }

            return readyEvents.compactMap { $0.report(deadline: deadline) }
        }
        catch {
            DDLogError("CryptoData/generateReport/error \(error)")
            return []
        }
    }

    func startReporting(interval: TimeInterval, reportEvents: @escaping ([DiscreteEvent]) -> Void) {
        guard reportTimer == nil else {
            DDLogError("CryptoData/startReporting/error already-reporting")
            return
        }
        DDLogInfo("CryptoData/startReporting/starting [interval=\(interval)]")
        reportTimer = DispatchSource.makeTimerSource(flags: [], queue: .main)
        reportTimer?.setEventHandler(handler: { [weak self] in
            guard let self = self else { return }
            let events = self.generateReport()
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

    // MARK: Private

    private let queue = DispatchQueue(label: "com.halloapp.crypto-stats")
    private let deadline = TimeInterval(24*60*60) // 24 hour deadline

    private var reportTimer: DispatchSourceTimer?

    private var viewContext: NSManagedObjectContext
    private var bgContext: NSManagedObjectContext

    private let persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: MainAppContext.cryptoStatsStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let container = NSPersistentContainer(name: "CryptoStats")
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

    private func fetchMessageDecryption(id: String, in context: NSManagedObjectContext) -> MessageDecryption? {
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

    private func markDecryptionsAsReported(_ managedObjectIDs: [NSManagedObjectID]) {
        queue.async {
            for id in managedObjectIDs {
                guard let messageDecryption = try? self.bgContext.existingObject(with: id) as? MessageDecryption else {
                    DDLogError("CryptoData/markDecryptionsAsReported/\(id)/error could not find row to update")
                    continue
                }
                messageDecryption.hasBeenReported = true
            }
            if self.bgContext.hasChanges {
                do {
                    try self.bgContext.save()
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
            let messageID = messageID,
            let result = decryptionResult,
            let clientVersion = UserAgent(string: userAgentReceiver ?? "")?.version,
            let sender = UserAgent(string: userAgentSender ?? ""),
            let timeReceived = timeReceived
            else
        {
            return nil
        }

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
            result: result,
            clientVersion: clientVersion,
            sender: sender,
            rerequestCount: Int(rerequestCount),
            timeTaken: timeTaken,
            isSilent: isSilent)
    }
}
