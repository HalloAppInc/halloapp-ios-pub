//
//  FeedElement+XMPP.swift
//  HalloApp
//
//  Created by Garrett on 8/20/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import XMPPFramework

extension FeedElement {
    init?(_ item: DDXMLElement) {
        if item.name == "post", let feedPost = XMPPFeedPost(itemElement: item) {
            self = .post(feedPost)
        } else if item.name == "comment", let comment = XMPPComment(itemElement: item) {
            let publisherName = item.attributeStringValue(forName: "publisher_name")
            self = .comment(comment, publisherName: publisherName)
        } else {
            DDLogError("FeedElement/init/error Invalid item: [\(item)]")
            return nil
        }
    }
}

extension FeedRetract {
    init?(_ item: DDXMLElement) {
        if item.name == "post", let postID = item.attributeStringValue(forName: "id") {
            self = .post(postID)
        } else if item.name == "comment", let commentID = item.attributeStringValue(forName: "id") {
            self = .comment(commentID)
        } else {
            DDLogError("FeedRetract/init/error Invalid item: [\(item)]")
            return nil
        }
    }
}
