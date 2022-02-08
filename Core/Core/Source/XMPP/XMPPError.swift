//
//  XMPPError.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/11/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

public enum RequestError: Error {
    case notConnected
    case timeout
    case canceled
    case aborted
    case malformedRequest
    case malformedResponse
    case serverError(String)
    case audienceHashMismatch
    case retryDelay(TimeInterval)
}

extension RequestError {
    /// `true` for errors that represent definite failure states (e.g., never sent request), `false` for indeterminate errors (e.g., never received response)
    public var isKnownFailure: Bool {
        switch self {
        case .timeout, .canceled, .aborted, .malformedResponse:
            return false
        case .notConnected, .malformedRequest, .serverError, .retryDelay, .audienceHashMismatch:
            return true
        }
    }

    public var canAck: Bool {
        switch self {
        case .aborted, .canceled:
            return true
        case .timeout, .malformedRequest, .malformedResponse, .retryDelay, .serverError, .notConnected, .audienceHashMismatch:
            return false
        }
    }
}
