//
//  NotificationUtility.swift
//  Core
//
//  Created by Alan Luo on 6/9/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjack
import UIKit

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

