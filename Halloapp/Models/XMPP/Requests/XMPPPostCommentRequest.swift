//
//  XMPPPostCommentRequest.swift
//  HalloApp
//
//  Created by Tony Jiang on 3/19/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

struct XMPPComment {
    let id: String
    let userPhoneNumber: String
    let parentId: String?
    let feedPostId: String
    let text: String
    var timestamp: TimeInterval?

    init(userPhoneNumber: String, feedPostId: String, parentCommentId: String?, text: String) {
        self.userPhoneNumber = userPhoneNumber
        self.id = UUID().uuidString
        self.parentId = parentCommentId
        self.feedPostId = feedPostId
        self.text = text
    }

    /**
     <item timestamp="1585847898" publisher="16504228573@s.halloapp.net/iphone" type="comment" id="F198FE77-EEF7-487A-9D40-A36A74B24221">
         <entry>
             <comment>
                <feedItemId>5099E935-65AD-4325-93B7-FA30B3FD8461</feedItemId>
                <text>Qwertyu</text>
             </comment>
         </entry>
     </item>
     */
    init?(itemElement item: XMLElement) {
        guard let id = item.attributeStringValue(forName: "id") else { return nil }
        guard let userPhoneNumber = item.attributeStringValue(forName: "publisher")?.components(separatedBy: "@").first else { return nil }
        guard let comment = item.element(forName: "entry")?.element(forName: "comment") else { return nil }
        guard let feedItemId = comment.element(forName: "feedItemId")?.stringValue else { return nil }
        guard let text = comment.element(forName: "text")?.stringValue else { return nil }

        self.id = id
        self.userPhoneNumber = userPhoneNumber
        self.feedPostId = feedItemId
        self.parentId = comment.element(forName: "parentCommentId")?.stringValue
        self.text = text
        self.timestamp = item.attributeDoubleValue(forName: "timestamp")
    }

    var xmppElement: XMPPElement {
        get {
            let item = XMPPElement(name: "item")
            item.addAttribute(withName: "type", stringValue: "comment")
            item.addAttribute(withName: "id", stringValue: id)
            item.addChild({
                let entry = XMPPElement(name: "entry")
                entry.addChild({
                    let comment = XMPPElement(name: "comment")
                    comment.addChild(XMPPElement(name: "feedItemId", stringValue: feedPostId))
                    comment.addChild(XMPPElement(name: "text", stringValue: text))
                    if let parentId = parentId {
                        comment.addChild(XMPPElement(name: "parentCommentId", stringValue: parentId))
                    }
                    return comment
                }())
                return entry
            }())
            return item
        }
    }
}


class XMPPPostCommentRequest : XMPPRequest {
    typealias XMPPPostCommentRequestCompletion = (Double?, Error?) -> Void

    let completion: XMPPPostCommentRequestCompletion

    init(xmppComment: XMPPComment, completion: @escaping XMPPPostCommentRequestCompletion) {
        self.completion = completion

        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: "pubsub.s.halloapp.net"), elementID: UUID().uuidString)
        iq.addChild({
            let pubsub = XMPPElement(name: "pubsub", xmlns: "http://jabber.org/protocol/pubsub")
            pubsub.addChild({
                let publish = XMPPElement(name: "publish")
                publish.addAttribute(withName: "node", stringValue: "feed-\(xmppComment.userPhoneNumber)")
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
