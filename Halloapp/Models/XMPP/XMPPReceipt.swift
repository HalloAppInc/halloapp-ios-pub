//
//  XMPPReceipt.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/4/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

struct XMPPReceipt {

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
    let `type`: Type
    let timestamp: Date
    let thread: Thread

    init?(xmlElement: XMLElement, type: XMPPReceipt.`Type`) {
        guard let itemId = xmlElement.attributeStringValue(forName: "id") else { return nil }
        let timestamp = xmlElement.attributeDoubleValue(forName: "timestamp")
        guard timestamp > 0 else { return nil }

        self.timestamp = Date(timeIntervalSince1970: timestamp)
        self.itemId = itemId
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
}


extension XMPPMessage {

    var deliveryReceipt: XMPPReceipt? {
        get {
            guard let received = self.element(forName: "received") else { return nil }
            return XMPPReceipt(xmlElement: received, type: .delivery)
        }
    }

    var readReceipt: XMPPReceipt? {
        get {
            guard let seen = self.element(forName: "seen") else { return nil }
            return XMPPReceipt(xmlElement: seen, type: .read)
        }
    }
}
