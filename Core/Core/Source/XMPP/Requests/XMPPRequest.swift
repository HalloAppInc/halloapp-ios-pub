//
//  XMPPRequest.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/11/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Foundation
import XMPPFramework

public let XMPPIQDefaultTo = "s.halloapp.net"

enum XMPPRequestState {
    case ready
    case sending
    case cancelled
    case finished
}

public typealias XMPPRequestCompletion = (Error?) -> Void

open class XMPPRequest {
    internal var state: XMPPRequestState = .ready
    internal var retriesRemaining = 0
    private(set) var requestId: String
    internal var iq: XMPPIQ
    private(set) var response: XMPPIQ?

    public init(iq: XMPPIQ) {
        self.iq = iq
        self.requestId = iq.elementID!
    }

    func send(using xmppController: XMPPController) {
        guard self.state == .ready else {
            DDLogWarn("xmpprequest/\(self.requestId)/send: not ready [\(self.state)]")
            return
        }
        DDLogInfo("xmpprequest/\(self.requestId)/sending")
        self.state = .sending
        xmppController.xmppStream.send(self.iq)
    }

    func failOnNoConnection() {
        guard self.state == .sending || self.state == .ready else {
            return
        }
        DDLogWarn("xmpprequest/\(self.requestId)/failed: not-connected")
        self.state = .cancelled
        self.didFail(with: xmppErrorNotConnected())
    }

    func cancelAndPrepareFor(retry willRetry: Bool) -> Bool {
        DDLogError("xmpprequest/\(self.requestId)/failed/rr=\(self.retriesRemaining)")
        switch (self.state) {
        case .finished, .cancelled:
                return false
        case .ready, .sending:
            if !willRetry || self.retriesRemaining <= 0 {
                self.state = .cancelled
                self.didFail(with: xmppErrorAborted())
                return false
            }
        }

        if self.state == .sending {
            self.retriesRemaining -= 1
            self.state = .ready
        }
        return true
    }

    func process(response: XMPPIQ) {
        guard self.state == .sending else {
            return
        }
        self.state = .finished
        self.response = response
        DDLogDebug("xmpprequest/\(self.requestId)/response \(response)")
        if response.isResultIQ {
            self.didFinish(with: response)
        } else if response.isErrorIQ {
            var iqError = xmppErrorUnknown()
            if let errorNode = response.childErrorElement {
                if let errorCodeString = errorNode.attribute(forName: "code")?.stringValue {
                    if let errorCode = Int(errorCodeString) {
                        let errorText = errorNode.attribute(forName: "text")?.stringValue
                        iqError = xmppError(code: errorCode, text: errorText)
                    }
                }
            }
            self.didFail(with: iqError)
        } else {
            assert(false, "Malformed IQ respose")
        }
    }

    open func didFinish(with response: XMPPIQ) { }

    open func didFail(with error: Error) { }
}
