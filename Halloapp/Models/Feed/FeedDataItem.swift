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

    var itemId: String
    var username: String
    var text: String?
    var timestamp: Date
    var mediaHeight: Int?

    @Published var media: [FeedMedia] = []

    var commentsChange = PassthroughSubject<Int, Never>()
    var unreadComments: Int {
        didSet {
            commentsChange.send(unreadComments)
        }
    }

    private var cancellableSet: Set<AnyCancellable> = []

    init(_ post: XMPPFeedPost) {
        self.itemId = post.id
        self.username = post.userPhoneNumber
        self.text = post.text
        if post.timestamp != nil {
            self.timestamp = Date(timeIntervalSince1970: post.timestamp!)
        } else {
            self.timestamp = Date()
        }
        self.unreadComments = 0
        self.media = post.media.enumerated().map{ FeedMedia($0.element, feedPostId: post.id, order: $0.offset) }
    }

    init(_ post: FeedCore) {
        self.itemId = post.itemId!
        self.username = post.username!
        self.text = post.text
        self.unreadComments = Int(post.unreadComments)
        if post.mediaHeight > 0 {
            self.mediaHeight = Int(post.mediaHeight)
        } else {
            self.mediaHeight = nil
        }
        if post.timestamp > 0 {
            self.timestamp = Date(timeIntervalSince1970: post.timestamp)
        } else {
            self.timestamp = Date()
        }
    }

    func loadMedia() {
        for med in self.media {
            if (med.type == .image && med.image == nil) || (med.type == .video && med.tempUrl == nil) {
                if med.numTries < 10 {
                    cancellableSet.insert(
                        med.didChange.sink { [weak self] _ in
                            guard let self = self else { return }

                            self.objectWillChange.send()
                        }
                    )
                    
                    med.loadImage()
                }
            }
        }
    }
    
    static func == (lhs: FeedDataItem, rhs: FeedDataItem) -> Bool {
        return lhs.itemId == rhs.itemId
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(itemId)
    }
}
