//
//  NotificationMetadata.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 9/3/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import UserNotifications

enum NotificationContentType: String, RawRepresentable {
    case feedPost = "feedpost"
    case groupFeedPost = "group_post"

    case feedComment = "comment"
    case groupFeedComment = "group_comment"

    case chatMessage = "chat"
    case groupChatMessage = "group_chat"
}

class NotificationMetadata {

    static let userInfoKey = "metadata"
    static let userDefaultsKey = "tap-notification-metadata"

    private struct Keys {
        static let contentId = "content-id"
        static let contentType = "content-type"
        static let fromId = "from-id"
        static let threadId = "thread-id"
        static let threadName = "thread-name"
        static let senderName = "sender-name"
        static let timestamp = "timestamp"
        static let data = "data"
    }

    /*
     The meaning of contentId depends on contentType.
     For chat, contentId refers to ChatMessage.id.
     For feedpost, contentId refers to FeedPost.id
     For comment, contentId refers to FeedPostComment.id.
     */
    let contentId: String
    let contentType: NotificationContentType
    let fromId: UserID
    let timestamp: Date?
    let data: Data?

    private var threadId: String? = nil
    private var threadName: String? = nil
    private var senderName: String? = nil

    var rawData: [String: String] {
        get {
            var result: [String: String] = [
                Keys.contentId: contentId,
                Keys.contentType: contentType.rawValue,
                Keys.fromId: fromId
            ]
            if let threadId = threadId {
                result[Keys.threadId] = threadId
            }
            if let threadName = threadName {
                result[Keys.threadName] = threadName
            }
            if let senderName = senderName {
                result[Keys.senderName] = senderName
            }
            if let data = data {
                result[Keys.data] = data.base64EncodedString()
            }
            if let timestamp = timestamp {
                result[Keys.timestamp] = String(timestamp.timeIntervalSince1970)
            }
            return result
        }
    }

    var protoContainer: Clients_Container? {
        guard let protobufData = data else { return nil }
        do {
            return try Clients_Container(serializedData: protobufData)
        }
        catch {
            DDLogError("NotificationMetadata/protobuf/error Invalid protobuf. \(error)")
        }
        return nil
    }

    /**
     Lightweight parsing of metadata attached to a notification.

     - returns: Identifier and type of the content that given notification is for.
     */
    static func parseIds(from request: UNNotificationRequest) -> (String, NotificationContentType)? {
        guard let metadata = request.content.userInfo[Self.userInfoKey] as? [String: String] else { return nil }
        if let contentId = metadata[Keys.contentId], let contentType = NotificationContentType(rawValue: metadata[Keys.contentType] ?? "") {
            return (contentId, contentType)
        }
        return nil
    }

    private init?(rawMetadata: Any) {
        guard let metadata = rawMetadata as? [String: String] else {
            DDLogError("NotificationMetadata/init/error Can't convert metadata to [String: String]. Metadata: [\(rawMetadata)]")
            return nil
        }

        guard let contentId = metadata[Keys.contentId] else {
            DDLogError("NotificationMetadata/init/error Missing ContentId")
            return nil
        }
        self.contentId = contentId

        guard let contentType = NotificationContentType(rawValue: metadata[Keys.contentType] ?? "") else {
            DDLogError("NotificationMetadata/init/error Unsupported ContentType \(String(describing: metadata[Keys.contentType]))")
            return nil
        }
        self.contentType = contentType

        guard let fromId = metadata[Keys.fromId] else {
            DDLogError("NotificationMetadata/init/error Missing fromId")
            return nil
        }
        self.fromId = fromId

        guard let base64Data = metadata[Keys.data] else {
            DDLogError("NotificationMetadata/init/error Missing Data")
            return nil
        }
        self.data = Data(base64Encoded: base64Data)

        if let timestamp = TimeInterval(metadata[Keys.timestamp] ?? "") {
            self.timestamp = Date(timeIntervalSince1970: timestamp)
        } else {
            self.timestamp = nil
        }

        self.threadId = metadata[Keys.threadId]
        self.threadName = metadata[Keys.threadName]
        self.senderName = metadata[Keys.senderName]
    }

    init(contentId: String, contentType: NotificationContentType, fromId: UserID, data: Data?, timestamp: Date?) {
        self.contentId = contentId
        self.contentType = contentType
        self.fromId = fromId
        self.data = data
        self.timestamp = timestamp
    }

    convenience init?(notificationRequest: UNNotificationRequest) {
        guard let metadata = notificationRequest.content.userInfo[Self.userInfoKey] else { return nil }
        self.init(rawMetadata: metadata)
    }

    convenience init?(notificationResponse: UNNotificationResponse) {
        guard let metadata = notificationResponse.notification.request.content.userInfo[Self.userInfoKey] else { return nil }
        self.init(rawMetadata: metadata)
    }

    static func fromUserDefaults() -> NotificationMetadata? {
        guard let metadata = UserDefaults.standard.object(forKey: Self.userDefaultsKey) else { return nil }
        return NotificationMetadata(rawMetadata: metadata)
    }

    func saveToUserDefaults() {
        DDLogDebug("NotificationMetadata/saveToUserDefaults")
        UserDefaults.standard.set(self.rawData, forKey: Self.userDefaultsKey)
    }

    func removeFromUserDefaults() {
        DDLogDebug("NotificationMetadata/removeFromUserDefaults")
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
    }
}

extension NotificationMetadata {

    var isFeedNotification: Bool {
        switch contentType {
        case .feedPost, .groupFeedPost, .feedComment, .groupFeedComment:
            return true
        case .chatMessage, .groupChatMessage:
            return false
        }
    }

    var isChatNotification: Bool {
        return contentType == .chatMessage || contentType == .groupChatMessage
    }
    
    var isGroupChatNotification: Bool {
        return contentType == .groupChatMessage
    }
    
    var isGroupNotification: Bool {
        switch contentType {
        case .groupFeedPost, .groupFeedComment, .groupChatMessage:
            return true
        case .feedPost, .feedComment, .chatMessage:
            return false
        }
    }

    var feedPostId: FeedPostID? {
        if contentType == .feedPost || contentType == .groupFeedPost {
            return contentId
        }
        return nil
    }

    var feedPostCommentId: FeedPostCommentID? {
        if contentType == .feedComment || contentType == .groupFeedComment {
            return contentId
        }
        return nil
    }

    var messageId: String? {
        if isChatNotification {
            return contentId
        }
        return nil
    }

    var groupName: String? {
        get {
            return isGroupNotification ? threadName : nil
        }
        set {
            if isGroupNotification {
                threadName = newValue
            }
        }
    }

    var groupId: GroupID? {
        get {
            return isGroupNotification ? threadId : nil
        }
        set {
            if isGroupNotification {
                threadId = newValue
            }
        }
    }

    var pushName: String? {
        senderName
    }
}

