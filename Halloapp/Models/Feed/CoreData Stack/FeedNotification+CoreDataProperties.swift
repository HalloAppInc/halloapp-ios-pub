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

    @nonobjc class func fetchRequest() -> NSFetchRequest<FeedNotification> {
        return NSFetchRequest<FeedNotification>(entityName: "FeedNotification")
    }

    @NSManaged private var eventValue: Int16
    var event: FeedActivity.Event {
        get {
            return FeedActivity.Event(rawValue: self.eventValue)!
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
    var mediaType: FeedActivity.MediaType {
        get {
            return FeedActivity.MediaType(rawValue: self.postMediaType) ?? .none
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
            let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
            let boldFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)

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

            case .groupComment:
                if !(self.text?.isEmpty ?? true) {
                    eventText = NSLocalizedString("feed.group.notification.other.comment.w.text",
                                                  value: "<$author$> commented: <$text$>",
                                                  comment: "Text for group feed notification displayed in Activity Center.")
                } else {
                    eventText =  NSLocalizedString("feed.group.notification.other.comment.no.text",
                                                   value: "<$author$> commented",
                                                   comment: "Text for group feed notification displayed in Activity Center.")
                }

            case .homeFeedComment:
                if (self.text?.isEmpty ?? true) {
                    eventText =  NSLocalizedString("feed.home.notification.other.comment.no.text",
                                                   value: "<$author$> commented",
                                                   comment: "Text for home feed notification displayed in Activity Center.")
                } else {
                    eventText = NSLocalizedString("feed.home.notification.other.comment.w.text",
                                                  value: "<$author$> commented: <$text$>",
                                                  comment: "Text for home feed notification displayed in Activity Center.")
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
            case .favoritesPromo:
                let attributedText = NSMutableAttributedString()
                let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
                attributedText.append(NSAttributedString(string: NSLocalizedString("activityCenter.promo.favorites",
                                                                                   value: "Check out the new Favorites feature!",
                                                                                   comment: "First tab in the main app interface."),
                                                         attributes: [.font: baseFont]))
                return attributedText
            }


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
                    image = UIImage(systemName: "photo")?.withRenderingMode(.alwaysTemplate)
                case .video:
                    image = UIImage(systemName: "video")?.withRenderingMode(.alwaysTemplate)
                case .audio:
                    image = UIImage(systemName: "speaker.wave.2.fill")?.withRenderingMode(.alwaysTemplate)
                default:
                    break
                }
            }
            
            return image
        }
    }
}
