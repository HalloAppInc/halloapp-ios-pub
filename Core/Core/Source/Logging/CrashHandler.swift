//
//  CrashHandler.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Foundation

class CrashHandler {

    static func registerHandlers() {
        NSSetUncaughtExceptionHandler { (exception) in
            let name = exception.reason ?? "Unknown"
            let stackTrace = exception.callStackSymbols.joined(separator: "\n\t")
            DDLogError("\n======\nCrash: \(name)\nStack:\n(\n\(stackTrace)\n)")
        }
    }

}
