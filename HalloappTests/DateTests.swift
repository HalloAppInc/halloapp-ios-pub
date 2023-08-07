//
//  DateTests.swift
//  HalloAppTests
//
//  Created by Matt Geimer on 6/22/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import XCTest
@testable import HalloApp
@testable import Core
@testable import CoreCommon

class DateTests: XCTestCase {
    
    var referenceDate: Date!
    var referenceDateToday: Date!
    
    override func setUp() {
        // Tests are run with time zone set to UTC for CI environment
        // UTC: Wednesday, June 23, 2021 4:35:35 PM
        referenceDate = Date(timeIntervalSince1970: 1624466135)
        // UTC: Today (whenever tests are run), 4:35:35 PM
        referenceDateToday = Calendar.current.date(bySettingHour: 16, minute: 35, second: 35, of: Date()) ?? Date()
    }
    
    // MARK: Test TimeInterval convenience
    // Testing these is important because they're dependencies in the rest of the Date extension
    // They're also useful to use in our test cases
    
    func testDateSeconds() {
        XCTAssertEqual(Date.seconds(5), TimeInterval(5))
    }
    
    func testDateMinutes() {
        XCTAssertEqual(Date.minutes(5), TimeInterval(5 * 60))
    }
    
    func testDateHours() {
        XCTAssertEqual(Date.hours(5), TimeInterval(5 * 60 * 60))
    }
    
    func testDateDays() {
        XCTAssertEqual(Date.days(5), TimeInterval(5 * 60 * 60 * 24))
    }
    
    func testDateWeeks() {
        XCTAssertEqual(Date.weeks(5), TimeInterval(5 * 60 * 60 * 24 * 7))
    }
    
    func testDateToSeconds() {
        let timeInterval = Date.seconds(5)
        XCTAssertEqual(Date.toSeconds(timeInterval), 5)
    }
    
    func testDateToMinutes() {
        let minutes = 2
        let seconds = 35
        let timeInterval = Date.minutes(minutes) + Date.seconds(seconds)
        XCTAssertEqual(Date.toMinutes(timeInterval, rounded: false), minutes)
        XCTAssertEqual(Date.toMinutes(timeInterval, rounded: true), minutes + 1)
    }
    
    func testDateToHours() {
        let hours = 5
        let minutes = 35
        let timeInterval = Date.hours(hours) + Date.minutes(minutes)
        XCTAssertEqual(Date.toHours(timeInterval, rounded: false), hours)
        XCTAssertEqual(Date.toHours(timeInterval, rounded: true), hours + 1)
    }
    
    func testDateToDays() {
        let days = 2
        let hours = 13
        let timeInterval = Date.days(days) + Date.hours(hours)
        XCTAssertEqual(Date.toDays(timeInterval, rounded: false), days)
        XCTAssertEqual(Date.toDays(timeInterval, rounded: true), days + 1)
    }
    
    func testDateToWeeks() {
        let weeks = 2
        let days = 4
        let timeInterval = Date.weeks(weeks) + Date.days(days)
        XCTAssertEqual(Date.toWeeks(timeInterval, rounded: false), weeks)
        XCTAssertEqual(Date.toWeeks(timeInterval, rounded: true), weeks + 1)
    }
    
    // MARK: Timestamp formats tests
    // These test for the different formatting of dates based on how long ago they were.
    
    func testFeedTimestamp() {
        // Test now timestamp
        let nowDateLowerBound = Date(timeInterval: -1, since: referenceDate)
        XCTAssertEqual(nowDateLowerBound.feedTimestamp(referenceDate), "Now")
        
        let nowDateUpperBound = Date(timeInterval: -59, since: referenceDate)
        XCTAssertEqual(nowDateUpperBound.feedTimestamp(referenceDate), "Now")
        
        // Test time timestamp
        let underSixHoursDateLowerBound = Date(timeInterval: -Date.minutes(1), since: referenceDate)
        if #available(iOS 17, *) {
            XCTAssertEqual(underSixHoursDateLowerBound.feedTimestamp(referenceDate), "4:34\u{202F}PM")
        } else {
            XCTAssertEqual(underSixHoursDateLowerBound.feedTimestamp(referenceDate), "4:34 PM")
        }

