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

