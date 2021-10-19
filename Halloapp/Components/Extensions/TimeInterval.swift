//
//  TimeInterval.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation

extension TimeInterval {
    // 08:20
    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = [.minute, .second]

        return formatter
    }()

    // 8:20
    public var formatted: String {
        guard var formatted = Self.durationFormatter.string(from: self) else { return "\(self)" }

        if formatted.hasPrefix("0") == true && formatted.count > 4 {
            formatted = String(formatted.dropFirst())
        }

        return formatted
    }

    // 8:20.742
    public var formattedPrecise: String {
        let ms = String(Int(self * 1000) % 1000)
        return formatted + "." + (String(repeating: "0", count: 3 - ms.count) + ms)
    }
}
