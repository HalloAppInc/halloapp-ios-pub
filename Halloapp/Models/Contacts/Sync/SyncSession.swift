//
//  SyncSession.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/14/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import Foundation

/**
 Defines what gets sent during sync session.
 - none: nothing, sync is not performed.
 - delta: only contacts that were added or deleted since last full sync.
 - full: all contacts from device address book.
 */
enum SyncMode {
    case delta
    case full
}

enum ContactSyncRequestType: String, RawRepresentable {
    case full
    case delta
}

class SyncSession {
    typealias Completion = (RequestError?) -> Void
    typealias SyncProgress = (processed: Int, total: Int)

    private let syncMode: SyncMode
    private let completion: Completion
    private let processResultsAsyncBlock: ([XMPPContact], SyncProgress) -> Void

    /**
     Set to `0` to turn off chuncked sync.
     */
    let batchSize: Int = 1024
    let syncID = UUID().uuidString

    private var batchIndex: Int = 0

    private var contacts: [XMPPContact]
    private var results: [XMPPContact] = []
    private var error: RequestError? = nil

    init(mode: SyncMode, contacts: [XMPPContact], processResultsAsyncBlock: @escaping ([XMPPContact], SyncProgress) -> Void, completion: @escaping Completion) {
        self.syncMode = mode
        self.contacts = contacts
        self.processResultsAsyncBlock = processResultsAsyncBlock
        self.completion = completion
    }

    deinit {
        DDLogDebug("sync-session/deinit")
    }

    func start() {
        DDLogInfo("sync-session/\(self.syncMode)/start contacts=[\(self.contacts.count)]")
        self.sendNextBatchIfNecessary()
    }

    func sendNextBatchIfNecessary() {
        /* client side error */
        guard self.error == nil else {
            DDLogError("sync-session/\(self.syncMode)/request/error/\(self.error!)")
            DispatchQueue.main.async {
                self.completion(self.error)
            }
            return
        }

        if !self.contacts.isEmpty || self.batchIndex == 0 {
            var isLastBatch: Bool? = nil
            var range = 0..<self.contacts.count
            if self.batchSize > 0 {
                if self.batchSize < range.count {
                    range = 0..<self.batchSize
                }
                isLastBatch = range.count == self.contacts.count
            }
            let contactsToSend = self.contacts[range]
            let requestType: ContactSyncRequestType = self.syncMode == .full ? .full : .delta
            let batchIndex = self.batchIndex
            let previouslyProcessed = batchIndex * batchSize
            let batchProgress: SyncProgress = (processed: previouslyProcessed + range.count, total: previouslyProcessed + contacts.count)
            MainAppContext.shared.service.syncContacts(with: contactsToSend, type: requestType, syncID: self.syncID,
                                                 batchIndex: batchIndex, isLastBatch: isLastBatch) { (result) in
                DDLogInfo("sync-session/\(self.syncMode)/request/end/batch/\(batchIndex)")
                switch result {
                case .success(let batchResults):
                    DDLogInfo("sync-session/\(self.syncMode)/finished/\(batchIndex)/success, count:/\(batchResults.count)")
                    self.processResultsAsyncBlock(batchResults, batchProgress)
                    
                case .failure(let requestError):

                    DDLogInfo("sync-session/\(self.syncMode)/finished/\(batchIndex)/failure, error:/\(requestError)")
                    self.error = requestError
                }
                self.sendNextBatchIfNecessary()
            }
            DDLogInfo("sync-session/\(self.syncMode)/request/begin/batch/\(batchIndex)")

            self.contacts.removeSubrange(range)
            self.batchIndex += 1

            return
        }

        DDLogInfo("sync-session/\(self.syncMode)/finished/all batches")
        DispatchQueue.main.async {
            self.completion(nil)
        }
    }
}
