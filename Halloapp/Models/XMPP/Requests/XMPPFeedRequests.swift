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

class XMPPPostItemRequest : XMPPRequest {

    typealias XMPPPostItemRequestCompletion = (Date?, Error?) -> Void

    let completion: XMPPPostItemRequestCompletion

    init<T>(feedItem: T, feedOwnerId: UserID, completion: @escaping XMPPPostItemRequestCompletion) where T: FeedItemProtocol {
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

    override func didFinish(with response: XMPPIQ) {
        var timestamp: Date?
        if let ts: TimeInterval = response.element(forName: "pubsub")?.element(forName: "publish")?.element(forName: "item")?.attributeDoubleValue(forName: "timestamp") {
            timestamp = Date(timeIntervalSince1970: ts)
        }
        self.completion(timestamp, nil)
    }

    override func didFail(with error: Error) {
        self.completion(nil, error)
    }
}

struct MediaURL {
    var get: URL, put: URL
}

class XMPPMediaUploadURLRequest : XMPPRequest {

    typealias XMPPMediaUploadURLRequestCompletion = (MediaURL?, Error?) -> Void

    var completion: XMPPMediaUploadURLRequestCompletion

    init(completion: @escaping XMPPMediaUploadURLRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .get, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild(XMPPElement(name: "upload_media", xmlns: "ns:upload_media"))
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        var urls: MediaURL?
        if let mediaURLs = response.childElement?.element(forName: "media_urls") {
            if let get = mediaURLs.attributeStringValue(forName: "get"), let put = mediaURLs.attributeStringValue(forName: "put") {
                if let getURL = URL(string: get), let putURL = URL(string: put) {
                    urls = MediaURL(get: getURL, put: putURL)
                }
            }
        }
        self.completion(urls, nil)
    }

    override func didFail(with error: Error) {
        self.completion(nil, error)
    }
}


class XMPPRetractItemRequest: XMPPRequest {

    typealias XMPPRetractItemRequestCompletion = (Error?) -> Void

    let completion: XMPPRetractItemRequestCompletion

    init<T>(feedItem: T, feedOwnerId: UserID, completion: @escaping XMPPRetractItemRequestCompletion) where T: FeedItemProtocol {
        self.completion = completion

        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: "pubsub.s.halloapp.net"))
        iq.addChild({
            let pubsub = XMPPElement(name: "pubsub", xmlns: "http://jabber.org/protocol/pubsub")
            pubsub.addChild({
                let retract = XMPPElement(name: "retract")
                retract.addAttribute(withName: "node", stringValue: "feed-\(feedOwnerId)")
                retract.addChild(feedItem.xmppElement(withData: false))
                return retract
            }())
            return pubsub
        }())
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        self.completion(nil)
    }

    override func didFail(with error: Error) {
        self.completion(error)
    }
}
