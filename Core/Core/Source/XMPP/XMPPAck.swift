//
//  XMPPAck.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import XMPPFramework

public struct XMPPAck {
    public let from: XMPPJID
    public let to: XMPPJID
    public let id: String
    public let timestamp: Date?

    private init(from: XMPPJID, to: XMPPJID, id: String) {
        self.from = from
        self.to = to
        self.id = id
        self.timestamp = nil
    }

    init?(itemElement item: XMLElement) {
        guard let fromStr = item.attributeStringValue(forName: "from") else { return nil }
        guard let from = XMPPJID(string: fromStr) else { return nil }

        guard let toStr = item.attributeStringValue(forName: "to") else { return nil }
        guard let to = XMPPJID(string: toStr) else { return nil }

        guard let id = item.attributeStringValue(forName: "id") else { return nil }

        let ts = item.attributeDoubleValue(forName: "timestamp")

        self.from = from
        self.to = to
        self.id = id
        self.timestamp = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    static func ack(for message: XMPPMessage) -> XMPPAck? {
        guard let id = message.elementID else { return nil }
        guard let from = message.to else { return nil }
        guard let to = message.from else { return nil }
        return XMPPAck(from: from, to: to, id: id)
    }

    var xmlElement: XMLElement {
        get {
            let ack = XMLElement(name: "ack")
            ack.addAttribute(withName: "from", stringValue: from.full)
            ack.addAttribute(withName: "to", stringValue: to.full)
            ack.addAttribute(withName: "id", stringValue: id)
            return ack
        }
    }
}
