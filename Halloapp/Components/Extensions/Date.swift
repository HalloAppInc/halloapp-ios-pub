//
//  Date.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

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
     - returns: Localized timstamp to be used in Feed and comments.

     Timestamp formatting rules are:
     - under 1 minute: "Now"
     - same day or under 6 hours: 12:05 pm
     - under 1 week: Tue 12:05 pm
     - otherwise: 5d
     */
    func feedTimestamp() -> String {
        let seconds = -self.timeIntervalSinceNow

        // TODO: Localize
        if seconds < Date.minutes(1) {
            return "Now"
        } else if seconds < Date.hours(6) || Calendar.current.isDateInToday(self) {
            return DateFormatter.dateTimeFormatterCompactTime.string(from: self)
        } else if seconds < Date.weeks(1) {
            return DateFormatter.dateTimeFormatterDayOfWeekCompactTime.string(from: self)
        } else {
            return "\(Date.toDays(seconds))d"
        }
    }

    func chatListTimestamp() -> String {
        let seconds = -self.timeIntervalSinceNow
        
        if seconds < Date.minutes(1) {
            return "Now"
        } else if Calendar.current.isDateInToday(self) {
            let dateFormatter = DateFormatter.dateTimeFormatterCompactTime
            return dateFormatter.string(from: self)
        } else if Calendar.current.isDateInYesterday(self) {
            return "Yesterday"
        } else if seconds < Date.weeks(1) {
            let dateFormatter = DateFormatter.dateTimeFormatterDayOfWeek
            return dateFormatter.string(from: self)
        } else if seconds < Date.weeks(52) {
            let dateFormatter = DateFormatter.dateTimeFormatterMonthDay
            return dateFormatter.string(from: self)
        } else {
            let dateFormatter = DateFormatter.dateTimeFormatterMonthYear
            return dateFormatter.string(from: self)
        }
    }
    
    func chatTimestamp() -> String {
        let seconds = -self.timeIntervalSinceNow
        
        if seconds < Date.minutes(1) {
            return "now"
        } else if Calendar.current.isDateInToday(self) {
            let dateFormatter = DateFormatter.dateTimeFormatterCompactTime
            return dateFormatter.string(from: self)
        } else if seconds < Date.weeks(1) {
            let dateFormatter = DateFormatter.dateTimeFormatterDayOfWeekCompactTime
            return dateFormatter.string(from: self)
        } else if seconds < Date.weeks(52) {
            let dateFormatter = DateFormatter.dateTimeFormatterMonthDayCompactTime
            return dateFormatter.string(from: self)
        } else {
            let dateFormatter = DateFormatter.dateTimeFormatterMonthDayYearCompactTime
            return dateFormatter.string(from: self)
        }
    }
    
    func lastSeenTimestamp() -> String {
        let seconds = -self.timeIntervalSinceNow
        
        if seconds < Date.minutes(1) {
            return "Last seen less than a minute ago"
        } else if seconds < Date.hours(1) {
            let unitTime = Date.toMinutes(seconds, rounded: true)
            let plural = unitTime == 1 ? "" : "s"
            return "Last seen \(unitTime) minute\(plural) ago"
        } else if Calendar.current.isDateInToday(self) {
            let dateFormatter = DateFormatter.dateTimeFormatterTime
            return "Last seen today at \(dateFormatter.string(from: self))"
        } else if Calendar.current.isDateInYesterday(self) {
            let dateFormatter = DateFormatter.dateTimeFormatterTime
            return "Last seen yesterday at \(dateFormatter.string(from: self))"
        } else if seconds < Date.weeks(1) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEE 'at' h:mm a"
            return "Last seen \(dateFormatter.string(from: self))"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "M/d/yy 'at' h:mm a"
            return "Last seen \(dateFormatter.string(from: self))"
        }
    }
}
