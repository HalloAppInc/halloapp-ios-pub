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

fileprivate struct ActivityCenterConstants {
    static let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
    static let boldFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
}

struct ActivityCenterItem: Hashable {
    private(set) var content: Content
    
    /// Initializer is failable so that there must always be at least one `FeedActivity`
    init?(content: Content) {
        self.content = content

        // precompute read, as computed properties are not included in diffs
        switch content {
        case .singleNotification(let notification):
            read = notification.read
        case .unknownCommenters(let notifications):
            read = notifications.allSatisfy { $0.read }
        case .groupEvent(let groupEvent):
            read = groupEvent.read
        }
    }
    
    /// Value describing whether the notification has been read or not. When multiple notifications are grouped together,
    /// this value is the `&&` of all the individual notifications read status.
    let read: Bool
    
    /// The text that will be displayed in the notification tableview cell.
    var text: NSAttributedString {
        switch content {
        case .singleNotification(let notification):
            return notification.formattedText
        case .unknownCommenters(let notifications):
            return textForUnknownCommenters(with: notifications)
        case .groupEvent(let groupEvent):
            return groupEvent.formattedNotificationText ?? NSAttributedString()
        }
    }
    
    var image: UIImage? {
        switch content {
        case .singleNotification(let notification):
            return notification.image ?? Self.image(for: notification.postID)
        case .unknownCommenters(let notifications):
            return notifications.first.flatMap { $0.image ?? Self.image(for: $0.postID) }
        case .groupEvent:
            return nil
        }
    }
    
    /// The userID related to the notification. If the notification is grouped, then the `UserID` is `nil` since they contacts are all unknown.
    var userID: UserID? {
        switch content {
        case .singleNotification(let notification):
            return notification.userID
        case .unknownCommenters:
            return nil
        case .groupEvent:
            return nil
        }
    }
    
    var timestamp: Date {
        switch content {
        case .singleNotification(let notification):
            return notification.timestamp
        case .unknownCommenters(let notifications):
            return notifications.map(\.timestamp).max() ?? Date()
        case .groupEvent(let groupEvent):
            return groupEvent.timestamp
        }
    }
    
    /// Feed post to navigate to when the notification is tapped
    var postId: FeedPostID? {
        switch content {
        case .singleNotification(let notification):
            return notification.postID
        case .unknownCommenters(let notifications):
            return Self.latestUnseen(for: notifications)?.postID ?? nil
        case .groupEvent:
            return nil
        }
    }
    
    /// Comment to highlight when the post related to the notification tapped is displayed. Should be a comment on post related to `postId` property.
    var commentId: FeedPostCommentID? {
        switch content {
        case .singleNotification(let notification):
            return notification.commentID
        case .unknownCommenters(let notifications):
            return Self.latestUnseen(for: notifications)?.commentID ?? nil
        case .groupEvent:
            return nil
        }
    }

    private func textForUnknownCommenters(with notifications: [FeedActivity]) -> NSAttributedString {
        let format = NSLocalizedString("n.others.replied", comment: "Summary when multiple commenters commented on the same post you commented on")
        let numberOfOtherCommenters = Set<UserID>(notifications.map { $0.userID }).count - 1 // Subtract 1 because text is "<$user$> and %d others replied..."
        let localizedString = String.localizedStringWithFormat(format, numberOfOtherCommenters)
        
        let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let boldFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
        let result = NSMutableAttributedString(string: localizedString, attributes: [ .font: baseFont ])
        let contactsViewContext = MainAppContext.shared.contactStore.viewContext
        
        let authorRange = (result.string as NSString).range(of: "<$author$>")
        if authorRange.location != NSNotFound {
            let authorUserID = MainAppContext.shared.feedData.feedPost(with: notifications[0].postID, in: MainAppContext.shared.feedData.viewContext)?.userId
            let authorName = authorUserID.flatMap {
                UserProfile.find(with: $0, in: MainAppContext.shared.mainDataStore.viewContext)?.displayName
            } ?? ""
            let author = NSAttributedString(string: authorName, attributes: [ .font: boldFont ])
            result.replaceCharacters(in: authorRange, with: author)
        }

        let commenterRange = (result.string as NSString).range(of: "<$user$>")
        if commenterRange.location != NSNotFound {
            let commenterName = notifications.first.flatMap {
                UserProfile.find(with: $0.userID, in: MainAppContext.shared.mainDataStore.viewContext)?.displayName
            } ?? ""
            let commenter = NSAttributedString(string: commenterName, attributes: [ .font: boldFont ])
            result.replaceCharacters(in: commenterRange, with: commenter)
        }
        
        let timestampString = NSAttributedString(string: " \(timestamp.feedTimestamp())", attributes: [ .font: baseFont, .foregroundColor: UIColor.secondaryLabel ])
        result.append(timestampString)
        
        return result
    }

