//
//  ProfileLink.swift
//  CoreCommon
//
//  Created by Tanveer on 11/2/23.
//

import Foundation

public struct ProfileLink: Codable, Hashable, Comparable {

    public enum `Type`: Codable {
        case instagram, tiktok, twitter, youtube, other

        public var base: String? {
            switch self {
            case .instagram:
                return "instagram.com/"
            case .tiktok:
                return "tiktok.com/@"
            case .twitter:
                return "x.com/"
            case .youtube:
                return "youtube.com/"
            case .other:
                return nil
            }
        }

        fileprivate var rank: Int {
            switch self {
            case .instagram:
                return 0
            case .tiktok:
                return 1
            case .twitter:
                return 2
            case .youtube:
                return 3
            case .other:
                return 4
            }
        }
    }

    public let `type`: `Type`
    public let string: String

    public init(type: `Type`, string: String) {
        self.type = type
        self.string = string
    }

    public init(serverLink: Server_Link) {
        self.type = serverLink.userProfileLinkType
        self.string = serverLink.text
    }

    public var serverLink: Server_Link {
        var serverLink = Server_Link()
        let type: Server_Link.TypeEnum

        switch self.type {
        case .instagram:
            type = .instagram
        case .tiktok:
            type = .tiktok
        case .twitter:
            type = .x
        case .youtube:
            type = .youtube
        case .other:
            type = .userDefined
        }

        serverLink.type = type
        serverLink.text = string
        return serverLink
    }

    public static func < (lhs: ProfileLink, rhs: ProfileLink) -> Bool {
        if lhs.type.rank == rhs.type.rank {
            return lhs.string < rhs.string
        }

        return lhs.type.rank < rhs.type.rank
    }
}

extension Server_Link {

    var userProfileLinkType: ProfileLink.`Type` {
        switch self.type {
        case .instagram:
            return .instagram
        case .tiktok:
            return .tiktok
        case .x:
            return .twitter
        case .youtube:
            return .youtube
        default:
            return .other
        }
    }
}
