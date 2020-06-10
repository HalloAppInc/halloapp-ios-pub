//
//  Logger.swift
//  Core
//
//  Created by Ethan Rosenthal on 6/10/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation
import CocoaLumberjack
import FirebaseCrashlytics

public final class Log {
    
    public final class func i(_ message: String) -> Void {
        DDLogInfo(message)
        guard let threadName = Thread.current.name else { return }
        Crashlytics.crashlytics().log(threadName + "/I/halloapp: " + message)
    }
    
    public final class func e(_ message: String) -> Void {
        DDLogError(message)
        guard let threadName = Thread.current.name else { return }
        Crashlytics.crashlytics().log(threadName + "/E/halloapp: " + message)
    }
    
    public final class func w(_ message: String) -> Void {
        DDLogWarn(message)
        guard let threadName = Thread.current.name else { return }
        Crashlytics.crashlytics().log(threadName + "/W/halloapp: " + message)
    }
    
    public final class func d(_ message: String) -> Void {
        DDLogDebug(message)
        guard let threadName = Thread.current.name else { return }
        Crashlytics.crashlytics().log(threadName + "/D/halloapp: " + message)
    }
    
    public final class func v(_ message: String) -> Void {
        DDLogVerbose(message)
        guard let threadName = Thread.current.name else { return }
        Crashlytics.crashlytics().log(threadName + "/V/halloapp: " + message)
    }
}
