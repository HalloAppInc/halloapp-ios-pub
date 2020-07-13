//
//  LogFileManager.swift
//  Core
//
//  Created by Igor Solomennikov on 7/13/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjack
import Foundation

class LogFileManager: DDLogFileManagerDefault {

    override func isLogFile(withName fileName: String) -> Bool {
        let hasProperPrefix = fileName.hasPrefix("com.halloapp.hallo")
        let hasProperSuffix = fileName.hasSuffix(".log")
        return hasProperPrefix && hasProperSuffix
    }
}
