//
//  Log.swift
//  Core
//
//  Created by Ethan Rosenthal on 6/10/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation
import CocoaLumberjack
import FirebaseCrashlytics

public final class CLLogger: DDAbstractLogger {

    public override func log(message logMessage: DDLogMessage) {
        #if DEBUG
        #else
        switch logMessage.flag {
            case .error: break
            case .warning: break
            case .info: break
            case .debug: break
            default: return
            }
        #endif
        var message = logMessage.message
        
        let ivar = class_getInstanceVariable(object_getClass(self), "_logFormatter")
        if let formatter = object_getIvar(self, ivar!) as? DDLogFormatter {
            message = formatter.format(message: logMessage) ?? message
        }

        Crashlytics.crashlytics().log(message)
    }
}
