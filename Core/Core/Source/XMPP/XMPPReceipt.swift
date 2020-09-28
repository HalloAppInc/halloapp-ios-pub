//
//  XMPPReceipt.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/4/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

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

    private init(feedItem: FeedItemProtocol) {
        self.itemId = feedItem.id
        self.userId = feedItem.userId
        self.type = .read
        self.thread = .feed
        // Server timestamps outgoing receipts.
        self.timestamp = nil
    }

    public static func seenReceipt(for feedItem: FeedItemProtocol) -> XMPPReceipt {
        return XMPPReceipt(feedItem: feedItem)
    }

    init?(xmlElement: XMLElement, userId: UserID, type: XMPPReceipt.`Type`) {
        guard let itemId = xmlElement.attributeStringValue(forName: "id") else { return nil }
        let timestamp = xmlElement.attributeDoubleValue(forName: "timestamp")
        guard timestamp > 0 else { return nil }

        self.itemId = itemId
        self.userId = userId
        self.timestamp = Date(timeIntervalSince1970: timestamp)
        if let threadId = xmlElement.attributeStringValue(forName: "thread_id"), threadId != "" {
            if threadId == "feed" {
                self.thread = .feed
            } else {
                self.thread = .group(threadId)
            }
        } else {
            self.thread = .none
        }
        self.type = type
    }

    public var xmlElement: XMLElement {
        get {
            let elementName: String = {
                switch type {
                case .delivery: return "received"
                case .read: return "seen"
                }}()
            let receipt = XMLElement(name: elementName, xmlns: "urn:xmpp:receipts")
            receipt.addAttribute(withName: "id", stringValue: itemId)
            if let threadId: String = {
                switch thread {
                case .none: return nil
                case .feed: return "feed"
                case let .group(groupId): return groupId
                }}() {
                receipt.addAttribute(withName: "thread_id", stringValue: threadId)
            }
            return receipt
        }
    }

    public static func == (lhs: XMPPReceipt, rhs: XMPPReceipt) -> Bool {
        if lhs.type != rhs.type { return false }
        if lhs.itemId != rhs.itemId { return false }
        if lhs.userId != rhs.userId { return false }
        return true
    }

}


extension XMPPMessage {

    public var deliveryReceipt: XMPPReceipt? {
        get {
            guard let received = self.element(forName: "received") else { return nil }
            guard let userId = self.from?.user else { return nil }
            return XMPPReceipt(xmlElement: received, userId: userId, type: .delivery)
        }
    }

    public var readReceipt: XMPPReceipt? {
        get {
            guard let seen = self.element(forName: "seen") else { return nil }
            guard let userId = self.from?.user else { return nil }
            return XMPPReceipt(xmlElement: seen, userId: userId, type: .read)
        }
    }
}
