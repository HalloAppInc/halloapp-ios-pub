//
//  XMPPPostItemRequest.swift
//  HalloApp
//
//  Created by Tony Jiang on 3/18/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

struct XMPPFeedMedia {
    let url: URL
    let type: FeedMediaType
    let size: CGSize
    let key: String?
    let sha256: String?

    init?(feedMedia: PendingMedia) {
        self.url = feedMedia.url!
        self.type = feedMedia.type
        self.size = feedMedia.size!
        self.key = feedMedia.key
        self.sha256 = feedMedia.sha256hash
    }

    /**
    <url type="image" width="1200" height="1600" key="wn58/JZ4nsZgxOBHw6usvdHfSIBRltZWzqb7u4kSyxc=" sha256hash="FA0cGbpNOfG9oFXezNIdsGVy3GSL2OXGxZ5sX8uXZls=">https://cdn.halloapp.net/CumlsHUTEeqobwpeZJbt6A</url>
     */
    init?(urlElement: XMLElement) {
        guard let type = FeedMediaType(rawValue: urlElement.attributeStringValue(forName: "type") ?? "") else { return nil }
        guard let urlString = urlElement.stringValue else { return nil }
        guard let url = URL(string: urlString) else { return nil }
        let width = urlElement.attributeIntegerValue(forName: "width"), height = urlElement.attributeIntegerValue(forName: "height")
        guard width > 0 && height > 0 else { return nil }

        self.url = url
        self.type = type
        self.size = CGSize(width: width, height: height)
        self.key = urlElement.attributeStringValue(forName: "key")
        self.sha256 = urlElement.attributeStringValue(forName: "sha256hash")
    }

    var xmppElement: XMPPElement {
        get {
            let media = XMPPElement(name: "url", stringValue: self.url.absoluteString)
            media.addAttribute(withName: "type", stringValue: self.type.rawValue)
            media.addAttribute(withName: "width", integerValue: Int(self.size.width))
            media.addAttribute(withName: "height", integerValue: Int(self.size.height))
            if let key = self.key, let sha256 = self.sha256 {
                media.addAttribute(withName: "key", stringValue: key)
                media.addAttribute(withName: "sha256hash", stringValue: sha256)
            }
            return media
        }
    }
}

struct XMPPFeedPost {
    let id: String
    let userPhoneNumber: String
    let text: String?
    let media: [XMPPFeedMedia]
    var timestamp: TimeInterval?

    init(text: String?, media: [PendingMedia]?) {
        self.id = UUID().uuidString
        self.userPhoneNumber = AppContext.shared.userData.phone
        self.text = text
        if let media = media?.compactMap({ XMPPFeedMedia(feedMedia: $0) }) {
            self.media = media
        } else {
            self.media = []
        }
    }

    /**
     <item timestamp="1585853535" publisher="16504228573@s.halloapp.net/iphone" type="feedpost" id="4A0D1C4E-566A-4BED-93A3-0D6D995B3B9B">
        <entry>
            <feedpost>
                <text>Test post</text>
                <media>
                    <url type="image" width="1200" height="1600" key="wn58/JZ4nsZgxOBHw6usvdHfSIBRltZWzqb7u4kSyxc=" sha256hash="FA0cGbpNOfG9oFXezNIdsGVy3GSL2OXGxZ5sX8uXZls=">https://cdn.halloapp.net/CumlsHUTEeqobwpeZJbt6A</url>
                </media>
            </feedpost>
        </entry>
     </item>
     */
    init?(itemElement item: XMLElement) {
        guard let id = item.attributeStringValue(forName: "id") else { return nil }
        guard let userPhoneNumber = item.attributeStringValue(forName: "publisher")?.components(separatedBy: "@").first else { return nil }
        guard let feedPost = item.element(forName: "entry")?.element(forName: "feedpost") else { return nil }

        self.id = id
        self.userPhoneNumber = userPhoneNumber
        self.text = feedPost.element(forName: "text")?.stringValue
        if let media = feedPost.element(forName: "media") {
            self.media = media.elements(forName: "url").compactMap{ XMPPFeedMedia(urlElement: $0) }
        } else {
            self.media = []
        }
        self.timestamp = item.attributeDoubleValue(forName: "timestamp")
    }

    var xmppElement: XMPPElement {
        get {
            let item = XMPPElement(name: "item")
            item.addAttribute(withName: "type", stringValue: "feedpost")
            item.addAttribute(withName: "id", stringValue: id)
            item.addChild({
                let entry = XMPPElement(name: "entry")
                entry.addChild({
                    let feedPost = XMPPElement(name: "feedpost")
                    if let text = text {
                        feedPost.addChild(XMPPElement(name: "text", stringValue: text))
                    }
                    if !self.media.isEmpty {
                        feedPost.addChild({
                            let media = XMLElement(name: "media")
                            media.setChildren(self.media.map{ $0.xmppElement })
                            return media
                        }())
                    }
                    return feedPost
                    }())
                return entry
            }())
            return item
        }
    }
}

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
                publish.addAttribute(withName: "node", stringValue: "feed-\(xmppFeedPost.userPhoneNumber)")
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
