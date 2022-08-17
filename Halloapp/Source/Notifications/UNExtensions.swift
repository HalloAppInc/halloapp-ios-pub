//
//  UNExtensions.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 9/3/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
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

    var screenshotPostId: FeedPostID? {
        if let notificationContent = NotificationMetadata.load(from: self), case .screenshot = notificationContent.contentType {
            return notificationContent.contentId
        }

        return nil
    }
}

extension UNMutableNotificationContent {

    func populateMoments(from metadata: NotificationMetadata, using moments: [PostData], contactStore: ContactStore) {
        // populate title and body if metadata has more information - else dont modify the fields.
        if metadata.populateContent(using: moments, contactStore: contactStore) {
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

    func populateScreenshotBody(using metadata: NotificationMetadata, contactStore: ContactStore) {
        metadata.populateScreenshotContent(contactStore: contactStore)
        title = metadata.title
        body = metadata.body
        userInfo[NotificationMetadata.contentTypeKey] = metadata.contentType.rawValue
        userInfo[NotificationMetadata.userDefaultsKeyRawData] = metadata.rawData
        DDLogInfo("UNExtensions/populateScreenshotBody")
    }
}

extension UNUserNotificationCenter {

    func getMomentNotification(for context: NotificationMetadata.MomentType, completion: @escaping (NotificationMetadata?) -> ()) {
        getDeliveredNotifications { (notifications) in
            for notification in notifications {
                guard let metadata = NotificationMetadata.load(from: notification.request),
                      metadata.momentContext == context else { continue }
                completion(metadata)
                return
            }
            completion(nil)
        }
    }

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

    func getScreenshotIdsForDeliveredNotifications() async -> [FeedPostID] {
        return await deliveredNotifications().compactMap { $0.request.screenshotPostId }
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

    func removeDeliveredPostNotifications(postId: FeedPostID) {
        removeDeliveredNotifications(withIdentifiers: [postId])
    }

    func removeDeliveredPostNotifications(postIds: [FeedPostID]) {
        removeDeliveredNotifications(withIdentifiers: postIds)
    }

    func removeDeliveredCommentNotifications(commentId: FeedPostCommentID) {
        removeDeliveredNotifications(withIdentifiers: [commentId])
    }

    func removeDeliveredCommentNotifications(commentIds: [FeedPostCommentID]) {
        removeDeliveredNotifications(withIdentifiers: commentIds)
    }

    func removeDeliveredChatNotifications(fromUserId: UserID) {
        removeDeliveredNotifications { (notificationMetadata) -> (Bool) in
            return notificationMetadata.fromId == fromUserId && notificationMetadata.isChatNotification
        }
    }

    func removeDeliveredGroupPostNotifications(groupId: GroupID) {
        removeDeliveredNotifications { (notificationMetadata) -> (Bool) in
            return notificationMetadata.groupId == groupId && notificationMetadata.isPostNotification
        }
        removeDeliveredGroupAddNotification(groupId: groupId)
    }

    func removeDeliveredGroupAddNotification(groupId: GroupID?) {
        guard let groupId = groupId else {
            return
        }
        removeDeliveredNotifications(withIdentifiers: [groupId])
    }

    func removeDeliveredMomentNotifications() {
        removeDeliveredNotifications { (notificationMetadata) -> (Bool) in
            return notificationMetadata.momentContext != nil
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
    
    static var newCommentWithReactionNotificationBody: String {
        NSLocalizedString("notification.comment.reaction",
                          value: "Reacted %@ to a comment",
                          comment: "Push notification for a comment to message")
    }

    static var newMessageNotificationBody: String {
        NSLocalizedString(
            "notification.new.message",
            value: "New Message",
            comment: "Fallback text for new message notification.")
    }

    static var messageReactionNotificationTitle: String {
        NSLocalizedString("notification.message.reaction",
                          value: "Reacted %@ to a message",
                          comment: "Push notification for a reaction to message")
    }
    
    static var newLocationNotificationBody: String {
        NSLocalizedString("notification.location",
                          value: "📍 Location",
                          comment: "New message notification text when message is a location.")
    }
    
    static var newAudioNoteNotificationBody: String {
        NSLocalizedString(
            "notification.voicenote",
            value: "🎤 Audio note",
            comment: "New post notification text when post is a voice note.")
    }

    static var newAudioPostNotificationBody: String {
        NSLocalizedString(
            "notification.voicepost",
            value: "🎤 Audio post",
            comment: "New post notification text when post is a voice note.")
    }

    static var newAudioCommentNotificationBody: String {
        NSLocalizedString(
            "notification.voicecomment",
            value: "🎤 Audio comment",
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

    static var newMomentNotificationSubtitle: String {
        NSLocalizedString("notification.moment",
                   value: "New moment",
                 comment: "New moment notification text to be shown to the user.")
    }

    static var oneNewMomentNotificationTitle: String {
        NSLocalizedString("notification.moment.1",
                          value: "%@ shared a new moment",
                          comment: "New moment notification text to be shown to the user.")
    }

    static var twoNewMomentNotificationTitle: String {
        NSLocalizedString("notification.moment.2",
                          value: "%1@ and %2@ shared new moments",
                          comment: "New moment notification text to be shown to the user.")
    }

    static var threeNewMomentNotificationTitle: String {
        NSLocalizedString("notification.moment.3",
                          value: "%1@, %2@ and %3@ shared new moments",
                          comment: "New moment notification text to be shown to the user.")
    }

    static var tooManyNewMomentNotificationTitle: String {
        NSLocalizedString("notification.moment.5",
                          value: "%1@, %2@, %3@ and others shared new moments",
                          comment: "New moment notification text to be shown to the user.")
    }

    static var oneUnlockedMomentNotificationTitle: String {
        NSLocalizedString("notification.unlocked.moment.1",
                   value: "%@ shared a new moment to see yours",
                 comment: "New moment unlock notification text to be shown to the user.")
    }

    static var twoUnlockedMomentNotificationTitle: String {
        NSLocalizedString("notification.unlocked.moment.2",
                   value: "%1@ and %2@ shared a new moment to see yours",
                 comment: "New moment unlock notification text to be shown to the user.")
    }

    static var threeUnlockedMomentNotificationTitle: String {
        NSLocalizedString("notification.unlocked.moment.3",
                   value: "%1@, %2@, and %3@ shared a new moment to see yours",
                 comment: "New moment unlock notification text to be shown to the user.")
    }

    static var tooManyUnlockedMomentNotificationTitle: String {
        NSLocalizedString("notification.unlocked.moment.4",
                   value: "%1@, %2@, %3@, and others shared a new moment to see yours",
                 comment: "New moment unlock notification text to be shown to the user.")
    }

    static var momentScreenshotNotificationTitle: String {
        NSLocalizedString("notification.moment.screenshot",
                   value: "%@ took a screenshot of your moment",
                 comment: "New moment screenshot notification text to be shown to the user.")
    }
}
