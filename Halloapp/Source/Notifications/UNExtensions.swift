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
        if let (contentId, contentType) = NotificationMetadata.parseIds(from: self) {
            if contentType == .feedPost || contentType == .groupFeedPost {
                return contentId
            }
        }
        return nil
    }

    var feedPostCommentId: FeedPostCommentID? {
        if let (contentId, contentType) = NotificationMetadata.parseIds(from: self) {
            if contentType == .feedComment || contentType == .groupFeedComment {
                return contentId
            }
        }
        return nil
    }
}

extension UNMutableNotificationContent {

    private static func mediaIcon(_ protoMedia: Clients_Media) -> String {
        switch protoMedia.type {
            case .image:
                return "📷"
            case .video:
                return "📹"
            default:
                return ""
        }
    }

    private static func notificationBody(forMedia media: [Clients_Media]) -> String {
        let numPhotos = media.filter { $0.type == .image }.count
        let numVideos = media.filter { $0.type == .video }.count
        if numPhotos == 1 && numVideos == 0 {
            return NSLocalizedString("notification.one.photo", value: "📷 photo", comment: "New post notification text when post is one photo without caption.")
        }
        if numVideos == 1 && numPhotos == 0 {
             return NSLocalizedString("notification.one.video", value: "📹 video", comment: "New post notification text when post is one video without caption.")
        }
        var strings: [String] = []
        if numPhotos > 0 {
            let format = NSLocalizedString("notification.n.photos", comment: "New post notification text when post is multiple photos without caption.")
            strings.append(String.localizedStringWithFormat(format, numPhotos))
        }
        if numVideos > 0 {
            let format = NSLocalizedString("notification.n.videos", comment: "New post notification text when post is multiple videos without caption.")
            strings.append(String.localizedStringWithFormat(format, numVideos))
        }
        return ListFormatter.localizedString(byJoining: strings)
    }

    func populate(withDataFrom protoContainer: Clients_Container, notificationMetadata: NotificationMetadata, mentionNameProvider: (UserID) -> String) {
        if protoContainer.hasPost {
            subtitle = NSLocalizedString("notification.new.post", value: "New Post", comment: "Title for the new feed post notification.")
            body = protoContainer.post.mentionText.expandedText(nameProvider: mentionNameProvider).string
            if !protoContainer.post.media.isEmpty {
                // Display how many photos and videos post contains if there's no caption.
                if body.isEmpty {
                    body = Self.notificationBody(forMedia: protoContainer.post.media)
                } else {
                    let mediaIcon = Self.mediaIcon(protoContainer.post.media.first!)
                    body = "\(mediaIcon) \(body)"
                }
            }
        } else if protoContainer.hasComment {
            let commentText = protoContainer.comment.mentionText.expandedText(nameProvider: mentionNameProvider).string
            body = String(format: NSLocalizedString("notification.commented.with.text", value: "Commented: %@", comment: "Push notification for a new comment. Parameter is the text of the comment"), commentText)
        } else if protoContainer.hasChatMessage {
            let protoMessage = protoContainer.chatMessage

            body = protoContainer.chatMessage.mentionText.expandedText(nameProvider: mentionNameProvider).string
            if !protoMessage.media.isEmpty {
                // Display how many photos and videos message contains if there's no caption.
                if body.isEmpty {
                    body = Self.notificationBody(forMedia: protoMessage.media)
                } else {
                    let mediaIcon = Self.mediaIcon(protoMessage.media.first!)
                    body = "\(mediaIcon) \(body)"
                }
            }
        }
    }

    func populate(withMsg msg: Server_Msg, notificationMetadata: NotificationMetadata, contactStore: ContactStore) {
        // Currently, this function only supports contact notifications.
        // Extend this to support other notification types as well.
        DDLogInfo("populate/msg populating content from msg \(msg)")

        switch msg.payload {
        case .contactList(let contactList):
            guard let contact = contactList.contacts.first else {
                DDLogError("populate/contactList Invalid contact.")
                return
            }
            if contact.uid <= 0 {
                DDLogError("populate/contactList Invalid contactUid.")
                return
            }
            let contactUid = String(contact.uid)
            // Look up contact using phone number as the user ID probably hasn't synced yet
            let contactName = contactStore.fullNameIfAvailable(forNormalizedPhone: contact.normalized) ?? nil
            DDLogInfo("populate/msg contact notification, type:\(contactList.type), uid:\(String(describing: contactUid)), name:\(String(describing: contactName))")
            title = ""
            guard let name = contactName else {
                body = Localizations.contactNotificationUnknownContent
                return
            }
            if contactList.type == .inviterNotice {
                body = String(format: Localizations.contactNotificationInviteContent, name)
            } else if contactList.type == .friendNotice {
                body = String(format: Localizations.contactNotificationFriendContent, name)
            } else if contactList.type == .contactNotice {
                body = String(format: Localizations.contactNotificationContent, name)
            }
            return
        default:
            DDLogInfo("populate/msg invalid payload:\(String(describing: msg.payload))")
            return
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
                guard let metadata = NotificationMetadata(notificationRequest: notification.request) else { continue }
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
}
