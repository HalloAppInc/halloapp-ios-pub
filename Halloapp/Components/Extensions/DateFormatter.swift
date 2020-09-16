//
//  DateFormatter.swift
//  HalloApp
//
//  Created by Tony Jiang on 6/18/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

extension DateFormatter {
        
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
    
    // Thu 8:48 PM
    static let dateTimeFormatterDayOfWeekTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "eee h:mm a", options: 0, locale: NSLocale.current)
        return dateFormatter
    }()

    // Jun 20 8:48 PM
    static let dateTimeFormatterMonthDayTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMM d h:mm a", options: 0, locale: NSLocale.current)
        return dateFormatter
    }()
    
    // Jun 20 2020 8:48 PM
    static let dateTimeFormatterMonthDayYearTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMM d yyyy h:mm a", options: 0, locale: NSLocale.current)
        return dateFormatter
    }()
}
