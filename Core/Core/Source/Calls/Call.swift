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

public enum CallError: Error {
    case systemError
    case alreadyInCall
    case noActiveCall
}

public enum EndCallReason: Int, Codable {
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
        }
    }
}

public enum CallState {
    case inactive
    case connecting
    case ringing
    case active
    case held
    case disconnected
}

extension String {
    public var callUUID: UUID {
        let hash = SHA256.hash(data: Data(self .utf8)).data
        let truncatedHash = Array(hash.prefix(16))
        let uuidString = NSUUID(uuidBytes: truncatedHash).uuidString
        return UUID(uuidString: uuidString)!
    }
}
