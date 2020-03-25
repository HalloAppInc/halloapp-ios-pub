//
//  SyncSession.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/14/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Foundation
import XMPPFramework

/**
 Defines what gets sent during sync session.
 - none: nothing, sync is not performed.
 - delta: only contacts that were added or deleted since last full sync.
 - full: all contacts from device address book.
 */
enum SyncMode {
    case none
    case delta
    case full
}

class SyncSession {
    typealias Completion = ([XMPPContact]?, Error?) -> Void

    private let syncMode: SyncMode
    private let completion: Completion

    /**
     Set to `0` to turn off chuncked sync.
     */
    let batchSize: Int = 512
    let syncID = UUID().uuidString

    private var batchIndex: Int = 0

    private var contacts: [XMPPContact]
    private var results: [XMPPContact] = []
    private var error: Error? = nil

    init(mode: SyncMode, contacts: [XMPPContact], completion: @escaping Completion) {
        self.syncMode = mode
        self.contacts = contacts
        self.completion = completion
    }

    deinit {
        DDLogDebug("sync-session/deinit")
    }

    func start() {
        DDLogInfo("sync-session/request/start n=[\(self.contacts.count)]")
        self.sendNextBatchIfNecessary()
    }

    func sendNextBatchIfNecessary() {
        /* client side error */
        guard self.error == nil else {
            DDLogError("sync-session/request/error/\(self.error!)")
            DispatchQueue.main.async {
                self.completion(nil, self.error)
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
            let requestType: XMPPContactSyncRequest.RequestType = self.syncMode == .full ? .full : .delta
            let request = XMPPContactSyncRequest(with: contactsToSend, type: requestType, syncID: self.syncID,
                                                 batchIndex: self.batchIndex, isLastBatch: isLastBatch) { (batchResults, error) in
                DDLogInfo("sync-session/request/end/batch/\(self.batchIndex)")
                if error != nil {
                    self.error = error
                } else {
                    self.results.append(contentsOf: batchResults!)
                }
                self.sendNextBatchIfNecessary()
            }
            self.contacts.removeSubrange(range)
            self.batchIndex += 1

            DDLogInfo("sync-session/request/begin/batch/\(self.batchIndex)")
            AppContext.shared.xmppController.enqueue(request: request)

            return
        }

        DispatchQueue.main.async {
            self.completion(self.results, nil)
        }
    }
}
