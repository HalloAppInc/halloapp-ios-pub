//
//  XMPPCommonRequests.swift
//  Core
//
//  Created by Alan Luo on 7/15/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

public typealias XMPPPostItemRequestCompletion = (Result<Date?, Error>) -> Void

extension FeedAudience: XMPPElementRepresentable {

    public var xmppElement: XMPPElement {
        get {
            let audienceElement = XMPPElement(name: "audience_list")
            audienceElement.addAttribute(withName: "type", stringValue: privacyListType.rawValue)
            for userId in userIds {
                audienceElement.addChild(XMPPElement(name: "uid", stringValue: userId))
            }
            return audienceElement
        }
    }
}

public class XMPPMediaUploadURLRequest: XMPPRequest {

    public typealias XMPPMediaUploadURLRequestCompletion = (Result<MediaURL, Error>) -> Void

    private let completion: XMPPMediaUploadURLRequestCompletion

    public init(completion: @escaping XMPPMediaUploadURLRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .get, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild(XMPPElement(name: "upload_media", xmlns: "ns:upload_media"))
        super.init(iq: iq)
    }

    public override func didFinish(with response: XMPPIQ) {
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

    public override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

public class XMPPPostItemRequestOld: XMPPRequest {
    
    private let completion: XMPPPostItemRequestCompletion

    public init(feedItem: FeedItemProtocol, feedOwnerId: UserID, completion: @escaping XMPPPostItemRequestCompletion) {
        self.completion = completion
        
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: "pubsub.s.halloapp.net"))
        iq.addChild({
            let pubsub = XMPPElement(name: "pubsub", xmlns: "http://jabber.org/protocol/pubsub")
            pubsub.addChild({
                let publish = XMPPElement(name: "publish")
                publish.addAttribute(withName: "node", stringValue: "feed-\(feedOwnerId)")
                publish.addChild(feedItem.oldFormatXmppElement(withData: true))
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

public class XMPPPostItemRequest: XMPPRequest {

    private let completion: XMPPPostItemRequestCompletion

    public init(feedPost: FeedPostProtocol, audience: FeedAudience, completion: @escaping XMPPPostItemRequestCompletion){
        self.completion = completion
        
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild({
            let feedElement = XMPPElement(name: "feed", xmlns: "halloapp:feed")
            feedElement.addAttribute(withName: "action", stringValue: "publish")
            feedElement.addChild(audience.xmppElement)
            feedElement.addChild(feedPost.xmppElement(withData: true))
            return feedElement
        }())
        super.init(iq: iq)
    }

    public init(feedPostComment: FeedCommentProtocol, completion: @escaping XMPPPostItemRequestCompletion) {
        self.completion = completion

        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild({
            let feedElement = XMPPElement(name: "feed", xmlns: "halloapp:feed")
            feedElement.addAttribute(withName: "action", stringValue: "publish")
            feedElement.addChild(feedPostComment.xmppElement(withData: true))
            return feedElement
        }())
        super.init(iq: iq)
    }

    public override func didFinish(with response: XMPPIQ) {
        var timestamp: Date?
        if let postElement = response.element(forName: "feed")?.element(forName: "post") {
            let ts = postElement.attributeDoubleValue(forName: "timestamp")
            if ts > 0 {
                timestamp = Date(timeIntervalSince1970: ts)
            }
        }
        else if let commentElement = response.element(forName: "feed")?.element(forName: "comment") {
            let ts = commentElement.attributeDoubleValue(forName: "timestamp")
            if ts > 0 {
                timestamp = Date(timeIntervalSince1970: ts)
            }
        }
        self.completion(.success(timestamp))
    }

    public override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

public class XMPPGetServerPropertiesRequest: XMPPRequest {
    public typealias Completion = (Result<(String, [String:String]), Error>) -> ()

    private static let xmlns = "halloapp:props"

    private let completion: Completion

    public init(completion: @escaping Completion) {
        self.completion = completion

        let iq = XMPPIQ(iqType: .get, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild(XMLElement(name: "props", xmlns: Self.xmlns))
        super.init(iq: iq)
    }

    public override func didFinish(with response: XMPPIQ) {
        guard let propsElement = response.element(forName: "props") else {
            self.completion(.failure(XMPPError.malformed))
            return
        }
        guard let version = propsElement.attributeStringValue(forName: "hash"), !version.isEmpty else {
            self.completion(.failure(XMPPError.malformed))
            return
        }
        let props = propsElement.elements(forName: "prop").reduce(into: [String:String]()) { (properties, propElement) in
            guard let propName = propElement.attributeStringValue(forName: "name"), !propName.isEmpty else {
                return
            }
            guard let propValue = propElement.stringValue, !propValue.isEmpty else {
                return
            }
            properties[propName] = propValue
        }
        self.completion(.success((version, props)))
    }

    public override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}
