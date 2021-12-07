//
//  CommonEvents.swift
//  Core
//
//  Created by Garrett on 10/7/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation

public extension CountableEvent {
    static func decryption(error: DecryptionError?, sender: UserAgent?) -> CountableEvent {
        var extraDimensions = ["result": error?.rawValue ?? "success"]
        extraDimensions["senderPlatform"] = sender?.platform.rawValue.lowercased()
        extraDimensions["senderVersion"] = sender?.version
        return CountableEvent(namespace: "crypto", metric: "decryption", extraDimensions: extraDimensions)
    }

    static func encryption(error: EncryptionError?) -> CountableEvent {
        let result = error?.rawValue ?? "success"
        return CountableEvent(namespace: "crypto", metric: "encryption", extraDimensions: ["result": result])
    }

    static func groupDecryption(error: DecryptionError?, itemType: FeedElementType, sender: UserAgent?) -> CountableEvent {
        var extraDimensions = ["result": error == nil ? "ok" : "fail"]
        if let error = error {
            extraDimensions["failure_reason"] = error.rawValue
        }
        extraDimensions["version"] = AppContext.appVersionForService
        extraDimensions["item_type"] = itemType.rawString
        extraDimensions["senderPlatform"] = sender?.platform.rawValue.lowercased()
        extraDimensions["senderVersion"] = sender?.version
        return CountableEvent(namespace: "crypto", metric: "group_decryption", extraDimensions: extraDimensions)
    }

    static func groupEncryption(error: EncryptionError?, itemType: FeedElementType) -> CountableEvent {
        var extraDimensions = ["result": error == nil ? "ok" : "fail"]
        if let error = error {
            extraDimensions["failure_reason"] = error.rawValue
        }
        extraDimensions["version"] = AppContext.appVersionForService
        extraDimensions["item_type"] = itemType.rawString
        return CountableEvent(namespace: "crypto", metric: "group_encryption", extraDimensions: extraDimensions)
    }

    static func sessionReset(_ reset: Bool) -> CountableEvent {
        var extraDimensions = ["reset": reset ? "true" : "false"]
        extraDimensions["version"] = AppContext.appVersionForService
        return CountableEvent(namespace: "crypto", metric: "e2e_session", extraDimensions: extraDimensions)
    }

    static func packetDecryption(duringHandshake: Bool) -> CountableEvent {
        let extraDimensions = ["type": duringHandshake ? "handshake" : "stream"]
        return CountableEvent(namespace: "noise", metric: "decryption_error", extraDimensions: extraDimensions)
    }
}
