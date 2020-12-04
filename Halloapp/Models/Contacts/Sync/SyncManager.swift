//
//  SyncManager.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/14/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import Foundation

class SyncManager {

    enum SyncFailureReason: Error {
        case empty
        case notAllowed
        case notEnabled
        case serverError(Error)
        case alreadyRunning
        case awaitingAuthorization
    }

    typealias SyncResult = Result<Void, SyncFailureReason>

    // Later to be replaced with userId.
    private var pendingDeletes: Set<ABContact.NormalizedPhoneNumber> = []
    private var processedDeletes: Set<ABContact.NormalizedPhoneNumber> = []

    private(set) var isSyncEnabled = false
    private var isSyncInProgress = false

    private var nextSyncMode: SyncMode = .none
    private var nextSyncDate: Date?
    let queue = DispatchQueue(label: "com.halloapp.syncmanager")
    private var fullSyncTimer: DispatchSourceTimer

    private var cancellableSet: Set<AnyCancellable> = []

    private let contactStore: ContactStoreMain
    private let service: HalloService

    private static let UDDisabledAddressBookSynced = "isabledAddressBookSynced"

    init(contactStore: ContactStoreMain, service: HalloService, userData: UserData) {
        self.contactStore = contactStore
        self.service = service

        fullSyncTimer = DispatchSource.makeTimerSource(queue: queue)
        fullSyncTimer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.contactStore.performOnBackgroundContextAndWait { (managedObjectContext) in
                self.runFullSyncIfNecessary(using: managedObjectContext)
            }
        }

        cancellableSet.insert(self.service.didConnect.sink { [weak self] in
            guard let self = self else { return }
            self.queue.async {
                self.contactStore.performOnBackgroundContextAndWait { (managedObjectContext) in
                    self.runSyncIfNecessary(using: managedObjectContext)
                }
            }
        })

