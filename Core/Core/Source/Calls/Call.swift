//
//  Call.swift
//  Core
//
//  Created by Murali Balusu on 12/13/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift
import CallKit
import CryptoKit
import Reachability

public typealias CallID = String

public enum CallType: String {
    case audio
    case video
}

public enum CallDirection: String {
    case incoming
    case outgoing
}

extension CallType {
    public var serverCallType: Server_CallType {
        switch self {
        case .audio:
            return .audio
        case .video:
            return .video
        }
    }
}

extension Server_CallType {
    public var callType: CallType? {
        switch self {
        case .audio: return .audio
        case .video: return .video
        default: return nil
        }
    }
}

extension Server_EndCall {
    public var cxEndCallReason: CXCallEndedReason {
        switch self.reason {
        case .timeout:
            return .unanswered
        case .systemError, .connectionError, .decryptionFailed, .encryptionFailed, .videoUnsupported:
            return .failed
        case .cancel, .reject, .busy, .callEnd:
            return .remoteEnded
        case .unknown, .UNRECOGNIZED(_):
            return .failed
        }
    }

    public var shouldResetWhisperSession: Bool {
        switch self.reason {
        case .decryptionFailed:
            return true
        case .timeout, .systemError, .connectionError, .encryptionFailed, .cancel, .reject, .busy, .callEnd, .videoUnsupported:
            return false
        case .unknown, .UNRECOGNIZED(_):
            return false
        }
    }
}

public enum CallError: Error {
    case systemError
    case alreadyInCall
    case noActiveCall
}

public enum EndCallReason: Int16, Codable {
    case ended = 0
    case canceled = 1
    case reject = 2
    case busy = 3
    case timeout = 4
    case systemError = 5
    case decryptionError = 6
    case encryptionError = 7
    case connectionError = 8
    case videoUnsupportedError = 9
    case unknown = 10   // ongoingCall
}

extension EndCallReason {
    public var serverEndCallReason: Server_EndCall.Reason {
        switch self {
        case .ended:
            return .callEnd
        case .canceled:
            return .cancel
        case .reject:
            return .reject
        case .busy:
            return .busy
        case .timeout:
            return .timeout
        case .systemError:
            return .systemError
        case .encryptionError:
            return .encryptionFailed
        case .decryptionError:
            return .decryptionFailed
        case .connectionError:
            return .connectionError
        case .videoUnsupportedError:
            return .videoUnsupported
        case .unknown:
            return .unknown
        }
    }

    public var serverEndCallReasonStr: String {
        switch self {
        case .ended:
            return "callEnd"
        case .canceled:
            return "cancel"
        case .reject:
            return "reject"
        case .busy:
            return "busy"
        case .timeout:
            return "timeout"
        case .systemError:
            return "systemError"
        case .encryptionError:
            return "encryptionFailed"
        case .decryptionError:
            return "decryptionFailed"
        case .connectionError:
            return "connectionError"
        case .videoUnsupportedError:
            return "videoUnsupported"
        case .unknown:
            return "unknown"
        }
    }
}

public enum CallState {
    case inactive
    case connecting
    case ringing
    case connected
    case active
    case held
    case disconnected
    case iceRestart
    case iceRestartConnecting
}

extension String {
    public var callUUID: UUID {
        let hash = SHA256.hash(data: Data(self .utf8)).data
        let truncatedHash = Array(hash.prefix(16))
        let uuidString = NSUUID(uuidBytes: truncatedHash).uuidString
        return UUID(uuidString: uuidString)!
    }
}

extension Server_IncomingCall {
    public var isTooLate: Bool {
        // If the serverTimestamp is later than callWaitTimeout seconds: typically 60seconds from the original timestamp.
        // This call is late and should be considered as a missed call.
        return (serverSentTsMs - timestampMs) > ServerProperties.callWaitTimeoutSec * 1000
    }
}
