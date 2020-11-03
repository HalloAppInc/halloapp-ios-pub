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
        dateFormatter.locale = NSLocale.current
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = .none
        return dateFormatter
    }()
    
    // Thu
    static let dateTimeFormatterDayOfWeek: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = NSLocale.current
        dateFormatter.setLocalizedDateFormatFromTemplate("E")
        return dateFormatter
    }()

    // Jun 20
    static let dateTimeFormatterMonthDay: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = NSLocale.current
        dateFormatter.setLocalizedDateFormatFromTemplate("dMMM")
        return dateFormatter
    }()
    
    // Jun 2020
    static let dateTimeFormatterMonthYear: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = NSLocale.current
        dateFormatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
        return dateFormatter
    }()
    
    // Thu 8:48 PM
    static let dateTimeFormatterDayOfWeekTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = NSLocale.current
        dateFormatter.setLocalizedDateFormatFromTemplate("EHHmm")
        return dateFormatter
    }()

    // Jun 20 8:48 PM
    static let dateTimeFormatterMonthDayTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = NSLocale.current
        dateFormatter.setLocalizedDateFormatFromTemplate("dMMMHHmm")
        return dateFormatter
    }()
    
    // Jun 20 2020 8:48 PM
    static let dateTimeFormatterMonthDayYearTime: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = NSLocale.current
        dateFormatter.setLocalizedDateFormatFromTemplate("dMMMyyyyHHmm")
        return dateFormatter
    }()
}
