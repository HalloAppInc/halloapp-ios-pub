//
//  LogFileManager.swift
//  Core
//
//  Created by Igor Solomennikov on 7/13/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Foundation

class LogFileManager: DDLogFileManagerDefault {

    override func isLogFile(withName fileName: String) -> Bool {
        let hasProperPrefix = fileName.hasPrefix(Bundle.main.bundleIdentifier ?? "com.halloapp.hallo")
        let hasProperSuffix = fileName.hasSuffix(".log")
        return hasProperPrefix && hasProperSuffix
    }
    
    override var newLogFileName: String {
        get {
            let appName = Bundle.main.bundleIdentifier ?? "com.halloapp.hallo"
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            
            if let gmtTimeZone = TimeZone(secondsFromGMT: 0) {
                dateFormatter.timeZone = gmtTimeZone
            }
            
            let toReturn = "\(appName)-\(dateFormatter.string(from: Date())).log"
            return toReturn
        }
    }
}
