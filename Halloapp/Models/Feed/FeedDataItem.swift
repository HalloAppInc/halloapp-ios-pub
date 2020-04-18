//
//  FeedDataItem.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Foundation

class FeedDataItem: Identifiable, ObservableObject, Equatable, Hashable {

    var id: FeedPostID
    var userId: UserID
    var media: [FeedMedia]


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
        media = feedPost.orderedMedia.map { FeedMedia($0) }
    }

    func reload(from feedPost: FeedPost) {
        // Only 'unreadComments' might change at this point.
        hasUnreadComments = feedPost.unreadCount > 0
        numberOfComments = feedPost.comments?.count ?? 0
        if feedPost.isPostDeleted && !media.isEmpty {
            media = []
        }
    }

    func reloadMedia(from feedPost: FeedPost, order: Int) {
        let feedPostMediaObjects = feedPost.media as! Set<FeedPostMedia>
        guard let feedPostMedia = feedPostMediaObjects.first(where: { $0.order == order }) else { return }
        guard let feedMedia = self.media.first(where: { $0.order == order }) else { return }
        feedMedia.reload(from: feedPostMedia)
    }

    func mediaHeight(for mediaWidth: CGFloat) -> CGFloat {
        guard !self.media.isEmpty else { return 0 }

        let tallestItem = self.media.max { return $0.size.height < $1.size.height }
        let tallestItemAspectRatio = tallestItem!.size.height / tallestItem!.size.width
        let maxAllowedAspectRatio: CGFloat = 5/4
        return (mediaWidth * min(maxAllowedAspectRatio, tallestItemAspectRatio)).rounded()
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
