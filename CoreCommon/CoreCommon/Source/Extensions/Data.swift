//
//  Data.swift
//  Core
//
//  Created by Igor Solomennikov on 8/26/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation

public extension Data {

    init?(base64urlEncoded base64String: String) {
        var base64 = base64String
        base64 = base64.replacingOccurrences(of: "-", with: "+")
        base64 = base64.replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 = base64.appending("=")
        }
        self.init(base64Encoded: base64)
    }

    func base64urlEncodedString() -> String {
        var result = base64EncodedString()
        result = result.replacingOccurrences(of: "+", with: "-")
        result = result.replacingOccurrences(of: "/", with: "_")
        result = result.replacingOccurrences(of: "=", with: "")
        return result
    }
}
