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

    func contentId(forContentType requestedContentType: NotificationContentType) -> String? {
        if let (contentId, contentType) = NotificationMetadata.parseIds(from: self), contentType == requestedContentType {
            return contentId
        }
        return nil
    }
}

extension UNMutableNotificationContent {

    private static func mediaIcon(_ protoMedia: Proto_Media) -> String {
        switch protoMedia.type {
            case .image:
                return "📷"
            case .video:
                return "📹"
            default:
                return ""
        }
    }

    private static func notificationBody(forMedia media: [Proto_Media]) -> String {
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

    func populate(withDataFrom protoContainer: Proto_Container, mentionNameProvider: (UserID) -> String) {
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
            body = protoContainer.chatMessage.text
            if !protoContainer.chatMessage.media.isEmpty {
                // Display how many photos and videos message contains if there's no caption.
                if body.isEmpty {
                    body = Self.notificationBody(forMedia: protoContainer.chatMessage.media)
                } else {
                    let mediaIcon = Self.mediaIcon(protoContainer.chatMessage.media.first!)
                    body = "\(mediaIcon) \(body)"
                }
            }
        }
    }

}

public extension UNUserNotificationCenter {
    /**
     - returns: IDs of posts / comments / messages for which there were notifications presented.
     */
    func getContentIdsForDeliveredNotifications(ofType contentType: NotificationContentType, completion: @escaping ([String]) -> ()) {
        getDeliveredNotifications { (notifications) in
            completion(notifications.compactMap({ $0.request.contentId(forContentType: contentType) }))
        }
    }

    func removeDeliveredNotifications(forType type: NotificationContentType, fromId: String? = nil, contentId: String? = nil) {
        if type == .chat {
            guard fromId != nil else {
                DDLogError("Notification/removeDelivered fromId should not be nil")
                return
            }

            DDLogDebug("Notification/removeDelivered/\(type) fromId=\(fromId!)")
        } else { // .feedpost, .comment
            guard contentId != nil else {
                DDLogError("Notification/removeDelivered contentId should not be nil")
                return
            }

            DDLogDebug("Notification/removeDelivered/\(type) contentId=\(contentId!)")
        }

        getDeliveredNotifications { (notifications) in
            guard !notifications.isEmpty else { return }

            var identifiersToRemove = [String]()
            for notification in notifications {
                guard let metadata = NotificationMetadata(notificationRequest: notification.request), metadata.contentType == type else { continue }

                if type == .chat {
                    guard metadata.fromId == fromId! else { continue }
                } else { // .feedpost, .comment
                    guard metadata.contentId == contentId! else { continue }
                }

                DDLogDebug("Notification/removeDelivered \(notification.request.identifier) will be removed")

                identifiersToRemove.append(notification.request.identifier)
            }

            if !identifiersToRemove.isEmpty {
                DDLogInfo("Notification/removeDelivered/\(identifiersToRemove.count)")
                self.removeDeliveredNotifications(withIdentifiers: identifiersToRemove)
            }
        }
    }
}

