//
//  TimeInterval.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation

extension TimeInterval {

    // 8:20
    public var formatted: String {
        let seconds = Int(self)
        return String(format: "%d:%.2d", seconds / 60, seconds % 60)
    }

    // 8:20.742
    public var formattedPrecise: String {
        let seconds = Int(self)
        let milliseconds = Int(truncatingRemainder(dividingBy: 1) * 1000)
        return String(format: "%d:%.2d.%.3d", seconds / 60, seconds % 60, milliseconds)
    }
}
