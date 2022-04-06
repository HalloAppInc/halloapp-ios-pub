//
//  ActivityCenter.swift
//  HalloApp
//
//  Created by Matt Geimer on 7/15/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

enum ActivityCenterSection {
    case main
}

struct ActivityCenterItem: Hashable {
    private(set) var content: Content
    
    /// Initializer is failable so that there must always be at least one `FeedActivity`
    init?(content: Content) {
        self.content = content
    }
    
    /// Value describing whether the notification has been read or not. When multiple notifications are grouped together,
    /// this value is the `&&` of all the individual notifications read status.
    var read: Bool {
        get {
            var feedNotifications: [FeedActivity] = []
            
            switch content {
                case .singleNotification(let notification): feedNotifications.append(notification)
                case .unknownCommenters(let notifications): feedNotifications.append(contentsOf: notifications)
            }
            
            for notification in feedNotifications {
                if notification.read != true {
                    return false
                }
            }
            
            return true
        }
        
        set {
            switch content {
                case .singleNotification(let notification): notification.read = newValue
                case .unknownCommenters(let notifications): notifications.forEach { $0.read = newValue }
            }
        }
    }
    
    /// The text that will be displayed in the notification tableview cell.
    var text: NSAttributedString {
        get {
            switch content {
                case .singleNotification(let notification): return notification.formattedText
                case .unknownCommenters(let notifications): return textForUnknownCommenters(with: notifications)
            }
        }
    }
    
    var image: UIImage? {
        switch content {
        case .singleNotification(let notification):
            if let image = notification.image {
                return image
            }
        case .unknownCommenters(let notifications):
            if let image = notifications.first?.image {
                return image
            }
        }
        guard let postID = postId, let post = MainAppContext.shared.feedData.feedPost(with: postID) else
            {
                return nil
            }
        let postText = MainAppContext.shared.contactStore.textWithMentions(post.rawText ?? "", mentions: post.orderedMentions)
        return UIImage.thumbnail(forText: postText?.string)
    }
    
    /// The userID related to the notification. If the notification is grouped, then the `UserID` is `nil` since they contacts are all unknown.
    var userID: UserID? {
        get {
            switch content {
                case .singleNotification(let notification): return notification.userID
                case .unknownCommenters(_): return nil
            }
        }
    }
    
    var timestamp: Date {
        switch content {
            case .singleNotification(let notification): return notification.timestamp
            case .unknownCommenters(let notifications): return Self.latestTimestamp(for: notifications)
        }
    }
    
    /// Feed post to navigate to when the notification is tapped
    var postId: FeedPostID? {
        get {
            switch content {
                case .singleNotification(let notification): return notification.postID
                case .unknownCommenters(let notifications): return Self.latestUnseen(for: notifications)?.postID ?? nil
            }
        }
    }
    
    /// Comment to highlight when the post related to the notification tapped is displayed. Should be a comment on post related to `postId` property.
    var commentId: FeedPostCommentID? {
        get {
            switch content {
                case .singleNotification(let notification): return notification.commentID
                case .unknownCommenters(let notifications): return Self.latestUnseen(for: notifications)?.commentID ?? nil
            }
        }
    }
    
