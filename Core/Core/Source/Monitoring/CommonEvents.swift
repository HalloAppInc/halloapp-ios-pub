//
//  CommonEvents.swift
//  Core
//
//  Created by Garrett on 10/7/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation

public extension CountableEvent {
    static func decryption(error: DecryptionError?) -> CountableEvent {
        let result = error?.rawValue ?? "success"
        return CountableEvent(namespace: "crypto", metric: "decryption", extraDimensions: ["result": result])
    }

    static func encryption(error: EncryptionError?) -> CountableEvent {
        let result = error?.rawValue ?? "success"
        return CountableEvent(namespace: "crypto", metric: "encryption", extraDimensions: ["result": result])
    }
}
