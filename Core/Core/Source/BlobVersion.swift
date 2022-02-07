//
//  BlobVersion.swift
//  Core
//
//  Created by Vasil Lyutskanov on 6.01.22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import Foundation

public enum BlobVersion: Int {
    case `default` = 0
    case chunked = 1

    init(fromProto protoBlobVersion: Clients_BlobVersion) {
        switch protoBlobVersion {
        case .default:
            self = .default
        case .chunked:
            self = .chunked
        case .UNRECOGNIZED:
            self = .default
        }
    }

    var protoBlobVersion: Clients_BlobVersion {
        switch self {
        case .default: return .default
        case .chunked: return .chunked
        }
    }
}
