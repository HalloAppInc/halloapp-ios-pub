//
//  XMPPError.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/11/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

let XMPPErrorDomain = "XMPPErrorDomain"

fileprivate let xmppErrorTextKey = "XMPPErrorTextKey"

enum XMPPErrorCode: Int {
    case unknown = 0
    case notConnected = 1
    case timeout = 2
    case cancelled = 3  // operation was cancelled before execution started (no communication with the server)
    case aborted = 4    // operation was cancelled after execution started
    case malformed = 5  // stanza malformed
}

extension NSError {
    var isXMPPError: Bool {
        get {
            self.domain == XMPPErrorDomain
        }
    }

    var xmppErrorCode: Int {
        guard self.isXMPPError else {
            return XMPPErrorCode.unknown.rawValue
        }
        return self.code
    }

    var xmppErrorText: String? {
        if let errorText = self.userInfo[xmppErrorTextKey] as? String {
            return errorText
        }
        return nil
    }
}

func xmppErrorUnknown() -> NSError {
    return NSError(domain: XMPPErrorDomain,
                   code: XMPPErrorCode.unknown.rawValue,
                   userInfo: [ NSLocalizedDescriptionKey: "An error occurred. Please try again later."])
}

func xmppErrorNotConnected() -> NSError {
    return NSError(domain: XMPPErrorDomain,
                   code: XMPPErrorCode.notConnected.rawValue,
                   userInfo: [ NSLocalizedDescriptionKey: "Could not connect to service. Please try again later."])
}

func xmppErrorTimeout() -> NSError {
    return NSError(domain: XMPPErrorDomain,
                   code: XMPPErrorCode.timeout.rawValue,
                   userInfo: [ NSLocalizedDescriptionKey: "Something is wrong. Your request took too long. Please try again later."])
}

func xmppErrorCancelled() -> NSError {
    return NSError(domain: XMPPErrorDomain,
                   code: XMPPErrorCode.cancelled.rawValue,
                   userInfo: [ NSLocalizedDescriptionKey: "The operation was cancelled."])
}

func xmppErrorAborted() -> NSError {
    return NSError(domain: XMPPErrorDomain,
                   code: XMPPErrorCode.aborted.rawValue,
                   userInfo: [ NSLocalizedDescriptionKey: "The operation was aborted."])
}

func xmppError(code: Int, text: String?) -> NSError {
    var userInfo: [String: Any] = [NSLocalizedDescriptionKey: "There was a problem with the service. Code = \(code)."]
    if (text != nil) {
        userInfo[xmppErrorTextKey] = text
    }
    return NSError(domain: XMPPErrorDomain, code: code, userInfo: userInfo)
}
