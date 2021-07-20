//
//  ActivityCenter.swift
//  HalloApp
//
//  Created by Matt Geimer on 7/15/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import UIKit

enum ActivityCenterSection {
    case main
}

struct ActivityCenterNotification: Hashable {
    private var id: UUID = UUID()
    private var notificationType: ActivityCenterNotificationType
    
    /// Initializer is failable so that there must always be at least one `FeedNotification`
    init?(notificationType: ActivityCenterNotificationType) {
        self.notificationType = notificationType
    }
    
    /// Value describing whether the notification has been read or not. When multiple notifications are grouped together,
    /// this value is the `&&` of all the individual notifications read status.
    var read: Bool {
        get {
            var feedNotifications: [FeedNotification] = []
            
            switch notificationType {
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
    }
    
    /// The text that will be displayed in the notification tableview cell.
    var text: NSAttributedString {
        get {
            switch notificationType {
                case .singleNotification(let notification): return notification.formattedText
                case .unknownCommenters(let notifications): return textForUnknownCommenters(with: notifications)
            }
        }
    }
    
    var image: UIImage? {
        get {
            switch notificationType {
                case .singleNotification(let notification):
                    return notification.image
                case .unknownCommenters(let notifications):
                    return notifications[0].image // Since they're all comments on the same post, just use the first image
            }
        }
    }
    
    /// The userID related to the notification. If the notification is grouped, then the `UserID` is `nil` since they contacts are all unknown.
    var userID: UserID? {
        get {
            switch notificationType {
                case .singleNotification(let notification): return notification.userId
                case .unknownCommenters(_): return nil
            }
        }
    }
    
    var timestamp: Date {
        switch notificationType {
            case .singleNotification(let notification): return notification.timestamp
            case .unknownCommenters(let notifications): return Self.latestTimestamp(for: notifications)
        }
    }
    
    private func textForUnknownCommenters(with notifications: [FeedNotification]) -> NSAttributedString {
        let localizedString = NSLocalizedString("feed.notification.comment.grouped", value: "<$numberOthers$> others replied to <$author$>'s post", comment: "Text for feed notification displayed in Activity Center.")
        
        let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let boldFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
        let result = NSMutableAttributedString(string: localizedString, attributes: [ .font: baseFont ])
        
        let authorRange = (result.string as NSString).range(of: "<$author$>")
        if authorRange.location != NSNotFound {
            let authorUserID = MainAppContext.shared.feedData.feedDataItem(with: notifications[0].postId)?.userId
            let authorName = MainAppContext.shared.contactStore.fullName(for: authorUserID ?? "")
            let author = NSAttributedString(string: authorName, attributes: [ .font: boldFont ])
            result.replaceCharacters(in: authorRange, with: author)
        }

        let textRange = (result.string as NSString).range(of: "<$numberOthers$>")
        if textRange.location != NSNotFound {
            result.replaceCharacters(in: textRange, with: "\(notifications.count)")
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
    
    enum ActivityCenterNotificationType: Equatable, Hashable {
        case singleNotification(FeedNotification)
        case unknownCommenters([FeedNotification])
    }
}
