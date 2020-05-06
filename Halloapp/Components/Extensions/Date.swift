//
//  Date.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

extension DateFormatter {
    /**
     Example: 24 December
     */
    static let dateTimeFormatterLongStyleNoYearNoTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMMd", options: 0, locale: NSLocale.current)
        return dateFormatter
    }()

    /**
     Example: 24 December, 2019
     */
    static let dateTimeFormatterLongStyleNoTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none
        return dateFormatter
    }()
}

extension Date {
    static func seconds(_ seconds: Int) -> TimeInterval { return TimeInterval(seconds) }
    static func minutes(_ minutes: Int) -> TimeInterval { return TimeInterval(minutes * 60) }
    static func hours(_ hours: Int) -> TimeInterval { return TimeInterval(hours * 60 * 60) }
    static func days(_ days: Int) -> TimeInterval { return TimeInterval(days * 24 * 60 * 60) }
    static func weeks(_ weeks: Int) -> TimeInterval { return TimeInterval(weeks * 7 * 24 * 60 * 60) }

    static func toSeconds(_ seconds: TimeInterval) -> Int { return Int(seconds) }
    static func toMinutes(_ seconds: TimeInterval, rounded: Bool = false) -> Int {
        if rounded {
            return Int((seconds / Date.minutes(1)).rounded())
        }
        return Int(seconds / Date.minutes(1))
    }
    static func toHours(_ seconds: TimeInterval, rounded: Bool = false) -> Int {
        if rounded {
            return Int((seconds / Date.hours(1)).rounded())
        }
        return Int(seconds / Date.hours(1))
    }
    static func toDays(_ seconds: TimeInterval, rounded: Bool = false) -> Int {
        if rounded {
            return Int((seconds / Date.days(1)).rounded())
        }
        return Int(seconds / Date.days(1))
    }
    static func toWeeks(_ seconds: TimeInterval, rounded: Bool = false) -> Int {
        if rounded {
            return Int((seconds / Date.weeks(1)).rounded())
        }
        return Int(seconds / Date.weeks(1))
    }

    /**
     - returns: Localized timstamp to be used in Feed.

     Timestamp formatting rules are:
     - under 1 minute: 15s
     - under 1 hour: 45m
     - under 1 day: 6h
     - otherwise: 5d
     */
    func postTimestamp() -> String {
        let seconds = -self.timeIntervalSinceNow

        // TODO: Localize
        if seconds < Date.minutes(1) {
            return "\(Date.toSeconds(seconds))s"
        } else if seconds < Date.hours(1) {
            return "\(Date.toMinutes(seconds))m"
        } else if seconds < Date.days(1) {
            return "\(Date.toHours(seconds))h"
        } else {
            return "\(Date.toDays(seconds))d"
        }
    }

    /**
     - returns: Localized timstamp to be used in Comments.

     Timestamp formatting rules are:
     - under 1 minute: 15s
     - under 1 hour: 45m
     - under 1 day: 6h
     - otherwise: 5d
     */
    func commentTimestamp() -> String {
        let seconds = -self.timeIntervalSinceNow

        // TODO: Localize
        if seconds < Date.minutes(1) {
            return "\(Date.toSeconds(seconds))s"
        } else if seconds < Date.hours(1) {
            return "\(Date.toMinutes(seconds, rounded: true))m"
        } else if seconds < Date.days(1) {
            return "\(Date.toHours(seconds, rounded: true))h"
        } else {
            return "\(Date.toDays(seconds, rounded: true))d"
        }
    }
    
    /**
     - returns: Localized timstamp to be used in Chat.

     Timestamp formatting rules are:
     - under 1 minute: now
     - under 1 hour: 45m
     - under 1 day: 6h
     - otherwise: 5d
     */
    func chatTimestamp() -> String {
        let seconds = -self.timeIntervalSinceNow

        // TODO: Localize
        if seconds < Date.minutes(1) {
            return "now"
        } else if seconds < Date.hours(1) {
            return "\(Date.toMinutes(seconds, rounded: true))m"
        } else if seconds < Date.days(1) {
            return "\(Date.toHours(seconds, rounded: true))h"
        } else {
            return "\(Date.toDays(seconds, rounded: true))d"
        }
    }
}
