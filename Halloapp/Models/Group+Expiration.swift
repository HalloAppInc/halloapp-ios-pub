//
//  Group+Expiration.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 9/13/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon

extension Group {

    private static let expiryTimeFormatter: DateComponentsFormatter = {
        let expiryTimeFormatter = DateComponentsFormatter()
        expiryTimeFormatter.allowedUnits = [.day, .hour]
        expiryTimeFormatter.collapsesLargestUnit = true
        expiryTimeFormatter.maximumUnitCount = 1
        expiryTimeFormatter.unitsStyle = .full
        return expiryTimeFormatter
    }()

    private static let expiryDateFormatter: DateFormatter = {
        let expiryDateFormatter = DateFormatter()
        expiryDateFormatter.dateStyle = .short
        expiryDateFormatter.timeStyle = .none
        return expiryDateFormatter
    }()

    public class func formattedExpirationTime(type: ExpirationType, time: Int64) -> String {
        switch type {
        case .expiresInSeconds:
            // Special case - display 31 days as 30 days in UI
            var seconds = Int(time)
            if seconds == 31 * 24 * 60 * 60 {
                seconds = 30 * 24 * 60 * 60
            }
            return expiryTimeFormatter.string(from: DateComponents(second: seconds)) ?? ""
        case .never:
            return Localizations.chatGroupExpiryOptionNever
        case .customDate:
            return expiryDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(time)))
        }
    }
}
