//
//  Date.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import Foundation

private extension Localizations {

    static var nowCapitalized: String {
        NSLocalizedString("timestamp.now.capitalized", value: "Now", comment: "Capitalized translation of `Now` to be used as timestamp.")
    }

    static var nowLowercase: String {
        NSLocalizedString("timestamp.now.lowercase", value: "now", comment: "Lowercase translation of `Now` to be used as timestamp.")
    }

    static var today: String {
        NSLocalizedString("timestamp.today", value: "Today", comment: "Timestamp: `Today`")
    }
    
    static var yesterday: String {
        NSLocalizedString("timestamp.yesterday", value: "Yesterday", comment: "Timestamp: `Yesterday`")
    }
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
     - returns: Localized timstamp to be used in Feed and comments.

     Timestamp formatting rules are:
     - under 1 minute: "Now"
     - same day or under 6 hours: 12:05 pm
     - under 1 week: Tue 12:05 pm
     - otherwise: 5d
     */
    func feedTimestamp() -> String {
        let seconds = -timeIntervalSinceNow

        if seconds < Date.minutes(1) {
            return Localizations.nowCapitalized
        } else if seconds < Date.hours(6) || Calendar.current.isDateInToday(self) {
            return DateFormatter.dateTimeFormatterTime.string(from: self)
        } else if seconds < Date.days(5) {
            return DateFormatter.dateTimeFormatterDayOfWeekTime.string(from: self)
        } else if Calendar.current.isDate(self, equalTo: Date(), toGranularity: .year) {
            return DateFormatter.dateTimeFormatterMonthDay.string(from: self)
        } else {
            return DateFormatter.dateTimeFormatterShortDate.string(from: self)
        }
    }

    func chatListTimestamp() -> String {
        let seconds = -timeIntervalSinceNow
        
        if seconds < Date.minutes(1) {
            return Localizations.nowCapitalized
        } else if Calendar.current.isDateInToday(self) {
            return DateFormatter.dateTimeFormatterTime.string(from: self)
        } else if Calendar.current.isDateInYesterday(self) {
            return Localizations.yesterday
        } else if seconds < Date.days(5) {
            return DateFormatter.dateTimeFormatterDayOfWeek.string(from: self)
        } else if Calendar.current.isDate(self, equalTo: Date(), toGranularity: .year) {
            return DateFormatter.dateTimeFormatterMonthDay.string(from: self)
        } else {
            return DateFormatter.dateTimeFormatterShortDate.string(from: self)
        }
    }
    
    func chatMsgGroupingTimestamp() -> String {
        let seconds = -timeIntervalSinceNow
        
        if Calendar.current.isDateInToday(self) {
            return Localizations.today
        } else if Calendar.current.isDateInYesterday(self) {
            return Localizations.yesterday
        } else if seconds < Date.days(5) {
            return DateFormatter.dateTimeFormatterDayOfWeekLong.string(from: self)
        } else if Calendar.current.isDate(self, equalTo: Date(), toGranularity: .year) {
            return DateFormatter.dateTimeFormatterMonthDayLong.string(from: self)
        } else {
            return DateFormatter.dateTimeFormatterMonthDayYearLong.string(from: self)
        }
    }
    
    func chatTimestamp() -> String {
        let seconds = -timeIntervalSinceNow
        
        if seconds < Date.minutes(1) {
            return Localizations.nowLowercase
        } else if Calendar.current.isDateInToday(self) {
            let dateFormatter = DateFormatter.dateTimeFormatterTime
            return dateFormatter.string(from: self)
        } else if seconds < Date.weeks(1) {
            let dateFormatter = DateFormatter.dateTimeFormatterDayOfWeekTime
            return dateFormatter.string(from: self)
        } else if seconds < Date.weeks(52) {
            let dateFormatter = DateFormatter.dateTimeFormatterMonthDayTime
            return dateFormatter.string(from: self)
        } else {
            let dateFormatter = DateFormatter.dateTimeFormatterMonthDayYearTime
            return dateFormatter.string(from: self)
        }
    }
    
    func lastSeenTimestamp() -> String {
        let seconds = -self.timeIntervalSinceNow

        let time = DateFormatter.dateTimeFormatterTime.string(from: self)
        if Calendar.current.isDateInToday(self) {
            let formatString = NSLocalizedString("timestamp.last.seen.today.at", value: "Last seen today at %@", comment: "Last seen timestamp: today at specific time.")
            return String(format: formatString, time)
        } else if Calendar.current.isDateInYesterday(self) {
            let formatString = NSLocalizedString("timestamp.last.seen.yesterday.at", value: "Last seen yesterday at %@", comment: "Last seen timestamp: yesterday at specific time.")
            return String(format: formatString, time)
        } else if seconds < Date.weeks(1) {
            let dayOfWeek = DateFormatter.dateTimeFormatterDayOfWeek.string(from: self)
            let formatString = NSLocalizedString("timestamp.last.seen.dayofweek.at.time", value: "Last seen %1$@ at %2$@", comment: "Last seen timestamp: day of week and time")
            return String(format: formatString, dayOfWeek, time)
        } else {
            let date = DateFormatter.dateTimeFormatterShortDate.string(from: self)
            let formatString = NSLocalizedString("timestamp.last.seen.date.at.time", value: "Last seen %1$@ at %2$@", comment: "Last seen timestamp: full date in short format and time")
            return String(format: formatString, date, time)
        }
    }
}
