//
//  CommonEvents.swift
//  Core
//
//  Created by Garrett on 10/7/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation

public extension CountableEvent {
    static func decryption(error: DecryptionError?, senderPlatform: String?) -> CountableEvent {
        var extraDimensions = ["result": error?.rawValue ?? "success"]
        extraDimensions["senderPlatform"] = senderPlatform
        return CountableEvent(namespace: "crypto", metric: "decryption", extraDimensions: extraDimensions)
    }

    static func encryption(error: EncryptionError?) -> CountableEvent {
        let result = error?.rawValue ?? "success"
        return CountableEvent(namespace: "crypto", metric: "encryption", extraDimensions: ["result": result])
    }

    static func passwordMigrationBegan() -> CountableEvent {
        return CountableEvent(namespace: "keychain", metric: "migration", extraDimensions: ["status": "began"])
    }

    static func passwordMigrationSucceeded() -> CountableEvent {
        return CountableEvent(namespace: "keychain", metric: "migration", extraDimensions: ["status": "succeeded"])
    }
}
