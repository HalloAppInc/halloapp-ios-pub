//
//  XMPPPostItemRequest.swift
//  HalloApp
//
//  Created by Tony Jiang on 3/18/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import Foundation
import XMPPFramework

class XMPPRetractItemRequestOld: XMPPRequest {

    private let completion: XMPPRequestCompletion

    init(feedItem: FeedItemProtocol, feedOwnerId: UserID, completion: @escaping XMPPRequestCompletion) {
        self.completion = completion

        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: "pubsub.s.halloapp.net"))
        iq.addChild({
            let pubsub = XMPPElement(name: "pubsub", xmlns: "http://jabber.org/protocol/pubsub")
            pubsub.addChild({
                let retract = XMPPElement(name: "retract")
                retract.addAttribute(withName: "node", stringValue: "feed-\(feedOwnerId)")
                retract.addChild(feedItem.oldFormatXmppElement(withData: false))
                return retract
            }())
            return pubsub
        }())
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        self.completion(.success(()))
    }

    override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

class XMPPRetractItemRequest: XMPPRequest {

    private let completion: XMPPRequestCompletion

    init(feedItem: FeedItemProtocol, completion: @escaping XMPPRequestCompletion) {
        self.completion = completion

        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild({
            let feedElement = XMPPElement(name: "feed", xmlns: "halloapp:feed")
            feedElement.addAttribute(withName: "action", stringValue: "retract")
            feedElement.addChild(feedItem.xmppElement(withData: false))
            return feedElement
        }())
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        self.completion(.success(()))
    }

    override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}
