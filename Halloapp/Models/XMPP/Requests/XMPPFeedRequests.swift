//
//  XMPPPostItemRequest.swift
//  HalloApp
//
//  Created by Tony Jiang on 3/18/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import XMPPFramework


class XMPPPostItemRequest : XMPPRequest {
    typealias XMPPPostItemRequestCompletion = (Double?, Error?) -> Void

    let completion: XMPPPostItemRequestCompletion

    init(xmppFeedPost: XMPPFeedPost, completion: @escaping XMPPPostItemRequestCompletion) {
        self.completion = completion
        
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: "pubsub.s.halloapp.net"), elementID: UUID().uuidString)
        iq.addChild({
            let pubsub = XMPPElement(name: "pubsub", xmlns: "http://jabber.org/protocol/pubsub")
            pubsub.addChild({
                let publish = XMPPElement(name: "publish")
                publish.addAttribute(withName: "node", stringValue: "feed-\(xmppFeedPost.userId)")
                publish.addChild(xmppFeedPost.xmppElement)
                return publish
            }())
            return pubsub
        }())
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        let timestamp: TimeInterval? =
            response.element(forName: "pubsub")?.element(forName: "publish")?.element(forName: "item")?.attributeDoubleValue(forName: "timestamp")
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
        let iq = XMPPIQ(iqType: .get, to: XMPPJID(string: XMPPIQDefaultTo), elementID: UUID().uuidString)
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


class XMPPPostCommentRequest : XMPPRequest {
    typealias XMPPPostCommentRequestCompletion = (Double?, Error?) -> Void

    let completion: XMPPPostCommentRequestCompletion

    init(xmppComment: XMPPComment, postAuthor: UserID, completion: @escaping XMPPPostCommentRequestCompletion) {
        self.completion = completion

        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: "pubsub.s.halloapp.net"), elementID: UUID().uuidString)
        iq.addChild({
            let pubsub = XMPPElement(name: "pubsub", xmlns: "http://jabber.org/protocol/pubsub")
            pubsub.addChild({
                let publish = XMPPElement(name: "publish")
                publish.addAttribute(withName: "node", stringValue: "feed-\(postAuthor)")
                publish.addChild(xmppComment.xmppElement)
                return publish
            }())
            return pubsub
        }())
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        let timestamp: TimeInterval? =
            response.element(forName: "pubsub")?.element(forName: "publish")?.element(forName: "item")?.attributeDoubleValue(forName: "timestamp")
        self.completion(timestamp, nil)
    }

    override func didFail(with error: Error) {
        self.completion(nil, error)
    }
}

class XMPPRetractItemRequest: XMPPRequest {
    typealias XMPPRetractItemRequestCompletion = (Error?) -> Void

    let completion: XMPPRetractItemRequestCompletion

    convenience init(feedPost: FeedPost, completion: @escaping XMPPRetractItemRequestCompletion) {
        let item =  XMLElement(name: "item")
        item.addAttribute(withName: "id", stringValue: feedPost.id)
        item.addAttribute(withName: "type", stringValue: "feedpost")
        self.init(itemElement: item, feedOwnerId: feedPost.userId, completion: completion)
    }

    convenience init(feedPostComment: FeedPostComment, completion: @escaping XMPPRetractItemRequestCompletion) {
        let item =  XMLElement(name: "item")
        item.addAttribute(withName: "id", stringValue: feedPostComment.id)
        item.addAttribute(withName: "type", stringValue: "comment")
        self.init(itemElement: item, feedOwnerId: feedPostComment.post.userId, completion: completion)
    }

    private init(itemElement: XMLElement, feedOwnerId: UserID, completion: @escaping XMPPRetractItemRequestCompletion) {
        self.completion = completion

        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: "pubsub.s.halloapp.net"), elementID: UUID().uuidString)
        iq.addChild({
            let pubsub = XMPPElement(name: "pubsub", xmlns: "http://jabber.org/protocol/pubsub")
            pubsub.addChild({
                let retract = XMPPElement(name: "retract")
                retract.addAttribute(withName: "node", stringValue: "feed-\(feedOwnerId)")
                retract.addChild(itemElement)
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
