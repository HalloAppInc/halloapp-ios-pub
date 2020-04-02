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

    var completion: XMPPPostItemRequestCompletion

    init(user: String, text: String, media: [FeedMedia], itemId: String, completion: @escaping XMPPPostItemRequestCompletion) {
        self.completion = completion
        
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: "pubsub.s.halloapp.net"), elementID: UUID().uuidString)

        let pubsub = XMPPElement(name: "pubsub", xmlns: "http://jabber.org/protocol/pubsub")
        
        let publish = XMPPElement(name: "publish")
        publish.addAttribute(withName: "node", stringValue: "feed-\(user)")
        
        let item = XMPPElement(name: "item")
        item.addAttribute(withName: "type", stringValue: "feedpost")
        item.addAttribute(withName: "id", stringValue: itemId)
        
        let entry = XMLElement(name: "entry")
    
        let feedpost = XMLElement(name: "feedpost")
        
        let text = XMLElement(name: "text", stringValue: text)
        
        feedpost.addChild(text)
        
        if media.count > 0 {
            let mediaEl = XMLElement(name: "media")
            
            for med in media {
                let medEl = XMLElement(name: "url", stringValue: med.url)
                medEl.addAttribute(withName: "type", stringValue: med.type)
                medEl.addAttribute(withName: "width", stringValue: String(med.width))
                medEl.addAttribute(withName: "height", stringValue: String(med.height))
                
                if med.key != "" {
                    medEl.addAttribute(withName: "key", stringValue: String(med.key))
                    medEl.addAttribute(withName: "sha256hash", stringValue: String(med.sha256hash))
                }
                mediaEl.addChild(medEl)
            }
            
            feedpost.addChild(mediaEl)
        }
        
        entry.addChild(feedpost)
        item.addChild(entry)
        publish.addChild(item)
        pubsub.addChild(publish)
        iq.addChild(pubsub)
        
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        var timestamp: TimeInterval = 0
        
        if let pubsub = response.element(forName: "pubsub") {
            if let publish = pubsub.element(forName: "publish") {
                if let item = publish.element(forName: "item") {
                    timestamp = item.attributeDoubleValue(forName: "timestamp")
                }
            }
        }
        
        self.completion(timestamp, nil)
    }

    override func didFail(with error: Error) {
        self.completion(nil, error)
    }
}
