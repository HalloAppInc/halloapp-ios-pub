//
//  NSRange.swift
//  Core
//
//  Created by Garrett on 7/29/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation

public extension NSRange {
    func contains(_ other: NSRange) -> Bool {
        return NSLocationInRange(other.location, self) && NSMaxRange(self) >= NSMaxRange(other)
    }
}
