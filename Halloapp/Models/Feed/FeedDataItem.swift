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

    var itemId: FeedPost.ID
    var username: String
    var media: [FeedMedia]

    var commentsChange = PassthroughSubject<Int, Never>()
    var unreadComments: Int {
        didSet {
            commentsChange.send(unreadComments)
        }
    }

    init(_ feedPost: FeedPost) {
        itemId = feedPost.id
        username = feedPost.userId
        unreadComments = Int(feedPost.unreadCount)
        media = feedPost.orderedMedia.map { FeedMedia($0) }
    }

    func reload(from feedPost: FeedPost) {
        // Only 'unreadComments' might change at this point.
        unreadComments = Int(feedPost.unreadCount)
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
        return lhs.itemId == rhs.itemId
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(itemId)
    }
}
