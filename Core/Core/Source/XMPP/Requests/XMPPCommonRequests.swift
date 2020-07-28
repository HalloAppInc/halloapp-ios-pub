//
//  XMPPCommonRequests.swift
//  Core
//
//  Created by Alan Luo on 7/15/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

public class XMPPPostItemRequest: XMPPRequest {
    public typealias XMPPPostItemRequestCompletion = (Result<Date?, Error>) -> Void

    private let completion: XMPPPostItemRequestCompletion

    public init<T>(feedItem: T, feedOwnerId: UserID, completion: @escaping XMPPPostItemRequestCompletion) where T: FeedItemProtocol {
        self.completion = completion
        
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: "pubsub.s.halloapp.net"))
        iq.addChild({
            let pubsub = XMPPElement(name: "pubsub", xmlns: "http://jabber.org/protocol/pubsub")
            pubsub.addChild({
                let publish = XMPPElement(name: "publish")
                publish.addAttribute(withName: "node", stringValue: "feed-\(feedOwnerId)")
                publish.addChild(feedItem.xmppElement(withData: true))
                return publish
            }())
            return pubsub
        }())
        super.init(iq: iq)
    }

    public override func didFinish(with response: XMPPIQ) {
        var timestamp: Date?
        if let ts: TimeInterval = response.element(forName: "pubsub")?.element(forName: "publish")?.element(forName: "item")?.attributeDoubleValue(forName: "timestamp") {
            timestamp = Date(timeIntervalSince1970: ts)
        }
        self.completion(.success(timestamp))
    }

    public override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}
