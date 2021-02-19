//
//  UserAgent.swift
//  Core
//
//  Created by Garrett on 2/19/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation

public struct UserAgent: CustomStringConvertible {
    public enum Platform: String, CaseIterable {
        case ios = "iOS"
        case android = "Android"
    }

    var platform: Platform
    var version: String

    public init?(string: String) {
        let components = string.split(separator: "/")
        guard components.count == 2, components[0] == "HalloApp" else {
            return nil
        }
        let clientVersion = components[1]
        guard let platform = Platform.allCases.first(where: { clientVersion.hasPrefix($0.rawValue) }) else {
            return nil
        }
        self.platform = platform
        self.version = String(clientVersion.dropFirst(platform.rawValue.count))
    }

    public init(platform: Platform, version: String) {
        self.platform = platform
        self.version = version
    }

    public var description: String {
        "HalloApp/\(platform.rawValue)\(version)"
    }
}
