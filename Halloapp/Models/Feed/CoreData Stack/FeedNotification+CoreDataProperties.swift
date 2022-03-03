//
//  FeedNotification+CoreDataProperties.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreCommon
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
        case mentionPost = 6   // mentioned in a post
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
            return MainAppContext.shared.contactStore.firstName(for: self.userId)
        }
    }

    var textWithMentions: NSAttributedString? {
        get {
            let orderedMentions = mentions?.sorted(by: { $0.index < $1.index }) ?? []
            return MainAppContext.shared.contactStore.textWithMentions(
                text,
                mentions: orderedMentions)
        }
    }

    var formattedText: NSAttributedString {
        get {
            var eventText: String
            switch self.event {
            case .comment:
                if !(self.text?.isEmpty ?? true) {
                    eventText = NSLocalizedString("feed.notification.commented.w.text",
                                                  value: "<$author$> commented: <$text$>",
                                                  comment: "Text for feed notification displayed in Activity Center.")
                } else {
                    eventText = NSLocalizedString("feed.notification.commented.no.text",
                                                  value: "<$author$> commented on your post",
                                                  comment: "Text for feed notification displayed in Activity Center.")
                }

            case .reply:
                if !(self.text?.isEmpty ?? true) {
                    eventText = NSLocalizedString("feed.notification.replied.w.text",
                                                  value: "<$author$> replied: <$text$>",
                                                  comment: "Text for feed notification displayed in Activity Center.")
                } else {
                    eventText = NSLocalizedString("feed.notification.replied.no.text",
                                                  value: "<$author$> replied to your comment",
                                                  comment: "Text for feed notification displayed in Activity Center.")
                }

            case .retractedComment:
                eventText = NSLocalizedString("feed.notification.deleted.comment",
                                              value: "<$author$> deleted their comment",
                                              comment: "Text for feed notification displayed in Activity Center.")

            case .retractedPost:
                eventText = NSLocalizedString("feed.notification.deleted.post",
                                              value: "<$author$> commented. This post has been deleted.",
                                              comment: "Text for feed notification displayed in Activity Center.")

            case .otherComment:
                if !(self.text?.isEmpty ?? true) {
                    eventText = NSLocalizedString("feed.notification.other.comment.w.text",
                                                  value: "<$author$> also commented: <$text$>",
                                                  comment: "Text for feed notification displayed in Activity Center.")
                } else {
                    eventText =  NSLocalizedString("feed.notification..other.comment.no.text",
                                                   value: "<$author$> also commented",
                                                   comment: "Text for feed notification displayed in Activity Center.")
                }

            case .mentionComment:
                if !(self.text?.isEmpty ?? true) {
                    eventText = NSLocalizedString("feed.notification.mention.comment.w.text",
                                                  value: "<$author$> mentioned you in a comment: <$text$>",
                                                  comment: "Text for feed notification displayed in Activity Center.")
                } else {
                    eventText = NSLocalizedString("feed.notification.mention.comment.no.text",
                                                  value: "<$author$> mentioned you in a comment",
                                                  comment: "Text for feed notification displayed in Activity Center.")
                }

            case .mentionPost:
                if !(self.text?.isEmpty ?? true) {
                    eventText = NSLocalizedString("feed.notification.mention.post.w.text",
                                                  value: "<$author$> mentioned you in a post: <$text$>",
                                                  comment: "Text for feed notification displayed in Activity Center.")
                } else {
                    eventText = NSLocalizedString("feed.notification.mention.post.no.text",
                                                  value: "<$author$> mentioned you in a post",
                                                  comment: "Text for feed notification displayed in Activity Center.")
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
                let ham = HAMarkdown(font: baseFont, color: UIColor.label)
                let textWithMentions = textWithMentions?.string ?? ""
                let parsedText = ham.parse(textWithMentions)
                result.replaceCharacters(in: textRange, with: parsedText)
            }
            
            let strLen = 50
            if result.length > strLen + 3 {
                result.deleteCharacters(in: NSRange(location: strLen, length: result.length - strLen))
                result.append(NSAttributedString(string: "..."))
            }

            result.addAttribute(.foregroundColor, value: UIColor.label, range: NSRange(location: 0, length: result.length))

            let timestampString = NSAttributedString(string: " \(self.formattedTimestamp.withNonBreakingSpaces())", attributes: [ .font: baseFont, .foregroundColor: UIColor.secondaryLabel ])
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
