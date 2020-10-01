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

    public typealias XMPPMediaUploadURLRequestCompletion = (Result<MediaURLInfo, Error>) -> Void

    private let completion: XMPPMediaUploadURLRequestCompletion

    public init(size: Int, completion: @escaping XMPPMediaUploadURLRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .get, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild({
            let uploadMedia = XMPPElement(name: "upload_media", xmlns: "ns:upload_media")
            if size > 0 {
                uploadMedia.addAttribute(withName: "size", integerValue: size)
            }
            return uploadMedia
        }())
        super.init(iq: iq)
    }

    public override func didFinish(with response: XMPPIQ) {
        if let mediaURLs = response.childElement?.element(forName: "media_urls") {
            if let get = mediaURLs.attributeStringValue(forName: "get"), let getURL = URL(string: get),
               let put = mediaURLs.attributeStringValue(forName: "put"), let putURL = URL(string: put) {
                completion(.success(.getPut(getURL, putURL)))
                return
            } else if let patch = mediaURLs.attributeStringValue(forName: "patch"), let patchURL = URL(string: patch) {
                completion(.success(.patch(patchURL)))
                return
            }
        }
        self.completion(.failure(XMPPError.malformed))
    }

    public override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

public class XMPPPostItemRequest: XMPPRequest {

    private let completion: XMPPPostItemRequestCompletion
    private let isGroupFeedRequest: Bool

    public init(feedPost: FeedPostProtocol, feed: Feed, completion: @escaping XMPPPostItemRequestCompletion) {
        self.completion = completion
        
        let feedElement: XMPPElement
        switch feed {
        case .personal(let audience):
            isGroupFeedRequest = false

            feedElement = XMPPElement(name: "feed", xmlns: "halloapp:feed")
            feedElement.addChild(audience.xmppElement)

        case .group(let groupId):
            isGroupFeedRequest = true

            feedElement = XMPPElement(name: "group_feed", xmlns: "halloapp:group:feed")
            feedElement.addAttribute(withName: "gid", stringValue: groupId)
        }
        feedElement.addAttribute(withName: "action", stringValue: "publish")
        feedElement.addChild(feedPost.xmppElement(withData: true))

        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild(feedElement)
        super.init(iq: iq)
    }

    public init(feedPostComment: FeedCommentProtocol, groupId: GroupID?, completion: @escaping XMPPPostItemRequestCompletion) {
        self.completion = completion

        let feedElement: XMPPElement
        if let groupId = groupId {
            isGroupFeedRequest = true

            feedElement = XMPPElement(name: "group_feed", xmlns: "halloapp:group:feed")
            feedElement.addAttribute(withName: "gid", stringValue: groupId)
        } else {
            isGroupFeedRequest = false
            
            feedElement = XMPPElement(name: "feed", xmlns: "halloapp:feed")
        }
        feedElement.addAttribute(withName: "action", stringValue: "publish")
        feedElement.addChild(feedPostComment.xmppElement(withData: true))

        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild(feedElement)
        super.init(iq: iq)
    }

    public override func didFinish(with response: XMPPIQ) {
        var timestamp: Date?
        let rootElementName = isGroupFeedRequest ? "group_feed" : "feed"
        if let postElement = response.element(forName: rootElementName)?.element(forName: "post") {
            let ts = postElement.attributeDoubleValue(forName: "timestamp")
            if ts > 0 {
                timestamp = Date(timeIntervalSince1970: ts)
            }
        }
        else if let commentElement = response.element(forName: rootElementName)?.element(forName: "comment") {
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
    public typealias Completion = (Result<ServerPropertiesResponse, Error>) -> ()

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
