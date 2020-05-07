//
//  XMPPReceipt.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/4/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

struct XMPPReceipt: Equatable {

    enum `Type` {
        case delivery
        case read
    }

    enum Thread {
        case none           // 1-1 messages
        case feed           // feed
        case group(String)  // associated value is group id
    }

    let itemId: String
    let userId: UserID
    let `type`: Type
    let timestamp: Date?
    let thread: Thread

    private init(feedItem: FeedItemProtocol) {
        self.itemId = feedItem.id
        self.userId = feedItem.userId
        self.type = .read
        self.thread = .feed
        // Server timestamps outgoing receipts.
        self.timestamp = nil
    }

    static func seenReceipt(for feedItem: FeedItemProtocol) -> XMPPReceipt {
        return XMPPReceipt(feedItem: feedItem)
    }

    private init(chatMessage: ChatMessage) {
        self.itemId =  chatMessage.id
        self.userId = chatMessage.fromUserId
        self.type = .read
        self.thread = .none
        // Server timestamps outgoing receipts.
        self.timestamp = nil
    }

    static func seenReceipt(for chatMessage: ChatMessage) -> XMPPReceipt {
        return XMPPReceipt(chatMessage: chatMessage)
    }

    init?(xmlElement: XMLElement, userId: UserID, type: XMPPReceipt.`Type`) {
        guard let itemId = xmlElement.attributeStringValue(forName: "id") else { return nil }
        let timestamp = xmlElement.attributeDoubleValue(forName: "timestamp")
        guard timestamp > 0 else { return nil }

        self.itemId = itemId
        self.userId = userId
        self.timestamp = Date(timeIntervalSince1970: timestamp)
        if let threadId = xmlElement.attributeStringValue(forName: "thread_id") {
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

    var xmlElement: XMLElement {
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

    static func == (lhs: XMPPReceipt, rhs: XMPPReceipt) -> Bool {
        if lhs.type != rhs.type { return false }
        if lhs.itemId != rhs.itemId { return false }
        if lhs.userId != rhs.userId { return false }
        return true
    }

}


extension XMPPMessage {

    var deliveryReceipt: XMPPReceipt? {
        get {
            guard let received = self.element(forName: "received") else { return nil }
            guard let userId = self.from?.user else { return nil }
            return XMPPReceipt(xmlElement: received, userId: userId, type: .delivery)
        }
    }

    var readReceipt: XMPPReceipt? {
        get {
            guard let seen = self.element(forName: "seen") else { return nil }
            guard let userId = self.from?.user else { return nil }
            return XMPPReceipt(xmlElement: seen, userId: userId, type: .read)
        }
    }
}
