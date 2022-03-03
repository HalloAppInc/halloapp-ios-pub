//
//  CommonEvents.swift
//  Core
//
//  Created by Garrett on 10/7/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//
import Foundation

public extension CountableEvent {

    static func sessionReset(_ reset: Bool) -> CountableEvent {
        var extraDimensions = ["reset": reset ? "true" : "false"]
        extraDimensions["version"] = AppContextCommon.appVersionForService
        return CountableEvent(namespace: "crypto", metric: "e2e_session", extraDimensions: extraDimensions)
    }

    static func packetDecryption(duringHandshake: Bool) -> CountableEvent {
        let extraDimensions = ["type": duringHandshake ? "handshake" : "stream"]
        return CountableEvent(namespace: "noise", metric: "decryption_error", extraDimensions: extraDimensions)
    }
}