        cancellableSet.insert(userData.didLogOff.sink {
            self.disableSync()
        })
    }

    func enableSync() {
        guard !isSyncEnabled else {
            return
        }
        DDLogInfo("syncmanager/enabled")
        isSyncEnabled = true

        fullSyncTimer.schedule(wallDeadline: DispatchWallTime.now(), repeating: 60)
        fullSyncTimer.activate()

        queue.async {
            self.contactStore.performOnBackgroundContextAndWait { (managedObjectContext) in
                self.runFullSyncIfNecessary(using: managedObjectContext)
                if !self.isSyncInProgress {
                    self.runSyncWith(mode: .delta, using: managedObjectContext)
                }
            }
        }

        cancellableSet.insert(AppContext.shared.userData.didLogOff.sink { _ in
            self.disableSync()
        })
    }

    func disableSync() {
        DDLogInfo("syncmanager/disabled")

        isSyncEnabled = false
        isSyncInProgress = false

        nextSyncDate = nil
        nextSyncMode = .none
        pendingDeletes.removeAll()
        processedDeletes.removeAll()

        fullSyncTimer.suspend()

        if !ContactStore.contactsAccessAuthorized {
            UserDefaults.standard.removeObject(forKey: SyncManager.UDDisabledAddressBookSynced)
        }

        // Reset next full sync date.
        contactStore.mutateDatabaseMetadata { (metadata) in
            metadata[ContactStoreMetadataNextFullSyncDate] = nil
        }
    }

    func add(deleted userIds: Set<ABContact.NormalizedPhoneNumber>) {
        DDLogDebug("syncmanager/add-deleted [\(userIds)]")
        pendingDeletes.formUnion(userIds)
    }

    // MARK: Scheduling

    func requestDeltaSync() {
        DDLogInfo("syncmanager/request/delta")
        queue.async {
            self.contactStore.performOnBackgroundContextAndWait { (managedObjectContext) in
                self.runSyncWith(mode: .delta, using: managedObjectContext)
            }
        }
    }

    func requestFullSync() {
        DDLogInfo("syncmanager/request/full")

        // Remember that database is due for a full sync in case we get interrupted
        contactStore.mutateDatabaseMetadata { (metadata) in
            metadata[ContactStoreMetadataNextFullSyncDate] = Date()
        }

        queue.async {
            self.contactStore.performOnBackgroundContextAndWait { (managedObjectContext) in
                self.runSyncWith(mode: .full, using: managedObjectContext)
            }
        }
    }

    // Must be called from `queue`.
    private func runSyncWith(mode: SyncMode, using managedObjectContext: NSManagedObjectContext) {
        nextSyncDate = Date()
        nextSyncMode = mode

        if case .failure(let failureReason) = runSyncIfNecessary(using: managedObjectContext) {
            DDLogError("syncmanager/sync/failed [\(failureReason)]")
        }
    }

    // MARK: Run sync

    private func runFullSyncIfNecessary(using managedObjectContext: NSManagedObjectContext) {
        let nextFullSyncDate = contactStore.databaseMetadata?[ContactStoreMetadataNextFullSyncDate] as? Date
        DDLogInfo("syncmanager/full/check-schedule Next full sync is scheduled at [\(String(describing: nextFullSyncDate))]")

        var runFullSync = false

        // Force full sync on address book permissions change.
        if ContactStore.contactsAccessAuthorized == UserDefaults.standard.bool(forKey: SyncManager.UDDisabledAddressBookSynced) {
            DDLogInfo("syncmanager/full/check-schedule Force full sync on contacts permissions change. Access granted: \(ContactStore.contactsAccessAuthorized)")
            runFullSync = true
            nextSyncDate = Date()
        }
        // Sync was never run - do it now.
        if nextFullSyncDate == nil {
            if !isSyncInProgress {
                runFullSync = true
                nextSyncDate = Date()
            }
        }
        // Time for a scheduled sync
        else if nextFullSyncDate!.timeIntervalSinceNow < 0 {
            runFullSync = true
            nextSyncDate = nextFullSyncDate
        }

        if runFullSync {
            nextSyncMode = .full
            runSyncIfNecessary(using: managedObjectContext)
        }
    }

    @discardableResult private func runSyncIfNecessary(using managedObjectContext: NSManagedObjectContext) -> SyncResult {
        guard !isSyncInProgress else {
            return .failure(.alreadyRunning)
        }

        guard !ContactStore.contactsAccessRequestNecessary else {
            return .failure(.awaitingAuthorization)
        }

        guard isSyncEnabled else {
            return .failure(.notEnabled)
        }

        // Sync mode must be set.
        guard nextSyncMode != .none else {
            return .failure(.empty)
        }

        // Next sync date should be set.
        guard nextSyncDate != nil else {
            return .failure(.empty)
        }
        guard nextSyncDate!.timeIntervalSinceNow < 0 else {
            return .failure(.empty)
        }

        // Must be connected.
        guard service.isConnected else {
            return .failure(.notAllowed)
        }

        return reallyPerformSync(using: managedObjectContext)
    }

    private func reallyPerformSync(using managedObjectContext: NSManagedObjectContext) -> SyncResult {
        DDLogInfo("syncmanager/sync/prepare/\(nextSyncMode)")

        defer {
            nextSyncMode = .none
            nextSyncDate = nil
        }

        let contactsToSync: [ABContact]
        if ContactStore.contactsAccessAuthorized {
            contactsToSync = contactStore.contactsFor(fullSync: nextSyncMode == .full, in: managedObjectContext)
        } else {
            DDLogInfo("syncmanager/sync/prepare Access to contacts disabled - syncing an empty list")
            contactsToSync = []
        }

        // Do not run delta syncs with an empty set of users.
        guard nextSyncMode == .full || !contactsToSync.isEmpty || !pendingDeletes.isEmpty else {
            DDLogInfo("syncmanager/sync/prepare Empty delta sync - exiting now")
            return .failure(.empty)
        }

        // Prepare what gets sent to the server.
        var xmppContacts = contactsToSync.map { XMPPContact($0) }

        // Individual deleted phone don't matter if the entire address book is about to be synced.
        if nextSyncMode == .full {
            pendingDeletes.removeAll()
        } else {
            xmppContacts.append(contentsOf: pendingDeletes.map { XMPPContact.deletedContact(with: $0) })
            processedDeletes.formUnion(pendingDeletes)
        }

        isSyncInProgress = true

        let syncMode = nextSyncMode
        DDLogInfo("syncmanager/sync/start/\(nextSyncMode) [\(xmppContacts.count)]")
        let syncSession = SyncSession(mode: syncMode, contacts: xmppContacts) { results, error in
            self.queue.async {
                self.processSyncResponse(mode: syncMode, contacts: results, error: error)
            }
        }
        syncSession.start()

        return .success(())
    }

    private func processSyncResponse(mode: SyncMode, contacts: [XMPPContact]?, error: Error?) {
        guard error == nil else {
            DDLogError("syncmanager/sync/\(mode)/response/error [\(error!)]")
            finishSync(withMode: mode, result: .failure(.serverError(error!)))
            return
        }

        // Process results
        pendingDeletes.subtract(processedDeletes)
        processedDeletes.removeAll()

        if mode == .full {
            // Mark that contacts were resynced after Contacts permissions change.
            if ContactStore.contactsAccessAuthorized {
                UserDefaults.standard.removeObject(forKey: SyncManager.UDDisabledAddressBookSynced)
            } else {
                UserDefaults.standard.set(true, forKey: SyncManager.UDDisabledAddressBookSynced)
            }

            // Set next full sync date: now + 1 day
            contactStore.mutateDatabaseMetadata { (metadata) in
                metadata[ContactStoreMetadataNextFullSyncDate] = Date(timeIntervalSinceNow: 3600*24)
            }
        }

        if let contacts = contacts {
            contactStore.performOnBackgroundContextAndWait { managedObjectContext in
                self.contactStore.processSync(results: contacts, isFullSync: mode == .full, using: managedObjectContext)
            }

            let pushNames = contacts.reduce(into: [UserID: String]()) { (dict, contact) in
                if let userID = contact.userid, let pushName = contact.pushName {
                    dict[userID] = pushName
                }
            }
            contactStore.addPushNames(pushNames)
            
            let contactsWithAvatars = contacts.filter { $0.avatarid != nil }
            let avatarDict = contactsWithAvatars.reduce(into: [UserID: AvatarID]()) { (dict, contact) in
                dict[contact.userid!] = contact.avatarid!
            }
            MainAppContext.shared.avatarStore.processContactSync(avatarDict)
        }

        finishSync(withMode: mode, result: .success(()))
    }

    func processNotification(contacts: [XMPPContact], completion: @escaping () -> Void) {
        DDLogInfo("syncmanager/notification contacts=[\(contacts)]")
        guard !contacts.isEmpty else {
            completion()
            return
        }
        queue.async {
            self.contactStore.performOnBackgroundContextAndWait { managedObjectContext in
                self.contactStore.processNotification(contacts: contacts, using: managedObjectContext)
            }
            completion()
        }
    }

    func processNotification(contactHashes: [Data], completion: @escaping () -> Void) {
        DDLogInfo("syncmanager/notification hashes=[\(contactHashes.map({ $0.toHexString() }))]")
        guard !contactHashes.isEmpty else {
            completion()
            return
        }
        queue.async {
            self.contactStore.performOnBackgroundContextAndWait { managedObjectContext in
                self.contactStore.processNotification(contactHashes: contactHashes, using: managedObjectContext)
                self.runSyncWith(mode: .delta, using: managedObjectContext)
            }
            completion()
        }
    }

    private func finishSync(withMode mode: SyncMode, result: SyncResult) {
        guard isSyncInProgress else {
            return
        }

        isSyncInProgress = false

        switch result {
        case .success:
            DDLogInfo("syncmanager/sync/\(mode)/finished")

        case .failure:
            let retryDelay: TimeInterval = 20
            DDLogInfo("syncmanager/sync/\(mode)/retrying in \(retryDelay)s")

            queue.asyncAfter(deadline: .now() + retryDelay) {
                self.contactStore.performOnBackgroundContextAndWait { (managedObjectContext) in
                    self.runFullSyncIfNecessary(using: managedObjectContext)
                    if !self.isSyncInProgress {
                        self.runSyncWith(mode: .delta, using: managedObjectContext)
                    }
                }
            }
        }
    }
}
