//
//  Data.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/15/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

extension Data {
    func hexString() -> String {
        return self.map { String(format: "%02.2hhx", $0) }.joined()
    }
}
