//
//  FeedNotification+CoreDataProperties.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreData
import Foundation
import UIKit

extension FeedNotification {
    enum Event: Int16 {
        case comment = 0          // comment on your post
        case reply = 1            // reply to your comment
        case retractedComment = 2 // comment was deleted
        case retractedPost = 3    // post was deleted
        case otherComment = 4     // comment on the post your commented on
        case mentionComment = 5   // mentioned in a comment
    }

    enum MediaType: Int16 {
        case none = 0
        case image = 1
        case video = 2
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<FeedNotification> {
        return NSFetchRequest<FeedNotification>(entityName: "FeedNotification")
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
    @NSManaged var commentId: FeedPostCommentID?
    @NSManaged var mediaPreview: Data?
    @NSManaged var mentions: Set<FeedMention>?
    @NSManaged var postId: FeedPostID
    @NSManaged var userId: UserID
    @NSManaged var read: Bool
    @NSManaged var text: String?
    @NSManaged var timestamp: Date
    @NSManaged private var postMediaType: Int16
    var mediaType: MediaType {
        get {
            return MediaType(rawValue: self.postMediaType) ?? .none
        }
        set {
            self.postMediaType = newValue.rawValue
        }
    }

    // MARK: UI Support

    var formattedTimestamp: String {
        get {
            return self.timestamp.feedTimestamp()
        }
    }

    var authorName: String {
        get {
            return AppContext.shared.contactStore.firstName(for: self.userId)
        }
    }

    var textWithMentions: NSAttributedString? {
        get {
            let orderedMentions = mentions?.sorted(by: { $0.index < $1.index }) ?? []
            return AppContext.shared.contactStore.textWithMentions(
                text,
                orderedMentions: orderedMentions)
        }
    }

    var formattedText: NSAttributedString {
        get {
            var eventText: String
            switch self.event {
            case .comment:
                if self.text != nil {
                    eventText = "<$author$> commented: <$text$>"
                } else {
                    eventText =  "<$author$> commented on your post"
                }
            case .reply:
                eventText = "<$author$> replied to your comment"

            case .retractedComment:
                eventText = "<$author$> deleted this comment"

            case .retractedPost:
                eventText = "<$author$> deleted this post"

            case .otherComment:
                if self.text != nil {
                    eventText = "<$author$> also commented: <$text$>"
                } else {
                    eventText =  "<$author$> also commented"
                }

            case .mentionComment:
                if self.text != nil {
                    eventText = "<$author$> mentioned you in a comment: <$text$>"
                } else {
                    eventText = "<$author$> mentioned you in a comment"
                }
            }


            let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
            let boldFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
            let result = NSMutableAttributedString(string: eventText, attributes: [ .font: baseFont ])

            let authorRange = (result.string as NSString).range(of: "<$author$>")
            if authorRange.location != NSNotFound {
                let author = NSAttributedString(string: self.authorName, attributes: [ .font: boldFont ])
                result.replaceCharacters(in: authorRange, with: author)
            }

            let textRange = (result.string as NSString).range(of: "<$text$>")
            if textRange.location != NSNotFound {
                // TODO: truncate as necessary
                let replacementString = textWithMentions?.string ?? ""
                result.replaceCharacters(in: textRange, with: replacementString)
            }

            result.addAttribute(.foregroundColor, value: UIColor.label, range: NSRange(location: 0, length: result.length))

            let timestampString = NSAttributedString(string: " \(self.formattedTimestamp)", attributes: [ .font: baseFont, .foregroundColor: UIColor.secondaryLabel ])
            result.append(timestampString)

            return result
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
