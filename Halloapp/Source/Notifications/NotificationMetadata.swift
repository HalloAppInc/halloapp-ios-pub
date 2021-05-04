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
import SwiftNoise

enum NotificationContentType: String, RawRepresentable, Codable {
    case feedPost = "feedpost"
    case groupFeedPost = "group_post"

    case feedComment = "comment"
    case groupFeedComment = "group_comment"

    case chatMessage = "chat"
    case groupChatMessage = "group_chat"
    
    case groupAdd = "group_add"

    case newInvitee = "inviter_notice"
    case newFriend = "friend_notice"
    case newContact = "contact_notice"

    case feedPostRetract = "feedpost_retract"
    case groupFeedPostRetract = "group_post_retract"
    case feedCommentRetract = "comment_retract"
    case groupFeedCommentRetract = "group_comment_retract"
    case chatMessageRetract = "chat_retract"
    case groupChatMessageRetract = "group_chat_retract"
}

class NotificationMetadata: Codable {

    static let userInfoKeyMetadata = "metadata"
    static let userDefaultsKeyRawData = "rawdata"
    static let messagePacketData = "message"
    static let encryptedData = "content"

    /*
     The meaning of contentId depends on contentType.
     For chat, contentId refers to ChatMessage.id.
     For feedpost, contentId refers to FeedPost.id
     For comment, contentId refers to FeedPostComment.id.
     */
    var contentId: String
    var contentType: NotificationContentType
    var fromId: UserID
    var timestamp: Date?
    var data: Data?
    var messageId: String?
    var pushName: String?
    var serverMsgPb: Data?

    // Chat specific fields
    var serverChatStanzaPb: Data? = nil
    var senderClientVersion: String? = nil


    // Fields to set in the actual UNMutableNotificationContent
    var title: String = ""
    var subtitle: String = ""
    var body: String = ""

    // Notification specific fields
    var groupId: String? = nil
    var groupName: String? = nil
    var normalizedPhone: String? = nil

    var protoContainer: Clients_Container? {
        guard let protobufData = data else { return nil }
        do {
            return try Clients_Container(serializedData: protobufData)
        }
        catch {
            DDLogError("NotificationMetadata/protoContainer/protobuf/error Invalid protobuf. \(error)")
        }
        return nil
    }

    var rawData: Data? {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(self) {
            return data
        } else {
            DDLogError("NotificationMetadata/init/error invalid object to encode: [\(self)]")
            return nil
        }
    }

    static func load(from rawData: Data?) -> NotificationMetadata? {
        guard let rawData = rawData else { return nil }
        let decoder = JSONDecoder()
        guard let metadata = try? decoder.decode(NotificationMetadata.self, from: rawData) else {
            DDLogError("NotificationMetadata/init/error invalid object to decode: [\(rawData)]")
            return nil
        }
        return metadata
    }

    static func load(from notificationRequest: UNNotificationRequest) -> NotificationMetadata? {
        initialize(userInfo: notificationRequest.content.userInfo)
    }

    static func load(from notificationRequest: UNNotificationRequest, userData: UserData) -> NotificationMetadata? {
        initialize(userInfo: notificationRequest.content.userInfo, userData: userData)
    }

    static func load(from notificationResponse: UNNotificationResponse) -> NotificationMetadata? {
        initialize(userInfo: notificationResponse.notification.request.content.userInfo)
    }

    private static func initialize(userInfo: [AnyHashable: Any]) -> NotificationMetadata? {
        if let rawData = userInfo[Self.userDefaultsKeyRawData] as? Data {
            return NotificationMetadata.load(from: rawData)
        } else {
            guard let metadata = userInfo[Self.userInfoKeyMetadata] as? [String: String],
                  let data = metadata[Self.messagePacketData],
                  let packetData = Data(base64Encoded: data) else {
                return nil
            }
            do {
                let msg = try Server_Msg(serializedData: packetData)
                logPushDecryptionError(with: msg)
                return NotificationMetadata(msg: msg)
            } catch {
                DDLogError("NotificationMetadata/init/error invalid protobuf data: [\(packetData)]")
                return nil
            }
        }
    }

