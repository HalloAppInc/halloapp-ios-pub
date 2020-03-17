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

class SyncSession {
    typealias Completion = ([XMPPContact]?, Error?) -> Void

    private var operation: XMPPContactSyncRequest.RequestType
    private var completion: Completion

    /**
     Set to `0` to turn off chuncked sync.
     */
    var batchSize: Int = 0
    let syncID = UUID().uuidString

    private var batchIndex = 0

    private var contacts: [XMPPContact]
    private var results: [XMPPContact] = []
    private var error: Error? = nil

    init(operation: XMPPContactSyncRequest.RequestType, contacts: [XMPPContact], completion: @escaping Completion) {
        self.operation = operation
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
            let request = XMPPContactSyncRequest(with: contactsToSend, operation: self.operation, syncID: self.syncID, isLastBatch: isLastBatch) { (batchResults, error) in
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
