//
//  CrashlyticsLogger.swift
//  Core
//
//  Created by Ethan Rosenthal on 6/10/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation
import CocoaLumberjack
import FirebaseCrashlytics

public final class CrashlyticsLogger: DDAbstractLogger {

    public override func log(message logMessage: DDLogMessage) {

        var message = logMessage.message

        let ivar = class_getInstanceVariable(object_getClass(self), "_logFormatter")
        if let formatter = object_getIvar(self, ivar!) as? DDLogFormatter {
            message = formatter.format(message: logMessage) ?? message
        }

        Crashlytics.crashlytics().log(message)
    }
}

extension CrashlyticsLogger: ErrorLogger {
    public func logError(_ error: Error) {
        Crashlytics.crashlytics().record(error: error)
    }
}
