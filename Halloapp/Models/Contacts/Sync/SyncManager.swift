//
//  SyncManager.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/14/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Foundation

class SyncManager {
    enum SyncResult {
        case success
        case fail
        case cancel
    }

    enum FailureReason {
        case none
        case empty
        case notAllowed
        case notEnabled
        case serverError
        case alreadyRunning
    }

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

    private let contactStore: ContactStore
    private let xmppController: XMPPController

    private static let UDDisabledAddressBookSynced = "isabledAddressBookSynced"

    init(contactStore: ContactStore, xmppController: XMPPController) {
        self.contactStore = contactStore
        self.xmppController = xmppController

        self.fullSyncTimer = DispatchSource.makeTimerSource(queue: self.queue)
        self.fullSyncTimer.setEventHandler {
            self.runFullSyncIfNecessary()
        }

        self.cancellableSet.insert(self.xmppController.didConnect.sink { _ in
            self.queue.async {
                self.runSyncIfNecessary()
            }
        })
    }

    func enableSync() {
        guard !self.isSyncEnabled else {
            return
        }
        DDLogInfo("syncmanager/enabled")
        self.isSyncEnabled = true

        self.fullSyncTimer.schedule(wallDeadline: DispatchWallTime.now(), repeating: 60)
        self.fullSyncTimer.activate()
        self.queue.async {
            self.runFullSyncIfNecessary()
            if !self.isSyncInProgress {
                self.requestDeltaSync()
            }
        }

        self.cancellableSet.insert(AppContext.shared.userData.didLogOff.sink { _ in
            self.disableSync()
        })
    }

    func disableSync() {
        DDLogInfo("syncmanager/disabled")

        self.isSyncEnabled = false
        self.isSyncInProgress = false

        self.nextSyncDate = nil
        self.nextSyncMode = .none
        self.pendingDeletes.removeAll()
        self.processedDeletes.removeAll()

        self.fullSyncTimer.suspend()

        if !ContactStore.contactsAccessAuthorized {
            UserDefaults.standard.removeObject(forKey: SyncManager.UDDisabledAddressBookSynced)
        }

        // Reset next full sync date.
        self.contactStore.mutateDatabaseMetadata { (metadata) in
            metadata[ContactStoreMetadataNextFullSyncDate] = nil
        }
    }

    func add(deleted userIds: Set<ABContact.NormalizedPhoneNumber>) {
        DDLogDebug("syncmanager/add-deleted [\(userIds)]")
        self.pendingDeletes.formUnion(userIds)
    }

    // MARK: Scheduling

    func requestDeltaSync() {
        DDLogInfo("syncmanager/request/delta")
        self.requestSyncWith(mode: .delta)
    }

    func requestFullSync() {
        DDLogInfo("syncmanager/request/full")
        self.requestSyncWith(mode: .full)
    }

    private func requestSyncWith(mode: SyncMode) {
        self.queue.async {
            self.nextSyncDate = Date()
            self.nextSyncMode = mode

            let failureReason = self.runSyncIfNecessary()
            if failureReason != .none {
                DDLogError("syncmanager/sync/failed [\(failureReason)]")
            }
        }
    }

    // MARK: Run sync
    private func runFullSyncIfNecessary() {
        let nextFullSyncDate = self.contactStore.databaseMetadata?[ContactStoreMetadataNextFullSyncDate] as? Date
        DDLogInfo("syncmanager/scheduled-full/check d:[\(String(describing: nextFullSyncDate))]")

        var runFullSync = false

        // Force full sync on address book permissions change.
        if ContactStore.contactsAccessAuthorized == UserDefaults.standard.bool(forKey: SyncManager.UDDisabledAddressBookSynced) {
            runFullSync = true
            self.nextSyncDate = Date()
        }
        // Sync was never run - do it now.
        if nextFullSyncDate == nil {
            if !self.isSyncInProgress {
                runFullSync = true
                self.nextSyncDate = Date()
            }
        }
        // Time for a scheduled sync
        else if nextFullSyncDate!.timeIntervalSinceNow < 0 {
            runFullSync = true
            self.nextSyncDate = nextFullSyncDate
        }

        if runFullSync {
            self.nextSyncMode = .full
            self.runSyncIfNecessary()
        }
    }

