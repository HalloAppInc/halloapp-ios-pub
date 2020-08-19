//
//  NotificationUtility.swift
//  Core
//
//  Created by Alan Luo on 6/9/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjack
import UIKit

fileprivate extension UNNotificationRequest {
    func contentId(forContentType requestedContentType: NotificationUtility.ContentType) -> String? {
        if let (contentId, contentType) = NotificationUtility.Metadata.parseIds(from: self), contentType == requestedContentType {
            return contentId
        }
        return nil
    }
}

public class NotificationUtility {
    public enum ContentType: String {
        case chat = "chat"
        case comment = "comment"
        case feedpost = "feedpost"
    }
    
    public class Metadata {
        public static let userInfoKey = "metadata"
        public static let userDefaultsKey = "tap-notification-metadata"
        
        private struct Keys {
            static let contentId = "content-id"
            static let contentType = "content-type"
            static let data = "data"
            static let fromId = "from-id"
        }
        
        /*
         The meaning of contentId depends on contentType.
         For chat, contentId refers to ChatMessage.id.
         For feedpost, contentId refers to FeedPost.id
         For comment, contentId refers to FeedPostComment.id.
         */
        public let contentId: String
        public let contentType: ContentType
        public let data: Data?
        public let fromId: UserID
        
        public var rawData: [String:String] {
            return [
                Keys.contentId: contentId,
                Keys.contentType: contentType.rawValue,
                Keys.data: data?.base64EncodedString() ?? "",
                Keys.fromId: fromId
            ]
        }

        public var protoContainer: Proto_Container? {
            get {
                guard let protobufData = data else { return nil }
                do {
                    return try Proto_Container(serializedData: protobufData)
                }
                catch {
                    DDLogError("NotificationMetadata/protobuf/error Invalid protobuf. \(error)")
                }
                return nil
            }
        }

        /**
         Lightweight parsing of metadata attached to a notification.

         - returns: Identifier and type of the content that given notification is for.
         */
        fileprivate static func parseIds(from request: UNNotificationRequest) -> (String, ContentType)? {
            guard let metadata = request.content.userInfo[Metadata.userInfoKey] as? [String:String] else { return nil }
            if let contentId = metadata[Keys.contentId], let contentType = ContentType(rawValue: metadata[Keys.contentType] ?? "") {
                return (contentId, contentType)
            }
            return nil
        }
        
        private init?(fromRawMetadata rawMetadata: Any) {
            guard let metadata = rawMetadata as? [String: String] else {
                DDLogError("NotificationMetadata/init/error Can't convert metadata to [String: String]. Metadata: [\(rawMetadata)]")
                return nil
            }
            
            if let contentId = metadata[Keys.contentId] {
                self.contentId = contentId
            } else {
                DDLogError("NotificationMetadata/init/error Missing ContentId")
                return nil
            }
            
            guard let contentType = ContentType(rawValue: metadata[Keys.contentType] ?? "") else {
                DDLogError("NotificationMetadata/init/error Unsupported ContentType \(String(describing: metadata[Keys.contentType]))")
                return nil
            }
            
            self.contentType = contentType
            
            if let fromId = metadata[Keys.fromId] {
                self.fromId = fromId
            } else {
                DDLogError("NotificationMetadata/init/error Missing fromId")
                return nil
            }
            
            if let base64Data = metadata[Keys.data] {
                self.data = Data(base64Encoded: base64Data)
            } else {
                DDLogError("NotificationMetadata/init/error Missing Data")
                return nil
            }
        }
        
        public init(contentId: String, contentType: ContentType, data: Data?, fromId: UserID) {
            self.contentId = contentId
            self.contentType = contentType
            self.data = data
            self.fromId = fromId
        }
        
        public convenience init?(fromRequest request: UNNotificationRequest) {
            DDLogDebug("NotificationMetadata/init request=\(request)")
            guard let metadata = request.content.userInfo[Metadata.userInfoKey] else { return nil }
            self.init(fromRawMetadata: metadata)
        }
        
        public convenience init?(fromResponse response: UNNotificationResponse) {
            DDLogDebug("NotificationMetadata/init response=\(response)")
            guard let metadata = response.notification.request.content.userInfo[Metadata.userInfoKey] else { return nil }
            self.init(fromRawMetadata: metadata)
        }
        
        public static func fromUserDefaults() -> Metadata? {
            guard let metadata = UserDefaults.standard.object(forKey: Metadata.userDefaultsKey) else { return nil }
            return Metadata(fromRawMetadata: metadata)
        }
        
        public func saveToUserDefaults() {
            DDLogDebug("NotificationMetadata/saveToUserDefaults")
            UserDefaults.standard.set(self.rawData, forKey: Metadata.userDefaultsKey)
        }
        
        public func removeFromUserDefaults() {
            DDLogDebug("NotificationMetadata/removeFromUserDefaults")
            UserDefaults.standard.removeObject(forKey: Metadata.userDefaultsKey)
        }
    }

    static func notificationTextIcon(forMedia protoMedia: Proto_Media) -> String {
        switch protoMedia.type {
            case .image:
                return "📷"
            case .video:
                return "📹"
            default:
                return ""
        }
    }

    static func notificationText(forMedia media: [Proto_Media]) -> String {
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

    public static func populate(
        notification: UNMutableNotificationContent,
        withDataFrom protoContainer: Proto_Container,
        mentionNameProvider: (UserID) -> String)
    {
        if protoContainer.hasPost {
            notification.subtitle = "New Post"
            notification.body = protoContainer.post.mentionText.expandedText(nameProvider: mentionNameProvider).string
            if !protoContainer.post.media.isEmpty {
                // Display how many photos and videos post contains if there's no caption.
                if notification.body.isEmpty {
                    notification.body = Self.notificationText(forMedia: protoContainer.post.media)
                } else {
                    let mediaIcon = Self.notificationTextIcon(forMedia: protoContainer.post.media.first!)
                    notification.body = "\(mediaIcon) \(notification.body)"
                }
            }
        } else if protoContainer.hasComment {
            let commentText = protoContainer.comment.mentionText.expandedText(nameProvider: mentionNameProvider).string
            notification.body = "Commented: \(commentText)"
        } else if protoContainer.hasChatMessage {
            notification.body = protoContainer.chatMessage.text
            if !protoContainer.chatMessage.media.isEmpty {
                // Display how many photos and videos message contains if there's no caption.
                if notification.body.isEmpty {
                    notification.body = Self.notificationText(forMedia: protoContainer.chatMessage.media)
                } else {
                    let mediaIcon = Self.notificationTextIcon(forMedia: protoContainer.chatMessage.media.first!)
                    notification.body = "\(mediaIcon) \(notification.body)"
                }
            }
        }
    }

    /**
     - returns: IDs of posts / comments / messages for which there were notifications presented.
     */
    public static func getContentIdsForDeliveredNotifications(ofType contentType: ContentType, completion: @escaping ([String]) -> ()) {
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            completion(notifications.compactMap({ $0.request.contentId(forContentType: contentType) }))
        }
    }
    
    public static func removeDelivered(forType type: ContentType, withFromId fromId: String? = nil, withContentId contentId: String? = nil) {
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
        
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            guard !notifications.isEmpty else { return }

            var identifiersToRemove = [String]()
            for notification in notifications {
                guard let metadata = Metadata(fromRequest: notification.request), metadata.contentType == type else { continue }

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
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiersToRemove)
            }
        }
    }

}

