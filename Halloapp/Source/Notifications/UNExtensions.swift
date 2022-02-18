//
//  UNExtensions.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 9/3/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
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
            DDLogInfo("UNExtensions/populate updated content")
        } else {
            DDLogError("UNExtensions/populate Could not populate content")
        }
    }

    func populateChatBody(from chatContent: ChatContent, using metadata: NotificationMetadata, contactStore: ContactStore) {
        metadata.populateChatBody(from: chatContent, contactStore: contactStore)
        body = metadata.body
        // encode and store metadata - this will be used to handle user response on the notification.
        userInfo[NotificationMetadata.userDefaultsKeyRawData] = metadata.rawData
        DDLogInfo("UNExtensions/populateChatBody updated content")
    }

    func populateFeedPostBody(from postData: PostData, using metadata: NotificationMetadata, contactStore: ContactStore) {
        metadata.populateFeedPostBody(from: postData, contactStore: contactStore)
        subtitle = metadata.subtitle
        body = metadata.body
        // encode and store metadata - this will be used to handle user response on the notification.
        userInfo[NotificationMetadata.userDefaultsKeyRawData] = metadata.rawData
        DDLogInfo("UNExtensions/populateFeedPostBody updated content")
    }

    func populateFeedCommentBody(from commentData: CommentData, using metadata: NotificationMetadata, contactStore: ContactStore) {
        metadata.populateFeedCommentBody(from: commentData, contactStore: contactStore)
        body = metadata.body
        // encode and store metadata - this will be used to handle user response on the notification.
        userInfo[NotificationMetadata.userDefaultsKeyRawData] = metadata.rawData
        DDLogInfo("UNExtensions/populateFeedCommentBody updated content")
    }

    func populateMissedCallBody(using metadata: NotificationMetadata, contactStore: ContactStore) {
        if metadata.contentType == .missedVideoCall {
            metadata.populateMissedVideoCallContent(contactStore: contactStore)
        } else {
            metadata.populateMissedVoiceCallContent(contactStore: contactStore)
        }
        title = metadata.title
        body = metadata.body
        // encode and store metadata - this will be used to handle user response on the notification.
        userInfo[NotificationMetadata.userDefaultsKeyRawData] = metadata.rawData
        DDLogInfo("UNExtensions/populateMissedCallBody")
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
            "notification.new.contact.content",
            value: "%@ is now on HalloApp",
            comment: "Content for contact notification.")
    }

    static var groupsAddNotificationBody: String {
        NSLocalizedString(
            "groups.add.notification",
            value: "You were added to a new group",
            comment: "Text shown in notification when the user is added to a new group")
    }

    static var newPostNotificationBody: String {
        NSLocalizedString(
            "notification.new.post",
            value: "New Post",
            comment: "Title for the new feed post notification.")
    }

    static var newCommentNotificationBody: String {
        NSLocalizedString(
            "notification.new.comment",
            value: "New Comment",
            comment: "Title for the new comment notification.")
    }

    static var newCommentWithTextNotificationBody: String {
        NSLocalizedString(
            "notification.commented.with.text",
            value: "Commented: %@",
            comment: "Push notification for a new comment. Parameter is the text of the comment")
    }

    static var newMessageNotificationBody: String {
        NSLocalizedString(
            "notification.new.message",
            value: "New Message",
            comment: "Fallback text for new message notification.")
    }

    static var newAudioNoteNotificationBody: String {
        NSLocalizedString(
            "notification.voicenote",
            value: "🎤 Voice note",
            comment: "New post notification text when post is a voice note.")
    }

    static var newMissedVoiceCallNotificationBody: String {
        NSLocalizedString(
            "notification.voicecall.missed",
            value: "☎️ Missed voice call",
            comment: "Missed voice call notification text to be shown to the user.")
    }

    static var newMissedVideoCallNotificationBody: String {
        NSLocalizedString(
            "notification.videocall.missed",
            value: "📹 Missed video call",
            comment: "Missed video call notification text to be shown to the user.")
    }
}