    public static func initialize(userInfo: [AnyHashable: Any], userData: UserData) -> NotificationMetadata? {
        guard let noiseKeys = userData.noiseKeys,
              let metadata = userInfo[Self.userInfoKeyMetadata] as? [String: String],
              let encryptedContentB64 = metadata[Self.encryptedData],
              let encryptedMessage = Data(base64Encoded: encryptedContentB64) else {
            DDLogError("NotificationMetadata/noise/error unable to find encrypted content")
            return initialize(userInfo: userInfo)
        }

        do {
            if let pushContent = NoiseStream.decryptPushContent(noiseKeys: noiseKeys, encryptedMessage: encryptedMessage) {
                let msg = try Server_Msg(serializedData: pushContent.content)
                return NotificationMetadata(msg: msg)
            } else {
                DDLogError("NotificationMetadata/noise/error decrypting push content")
                return initialize(userInfo: userInfo)
            }
        } catch {
            DDLogError("NotificationMetadata/noise/error \(error)")
            return nil
        }
    }

    private static func logPushDecryptionError(with msg: Server_Msg) {
        let reportUserInfo = [
            "userId": UserID(msg.toUid),
            "msgId": msg.id,
            "reason": "PushDecryptionError"
        ]
        let customError = NSError.init(domain: "PushDecryptionErrorTest", code: 1003, userInfo: reportUserInfo)
        AppContext.shared.errorLogger?.logError(customError)
    }

    init(contentId: String, contentType: NotificationContentType, fromId: UserID, timestamp: Date?, data: Data?, messageId: String?, pushName: String? = nil) {
        self.contentId = contentId
        self.contentType = contentType
        self.fromId = fromId
        self.timestamp = timestamp
        self.data = data
        self.messageId = messageId
        self.pushName = pushName
    }

    init?(msg: Server_Msg?) {
        guard let msg = msg else {
            DDLogError("NotificationMetadata/init/msg is nil")
            return nil
        }
        do {
            serverMsgPb = try msg.serializedData()
        } catch {
            DDLogError("NotificationMetadata/init/msg - unable to serialize it.")
            return nil
        }
        messageId = msg.id
        switch msg.payload {

        case .contactList(let contactList):
            contentId = msg.id
            if contactList.type == .inviterNotice {
                contentType = .newInvitee
            } else if contactList.type == .friendNotice {
                contentType = .newFriend
            } else if contactList.type == .contactNotice {
                contentType = .newContact
            } else {
                DDLogError("NotificationMetadata/init/contactList Invalid contactListType, message: \(msg)")
                return nil
            }
            guard let contact = contactList.contacts.first else {
                DDLogError("NotificationMetadata/init/contactList Invalid contact, message: \(msg)")
                return nil
            }
            if contact.uid <= 0 {
                DDLogError("NotificationMetadata/init/contactList Invalid contactUid, message: \(msg)")
                return nil
            }
            let contactUid = String(contact.uid)
            fromId = UserID(contactUid)
            timestamp = nil
            data = nil
            pushName = contact.name
            normalizedPhone = contact.normalized

        case .feedItem(let feedItem):
            switch feedItem.item {
            case .post(let post):
                contentId = post.id
                switch feedItem.action {
                case .retract:
                    contentType = .feedPostRetract
                case .publish:
                    contentType = .feedPost
                default:
                    return nil
                }
                fromId = UserID(post.publisherUid)
                timestamp = Date(timeIntervalSince1970: TimeInterval(post.timestamp))
                data = post.payload
                pushName = post.publisherName
            case .comment(let comment):
                contentId = comment.id
                switch feedItem.action {
                case .retract:
                    contentType = .feedCommentRetract
                case .publish:
                    contentType = .feedComment
                default:
                    return nil
                }
                fromId = UserID(comment.publisherUid)
                timestamp = Date(timeIntervalSince1970: TimeInterval(comment.timestamp))
                data = comment.payload
                pushName = comment.publisherName
            default:
                DDLogError("NotificationMetadata/init/feedItem Invalid item, message: \(msg)")
                return nil
            }
        case .groupFeedItem(let groupFeedItem):

            switch groupFeedItem.item {
            case .post(let post):
                contentId = post.id
                switch groupFeedItem.action {
                case .retract:
                    contentType = .groupFeedPostRetract
                case .publish:
                    contentType = .groupFeedPost
                default:
                    return nil
                }
                fromId = UserID(post.publisherUid)
                timestamp = Date(timeIntervalSince1970: TimeInterval(post.timestamp))
                data = post.payload
                pushName = post.publisherName
            case .comment(let comment):
                contentId = comment.id
                switch groupFeedItem.action {
                case .retract:
                    contentType = .groupFeedCommentRetract
                case .publish:
                    contentType = .groupFeedComment
                default:
                    return nil
                }
                fromId = UserID(comment.publisherUid)
                timestamp = Date(timeIntervalSince1970: TimeInterval(comment.timestamp))
                data = comment.payload
                pushName = comment.publisherName
            default:
                DDLogError("NotificationMetadata/init/groupFeedItem Invalid item, message: \(msg)")
                return nil
            }
            groupId = groupFeedItem.gid
            groupName = groupFeedItem.name
        case .chatStanza(let chatMsg):
            contentId = msg.id
            contentType = .chatMessage
            fromId = UserID(msg.fromUid)
            timestamp = Date(timeIntervalSince1970: TimeInterval(chatMsg.timestamp))
            data = chatMsg.payload
            pushName = chatMsg.senderName
            do {
                serverChatStanzaPb = try chatMsg.serializedData()
            } catch {
                DDLogError("NotificationMetadata/init/chatStanza could not serialize chatMsg: \(msg)")
                return nil
            }
            senderClientVersion = chatMsg.senderClientVersion
        case .chatRetract(let chatRetractStanza):
            contentId = chatRetractStanza.id
            contentType = .chatMessageRetract
            fromId = UserID(msg.fromUid)
            timestamp = nil
            data = nil
            pushName = nil
        case .groupStanza(let groupStanza):
            if groupStanza.action == .modifyMembers {
                contentId = msg.id
                contentType = .groupAdd
                fromId = UserID(groupStanza.senderUid)
                timestamp = nil
                data = nil
                pushName = nil
                groupId = groupStanza.gid
                groupName = groupStanza.name
            } else {
                DDLogError("NotificationMetadata/init/groupStanza Invalid action, message: \(msg)")
                return nil
            }
        default:
            return nil
        }
    }

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

