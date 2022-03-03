//
//  PacketID.swift
//  Core
//
//  Created by Garrett on 5/28/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation

public enum PacketID {
    public static func generate(short: Bool = false) -> String {
        if short {
            var data = Data()
            shortIDQueue.sync {
                data = nextShortID ?? Data.random(length: 3)
                nextShortID = data.next()
            }
            return data.base64urlEncodedString()
        }
        return Data.random(length: 18).base64urlEncodedString()
    }

    private static var nextShortID: Data?
    private static var shortIDQueue = DispatchQueue(label: "com.halloapp.id.generation")
}

extension Data {
    static func random(length: UInt8) -> Data {
        return Data((0..<length).map { _ in UInt8.random(in: 0...UInt8.max) })
    }

    /// Increments binary data. Wraps back to 0 on overflow.
    func next() -> Data {
        var outBytes = Array(self)
        var i = outBytes.count - 1
        while i >= 0 {
            if outBytes[i] == UInt8.max {
                outBytes[i] = 0
                i -= 1
            } else {
                outBytes[i] += 1
                break
            }
        }
        return Data(outBytes)
    }
}
