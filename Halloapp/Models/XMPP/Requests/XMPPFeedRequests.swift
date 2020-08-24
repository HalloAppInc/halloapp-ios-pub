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

struct MediaURL {
    var get: URL, put: URL
}

class XMPPMediaUploadURLRequest: XMPPRequest {

    typealias XMPPMediaUploadURLRequestCompletion = (Result<MediaURL, Error>) -> Void

    private let completion: XMPPMediaUploadURLRequestCompletion

    init(completion: @escaping XMPPMediaUploadURLRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .get, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild(XMPPElement(name: "upload_media", xmlns: "ns:upload_media"))
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        if let mediaURLs = response.childElement?.element(forName: "media_urls") {
            if let get = mediaURLs.attributeStringValue(forName: "get"), let put = mediaURLs.attributeStringValue(forName: "put") {
                if let getURL = URL(string: get), let putURL = URL(string: put) {
                    self.completion(.success(MediaURL(get: getURL, put: putURL)))
                    return
                }
            }
        }
        self.completion(.failure(XMPPError.malformed))
    }

    override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

class XMPPRetractItemRequestOld: XMPPRequest {

    private let completion: XMPPRequestCompletion

    init<T>(feedItem: T, feedOwnerId: UserID, completion: @escaping XMPPRequestCompletion) where T: FeedItemProtocol {
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

    init<T>(feedItem: T, completion: @escaping XMPPRequestCompletion) where T: FeedItemProtocol {
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