    func getMentionNames(contactStore: ContactStore) -> ((UserID) -> String) {
        let mentionNameProvider: (UserID) -> String = { [self] userID in
            // TODO: Pass in the push names included with the mentions
            let pushNameForMention = (userID == fromId) ? pushName : nil
            return contactStore.mentionNameIfAvailable(for: userID, pushName: pushNameForMention) ?? Localizations.unknownContact
        }
        return mentionNameProvider
    }

    func populateContent(contactStore: ContactStore) -> Bool {

        let mentionNameProvider = getMentionNames(contactStore: contactStore)

        // Title:
        // "Contact" for feed posts / comments and 1-1 chat messages.
        // "Contact @ Group" for group feed posts / comments and group chat messages.
        let contactName = contactStore.fullNameIfAvailable(for: fromId) ?? pushName
        title = [contactName, groupName].compactMap({ $0 }).joined(separator: " @ ")

        switch contentType {

        // Post on user feed or group feed
        case .feedPost, .groupFeedPost:
            guard let protoContainer = protoContainer else {
                return false
            }
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

        // Comment on user feed or group feed
        case .feedComment, .groupFeedComment:
            guard let protoContainer = protoContainer else {
                return false
            }
            let commentText = protoContainer.comment.mentionText.expandedText(nameProvider: mentionNameProvider).string
            body = String(format: NSLocalizedString("notification.commented.with.text", value: "Commented: %@", comment: "Push notification for a new comment. Parameter is the text of the comment"), commentText)

        // ChatMessage or GroupChatMessage
        case .chatMessage, .groupChatMessage:
            // Fallback text in case decryption fails.
            body = String(format: NSLocalizedString("notification.new.message", value: "New Message", comment: "Fallback text for new message notification."))

        // Contact notification for new friend or new invitee
        case .newFriend, .newInvitee, .newContact:
            // Look up contact using phone number as the user ID probably hasn't synced yet
            let contactName = contactStore.fullNameIfAvailable(forNormalizedPhone: normalizedPhone!) ?? nil
            title = ""
            guard let name = contactName else {
                body = Localizations.contactNotificationUnknownContent
                return true
            }
            if contentType == .newFriend {
                body = String(format: Localizations.contactNotificationFriendContent, name)
            } else if contentType == .newInvitee {
                body = String(format: Localizations.contactNotificationInviteContent, name)
            } else if contentType == .newContact {
                body = String(format: Localizations.contactNotificationContent, name)
            }

        case .groupAdd:
            body = Localizations.groupsAddNotificationBody

        default:
            break
        }
        return true
    }

