//
//  FeedDataItem.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import Foundation

class FeedDataItem: Identifiable, ObservableObject, Equatable, Hashable {

    var id: FeedPostID
    var userId: UserID
    var media: [FeedMedia]
    var currentMediaIndex: Int? = nil

    var commentsDidChange = PassthroughSubject<(Int, Bool), Never>()
    var hasUnreadComments: Bool {
        didSet {
            commentsDidChange.send((numberOfComments, hasUnreadComments))
        }
    }
    var numberOfComments: Int {
        didSet {
            commentsDidChange.send((numberOfComments, hasUnreadComments))
        }
    }

    init(_ feedPost: FeedPost) {
        id = feedPost.id
        userId = feedPost.userId
        hasUnreadComments = feedPost.unreadCount > 0
        numberOfComments = feedPost.comments?.count ?? 0
        media = (feedPost.media ?? []).sorted(by: { $0.order < $1.order }).map{ FeedMedia($0) }
        if !media.isEmpty {
            currentMediaIndex = 0
        }
    }

    func reload(from feedPost: FeedPost) {
        // Only 'unreadComments' might change at this point.
        hasUnreadComments = feedPost.unreadCount > 0
        numberOfComments = feedPost.comments?.count ?? 0
        if feedPost.isPostRetracted && !media.isEmpty {
            media = []
            currentMediaIndex = nil
        }
    }

    func reloadMedia(from feedPost: FeedPost, order: Int) {
        guard let feedPostMedia = feedPost.media?.first(where: { $0.order == order }) else { return }
        guard let feedMedia = self.media.first(where: { $0.order == order }) else { return }
        feedMedia.reload(from: feedPostMedia)
    }

    func loadImages() {
        self.media.forEach { $0.loadImage() }
    }
    
    static func == (lhs: FeedDataItem, rhs: FeedDataItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
