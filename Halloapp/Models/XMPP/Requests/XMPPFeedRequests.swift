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

class XMPPRetractItemRequest: XMPPRequest {

    private let completion: XMPPRequestCompletion

    init(feedItem: FeedItemProtocol, completion: @escaping XMPPRequestCompletion) {
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

//<iq to='s.halloapp.net' type='set' id='ieXQZ-1'
//    from='1000000000000000002@s.halloapp.net'>
//  <feed xmlns='halloapp:feed' action='share'>
//    <share_posts uid='1000000000000000001'>
//      <post id='bnd81g37d61f49fgn581'/>
//      <post id='7dg43b33f11f28bnd123'/>
//      ....
//    </share_posts>
//    <share_posts uid='1000000000000000003'>
//      ....
//    </share_posts>
//    ..
//  </feed>
//</iq>
class XMPPSharePostsRequest: XMPPRequest {

    private let completion: XMPPRequestCompletion

    init(feedPostIds: [FeedPostID], userId: UserID, completion: @escaping XMPPRequestCompletion) {
        self.completion = completion

        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild({
            let feedElement = XMPPElement(name: "feed", xmlns: "halloapp:feed")
            feedElement.addAttribute(withName: "action", stringValue: "share")
            feedElement.addChild({
                let sharePostsElement = XMPPElement(name: "share_posts")
                sharePostsElement.addAttribute(withName: "uid", stringValue: userId)
                for postId in feedPostIds {
                    sharePostsElement.addChild({
                        let postElement = XMPPElement(name: "post")
                        postElement.addAttribute(withName: "id", stringValue: postId)
                        return postElement
                        }())
                }
                return sharePostsElement
                }())
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
