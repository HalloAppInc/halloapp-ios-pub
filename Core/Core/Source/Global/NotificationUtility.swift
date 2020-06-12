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
        private struct Keys {
            static let contentId = "content-id"
            static let contentType = "content-type"
            static let data = "data"
            static let fromId = "from-id"
            static let metadata = "metadata"
            public static let userDefaults = "tap-notification-metadata"
        }
        
        /*
         The meaning of contentId depends on contentType.
         For chat, contentId refers to ChatMessage.id.
         For feedpost, contentId refers to FeedPost.id
         For comment, contentId refers to FeedPostComment.id.
         */
        public let contentId: String
        public let contentType: ContentType
        public let data: String
        public let fromId: UserID
        private let rawData: [String: String]
        
        private init?(fromDict metadata: Any?) {
            DDLogInfo("NotificationMetadata/init with metadata=\(String(describing: metadata))")
            
            guard let metadata = metadata as? [String: String] else {
                DDLogInfo("NotificationMetadata/error Can't convert metadata to [String: String]")
                return nil
            }
            
            if let contentId = metadata[Keys.contentId] {
                self.contentId = contentId
            } else {
                DDLogInfo("NotificationMetadata/error Missing ContentId")
                return nil
            }
            
            guard let contentType = ContentType(rawValue: metadata[Keys.contentType] ?? "") else {
                DDLogInfo("NotificationMetadata/error Unsupported ContentType \(String(describing: metadata[Keys.contentType]))")
                return nil
            }
            
            self.contentType = contentType
            
            if let fromId = metadata[Keys.fromId] {
                self.fromId = fromId
            } else {
                DDLogInfo("NotificationMetadata/error Missing FromId")
                return nil
            }
            
            if let data = metadata[Keys.data] {
                self.data = data
            } else {
                DDLogInfo("NotificationMetadata/error Missing Data")
                return nil
            }
            
            self.rawData = metadata
        }
        
        public convenience init?(fromRequest request: UNNotificationRequest) {
            DDLogInfo("NotificationMetadata/init with request=\(request)")
            
            self.init(fromDict: request.content.userInfo[Keys.metadata])
        }
        
        public convenience init?(fromResponse response: UNNotificationResponse) {
            DDLogInfo("NotificationMetadata/init with response=\(response)")
            
            self.init(fromDict: response.notification.request.content.userInfo[Keys.metadata])
        }
        
        public static func fromUserDefaults() -> Metadata? {
            DDLogInfo("NotificationMetadata/fromUserDefaults start")
            
            if let rawData = UserDefaults.standard.object(forKey: Keys.userDefaults) as? [String: String] {
                return Metadata(fromDict: rawData)
            }
            
            DDLogInfo("NotificationMetadata/fromUserDefaults error: Can't load from UserDefaults")
            
            return nil
        }
        
        public func saveToUserDefaults() {
            DDLogInfo("NotificationMetadata/saveToUserDefaults saved")
            
            UserDefaults.standard.set(self.rawData, forKey: Keys.userDefaults)
        }
        
        public func removeFromUserDefaults() {
            DDLogInfo("NotificationMetadata/removeFromUserDefaults removed")
            
            UserDefaults.standard.removeObject(forKey: Keys.userDefaults)
        }
    }
    
    public static func removeDelivered(forType type: ContentType, withFromId fromId: String? = nil, withContentId contentId: String? = nil) {
        DDLogInfo("Notification/removeDeliveredNotifications will remove for type=\(type) and fromId=\(String(describing: fromId)) and contentId=\(String(describing: contentId))")
        
        guard fromId != nil || contentId != nil else { return }
        
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications: [UNNotification]) in
            DDLogInfo("Notification/removeDeliveredNotifications found \(notifications.count) notifications")
            
            var identifiersToRemove = [String]()
            
            for notification in notifications {
                if let metadata = Metadata(fromRequest: notification.request) {
                    guard metadata.contentType == type else { continue }
                    
                    switch type {
                    case .chat:
                        guard metadata.fromId == fromId! else { continue }
                        
                        DDLogInfo("Notification/removeDeliveredNotifications \(notification.request.identifier) will be removed")
                        
                        identifiersToRemove.append(notification.request.identifier)
                        
                    default:
                        DDLogInfo("Notification/removeDeliveredNotifications unsuportted type \(type.rawValue)")
                    }
                }
            }
            
            if identifiersToRemove.count > 0 {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiersToRemove)
            }
        }
    }

}

