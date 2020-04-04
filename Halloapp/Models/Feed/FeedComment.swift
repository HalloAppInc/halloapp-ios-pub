//
//  File.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

struct FeedComment: Identifiable, Equatable, Hashable {
    
    let id: String
    let feedItemId: String
    let parentCommentId: String?
    var username: String
    let text: String
    var timestamp: Date

    init(_ comment: XMPPComment) {
        self.id = comment.id
        self.feedItemId = comment.feedPostId
        self.parentCommentId = comment.parentId
        self.username = comment.userPhoneNumber
        self.text = comment.text
        if let ts = comment.timestamp {
            self.timestamp = Date(timeIntervalSince1970: ts)
        } else {
            self.timestamp = Date()
        }
    }

    init(_ comment: FeedComments) {
        self.id = comment.commentId!
        self.feedItemId = comment.feedItemId!
        if let parentID = comment.parentCommentId {
            // Ignore empty strings from the db.
            self.parentCommentId = parentID.isEmpty ? nil : parentID
        } else {
            self.parentCommentId = nil
        }
        self.username = comment.username!
        self.text = comment.text!
        if comment.timestamp > 0 {
            self.timestamp = Date(timeIntervalSince1970: comment.timestamp)
        } else {
            self.timestamp = Date()
        }
    }

    static func == (lhs: FeedComment, rhs: FeedComment) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
