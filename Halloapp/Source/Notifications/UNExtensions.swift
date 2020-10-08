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
        var strings = [String]()
        if numPhotos > 1 {
            strings.append("📷 \(numPhotos) photos")
        } else if numPhotos > 0 {
            if numVideos > 0 {
                strings.append("📷 1 photo")
            } else {
                strings.append("📷 photo")
            }
        }
        if numVideos > 1 {
            strings.append("📹 \(numVideos) videos")
        } else if numVideos > 0 {
            if numPhotos > 0 {
                strings.append("📹 1 video")
            } else {
                strings.append("📹 video")
            }
        }
        return strings.joined(separator: ", ")
    }

    func populate(withDataFrom protoContainer: Clients_Container, notificationMetadata: NotificationMetadata, mentionNameProvider: (UserID) -> String) {
        if protoContainer.hasPost {
            subtitle = "New Post"
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
            body = "Commented: \(commentText)"
        } else if protoContainer.hasChatMessage {
            let protoMessage = protoContainer.chatMessage

            body = protoMessage.text
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

