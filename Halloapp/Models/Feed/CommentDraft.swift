//
//  CommentDraft.swift
//  HalloApp
//
//  Created by Matt Geimer on 6/3/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import Core
import CoreCommon

struct CommentDraft: Codable {
    var postID: FeedPostID
    var text: MentionText
    var parentComment: FeedPostCommentID?
}