        let underSixHoursDateUpperBound = Date(timeInterval: -Date.hours(5) - Date.minutes(59), since: referenceDate)
        if #available(iOS 17, *) {
            XCTAssertEqual(underSixHoursDateUpperBound.feedTimestamp(referenceDate), "10:36\u{202F}AM")
        } else {
            XCTAssertEqual(underSixHoursDateUpperBound.feedTimestamp(referenceDate), "10:36 AM")
        }
        
        // Test day/time timestamp
        let underOneWeekDateLowerBound = Date(timeInterval: -Date.days(1), since: referenceDate)
        if #available(iOS 17, *) {
            XCTAssertEqual(underOneWeekDateLowerBound.feedTimestamp(referenceDate), "Tue 4:35\u{202F}PM")
        } else {
            XCTAssertEqual(underOneWeekDateLowerBound.feedTimestamp(referenceDate), "Tue 4:35 PM")
        }
        
        let underOneWeekDateUpperBound = Date(timeInterval: -Date.days(5) + 1, since: referenceDate)
        if #available(iOS 17, *) {
            XCTAssertEqual(underOneWeekDateUpperBound.feedTimestamp(referenceDate), "Fri 4:35\u{202F}PM")
        } else {
            XCTAssertEqual(underOneWeekDateUpperBound.feedTimestamp(referenceDate), "Fri 4:35 PM")
        }
        
        // Test days ago timestamp
        let daysAgoDateLowerBound = Date(timeInterval: -Date.days(5), since: referenceDate)
        XCTAssertEqual(daysAgoDateLowerBound.feedTimestamp(referenceDate), "Jun 18")
        
        let daysAgoDateUpperBound = Date(timeInterval: -Date.weeks(26) + 1, since: referenceDate)
        XCTAssertEqual(daysAgoDateUpperBound.feedTimestamp(referenceDate), "Dec 23")
        
        // Test date timestamp
        let yearsAgoDateLowerBound = Date(timeInterval: -Date.weeks(26), since: referenceDate)
        XCTAssertEqual(yearsAgoDateLowerBound.feedTimestamp(referenceDate), "12/23/20")
    }
    
    func testDeletedPostTimestamp() {
        // Test now timestamp
        let nowDateLowerBound = Date(timeInterval: -1, since: referenceDate)
        XCTAssertEqual(nowDateLowerBound.deletedPostTimestamp(referenceDate), "Now")
        
        let nowDateUpperBound = Date(timeInterval: -59, since: referenceDate)
        XCTAssertEqual(nowDateUpperBound.deletedPostTimestamp(referenceDate), "Now")
        
        // Test today timestamp
        let todayDateLowerBound = Date(timeInterval: -60, since: Date())
        XCTAssertEqual(todayDateLowerBound.deletedPostTimestamp(Date()), "Today")
        
        let todayDateUpperBound = Calendar(identifier: .gregorian).startOfDay(for: Date())
        XCTAssertEqual(todayDateUpperBound.deletedPostTimestamp(Date()), "Today")
        
        // Test date timestamp
        let otherwiseDate = Date(timeInterval: -1, since: Calendar.current.startOfDay(for: referenceDate))
        XCTAssertEqual(otherwiseDate.deletedPostTimestamp(referenceDate), "6/22/21")
    }
    
    func testChatListTimestamp() {
        // Test now timestamp
        let nowDateLowerBound = Date(timeInterval: -1, since: referenceDate)
        XCTAssertEqual(nowDateLowerBound.chatListTimestamp(referenceDate), "Now")
        
        // Test today timestamp
        let todayDateLowerBound = Date(timeInterval: -60, since: referenceDateToday)
        if #available(iOS 17, *) {
            XCTAssertEqual(todayDateLowerBound.chatListTimestamp(referenceDateToday), "4:34\u{202F}PM")
        } else {
            XCTAssertEqual(todayDateLowerBound.chatListTimestamp(referenceDateToday), "4:34 PM")
        }
        
        let todayDateUpperBound = Calendar(identifier: .gregorian).startOfDay(for: referenceDateToday)
        if #available(iOS 17, *) {
            XCTAssertEqual(todayDateUpperBound.chatListTimestamp(referenceDateToday), "12:00\u{202F}AM")
        } else {
            XCTAssertEqual(todayDateUpperBound.chatListTimestamp(referenceDateToday), "12:00 AM")
        }
        
        // Test yesterday timestamp
        let yesterdayDateLowerBound = Date(timeInterval: -Date.days(1), since: todayDateLowerBound)
        XCTAssertEqual(yesterdayDateLowerBound.chatListTimestamp(referenceDateToday), "Yesterday")
        
        let yesterdayDateUpperBound = Date(timeInterval: -Date.days(1), since: todayDateUpperBound)
        XCTAssertEqual(yesterdayDateUpperBound.chatListTimestamp(referenceDateToday), "Yesterday")
        
        // Test day of the week timestamp
        let dayOfTheWeekLowerBound = Date(timeInterval: -Date.days(2), since: referenceDate)
        XCTAssertEqual(dayOfTheWeekLowerBound.chatListTimestamp(referenceDate), "Mon")
        
        let dayOfTheWeekUpperBound = Date(timeInterval: -Date.days(5) + 1, since: referenceDate)
        XCTAssertEqual(dayOfTheWeekUpperBound.chatListTimestamp(referenceDate), "Fri")
        
        // Test date month timestamp
        let dateMonthLowerBound = Date(timeInterval: -Date.days(5), since: referenceDate)
        XCTAssertEqual(dateMonthLowerBound.chatListTimestamp(referenceDate), "Jun 18")
        
        let dateMonthUpperBound = Date(timeInterval: -Date.weeks(26) + 1, since: referenceDate)
        XCTAssertEqual(dateMonthUpperBound.chatListTimestamp(referenceDate), "Dec 23")
        
        // Test date timestamp
        let dateStampLowerBound = Date(timeInterval: -Date.weeks(26), since: referenceDate)
        XCTAssertEqual(dateStampLowerBound.chatListTimestamp(referenceDate), "12/23/20")
    }
    
    func testChatMsgGroupingTimestamp() {
        // Test today timestamp
        let todayDateLowerBound = Date(timeInterval: -60, since: referenceDateToday)
        XCTAssertEqual(todayDateLowerBound.chatMsgGroupingTimestamp(referenceDateToday), "Today") // PROBLEM
        
        let todayDateUpperBound = Calendar(identifier: .gregorian).startOfDay(for: referenceDateToday)
        XCTAssertEqual(todayDateUpperBound.chatMsgGroupingTimestamp(referenceDateToday), "Today") // PROBLEM
        
        // Test yesterday timestamp
        let yesterdayDateLowerBound = Date(timeInterval: -Date.days(1), since: todayDateLowerBound)
        XCTAssertEqual(yesterdayDateLowerBound.chatMsgGroupingTimestamp(referenceDateToday), "Yesterday") // PROBLEM
        
        let yesterdayDateUpperBound = Date(timeInterval: -Date.days(1), since: todayDateUpperBound)
        XCTAssertEqual(yesterdayDateUpperBound.chatMsgGroupingTimestamp(referenceDateToday), "Yesterday") // PROBLEM
        
        // Test day of the week timestamp
        let dayOfTheWeekLowerBound = Date(timeInterval: -Date.days(2), since: referenceDate)
        XCTAssertEqual(dayOfTheWeekLowerBound.chatMsgGroupingTimestamp(referenceDate), "Monday")
        
        let dayOfTheWeekUpperBound = Date(timeInterval: -Date.days(5) + 1, since: referenceDate)
        XCTAssertEqual(dayOfTheWeekUpperBound.chatMsgGroupingTimestamp(referenceDate), "Friday")
        
        // Test date month timestamp
        let dateMonthLowerBound = Date(timeInterval: -Date.days(5), since: referenceDate)
        XCTAssertEqual(dateMonthLowerBound.chatMsgGroupingTimestamp(referenceDate), "June 18")
        
        let dateMonthUpperBound = Date(timeInterval: -Date.weeks(26) + 1, since: referenceDate)
        XCTAssertEqual(dateMonthUpperBound.chatMsgGroupingTimestamp(referenceDate), "December 23")
        
        // Test date timestamp
        let dateStampLowerBound = Date(timeInterval: -Date.weeks(26), since: referenceDate)
        XCTAssertEqual(dateStampLowerBound.chatMsgGroupingTimestamp(referenceDate), "December 23, 2020")
    }
    
    func testChatTimestamp() {
        // Test now timestamp
        let nowDateLowerBound = Date(timeInterval: -1, since: referenceDate)
        XCTAssertEqual(nowDateLowerBound.chatTimestamp(referenceDate), "now")
        
        let nowDateUpperBound = Date(timeInterval: -59, since: referenceDate)
        XCTAssertEqual(nowDateUpperBound.chatTimestamp(referenceDate), "now")
        
        // Test today timestamp
        let todayDateLowerBound = Date(timeInterval: -60, since: referenceDateToday)
        if #available(iOS 17, *) {
            XCTAssertEqual(todayDateLowerBound.chatTimestamp(referenceDateToday), "4:34\u{202F}PM") // PROBLEM
        } else {
            XCTAssertEqual(todayDateLowerBound.chatTimestamp(referenceDateToday), "4:34 PM") // PROBLEM
        }
        
        let todayDateUpperBound = Calendar(identifier: .gregorian).startOfDay(for: referenceDateToday)
        if #available(iOS 17, *) {
            XCTAssertEqual(todayDateUpperBound.chatTimestamp(referenceDateToday), "12:00\u{202F}AM") // PROBLEM
        } else {
            XCTAssertEqual(todayDateUpperBound.chatTimestamp(referenceDateToday), "12:00 AM") // PROBLEM
        }
        
        // Test day/time timestamp
        let underOneWeekDateLowerBound = Date(timeInterval: -Date.days(1), since: referenceDate)
        if #available(iOS 17, *) {
            XCTAssertEqual(underOneWeekDateLowerBound.chatTimestamp(referenceDate), "Tue 4:35\u{202F}PM")
        } else {
            XCTAssertEqual(underOneWeekDateLowerBound.chatTimestamp(referenceDate), "Tue 4:35 PM")
        }
        
        let underOneWeekDateUpperBound = Date(timeInterval: -Date.weeks(1) + 1, since: referenceDate)
        if #available(iOS 17, *) {
            XCTAssertEqual(underOneWeekDateUpperBound.chatTimestamp(referenceDate), "Wed 4:35\u{202F}PM")
        } else {
            XCTAssertEqual(underOneWeekDateUpperBound.chatTimestamp(referenceDate), "Wed 4:35 PM")
        }
        
        // Test day month timestamp
        let dateMonthLowerBound = Date(timeInterval: -Date.weeks(1), since: referenceDate)
        if #available(iOS 17, *) {
            XCTAssertEqual(dateMonthLowerBound.chatTimestamp(referenceDate), "Jun 16 at 4:35\u{202F}PM")
        } else {
            XCTAssertEqual(dateMonthLowerBound.chatTimestamp(referenceDate), "Jun 16 at 4:35 PM")
        }
        
        let dateMonthUpperBound = Date(timeInterval: -Date.weeks(26) + 1, since: referenceDate)
        if #available(iOS 17, *) {
            XCTAssertEqual(dateMonthUpperBound.chatTimestamp(referenceDate), "Dec 23 at 4:35\u{202F}PM")
        } else {
            XCTAssertEqual(dateMonthUpperBound.chatTimestamp(referenceDate), "Dec 23 at 4:35 PM")
        }
        
        // Test date timestamp
        let dateStampLowerBound = Date(timeInterval: -Date.weeks(26), since: referenceDate)
        if #available(iOS 17, *) {
            XCTAssertEqual(dateStampLowerBound.chatTimestamp(referenceDate), "Dec 23, 2020 at 4:35\u{202F}PM")
        } else {
            XCTAssertEqual(dateStampLowerBound.chatTimestamp(referenceDate), "Dec 23, 2020 at 4:35 PM")
        }
    }
    
    func testLastSeenTimestamp() {
        let todayTimestamp = Date()
        if #available(iOS 17, *) {
            XCTAssertEqual(todayTimestamp.lastSeenTimestamp(referenceDate), "Last seen today at 4:35\u{202F}PM")
        } else {
            XCTAssertEqual(todayTimestamp.lastSeenTimestamp(referenceDate), "Last seen today at 4:35 PM")
        }
        
        let yesterdayTimestamp = Date(timeIntervalSinceNow: -Date.days(1))
        if #available(iOS 17, *) {
            XCTAssertEqual(yesterdayTimestamp.lastSeenTimestamp(referenceDate), "Last seen yesterday at 4:35\u{202F}PM")
        } else {
            XCTAssertEqual(yesterdayTimestamp.lastSeenTimestamp(referenceDate), "Last seen yesterday at 4:35 PM")
        }
        
        let lastWeekTimestamp = Date(timeInterval: -Date.days(5) + 1, since: referenceDate)
        if #available(iOS 17, *) {
            XCTAssertEqual(lastWeekTimestamp.lastSeenTimestamp(referenceDate), "Last seen Wed at 4:35\u{202F}PM")
        } else {
            XCTAssertEqual(lastWeekTimestamp.lastSeenTimestamp(referenceDate), "Last seen Wed at 4:35 PM")
        }
        
        let weeksAgoTimestamp = Date(timeInterval: -Date.weeks(4), since: referenceDate)
        if #available(iOS 17, *) {
            XCTAssertEqual(weeksAgoTimestamp.lastSeenTimestamp(referenceDate), "Last seen 6/23/21 at 4:35\u{202F}PM")
        } else {
            XCTAssertEqual(weeksAgoTimestamp.lastSeenTimestamp(referenceDate), "Last seen 6/23/21 at 4:35 PM")
        }
    }
}