    private func textForUnknownCommenters(with notifications: [FeedActivity]) -> NSAttributedString {
        let format = NSLocalizedString("n.others.replied", comment: "Summary when multiple commenters commented on the same post you commented on")
        let numberOfOtherCommenters = notifications.count - 1 // Subtract 1 because text is "<$user$> and %d others replied..."
        let localizedString = String.localizedStringWithFormat(format, numberOfOtherCommenters)
        
        let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let boldFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
        let result = NSMutableAttributedString(string: localizedString, attributes: [ .font: baseFont ])
        
        let authorRange = (result.string as NSString).range(of: "<$author$>")
        if authorRange.location != NSNotFound {
            let authorUserID = MainAppContext.shared.feedData.feedPost(with: notifications[0].postID)?.userId
            let authorName = MainAppContext.shared.contactStore.fullName(for: authorUserID ?? "")
            let author = NSAttributedString(string: authorName, attributes: [ .font: boldFont ])
            result.replaceCharacters(in: authorRange, with: author)
        }

        let commenterRange = (result.string as NSString).range(of: "<$user$>")
        if commenterRange.location != NSNotFound {
            let commenterName = MainAppContext.shared.contactStore.fullName(for: notifications.first?.userID ?? "")
            let commenter = NSAttributedString(string: commenterName, attributes: [ .font: boldFont ])
            result.replaceCharacters(in: commenterRange, with: commenter)
        }
        
        let timestampString = NSAttributedString(string: " \(timestamp.feedTimestamp())", attributes: [ .font: baseFont, .foregroundColor: UIColor.secondaryLabel ])
        result.append(timestampString)
        
        return result
    }
    
    private static func latestTimestamp(for notifications: [FeedActivity]) -> Date {
        var latestTimestamp = notifications[0].timestamp
        
        for notification in notifications {
            if notification.timestamp > latestTimestamp {
                latestTimestamp = notification.timestamp
            }
        }
        
        return latestTimestamp
    }
    
    /// Gets the latest unseen notification in an array of notifications. If all notifications have been read, then return the latest notification.
    private static func latestUnseen(for notifications: [FeedActivity]) -> FeedActivity? {
        for notification in notifications.sorted(by: { $0.timestamp > $1.timestamp }) {
            if !notification.read {
                return notification
            }
        }
        
        return notifications.first
    }
    
    enum Content: Equatable, Hashable {
        case singleNotification(FeedActivity)
        case unknownCommenters([FeedActivity])
    }
}

extension FeedActivity {

    // MARK: UI Support

    var formattedTimestamp: String {
        get {
            return timestamp.feedTimestamp()
        }
    }

    var authorName: String {
        get {
            return MainAppContext.shared.contactStore.firstName(for: userID)
        }
    }

    var textWithMentions: NSAttributedString? {
        get {
            return MainAppContext.shared.contactStore.textWithMentions(
                rawText,
                mentions: orderedMentions)
        }
    }

    var formattedText: NSAttributedString {
        get {
            var eventText: String
            switch event {
            case .comment:
                if !(rawText?.isEmpty ?? true) {
                    eventText = NSLocalizedString("feed.notification.commented.w.text",
                                                  value: "<$author$> commented: <$text$>",
                                                  comment: "Text for feed notification displayed in Activity Center.")
                } else {
                    eventText = NSLocalizedString("feed.notification.commented.no.text",
                                                  value: "<$author$> commented on your post",
                                                  comment: "Text for feed notification displayed in Activity Center.")
                }

            case .reply:
                if !(rawText?.isEmpty ?? true) {
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
                if !(rawText?.isEmpty ?? true) {
                    eventText = NSLocalizedString("feed.notification.other.comment.w.text",
                                                  value: "<$author$> also commented: <$text$>",
                                                  comment: "Text for feed notification displayed in Activity Center.")
                } else {
                    eventText =  NSLocalizedString("feed.notification..other.comment.no.text",
                                                   value: "<$author$> also commented",
                                                   comment: "Text for feed notification displayed in Activity Center.")
                }

            case .mentionComment:
                if !(rawText?.isEmpty ?? true) {
                    eventText = NSLocalizedString("feed.notification.mention.comment.w.text",
                                                  value: "<$author$> mentioned you in a comment: <$text$>",
                                                  comment: "Text for feed notification displayed in Activity Center.")
                } else {
                    eventText = NSLocalizedString("feed.notification.mention.comment.no.text",
                                                  value: "<$author$> mentioned you in a comment",
                                                  comment: "Text for feed notification displayed in Activity Center.")
                }

            case .mentionPost:
                if !(rawText?.isEmpty ?? true) {
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
}
