//
//  XMPPPostCommentRequest.swift
//  HalloApp
//
//  Created by Tony Jiang on 3/19/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

class XMPPPostCommentRequest : XMPPRequest {
    typealias XMPPPostCommentRequestCompletion = (Double?, Error?) -> Void

    var completion: XMPPPostCommentRequestCompletion

    init(feedUser: String, feedItemId: String, parentCommentId: String?, text: String, commentItemId: String, completion: @escaping XMPPPostCommentRequestCompletion) {
        self.completion = completion
        
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: "pubsub.s.halloapp.net"), elementID: UUID().uuidString)

        let pubsub = XMPPElement(name: "pubsub", xmlns: "http://jabber.org/protocol/pubsub")
        
        let publish = XMPPElement(name: "publish")
        publish.addAttribute(withName: "node", stringValue: "feed-\(feedUser)")
        
        let item = XMPPElement(name: "item")
        item.addAttribute(withName: "type", stringValue: "comment")
        item.addAttribute(withName: "id", stringValue: commentItemId)
        
        let entry = XMLElement(name: "entry")
    
        let comment = XMLElement(name: "comment")
        
        let feedItemId = XMLElement(name: "feedItemId", stringValue: feedItemId)

        let text = XMLElement(name: "text", stringValue: text)
        
        comment.addChild(feedItemId)
        if (parentCommentId != nil) {
            comment.addChild(XMLElement(name: "parentCommentId", stringValue: parentCommentId!))
        }
        comment.addChild(text)
        entry.addChild(comment)
        item.addChild(entry)
        publish.addChild(item)
        pubsub.addChild(publish)
        iq.addChild(pubsub)
        
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        var timestamp: Double = 0
        
        if let pubsub = response.element(forName: "pubsub") {
            if let publish = pubsub.element(forName: "publish") {
                if let item = publish.element(forName: "item") {
                    
                    if let serverTimestamp = item.attributeStringValue(forName: "timestamp") {
                        
                        if let convertedServerTimestamp = Double(serverTimestamp) {
                            print("got timestamp for comment")
                            timestamp = convertedServerTimestamp
                        }
                    }
                }
            }
        }
        
        self.completion(timestamp, nil)
    }

    override func didFail(with error: Error) {
        self.completion(nil, error)
    }
}

