//
//  DateFormatter.swift
//  HalloApp
//
//  Created by Tony Jiang on 6/18/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

public extension DateFormatter {

    // 8:48 PM
    static let dateTimeFormatterTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = .none
        return dateFormatter
    }()

    // Thu
    static let dateTimeFormatterDayOfWeek: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.setLocalizedDateFormatFromTemplate("E")
        return dateFormatter
    }()

    // Thursday
    static let dateTimeFormatterDayOfWeekLong: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.setLocalizedDateFormatFromTemplate("EEEE")
        return dateFormatter
    }()

    // Jan 20
    static let dateTimeFormatterMonthDay: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.setLocalizedDateFormatFromTemplate("dMMM")
        return dateFormatter
    }()

    // January 20
    static let dateTimeFormatterMonthDayLong: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.setLocalizedDateFormatFromTemplate("dMMMM")
        return dateFormatter
    }()

    // 06/20/2020
    static let dateTimeFormatterShortDate: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.timeStyle = .none
        dateFormatter.dateStyle = .short
        return dateFormatter
    }()

    // Jun 2020
    static let dateTimeFormatterMonthYear: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
        return dateFormatter
    }()

    // Thu 8:48 PM
    static let dateTimeFormatterDayOfWeekTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.setLocalizedDateFormatFromTemplate("jEHHmm")
        return dateFormatter
    }()

    // Jun 20 8:48 PM
    static let dateTimeFormatterMonthDayTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.setLocalizedDateFormatFromTemplate("jdMMMHHmm")
        return dateFormatter
    }()

    // Jun 20 2020 8:48 PM
    static let dateTimeFormatterMonthDayYearTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.setLocalizedDateFormatFromTemplate("jdMMMyyyyHHmm")
        return dateFormatter
    }()

    // January 20 2020
    static let dateTimeFormatterMonthDayYearLong: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.setLocalizedDateFormatFromTemplate("dMMMMyyyy")
        return dateFormatter
    }()
}
