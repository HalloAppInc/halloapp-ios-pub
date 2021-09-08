//
//  XMPPReceipt.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/4/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

public typealias HalloReceipt = XMPPReceipt

public struct XMPPReceipt: Equatable {

    public enum `Type` {
        case delivery
        case read
    }

    public enum Thread: Equatable {
        case none           // 1-1 messages
        case feed           // feed
        case group(String)  // associated value is group id
    }

    public let itemId: String
    public let userId: UserID
    public let type: Type
    public let timestamp: Date?
    public let thread: Thread

    public init(itemId: String, userId: UserID, type: Type, timestamp: Date?, thread: Thread) {
        self.itemId = itemId
        self.userId = userId
        self.type = type
        self.timestamp = timestamp
        self.thread = thread
    }

    public static func == (lhs: XMPPReceipt, rhs: XMPPReceipt) -> Bool {
        if lhs.type != rhs.type { return false }
        if lhs.itemId != rhs.itemId { return false }
        if lhs.userId != rhs.userId { return false }
        return true
    }

}
