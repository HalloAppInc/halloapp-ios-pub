//
//  File.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

struct FeedComment: Identifiable, Equatable, Hashable {
    var id: String
    var feedItemId: String = ""
    var parentCommentId: String = ""
    var username: String = ""
    var userImageUrl: String = ""
    var text: String = ""
    var timestamp: Double = 0
    
    init() {
        self.id = UUID().uuidString
    }
    
    init(id: String) {
        self.id = id
    }
    
    init(id: String,
         feedItemId: String = "",
         parentCommentId: String = "",
         username: String = "",
         userImageUrl: String = "",
         text: String = "",
         timestamp: Double = 0) {
        
        self.id = id
        self.feedItemId = feedItemId
        self.parentCommentId = parentCommentId
        self.username = username
        self.userImageUrl = userImageUrl
        self.text = text
        self.timestamp = timestamp
    }
    
    static func == (lhs: FeedComment, rhs: FeedComment) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
}
