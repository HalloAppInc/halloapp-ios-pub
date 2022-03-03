//
//  LogFormatter.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift

public class LogFormatter: NSObject, DDLogFormatter {

    static private func logLevel(for logMessage: DDLogMessage) -> String {
        switch logMessage.flag {
        case .error: return "LL_E"
        case .warning: return "LL_W"
        case .info: return "LL_I"
        case .debug: return "LL_D"
        default: return "LL_V"
        }
    }

    static func queueLabel(for logMessage: DDLogMessage) -> String {
        let label = logMessage.queueLabel
        var shortName = label.components(separatedBy: ".").last!
        let maxLength = 14
        if shortName.count > maxLength {
            let suffixLength = 4
            let prefix = shortName.prefix(maxLength - suffixLength - 1)
            let suffix = shortName.suffix(suffixLength)
            shortName = "\(prefix)…\(suffix)"
        } else {
            shortName = shortName.padding(toLength: maxLength, withPad: " ", startingAt: 0)
        }
        return shortName
    }

    public func format(message logMessage: DDLogMessage) -> String? {
        let queueName = LogFormatter.queueLabel(for: logMessage)
        let logLevel = LogFormatter.logLevel(for: logMessage)
        let logMessageStr = logMessage.message.replacingOccurrences(of: "\n", with: "\n\(logLevel) ")

        return "\(queueName) \(logLevel) \(logMessageStr)"
    }
}

class FileLogFormatter: LogFormatter {
    private let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter.locale = Locale(identifier: "en_US")
        return dateFormatter
    }()

    override func format(message logMessage: DDLogMessage) -> String? {
        if let logMessageStr = super.format(message: logMessage) {
            let dateStr = dateFormatter.string(from: logMessage.timestamp)
            return "\(dateStr) \(logMessage.threadID) \(logMessageStr)"
        }
        return nil
    }
}
