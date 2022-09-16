//
//  FeedActivity+CoreDataProperties.swift
//  Core
//
//  Created by Garrett on 3/18/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CoreData
import Foundation
import UIKit

public extension FeedActivity {
    enum Event: Int16 {
        case comment = 0          // comment on your post
        case reply = 1            // reply to your comment
        case retractedComment = 2 // comment was deleted
        case retractedPost = 3    // post was deleted
        case otherComment = 4     // comment on the post your commented on
        case mentionComment = 5   // mentioned in a comment
        case mentionPost = 6      // mentioned in a post
        case favoritesPromo = 7   // Promo for new favorites
        case groupComment = 8   // batch and show comment related activity on group post
        case homeFeedComment = 9 // batch and show home feed comment related activity on home feed post.
    }

    enum MediaType: Int16 {
        case none = 0
        case image = 1
        case video = 2
        case audio = 3
        case document = 4
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<FeedActivity> {
        return NSFetchRequest<FeedActivity>(entityName: "FeedActivity")
    }

    @NSManaged private var eventValue: Int16
    var event: Event {
        get {
            return Event(rawValue: self.eventValue)!
        }
        set {
            self.eventValue = newValue.rawValue
        }
    }
    @NSManaged var commentID: FeedPostCommentID?
    @NSManaged var mediaPreview: Data?
    @NSManaged var postID: FeedPostID
    @NSManaged var userID: UserID
    @NSManaged var read: Bool
    @NSManaged var rawText: String?
    @NSManaged var timestamp: Date
    @NSManaged private var mentionsValue: Any?
    var mentions: [MentionData] {
        get { return mentionsValue as? [MentionData] ?? [] }
        set { mentionsValue = newValue }
    }

    @NSManaged private var postMediaType: Int16

    var orderedMentions: [MentionData] {
        return mentions.sorted(by: { $0.index < $1.index })
    }

    var mediaType: MediaType {
        get {
            return MediaType(rawValue: self.postMediaType) ?? .none
        }
        set {
            self.postMediaType = newValue.rawValue
        }
    }

    var image: UIImage? {
        get {
            let mediaType = self.mediaType
            guard mediaType != .none else {
                return nil

            }

            var image: UIImage?
            if let blob = self.mediaPreview {
                image = UIImage(data: blob)
            }
            if image == nil {
                switch mediaType {
                case .image:
                    // TODO: need better image
                    image = UIImage(systemName: "photo")
                case .video:
                    image = UIImage(systemName: "video")
                default:
                    break
                }
            }
            return image
        }
    }
}