    @discardableResult private func runSyncIfNecessary() -> FailureReason {
        guard !self.isSyncInProgress else {
            return .alreadyRunning
        }

        guard self.isSyncEnabled else {
            return .notEnabled
        }

        // Sync mode must be set.
        guard self.nextSyncMode != .none else {
            return .empty
        }

        // Next sync date should be set.
        guard self.nextSyncDate != nil else {
            return .empty
        }
        guard self.nextSyncDate!.timeIntervalSinceNow < 0 else {
            return.empty
        }

        // Must be connected.
        guard self.xmppController.xmppStream.isConnected else {
            return .notAllowed
        }

        self.reallyPerformSync()

        // Clean up.
        self.nextSyncDate = nil
        self.nextSyncMode = .none

        return self.isSyncInProgress ? .none : .empty
    }

    private func reallyPerformSync() {
        DDLogInfo("syncmanager/sync/prepare/\(self.nextSyncMode)")

        let contactsToSync = ContactStore.contactsAccessAuthorized ? self.contactStore.contactsFor(fullSync: self.nextSyncMode == .full) : []

        // Do not run delta syncs with an empty set of users.
        guard self.nextSyncMode == .full || !contactsToSync.isEmpty || !self.pendingDeletes.isEmpty else {
            DDLogInfo("syncmanager/delta/cancel-no-items")
            return
        }

        // Prepare what gets sent to the server.
        var xmppContacts: [XMPPContact] = contactsToSync.map{ XMPPContact($0) }

        // Individual deleted phone don't matter if the entire address book is about to be synced.
        if self.nextSyncMode == .full {
            self.pendingDeletes.removeAll()
        } else if !self.pendingDeletes.isEmpty {
            xmppContacts.append(contentsOf: self.pendingDeletes.map{ XMPPContact.deletedContact(with: $0) })
            self.processedDeletes.formUnion(self.pendingDeletes)
        }

        self.isSyncInProgress = true

        let syncMode = self.nextSyncMode
        DDLogInfo("syncmanager/sync/start/\(self.nextSyncMode) [\(xmppContacts.count)]")
        let syncSession = SyncSession(mode: syncMode, contacts: xmppContacts) { results, error in
            self.queue.async {
                self.processSyncResponse(mode: syncMode, contacts: results, error: error)
            }
        }
        syncSession.start()
    }

    private func processSyncResponse(mode: SyncMode, contacts: [XMPPContact]?, error: Error?) {
        guard error == nil else {
            DDLogError("syncmanager/sync/\(mode)/response/error [\(error!)]")
            self.finishSync(with: mode, result: .fail, failureReason: .serverError)
            return
        }

        // Process results
        self.pendingDeletes.subtract(self.processedDeletes)
        self.processedDeletes.removeAll()


        if mode == .full {
            // Mark that contacts were resynced after Contacts permissions change.
            if ContactStore.contactsAccessAuthorized {
                UserDefaults.standard.removeObject(forKey: SyncManager.UDDisabledAddressBookSynced)
            } else {
                UserDefaults.standard.set(true, forKey: SyncManager.UDDisabledAddressBookSynced)
            }

            // Set next full sync date: now + 1 day
            self.contactStore.mutateDatabaseMetadata { (metadata) in
                metadata[ContactStoreMetadataNextFullSyncDate] = Date(timeIntervalSinceNow: 3600*24)
            }
        }

        if contacts != nil {
            self.contactStore.performOnBackgroundContextAndWait{ managedObjectContext in
                self.contactStore.processSync(results: contacts!, isFullSync: mode == .full, using: managedObjectContext)
            }
        }
        self.finishSync(with: mode, result: .success, failureReason: .none)
    }

    func processNotification(contacts: [XMPPContact]) {
        DDLogInfo("syncmanager/notification contacts=[\(contacts)]")
        guard !contacts.isEmpty else {
            return
        }
        self.queue.async {
            self.contactStore.performOnBackgroundContextAndWait{ managedObjectContext in
                self.contactStore.processNotification(contacts: contacts, using: managedObjectContext)
            }
        }
    }

    private func finishSync(with mode: SyncMode, result: SyncResult, failureReason: FailureReason) {
        guard self.isSyncInProgress else {
            return
        }

        self.isSyncInProgress = false

        ///TODO: retry sync on failure
    }
}
