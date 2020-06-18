//
//  DateFormatter.swift
//  HalloApp
//
//  Created by Tony Jiang on 6/18/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

extension DateFormatter {
    
    // 8:48pm
    static let dateTimeFormatterCompactTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.amSymbol = "am"
        dateFormatter.pmSymbol = "pm"
        dateFormatter.dateFormat = "h:mma"
        return dateFormatter
    }()
    
    // 8:48 PM
    static let dateTimeFormatterTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "h:mm a", options: 0, locale: NSLocale.current)
        return dateFormatter
    }()
    
    // Thu
    static let dateTimeFormatterDayOfWeek: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "eee", options: 0, locale: NSLocale.current)
        return dateFormatter
    }()

    // Jun 20
    static let dateTimeFormatterMonthDay: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMM d", options: 0, locale: NSLocale.current)
        return dateFormatter
    }()
    
    // Jun 2020
    static let dateTimeFormatterMonthYear: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMM yyyy", options: 0, locale: NSLocale.current)
        return dateFormatter
    }()
    
    // Thu 8:48pm
    static let dateTimeFormatterDayOfWeekCompactTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.amSymbol = "am"
        dateFormatter.pmSymbol = "pm"
        dateFormatter.dateFormat = "eee h:mma"
        return dateFormatter
    }()

    // Jun 20 8:48pm
    static let dateTimeFormatterMonthDayCompactTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.amSymbol = "am"
        dateFormatter.pmSymbol = "pm"
        dateFormatter.dateFormat = "MMM d h:mma"
        return dateFormatter
    }()
    
    // Jun 20 2020 8:48pm
    static let dateTimeFormatterMonthDayYearCompactTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.amSymbol = "am"
        dateFormatter.pmSymbol = "pm"
        dateFormatter.dateFormat = "MMM d yyyy h:mma"
        return dateFormatter
    }()
}
