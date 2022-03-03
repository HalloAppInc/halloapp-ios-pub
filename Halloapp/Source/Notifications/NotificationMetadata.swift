//
//  NotificationMetadata.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 9/3/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import UserNotifications
import SwiftNoise


public enum NotificationMediaType: Int, Codable {
    case image = 0
    case video = 1
    case audio = 2
}

public extension NotificationMediaType {
    init?(clientsMediaType: Clients_MediaType) {
        switch clientsMediaType {
        case .image:
            self = .image
        case .video:
            self = .video
        case .audio:
            self = .audio
        case .unspecified, .UNRECOGNIZED:
            return nil
        }
    }

    init(chatMsgMediaType: ChatMessageMediaType) {
        switch chatMsgMediaType {
        case .image:
            self = .image
        case .video:
            self = .video
        case .audio:
            self = .audio
        }
    }

    init(feedMediaType: FeedMediaType) {
        switch feedMediaType {
        case .image:
            self = .image
        case .video:
            self = .video
        case .audio:
            self = .audio
        }
    }
}

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

    case chatRerequest = "chat_rerequest"

    case missedAudioCall = "missed_voice_call"
    case missedVideoCall = "missed_video_call"
}

class NotificationMetadata: Codable {

    static let userInfoKeyMetadata = "metadata"
    static let userDefaultsKeyRawData = "rawdata"
    static let messagePacketData = "message"
    static let encryptedData = "content"
    static let nseVoipData = "nse_content"
    static let contentTypeKey = "content_type"

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
    var messageId: String
    var pushName: String?
    var serverMsgPb: Data?
    var rerequestCount: Int32 = 0
    var messageTypeRawValue: Int = Server_Msg.TypeEnum.normal.rawValue

    // Chat specific fields
    var pushNumber: String?
    var serverChatStanzaPb: Data? = nil
    var senderClientVersion: String? = nil

    // GroupFeedItem specific fields
    var serverGroupFeedItemPb: Data? = nil


    // Fields to set in the actual UNMutableNotificationContent
    var title: String = ""
    var subtitle: String = ""
    var body: String = ""

    // Notification specific fields
    var postId: String? = nil
    var parentId: String? = nil
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
        // messageId could be nil for local pushes when app is alive - in those cases: this field is not that important.
        self.messageId = messageId ?? contentId
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
        rerequestCount = msg.rerequestCount
        messageTypeRawValue = msg.type.rawValue
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
            timestamp = Date()
            data = nil
            pushName = contact.name
            normalizedPhone = contact.normalized

        case .feedItem(let feedItem):
            switch feedItem.item {
            case .post(let post):
                contentId = post.id
                postId = post.id
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
                postId = comment.postID
                parentId = comment.parentCommentID.isEmpty ? nil : comment.parentCommentID
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
                postId = post.id
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
                data = post.payload.isEmpty ? nil : post.payload
                pushName = post.publisherName
            case .comment(let comment):
                contentId = comment.id
                postId = comment.postID
                parentId = comment.parentCommentID.isEmpty ? nil : comment.parentCommentID
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
                data = comment.payload.isEmpty ? nil : comment.payload
                pushName = comment.publisherName
            default:
                DDLogError("NotificationMetadata/init/groupFeedItem Invalid item, message: \(msg)")
                return nil
            }
            groupId = groupFeedItem.gid
            groupName = groupFeedItem.name
            do {
                serverGroupFeedItemPb = try groupFeedItem.serializedData()
            } catch {
                DDLogError("NotificationMetadata/init/groupFeedItem could not serialize payload: \(msg)")
                return nil
            }
        case .chatStanza(let chatMsg):
            contentId = msg.id
            contentType = .chatMessage
            fromId = UserID(msg.fromUid)
            timestamp = Date(timeIntervalSince1970: TimeInterval(chatMsg.timestamp))
            data = chatMsg.payload
            pushName = chatMsg.senderName
            pushNumber = chatMsg.senderPhone

