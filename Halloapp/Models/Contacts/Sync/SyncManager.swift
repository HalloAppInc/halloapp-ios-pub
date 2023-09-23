//
//  SyncManager.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/14/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import CoreData
import Foundation

class SyncManager {

    enum SyncFailureReason: Error {
        case empty
        case notAllowed
        case notEnabled
        case serverError(Error)
        case retryDelay(TimeInterval)
        case alreadyRunning
        case awaitingAuthorization
        case tooManyContacts
    }

    typealias SyncResult = Result<Void, SyncFailureReason>

    // Later to be replaced with userId.
    private var pendingDeletes: Set<ABContact.NormalizedPhoneNumber> = []
    private var processedDeletes: Set<ABContact.NormalizedPhoneNumber> = []

    private(set) var isSyncEnabled = false
    @Published private(set) var isSyncInProgress = false
    public let syncProgress = PassthroughSubject<Double, Never>()

    private var nextFullSyncDate: Date? {
        didSet {
            guard nextFullSyncDate != oldValue else {
                return
            }
            contactStore.mutateDatabaseMetadata { (metadata) in
                DDLogInfo("syncmanager/saving next full sync date [\(nextFullSyncDate?.description ?? "nil")]")
                metadata[ContactStoreMetadataNextFullSyncDate] = nextFullSyncDate
            }
        }
    }
    
    private var serverBusySyncDate: Date? {
        set {
            UserDefaults.standard.setValue(newValue, forKey: Self.UDNextSyncRetryDate)
        }
        
        get {
            UserDefaults.standard.value(forKey: Self.UDNextSyncRetryDate) as? Date
        }
    }

    let queue = DispatchQueue(label: "com.halloapp.syncmanager")
    private var fullSyncTimer: DispatchSourceTimer
    private var fullSyncTimerIsSuspended = false

    private var cancellableSet: Set<AnyCancellable> = []

    private let contactStore: ContactStoreMain
    private let service: HalloService

    private static let UDDisabledAddressBookSynced = "isabledAddressBookSynced" // TODO: Change this to be the correct spelling ("disabledAddressBookSynced")
    private static let UDNextSyncRetryDate = "nextSyncRetryDate"