    func populateChatBody(from chatMessage: Clients_ChatMessage, contactStore: ContactStore) {
        let mentionNameProvider = getMentionNames(contactStore: contactStore)
        body = chatMessage.mentionText.expandedText(nameProvider: mentionNameProvider).string
        if !chatMessage.media.isEmpty {
            // Display how many photos and videos message contains if there's no caption.
            if body.isEmpty {
                body = Self.notificationBody(forMedia: chatMessage.media)
            } else {
                let mediaIcon = Self.mediaIcon(chatMessage.media.first!)
                body = "\(mediaIcon) \(body)"
            }
        }
    }

    // Discuss with team - if we need this - there should be a better way to handle these cases.
    static func fromUserDefaults() -> NotificationMetadata? {
        guard let rawData = UserDefaults.standard.object(forKey: Self.userDefaultsKeyRawData) as? Data else { return nil }
        return NotificationMetadata.load(from: rawData)
    }

    func saveToUserDefaults() {
        DDLogDebug("NotificationMetadata/saveToUserDefaults")
        UserDefaults.standard.set(self.rawData, forKey: Self.userDefaultsKeyRawData)
    }

    func removeFromUserDefaults() {
        DDLogDebug("NotificationMetadata/removeFromUserDefaults")
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKeyRawData)
    }

}

extension NotificationMetadata {

    var isFeedNotification: Bool {
        switch contentType {
        case .feedPost, .groupFeedPost, .feedComment, .groupFeedComment, .feedPostRetract, .feedCommentRetract, .groupFeedPostRetract, .groupFeedCommentRetract:
            return true
        case .chatMessage, .groupChatMessage, .chatMessageRetract, .groupChatMessageRetract, .newFriend, .newInvitee, .newContact, .groupAdd:
            return false
        }
    }

    var isChatNotification: Bool {
        return contentType == .chatMessage || contentType == .groupChatMessage
    }
    
    var isGroupChatNotification: Bool {
        return contentType == .groupChatMessage
    }
    
    var isGroupAddNotification: Bool {
        return contentType == .groupAdd
    }
    
    var isContactNotification: Bool {
        switch contentType {
        case .newFriend, .newInvitee, .newContact:
            return true
        case .feedPost, .groupFeedPost, .feedComment, .groupFeedComment, .feedPostRetract, .feedCommentRetract, .groupFeedPostRetract, .groupFeedCommentRetract, .chatMessage, .groupChatMessage, .chatMessageRetract, .groupChatMessageRetract, .groupAdd:
            return false
        }
    }

    var isGroupNotification: Bool {
        switch contentType {
        case .groupFeedPost, .groupFeedComment, .groupChatMessage, .groupFeedPostRetract, .groupFeedCommentRetract, .groupChatMessageRetract, .groupAdd:
            return true
        case .feedPost, .feedComment, .feedPostRetract, .feedCommentRetract, .chatMessage, .chatMessageRetract, .newFriend, .newInvitee, .newContact:
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

    var isRetractNotification: Bool {
        switch contentType {
        case .chatMessageRetract, .groupChatMessageRetract, .feedCommentRetract, .groupFeedCommentRetract, .feedPostRetract, .groupFeedPostRetract:
            return true
        case .feedPost, .groupFeedPost, .feedComment, .groupFeedComment, .chatMessage, .groupChatMessage, .groupAdd, .newFriend, .newInvitee, .newContact:
            return false
        }
    }

}
