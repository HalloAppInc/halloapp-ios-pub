//
//  PrivacyExtensions.swift
//  Core
//
//  Created by Garrett on 11/4/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreCommon

public extension Server_PrivacyList.TypeEnum {
    init(_ privacyListType: PrivacyListType) {
        switch privacyListType {
        case .all: self = .all
        case .whitelist: self = .only
        case .blacklist: self = .except
        case .muted: self = .mute
        case .blocked: self = .block
        }
    }

    var privacyListType: PrivacyListType? {
        switch self {
        case .all: return .all
        case .block: return .blocked
        case .except: return .blacklist
        case .only: return .whitelist
        case .mute: return .muted
        case .UNRECOGNIZED: return nil
        }
    }
}

public extension Server_PrivacyLists.TypeEnum {
    init?(_ privacyListType: PrivacyListType) {
        switch privacyListType {
        case .all: self = .all
        case .whitelist: self = .only
        case .blacklist: self = .except
        case .muted: return nil
        case .blocked: self = .block
        }
    }

    var privacyListType: PrivacyListType? {
        switch self {
        case .all: return .all
        case .block: return .blocked
        case .except: return .blacklist
        case .only: return .whitelist
        case .UNRECOGNIZED: return nil
        }
    }
}