    init(contactStore: ContactStoreMain, service: HalloService, userData: UserData) {
        self.contactStore = contactStore
        self.service = service
        self.nextFullSyncDate = contactStore.databaseMetadata?[ContactStoreMetadataNextFullSyncDate] as? Date

        fullSyncTimer = DispatchSource.makeTimerSource(queue: queue)
        fullSyncTimer.setEventHandler { [weak self] in
            guard let self = self, !self.isSyncInProgress, self.isFullSyncRequired() else {
                DDLogInfo("syncmanager/fullsynctimer/skipping")
                return
            }
            self.contactStore.performOnBackgroundContextAndWait { (managedObjectContext) in
                self.runSyncIfNecessary(using: managedObjectContext)
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
        if fullSyncTimerIsSuspended {
            fullSyncTimer.resume()
            fullSyncTimerIsSuspended = false
        }

        queue.async {
            self.contactStore.performOnBackgroundContextAndWait { (managedObjectContext) in
                self.runSyncIfNecessary(using: managedObjectContext)
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

        nextFullSyncDate = nil
        pendingDeletes.removeAll()
        processedDeletes.removeAll()

        if !fullSyncTimerIsSuspended {
            fullSyncTimer.suspend()
            fullSyncTimerIsSuspended = true
        }

        if !ContactStore.contactsAccessAuthorized {
            UserDefaults.standard.removeObject(forKey: SyncManager.UDDisabledAddressBookSynced)
        }
    }

    func add(deleted userIds: Set<ABContact.NormalizedPhoneNumber>) {
        DDLogDebug("syncmanager/add-deleted [\(userIds)]")
        pendingDeletes.formUnion(userIds)
    }

    // MARK: Scheduling

    func requestSync(forceFullSync: Bool = false) {
        DDLogInfo("syncmanager/requestSync [forceFullSync=\(forceFullSync)]")

        if forceFullSync {
            nextFullSyncDate = Date()
        }

        queue.async {
            self.contactStore.performOnBackgroundContextAndWait { (managedObjectContext) in
                self.runSyncIfNecessary(using: managedObjectContext)
            }
        }
    }

    // MARK: Run sync

    private func isFullSyncRequired() -> Bool {
        DDLogInfo("syncmanager/full/check-schedule Next full sync is scheduled at [\(String(describing: nextFullSyncDate))]")

        // Force full sync on address book permissions change.
        if ContactStore.contactsAccessAuthorized == UserDefaults.standard.bool(forKey: SyncManager.UDDisabledAddressBookSynced) {
            DDLogInfo("syncmanager/full/required/true Contacts permissions change. Access granted: \(ContactStore.contactsAccessAuthorized)")
            return true
        }

        guard let nextFullSyncDate = nextFullSyncDate else {
            DDLogInfo("syncmanager/full/required/true Not yet scheduled.")
            return true
        }

        if nextFullSyncDate.timeIntervalSinceNow < 0 {
            DDLogInfo("syncmanager/full/required/true Scheduled for [\(nextFullSyncDate)]")
            return true
        }

        DDLogInfo("syncmanager/full/required/false Not necessary at this time")
        return false
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

        guard service.isConnected else {
            return .failure(.notAllowed)
        }

        if let retryDate = serverBusySyncDate, retryDate > Date() {
            return .failure(.retryDelay(retryDate.timeIntervalSince(Date())))
        }

        return reallyPerformSync(using: managedObjectContext)
    }

    private func reallyPerformSync(using managedObjectContext: NSManagedObjectContext) -> SyncResult {

        let isFullSync = isFullSyncRequired()
        let syncMode = isFullSync ? SyncMode.full : .delta

        DDLogInfo("syncmanager/sync/prepare/\(syncMode)")

        let contactsToSync: [ABContact]
        if ContactStore.contactsAccessAuthorized {
            contactsToSync = contactStore.contactsFor(fullSync: isFullSync, in: managedObjectContext)
        } else {
            DDLogInfo("syncmanager/sync/prepare Access to contacts disabled - syncing an empty list")
            contactsToSync = []
        }

        // Do not run delta syncs with an empty set of users.
        guard isFullSync || !contactsToSync.isEmpty || !pendingDeletes.isEmpty else {
            DDLogInfo("syncmanager/sync/prepare Empty delta sync - exiting now")
            return .failure(.empty)
        }

        // Prepare what gets sent to the server.
        var xmppContacts = contactsToSync.map { XMPPContact($0) }

        // Individual deleted phone don't matter if the entire address book is about to be synced.
        if isFullSync {
            pendingDeletes.removeAll()
        } else {
            xmppContacts.append(contentsOf: pendingDeletes.map { XMPPContact.deletedContact(with: $0) })
            processedDeletes.formUnion(pendingDeletes)
        }

        isSyncInProgress = true
        syncProgress.send(0)

        DDLogInfo("syncmanager/sync/start/\(syncMode) [\(xmppContacts.count)]")
        let syncSession = SyncSession(mode: syncMode, contacts: xmppContacts, processResultsAsyncBlock: { results, progress in
            self.queue.async {
                self.processSyncBatchResults(mode: syncMode, contacts: results)
                self.syncProgress.send(Double(progress.processed)/Double(progress.total))
            }
        }){ error in
            self.queue.async {
                self.processSyncCompletion(mode: syncMode, error: error)
            }
        }
        syncSession.start()

        return .success(())
    }

    private func processSyncBatchResults(mode: SyncMode, contacts: [XMPPContact]?) {
        if let contacts = contacts {
            contactStore.performOnBackgroundContextAndWait { managedObjectContext in
                self.contactStore.processSync(results: contacts, using: managedObjectContext)
            }

            let pushNames = contacts.reduce(into: [UserID: String]()) { (dict, contact) in
                if let userID = contact.userid, let pushName = contact.pushName {
                    dict[userID] = pushName
                }
            }
            UserProfile.updateNames(with: pushNames)

            let contactsWithAvatars = contacts.filter { $0.avatarid != nil }
            let avatarDict = contactsWithAvatars.reduce(into: [UserID: AvatarID]()) { (dict, contact) in
                dict[contact.userid!] = contact.avatarid!
            }
            MainAppContext.shared.avatarStore.processContactSync(avatarDict)
        }
    }

    private func processSyncCompletion(mode: SyncMode, error: RequestError?) {
        if let error = error {
            DDLogError("syncmanager/sync/\(mode)/response/error [\(error)]")
            switch error {
            case .retryDelay(let timeInterval):
                finishSync(withMode: mode, result: .failure(.retryDelay(timeInterval)))
            case .serverError("too_many_contacts"):
                finishSync(withMode: mode, result: .failure(.tooManyContacts))
            default:
                finishSync(withMode: mode, result: .failure(.serverError(error)))
            }
            return
        }

        if !contactStore.isInitialSyncCompleted {
            contactStore.isInitialSyncCompleted = true
            MainAppContext.shared.contactStore.didCompleteInitialSync.send()
        }

        // Clear deletes only on successful sync completion.
        pendingDeletes.subtract(processedDeletes)
        processedDeletes.removeAll()

        if mode == .full {
            // Mark that contacts were resynced after Contacts permissions change.
            if ContactStore.contactsAccessAuthorized {
                UserDefaults.standard.removeObject(forKey: SyncManager.UDDisabledAddressBookSynced)
            } else {
                UserDefaults.standard.set(true, forKey: SyncManager.UDDisabledAddressBookSynced)
            }

            // Set next full sync date to value in server properties (default value is 24 hrs from now)
            nextFullSyncDate = Date(timeIntervalSinceNow: ServerProperties.contactSyncFrequency)
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
                if case .failure(let failureReason) = self.runSyncIfNecessary(using: managedObjectContext) {
                    DDLogError("syncmanager/sync/failed [\(failureReason)]")
                }
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

        case .failure(.tooManyContacts):
            DDLogInfo("syncmanager/sync/\(mode)/sync ended/error: too many contacts")
            // TODO: maybe show an alert to the user indicating that they have too many contacts and app wont function perfectly!

        case .failure(let failureReason):
            let retryDelay: TimeInterval? = {
                switch failureReason {
                case .retryDelay(let timeInterval):
                    return timeInterval
                default:
                    return nil
                }
            }()

            if let retryDelay = retryDelay {
                // Server is busy. Retry after time specified by the server
                serverBusySyncDate = Date() + retryDelay
                DDLogInfo("syncmanager/sync/\(mode)/server_busy/disabling contact sync until \(String(describing: serverBusySyncDate))")
            }
            
            let retryDelaySeconds: TimeInterval = retryDelay ?? 20
            // Error not related to server being too busy, retrying in 20 seconds
            DDLogInfo("syncmanager/sync/\(mode)/retrying in \(retryDelaySeconds)s")

            queue.asyncAfter(deadline: .now() + retryDelaySeconds) {
                self.contactStore.performOnBackgroundContextAndWait { (managedObjectContext) in
                    self.runSyncIfNecessary(using: managedObjectContext)
                }
            }
        }
    }
}