    private static func image(for postID: FeedPostID) -> UIImage? {
        guard let feedPost = MainAppContext.shared.feedData.feedPost(with: postID, in: MainAppContext.shared.feedData.viewContext),
              let postText = UserProfile.text(with: feedPost.orderedMentions, 
                                              collapsedText: feedPost.rawText ?? "",
                                              in: MainAppContext.shared.mainDataStore.viewContext) else {
            return nil
        }

        return UIImage.thumbnail(forText: postText.string)
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
        case groupEvent(GroupEvent)
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
            return MainAppContext.shared.contactStore.firstName(for: userID, in: MainAppContext.shared.contactStore.viewContext)
        }
    }

    var textWithMentions: NSAttributedString? {
        get {
            guard let managedObjectContext else {
                return nil
            }

            return UserProfile.text(with: orderedMentions, collapsedText: rawText, in: managedObjectContext)
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

            case .groupComment:
                if !(rawText?.isEmpty ?? true) {
                    eventText = NSLocalizedString("feed.group.notification.other.comment.w.text",
                                                  value: "<$author$> commented: <$text$>",
                                                  comment: "Text for group feed notification displayed in Activity Center.")
                } else {
                    eventText =  NSLocalizedString("feed.group.notification.other.comment.no.text",
                                                   value: "<$author$> commented",
                                                   comment: "Text for group feed notification displayed in Activity Center.")
                }

            case .homeFeedComment:
                if (rawText?.isEmpty ?? true) {
                    eventText =  NSLocalizedString("feed.home.notification.other.comment.no.text",
                                                   value: "<$author$> commented",
                                                   comment: "Text for home feed notification displayed in Activity Center.")
                } else {
                    eventText = NSLocalizedString("feed.home.notification.other.comment.w.text",
                                                  value: "<$author$> commented: <$text$>",
                                                  comment: "Text for home feed notification displayed in Activity Center.")
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
                return NSAttributedString(string: NSLocalizedString("activityCenter.promo.favorites",
                                                                    value: "Check out the new Favorites feature!",
                                                                    comment: "First tab in the main app interface."),
                                          attributes: [.font: ActivityCenterConstants.baseFont])
            }

            let result = NSMutableAttributedString(string: eventText, attributes: [ .font: ActivityCenterConstants.baseFont ])

            let authorRange = (result.string as NSString).range(of: "<$author$>")
            if authorRange.location != NSNotFound {
                let author = NSAttributedString(string: self.authorName, attributes: [ .font: ActivityCenterConstants.boldFont ])
                result.replaceCharacters(in: authorRange, with: author)
            }

            let textRange = (result.string as NSString).range(of: "<$text$>")
            if textRange.location != NSNotFound {
                let ham = HAMarkdown(font: ActivityCenterConstants.baseFont, color: UIColor.label)
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

            let timestampString = NSAttributedString(string: " \(self.formattedTimestamp.withNonBreakingSpaces())", attributes: [ .font: ActivityCenterConstants.baseFont, .foregroundColor: UIColor.secondaryLabel ])
            result.append(timestampString)

            return result
        }
    }
}

extension GroupEvent {

