//
//  UNExtensions.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 9/3/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import UserNotifications

private extension UNNotificationRequest {

    var feedPostId: FeedPostID? {
        if let notificationContent = NotificationMetadata.load(from: self) {
            if notificationContent.contentType == .feedPost || notificationContent.contentType == .groupFeedPost {
                return notificationContent.contentId
            }
        }
        return nil
    }

    var feedPostCommentId: FeedPostCommentID? {
        if let notificationContent = NotificationMetadata.load(from: self) {
            if notificationContent.contentType == .feedComment || notificationContent.contentType == .groupFeedComment {
                return notificationContent.contentId
            }
        }
        return nil
    }
}

extension UNMutableNotificationContent {

    func populate(from metadata: NotificationMetadata, contactStore: ContactStore) {
        // populate title and body if metadata has more information - else dont modify the fields.
        if metadata.populateContent(contactStore: contactStore) {
            title = metadata.title
            subtitle = metadata.subtitle
            body = metadata.body
            // encode and store metadata - this will be used to handle user response on the notification.
            userInfo[NotificationMetadata.userDefaultsKeyRawData] = metadata.rawData
            DDLogInfo("UNExtensions/populate updated title: \(title), subtitle: \(subtitle), body: \(body)")
        } else {
            DDLogError("UNExtensions/populate Could not populate content")
        }
    }

}

extension UNUserNotificationCenter {

    func getFeedPostIdsForDeliveredNotifications(completion: @escaping ([FeedPostID]) -> ()) {
        getDeliveredNotifications { (notifications) in
            let ids = notifications.compactMap({ $0.request.feedPostId })
            completion(ids)
        }
    }

    func getFeedCommentIdsForDeliveredNotifications(completion: @escaping ([FeedPostCommentID]) -> ()) {
        getDeliveredNotifications { (notifications) in
            let ids = notifications.compactMap({ $0.request.feedPostCommentId })
            completion(ids)
        }
    }

    private func removeDeliveredNotifications(matching predicate: @escaping (NotificationMetadata) -> (Bool)) {
        getDeliveredNotifications { (notifications) in
            guard !notifications.isEmpty else { return }

            var identifiersToRemove: [String] = []
            for notification in notifications {
                guard let metadata = NotificationMetadata.load(from: notification.request) else { continue }
                if predicate(metadata) {
                    DDLogDebug("Notification/removeDelivered \(notification.request.identifier) will be removed")
                    identifiersToRemove.append(notification.request.identifier)
                }
            }

            if !identifiersToRemove.isEmpty {
                DDLogInfo("Notification/removeDelivered/\(identifiersToRemove.count)")
                self.removeDeliveredNotifications(withIdentifiers: identifiersToRemove)
            }
        }
    }

    func removeDeliveredFeedNotifications(postId: FeedPostID) {
        removeDeliveredNotifications { (notificationMetadata) -> (Bool) in
            return notificationMetadata.feedPostId == postId
        }
    }

    func removeDeliveredFeedNotifications(commentIds: [FeedPostCommentID]) {
        removeDeliveredNotifications { (notificationMetadata) -> (Bool) in
            guard let commentId = notificationMetadata.feedPostCommentId else {
                return false
            }
            return commentIds.contains(commentId)
        }
    }

    func removeDeliveredChatNotifications(fromUserId: UserID) {
        removeDeliveredNotifications { (notificationMetadata) -> (Bool) in
            return notificationMetadata.fromId == fromUserId
        }
    }

    func removeDeliveredChatNotifications(groupId: GroupID) {
        removeDeliveredNotifications { (notificationMetadata) -> (Bool) in
            return notificationMetadata.groupId == groupId
        }
    }
}

extension Localizations {

    static var contactNotificationUnknownContent: String {
        NSLocalizedString(
            "notification.contact.unknown.content",
            value: "One of your contacts is now on HalloApp",
            comment: "Content for unknown contact notification.")
    }

    static var contactNotificationInviteContent: String {
        NSLocalizedString(
            "notification.invite.accepted.content",
            value: "%@ just accepted your invite to join HalloApp 🎉",
            comment: "Content for inviter notification.")

    }

    static var contactNotificationFriendContent: String {
        NSLocalizedString(
            "notification.new.friend.content",
            value: "%@ is now on HalloApp",
            comment: "Content for friend notification.")
    }

    static var contactNotificationContent: String {
        NSLocalizedString(
            "notification.new.friend.content",
            value: "%@ is now on HalloApp",
            comment: "Content for contact notification.")
    }

    static var groupsAddNotificationBody: String {
        NSLocalizedString(
            "groups.add.notification",
            value: "You were added to a new group",
            comment: "Text shown in notification when the user is added to a new group")
    }

}
