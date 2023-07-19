//
//  SentryLogger.swift
//  Core
//
//  Created by Chris Leonavicius on 12/28/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift
import CoreCommon
import Sentry

private extension DDLogFlag {

    var sentryLevel: SentryLevel {
        switch self {
        case .error:
            return .error
        case .warning:
            return .warning
        case .info:
            return .info
        default:
            return .debug
        }
    }
}

public final class SentryLogger: DDAbstractLogger {

    // From https://develop.sentry.dev/sdk/event-payloads/breadcrumbs/#breadcrumb-types
    private static let category = "console"
    private static let type = "default"

    override public var logFormatter: DDLogFormatter? {
        get {
            // must access via ivar
            value(forKey: "_logFormatter") as? DDLogFormatter
        }
        set {
            super.logFormatter = newValue
        }
    }

    init(logFormatter: DDLogFormatter) {
        super.init()
        self.logFormatter = logFormatter
    }

    override public func log(message logMessage: DDLogMessage) {
        let crumb = Breadcrumb(level: logMessage.flag.sentryLevel, category: Self.category)
        crumb.timestamp = logMessage.timestamp
        crumb.type = Self.type
        crumb.message = logFormatter?.format(message: logMessage) ?? logMessage.message
        SentrySDK.addBreadcrumb(crumb)
    }
}

extension SentryLogger: ErrorLogger {

    public func logError(_ error: Error) {
        SentrySDK.capture(error: error)
    }
}