    var formattedNotificationText: NSAttributedString? {
        let eventText: String?

        let currentUserIsSender = (senderUserID == MainAppContext.shared.userData.userId)

        switch action {
        case .create:
            if currentUserIsSender {
                eventText = NSLocalizedString("group.notification.created.you",
                                              value: "You created the group <$groupname$>",
                                              comment: "Notification that you created a group")
            } else {
                eventText = NSLocalizedString("group.notification.created",
                                              value: "<$sender$> created the group <$groupname$>",
                                              comment: "Notification that a user created a group")
            }
        case .join:
            if currentUserIsSender {
                eventText = NSLocalizedString("group.notification.join.you",
                                              value: "You joined the group <$groupname$> via Group Invite Link",
                                              comment: "Notification that you joined a group")
            } else {
                eventText = NSLocalizedString("group.notification.join",
                                              value: "<$sender$> joined the group <$groupname$> via Group Invite Link",
                                              comment: "Notification that a user joined a group")
            }
        case .changeName:
            if currentUserIsSender {
                eventText = NSLocalizedString("group.notification.changeName.you",
                                              value: "You changed a group's name to <$groupname$>",
                                              comment: "Notification that you changed a groups name")
            } else {
                eventText = NSLocalizedString("group.notification.changeName",
                                              value: "<$sender$> changed a group's name to <$groupname$>",
                                              comment: "Notification that a user changed a groups name")
            }
        case .changeDescription:
            if currentUserIsSender {
                eventText = NSLocalizedString("group.notification.changeDescription.you",
                                              value: "You changed the description for the group <$groupname$>",
                                              comment: "Notification that you changed a groups description")
            } else {
                eventText = NSLocalizedString("group.notification.changeDescription",
                                              value: "<$sender$> changed the description for the group <$groupname$>",
                                              comment: "Notification that a user changed a groups description")
            }
        case .changeAvatar:
            if currentUserIsSender {
                eventText = NSLocalizedString("group.notification.changeAvatar.you",
                                              value: "You changed the icon for the group <$groupname$>",
                                              comment: "Notification that you changed a groups avatar")
            } else {
                eventText = NSLocalizedString("group.notification.changeAvatar",
                                              value: "<$sender$> changed the icon for the group <$groupname$>",
                                              comment: "Notification that a user changed a groups avatar")
            }
        case .setBackground:
            if currentUserIsSender {
                eventText = NSLocalizedString("group.notification.setBackground.you",
                                              value: "You changed the background color for the group <$groupname$>",
                                              comment: "Notification that you changed a groups background")
            } else {
                eventText = NSLocalizedString("group.notification.setBackground",
                                              value: "<$sender$> changed the background color for the group <$groupname$>",
                                              comment: "Notification that a user changed a groups background")
            }
        case .leave, .modifyMembers, .modifyAdmins:
            let currentUserIsMember = (memberUserID == MainAppContext.shared.userData.userId)
            switch memberAction {
            case .add:
                if currentUserIsSender {
                    eventText = NSLocalizedString("group.notification.memberaction.add.you.sender",
                                                  value: "You added <$member$> to the group <$groupname$>",
                                                  comment: "Notification that you added a group member")
                } else if currentUserIsMember {
                    eventText = NSLocalizedString("group.notification.memberaction.add.you.member",
                                                  value: "<$sender$> added you to the group <$groupname$>",
                                                  comment: "Notification that a user added a group member")
                } else {
                    eventText = NSLocalizedString("group.notification.memberaction.add",
                                                  value: "<$sender$> added <$member$> to the group <$groupname$>",
                                                  comment: "Notification that a user added a group member")
                }
            case .remove:
                if currentUserIsSender {
                    eventText = NSLocalizedString("group.notification.memberaction.remove.you.sender",
                                                  value: "You removed <$member$> from the group <$groupname$>",
                                                  comment: "Notification that you removed a group member")
                } else if currentUserIsMember {
                    eventText = NSLocalizedString("group.notification.memberaction.remove.you.member",
                                                  value: "<$sender$> removed you from the group <$groupname$>",
                                                  comment: "Notification that a user added a group member")
                } else {
                    eventText = NSLocalizedString("group.notification.memberaction.remove",
                                                  value: "<$sender$> removed <$member$> from the group <$groupname$>",
                                                  comment: "Notification that a user removed a group member")
                }
            case .promote:
                if currentUserIsSender {
                    eventText = NSLocalizedString("group.notification.memberaction.promote.you.sender",
                                                  value: "You made <$member$> an admin of the group <$groupname$>",
                                                  comment: "Notification that you promoted a group member")
                } else if currentUserIsMember {
                    eventText = NSLocalizedString("group.notification.memberaction.promote.you.member",
                                                  value: "<$sender$> made you an admin of the group <$groupname$>",
                                                  comment: "Notification that you promoted a group member")
                } else {
                    eventText = NSLocalizedString("group.notification.memberaction.promote",
                                                  value: "<$sender$> made <$member$> an admin of the group <$groupname$>",
                                                  comment: "Notification that a user promoted a group member")
                }
            case .demote:
                if currentUserIsSender {
                    eventText = NSLocalizedString("group.notification.memberaction.demote.you.sender",
                                                  value: "You removed <$member$> as an admin for the group <$groupname$>",
                                                  comment: "Notification that you demmoted a group member")
                } else if currentUserIsMember {
                    eventText = NSLocalizedString("group.notification.memberaction.demote.you.member",
                                                  value: "<$sender$> removed you as an admin for the group <$groupname$>",
                                                  comment: "Notification that a user demmoted you")
                } else {
                    eventText = NSLocalizedString("group.notification.memberaction.demote",
                                                  value: "<$sender$> removed <$member$> as an admin for the group <$groupname$>",
                                                  comment: "Notification that a user demmoted a group member")
                }
            case .leave:
                if currentUserIsSender {
                    eventText = NSLocalizedString("group.notification.memberaction.leave.you",
                                                  value: "You left the group <$groupname$>",
                                                  comment: "Notification that you left a group")
                } else {
                    eventText = NSLocalizedString("group.notification.memberaction.leave",
                                                  value: "<$sender$> left the group <$groupname$>",
                                                  comment: "Notification that a user left a group")
                }
            default:
                eventText = nil
            }
        case .changeExpiry:
            let formatString: String
            if currentUserIsSender {
                formatString = NSLocalizedString("group.notification.changeExpiry.you",
                                              value: "You changed the expiration for the group <$groupname$> to %1@",
                                              comment: "Notification that you changed a group's expiration")
            } else {
                formatString = NSLocalizedString("group.notification.changeExpiry",
                                              value: "<$sender$> changed the expiration for the group <$groupname$> to %1@",
                                              comment: "Notification that a user changed a group's expiration")
            }
            eventText = String(format: formatString, Group.formattedExpirationTime(type: groupExpirationType, time: groupExpirationTime))
        case .none, .get, .delete, .autoPromoteAdmins:
            eventText = nil
        }

        guard let eventText = eventText else {
            return nil
        }

        let result = NSMutableAttributedString(string: eventText, attributes: [ .font: ActivityCenterConstants.baseFont ])

        if let senderUserID = senderUserID, let senderRange = result.string.range(of: "<$sender$>") {
            let sender = MainAppContext.shared.contactStore.firstName(for: senderUserID, in: MainAppContext.shared.contactStore.viewContext)
            result.replaceCharacters(in: NSRange(senderRange, in: result.string),
                                     with: NSAttributedString(string: sender, attributes: [.font: ActivityCenterConstants.boldFont]))
        }

        if let memberUserID = memberUserID, let memberRange = result.string.range(of: "<$member$>") {
            let member = MainAppContext.shared.contactStore.firstName(for: memberUserID, in: MainAppContext.shared.contactStore.viewContext)
            result.replaceCharacters(in: NSRange(memberRange, in: result.string),
                                     with: NSAttributedString(string: member, attributes: [.font: ActivityCenterConstants.boldFont]))
        }

        if let group = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: MainAppContext.shared.chatData.viewContext),
           let groupNameRange = result.string.range(of: "<$groupname$>") {
            result.replaceCharacters(in: NSRange(groupNameRange, in: result.string),
                                     with: NSAttributedString(string: group.name, attributes: [.font: ActivityCenterConstants.boldFont]))
        }

        return result
    }
}
