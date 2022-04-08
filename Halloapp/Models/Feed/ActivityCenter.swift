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
    
    /// Initializer is failable so that there must always be at least one `FeedNotification`
    init?(content: Content) {
        self.content = content
    }
    
    /// Value describing whether the notification has been read or not. When multiple notifications are grouped together,
    /// this value is the `&&` of all the individual notifications read status.
    var read: Bool {
        get {
            var feedNotifications: [FeedNotification] = []
            
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
        let postText = MainAppContext.shared.contactStore.textWithMentions(post.text ?? "", mentions: post.orderedMentions)
        return UIImage.thumbnail(forText: postText?.string)
    }
    
    /// The userID related to the notification. If the notification is grouped, then the `UserID` is `nil` since they contacts are all unknown.
    var userID: UserID? {
        get {
            switch content {
                case .singleNotification(let notification): return notification.userId
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
                case .singleNotification(let notification): return notification.postId
                case .unknownCommenters(let notifications): return Self.latestUnseen(for: notifications)?.postId ?? nil
            }
        }
    }
    
    /// Comment to highlight when the post related to the notification tapped is displayed. Should be a comment on post related to `postId` property.
    var commentId: FeedPostCommentID? {
        get {
            switch content {
                case .singleNotification(let notification): return notification.commentId
                case .unknownCommenters(let notifications): return Self.latestUnseen(for: notifications)?.commentId ?? nil
            }
        }
    }
    
    private func textForUnknownCommenters(with notifications: [FeedNotification]) -> NSAttributedString {
        let format = NSLocalizedString("n.others.replied", comment: "Summary when multiple commenters commented on the same post you commented on")
        let numberOfOtherCommenters = notifications.count - 1 // Subtract 1 because text is "<$user$> and %d others replied..."
        let localizedString = String.localizedStringWithFormat(format, numberOfOtherCommenters)
        
        let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let boldFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
        let result = NSMutableAttributedString(string: localizedString, attributes: [ .font: baseFont ])
        
        let authorRange = (result.string as NSString).range(of: "<$author$>")
        if authorRange.location != NSNotFound {
            let authorUserID = MainAppContext.shared.feedData.feedPost(with: notifications[0].postId)?.userId
            let authorName = MainAppContext.shared.contactStore.fullName(for: authorUserID ?? "")
            let author = NSAttributedString(string: authorName, attributes: [ .font: boldFont ])
            result.replaceCharacters(in: authorRange, with: author)
        }

        let commenterRange = (result.string as NSString).range(of: "<$user$>")
        if commenterRange.location != NSNotFound {
            let commenterName = MainAppContext.shared.contactStore.fullName(for: notifications.first?.userId ?? "")
            let commenter = NSAttributedString(string: commenterName, attributes: [ .font: boldFont ])
            result.replaceCharacters(in: commenterRange, with: commenter)
        }
        
        let timestampString = NSAttributedString(string: " \(timestamp.feedTimestamp())", attributes: [ .font: baseFont, .foregroundColor: UIColor.secondaryLabel ])
        result.append(timestampString)
        
        return result
    }
    
    private static func latestTimestamp(for notifications: [FeedNotification]) -> Date {
        var latestTimestamp = notifications[0].timestamp
        
        for notification in notifications {
            if notification.timestamp > latestTimestamp {
                latestTimestamp = notification.timestamp
            }
        }
        
        return latestTimestamp
    }
    
    /// Gets the latest unseen notification in an array of notifications. If all notifications have been read, then return the latest notification.
    private static func latestUnseen(for notifications: [FeedNotification]) -> FeedNotification? {
        for notification in notifications.sorted(by: { $0.timestamp > $1.timestamp }) {
            if !notification.read {
                return notification
            }
        }
        
        return notifications.first
    }
    
    enum Content: Equatable, Hashable {
        case singleNotification(FeedNotification)
        case unknownCommenters([FeedNotification])
    }
}