            // Save pushNumber from the message received.
            if let phone = pushNumber, !phone.isEmpty {
                AppContext.shared.contactStore.addPushNumbers([ fromId : phone ])
            }

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
            timestamp = Date()
            data = nil
            pushName = nil
        case .groupStanza(let groupStanza):
            let addedToNewGroup = groupStanza.members.contains(where: { $0.action == .add && $0.uid == Int64(AppContext.shared.userData.userId) })
            if addedToNewGroup {
                contentId = msg.id
                contentType = .groupAdd
                fromId = UserID(groupStanza.senderUid)
                timestamp = Date()
                data = nil
                pushName = nil
                groupId = groupStanza.gid
                groupName = groupStanza.name
            } else {
                DDLogError("NotificationMetadata/init/groupStanza Invalid action, message: \(msg)")
                return nil
            }
        case .rerequest(let rerequestData):
            // TODO(murali@): in order to be able to act on this rerequest
            // we need access to the message store.
            contentId = rerequestData.id
            messageId = msg.id
            contentType = .chatRerequest
            fromId = UserID(msg.fromUid)
            timestamp = Date()
            data = nil
            pushName = nil
            return
        default:
            return nil
        }

        // Save pushName from the message received.
        checkAndSavePushName(for: fromId, with: pushName)
    }

    private static func mediaIcon(_ mediaType: NotificationMediaType) -> String {
        switch mediaType {
            case .image:
                return "📷"
            case .video:
                return "📹"
            case .audio:
                return "🎤"
        }
    }

    private static func notificationBody(forMedia mediaTypes: [NotificationMediaType]) -> String {
        let numPhotos = mediaTypes.filter { $0 == .image }.count
        let numVideos = mediaTypes.filter { $0 == .video }.count
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

    func getMentionNames(contactStore: ContactStore, mentions: [FeedMentionProtocol] = []) -> ((UserID) -> String) {
        // Add mention names if any in the payload to contactStore and then return dictionary.
        mentions.forEach{
            checkAndSavePushName(for: $0.userID, with: $0.name, to: contactStore)
        }

        let mentionNameProvider: (UserID) -> String = { [self] userID in
            let pushNameForMention = (userID == fromId) ? pushName : nil
            return contactStore.mentionNameIfAvailable(for: userID, pushName: pushNameForMention) ?? Localizations.unknownContact
        }
        return mentionNameProvider
    }

    func populateContent(contactStore: ContactStore) -> Bool {

        // Title:
        // "Contact" for feed posts / comments and 1-1 chat messages.
        // "Contact @ Group" for group feed posts / comments and group chat messages.
        let contactName = contactStore.fullNameIfAvailable(for: fromId, ownName: nil) ?? pushName
        title = [contactName, groupName].compactMap({ $0 }).joined(separator: " @ ")

        // Save push name for contact
        checkAndSavePushName(for: fromId, with: pushName, to: contactStore)

        switch contentType {

        // Post on user feed
        case .feedPost:
            populateFeedPostBody(from: postData(), contactStore: contactStore)
        // Comment on user feed
        case .feedComment:
            populateFeedCommentBody(from: commentData(), contactStore: contactStore)
        // Post on group feed
        case .groupFeedPost:
            body = String(format: Localizations.newPostNotificationBody)
        // Comment on group feed
        case .groupFeedComment:
            body = String(format: Localizations.newCommentNotificationBody)

        // ChatMessage or GroupChatMessage
        case .chatMessage, .groupChatMessage:
            // Fallback text in case decryption fails.
            body = String(format: Localizations.newMessageNotificationBody)

        // Contact notification for new friend or new invitee
        case .newFriend, .newInvitee, .newContact:
            // Look up contact using phone number as the user ID probably hasn't synced yet
            let contactName = contactStore.fullNameIfAvailable(forNormalizedPhone: normalizedPhone!, ownName: nil)
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

    func checkAndSavePushName(for fromUserID: UserID, with pushName: String?, to contactStore: ContactStore = AppContext.shared.contactStore) {
        if let name = pushName, !name.isEmpty {
            var contactNames = [UserID:String]()
            contactNames[fromUserID] = pushName
            contactStore.addPushNames(contactNames)
        }
    }

    func populateChatBody(from chatContent: ChatContent, contactStore: ContactStore) {
        guard let text = Self.bodyText(from: chatContent, contactStore: contactStore) else {
            return
        }
        let ham = HAMarkdown(font: .systemFont(ofSize: 17), color: .label)
        let bodyText = ham.parse(text).string // strips out markdown symbols
        body = bodyText
    }

    func populateFeedPostBody(from postData: PostData?, contactStore: ContactStore) {
        let mentions: [FeedMentionProtocol] = postData?.orderedMentions ?? []
        let mentionNameProvider = getMentionNames(contactStore: contactStore, mentions: mentions)
        let newPostString = Localizations.newPostNotificationBody
        switch postData?.content {
        case .text(let mentionText, _):
            subtitle = newPostString
            let ham = HAMarkdown(font: .systemFont(ofSize: 17), color: .label)
            let expandedText = mentionText.expandedText(nameProvider: mentionNameProvider).string
            let bodyText = ham.parse(expandedText).string // strips out markdown symbols
            body = bodyText
        case .album(let mentionText, let feedMediaData):
            subtitle = newPostString
            body = mentionText.expandedText(nameProvider: mentionNameProvider).string
            let knownMediaTypes = feedMediaData.compactMap { NotificationMediaType(feedMediaType: $0.type) }
            if !knownMediaTypes.isEmpty {
                // Display how many photos and videos post contains if there's no caption.
                if body.isEmpty {
                    body = Self.notificationBody(forMedia: knownMediaTypes)
                } else if let firstMediaType = knownMediaTypes.first {
                    let mediaIcon = Self.mediaIcon(firstMediaType)
                    body = "\(mediaIcon) \(body)"
                }
            }
        case .voiceNote:
            subtitle = newPostString
            body = ""
        case .none, .retracted, .unsupported(_), .waiting:
            subtitle = ""
            body = newPostString
        }
    }

    func populateFeedCommentBody(from commentData: CommentData?, contactStore: ContactStore) {
        let mentions: [FeedMentionProtocol] = commentData?.orderedMentions ?? []
        let mentionNameProvider = getMentionNames(contactStore: contactStore, mentions: mentions)
        let newCommentString = Localizations.newCommentNotificationBody

        switch commentData?.content {
        case .text(let mentionText, _):
            let commentText = mentionText.expandedText(nameProvider: mentionNameProvider).string
            body = String(format: Localizations.newCommentWithTextNotificationBody, commentText)
        case .album(let mentionText, let feedCommentMediaData):
            var commentText = mentionText.expandedText(nameProvider: mentionNameProvider).string
            let knownMediaTypes = feedCommentMediaData.compactMap { NotificationMediaType(feedMediaType: $0.type) }
            if !knownMediaTypes.isEmpty {
                // Display how many photos and videos comment contains if there's no caption.
                if commentText.isEmpty {
                    commentText = Self.notificationBody(forMedia: knownMediaTypes)
                } else if let firstMediaType = knownMediaTypes.first {
                    let mediaIcon = Self.mediaIcon(firstMediaType)
                    commentText = "\(mediaIcon) \(commentText)"
                }
            }
            body = String(format: Localizations.newCommentWithTextNotificationBody, commentText)
        case .voiceNote(_):
            body = String(format: Localizations.newCommentWithTextNotificationBody, Localizations.newAudioNoteNotificationBody)
        case .none, .retracted, .unsupported, .waiting:
            body = newCommentString
        }
    }

    func populateMissedVoiceCallContent(contactStore: ContactStore) {
        title = contactStore.fullNameIfAvailable(for: fromId, ownName: nil, showPushNumber: true) ?? Localizations.unknownContact
        body = Localizations.newMissedVoiceCallNotificationBody
    }

    func populateMissedVideoCallContent(contactStore: ContactStore) {
        title = contactStore.fullNameIfAvailable(for: fromId, ownName: nil, showPushNumber: true) ?? Localizations.unknownContact
        body = Localizations.newMissedVideoCallNotificationBody
    }

    static func bodyText(from chatContent: ChatContent, contactStore: ContactStore) -> String? {
        // NB: contactStore will be needed once we support mentions
        switch chatContent {
        case .text(let text, _):
            return text
        case .album(let text, let media):
            guard let text = text, !text.isEmpty else {
                return Self.notificationBody(forMedia: media.map { NotificationMediaType(chatMsgMediaType: $0.mediaType) } )
            }
            let mediaIcon: String? = {
                guard let firstMedia = media.first else { return nil }
                return Self.mediaIcon(NotificationMediaType(chatMsgMediaType: firstMedia.mediaType))
            }()
            return [mediaIcon, text].compactMap { $0 }.joined(separator: " ")
        case .voiceNote(_):
            return Localizations.newAudioNoteNotificationBody
        case .unsupported:
            DDLogInfo("NotificationMetadata/bodyText/unsupported")
            return nil
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
        case .chatMessage, .groupChatMessage, .chatMessageRetract, .groupChatMessageRetract, .newFriend, .newInvitee, .newContact, .groupAdd, .chatRerequest, .missedAudioCall, .missedVideoCall:
            return false
        }
    }

    var isChatNotification: Bool {
        return contentType == .chatMessage || contentType == .groupChatMessage
    }

    var isMissedCallNotification: Bool {
        return contentType == .missedAudioCall || contentType == .missedVideoCall
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
        case .feedPost, .groupFeedPost, .feedComment, .groupFeedComment, .feedPostRetract, .feedCommentRetract, .groupFeedPostRetract, .groupFeedCommentRetract, .chatMessage, .groupChatMessage, .chatMessageRetract, .groupChatMessageRetract, .groupAdd, .chatRerequest, .missedAudioCall, .missedVideoCall:
            return false
        }
    }

    var isGroupNotification: Bool {
        switch contentType {
        case .groupFeedPost, .groupFeedComment, .groupChatMessage, .groupFeedPostRetract, .groupFeedCommentRetract, .groupChatMessageRetract, .groupAdd:
            return true
        case .feedPost, .feedComment, .feedPostRetract, .feedCommentRetract, .chatMessage, .chatMessageRetract, .newFriend, .newInvitee, .newContact, .chatRerequest, .missedAudioCall, .missedVideoCall:
            return false
        }
    }

    var feedPostId: FeedPostID? {
        if contentType == .feedPost || contentType == .groupFeedPost {
            return contentId
        } else if contentType == .feedComment || contentType == .groupFeedComment {
            return postId
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
        case .feedPost, .groupFeedPost, .feedComment, .groupFeedComment, .chatMessage, .groupChatMessage, .groupAdd, .newFriend, .newInvitee, .newContact, .chatRerequest, .missedAudioCall, .missedVideoCall:
            return false
        }
    }

    var isVisibleNotification: Bool {
        switch contentType {
        case .feedPost, .groupFeedPost, .feedComment, .groupFeedComment, .chatMessage, .groupChatMessage, .groupAdd, .newFriend, .newInvitee, .newContact:
            return true
        case .chatMessageRetract, .groupChatMessageRetract, .feedCommentRetract, .groupFeedCommentRetract, .feedPostRetract, .groupFeedPostRetract, .chatRerequest, .missedAudioCall, .missedVideoCall:
            return false
        }
    }

    func postData(status: FeedItemStatus = .received, usePlainTextPayload: Bool = true) -> PostData? {
        if contentType == .feedPost || contentType == .groupFeedPost {
            // Fallback to plainText payload depending on the boolean here.
            if usePlainTextPayload {
                guard let timestamp = timestamp,
                      let postData = PostData(id: contentId,
                                              userId: fromId,
                                              timestamp: timestamp,
                                              payload: data ?? Data(),
                                              status: status) else
                {
                    DDLogError("postData is null \(debugDescription)")
                    return nil
                }
                return postData
            } else {
                return PostData(id: contentId, userId: fromId, content: .waiting, status: status)
            }
        } else {
            return nil
        }
    }

    func commentData(status: FeedItemStatus = .received, usePlainTextPayload: Bool = true) -> CommentData? {
        if contentType == .feedComment || contentType == .groupFeedComment {
            guard let timestamp = timestamp,
                  let postId = feedPostId else {
                      return nil
                  }
            // Fallback to plainText payload depending on the boolean here.
            if usePlainTextPayload {
                guard let commentData = CommentData(id: contentId,
                                                    userId: fromId,
                                                    feedPostId: postId,
                                                    parentId: parentId,
                                                    timestamp: timestamp,
                                                    payload: data ?? Data(),
                                                    status: status) else
                {
                    DDLogError("CommentData is null \(debugDescription)")
                    return nil
                }
                return commentData
            } else {
                return CommentData(id: contentId,
                                   userId: fromId,
                                   timestamp: timestamp,
                                   feedPostId: postId,
                                   parentId: parentId,
                                   content: .waiting,
                                   status: status)
            }
        } else {
            return nil
        }
    }

    private var debugDescription: String {
        return "[\(data?.bytes.count ?? 0) bytes] [timestamp: \(timestamp?.timeIntervalSince1970 ?? 0)] [postID: \(postId ?? "nil")] [contentID: \(contentId)]"
    }
}
