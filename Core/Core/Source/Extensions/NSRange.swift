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

    /// Returns true if ranges have intersection of non-zero length or a zero-length intersection anywhere other than start or end
    func overlaps(_ other: NSRange) -> Bool {
        guard let overlap = intersection(other) else { return false }
        return overlap.length > 0 || !isAdjacent(to: other)
    }

    /// Returns true if either range starts at the other's endpoint.
    func isAdjacent(to other: NSRange) -> Bool {
        return location == NSMaxRange(other) || other.location == NSMaxRange(self)
    }
}
