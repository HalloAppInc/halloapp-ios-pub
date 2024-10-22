//
//  ChatDraft.swift
//  HalloApp
//
//  Created by Matt Geimer on 6/15/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import Core
import CoreCommon

struct ChatDraft: Codable {
    var chatID: String
    var text: String
    var replyContext: ReplyContext?
}

struct ReplyContext: Codable {
    var feedPostID: String?
    var replyMessageID: String?
    var replySenderID: UserID
    var mediaIndex: Int32?
    
    var text: String
    var media: ChatReplyMedia?
}

struct ChatReplyMedia: Codable {
    var type: CommonMediaType
    var mediaURL: String
    var name: String?
}
