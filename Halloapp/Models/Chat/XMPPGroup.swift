//
//  XMPPGroup.swift
//  HalloApp
//
//  Created by Tony Jiang on 8/18/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreCommon
import Foundation

typealias HalloGroups = XMPPGroups
typealias HalloGroup = XMPPGroup
typealias HalloGroupChatMessage = XMPPChatGroupMessage

typealias ChatGroupAction = GroupAction
typealias ChatGroupMemberType = GroupMemberType
typealias ChatGroupMemberAction = GroupMemberAction

public struct XMPPChatMention: FeedMentionProtocol {
    public let index: Int
    public let userID: String
    public let name: String
}

struct XMPPGroups {
    private(set) var groups: [XMPPGroup]? = nil
    
    init?(protoGroups: Server_GroupsStanza) {
        self.groups = protoGroups.groupStanzas.compactMap { XMPPGroup(protoGroup: $0) }
    }
}

struct XMPPGroup {
    let groupId: GroupID
    let name: String
    var description: String? = nil
    var avatarID: String? = nil
    var background: Int32 = 0
    var retryCount: Int32 = 0

    private(set) var messageId: String? = nil
    private(set) var sender: UserID? = nil
    private(set) var senderName: String? = nil
    private(set) var action: ChatGroupAction? = nil
    private(set) var members: [XMPPGroupMember]? = nil
    private(set) var audienceHash: Data? = nil
    private(set) var expirationType: Group.ExpirationType? = nil
    private(set) var expirationTime: Int64? = nil

    init(id: GroupID, name: String, avatarID: String? = nil) {
        self.groupId = id
        self.name = name
        self.avatarID = avatarID
    }

    // used for inbound and outbound
    init?(protoGroup: Server_GroupStanza, msgId: String? = nil, retryCount: Int32 = 0) {
        // msgId used only for inbound group events
        if let msgId = msgId {
            self.messageId = msgId
        }
        self.sender = String(protoGroup.senderUid)
        self.senderName = protoGroup.senderName
        self.groupId = protoGroup.gid
        self.name = protoGroup.name
        self.description = protoGroup.description_p
        self.avatarID = protoGroup.avatarID
        self.members = protoGroup.members.compactMap { XMPPGroupMember(protoMember: $0) }

        if protoGroup.hasExpiryInfo {
            switch protoGroup.expiryInfo.expiryType {
            case .expiresInSeconds:
                expirationType = .expiresInSeconds
                expirationTime = protoGroup.expiryInfo.expiresInSeconds
            case .never:
                expirationType = .never
                expirationTime = 0
            case .customDate:
                expirationType = .customDate
                expirationTime = protoGroup.expiryInfo.expiryTimestamp
            case .UNRECOGNIZED(_):
                expirationType = .expiresInSeconds
                expirationTime = .thirtyDays
            }
        }

        if let protoBackgroundData = protoGroup.background.data(using: .utf8) {
            if let protoBackground = try? Clients_Background(serializedData: protoBackgroundData) {
                self.background = protoBackground.theme
            }
        }

        self.action = {
            switch protoGroup.action {
            case .set: return nil
            case .get: return .get
            case .create: return .create
            case .delete: return nil
            case .leave: return .leave
            case .changeAvatar: return .changeAvatar
            case .changeName: return .changeName
            case .changeDescription: return .changeDescription
            case .modifyAdmins: return .modifyAdmins
            case .modifyMembers: return .modifyMembers
            case .setName: return nil
            case .autoPromoteAdmins: return nil
            case .join: return .join
            case .preview: return nil
            case .setBackground: return .setBackground
            case .getMemberIdentityKeys: return nil // TODO: Does this need to be handled?
            case .shareHistory: return nil
            case .changeExpiry: return .changeExpiry
            case .UNRECOGNIZED(_): return nil
            }
        }()
        
        self.retryCount = retryCount
        self.audienceHash = protoGroup.audienceHash.isEmpty ? nil : protoGroup.audienceHash
    }
}

struct XMPPGroupMember {
    let userId: UserID
    let name: String? // getGroupInfo is not returning name in response
    let type: ChatGroupMemberType?
    
    let action: ChatGroupMemberAction? // does not need to be recorded in db
    let identityKey: Data?

    init?(protoMember: Server_GroupMember) {
        self.userId = String(protoMember.uid)
        self.name = protoMember.name

        self.action = {
            switch protoMember.action {
            case .add: return .add
            case .remove: return .remove
            case .promote: return .promote
            case .demote: return .demote
            case .leave: return .leave
            case .join: return .join
            case .UNRECOGNIZED(_): return nil
            }
        }()

        self.type = {
            switch protoMember.type {
            case .member: return .member
            case .admin: return .admin
            case .UNRECOGNIZED(_): return nil
            }
        }()

        self.identityKey = protoMember.identityKey.isEmpty ? nil : protoMember.identityKey
    }
}



struct XMPPChatGroupMessage {
    let id: String
    let groupId: GroupID
    let groupName: String?
    let userId: UserID?
    let userName: String?
    var retryCount: Int32? = nil
    let text: String?
    let mentions: [XMPPChatMention]
    let media: [XMPPChatMedia]
    let chatReplyMessageID: String?
    let chatReplyMessageSenderID: String?
    let chatReplyMessageMediaIndex: Int32
    var timestamp: Date?
    
    var orderedMedia: [ChatMediaProtocol] {
        media
    }
    
    var orderedMentions: [XMPPChatMention] {
        mentions
    }

    // used for outbound pending chat messages
    /*
    init(chatGroupMessage: ChatGroupMessage) {
        self.id = chatGroupMessage.id
        self.groupId = chatGroupMessage.groupId
        self.userId = chatGroupMessage.userId
        self.text = chatGroupMessage.text
        self.groupName = nil
        self.userName = nil
        
        self.chatReplyMessageID = chatGroupMessage.chatReplyMessageID
        self.chatReplyMessageSenderID = chatGroupMessage.chatReplyMessageSenderID
        self.chatReplyMessageMediaIndex = chatGroupMessage.chatReplyMessageMediaIndex

        self.media = []
        if let media = chatGroupMessage.media {
            self.media = media.sorted(by: { $0.order < $1.order }).map{ XMPPChatMedia(chatMedia: $0) }
        } else {
            self.media = []
        }

        if let mentions = chatGroupMessage.mentions {
            self.mentions = mentions.map { XMPPChatMention(index: Int($0.index), userID: $0.userID, name: $0.name) }
        } else {
            self.mentions = []
        }
    }
    */

    // init inbound message
    init?(_ pbGroupChat: Server_GroupChat, id: String, retryCount: Int32) {
        // TODO: Need to fix this to enable group-chat.
        return nil

//        self.id = id
//        self.retryCount = retryCount
//        self.groupId = pbGroupChat.gid
//        self.groupName = pbGroupChat.name
//        self.userId = UserID(pbGroupChat.senderUid)
//        self.userName = pbGroupChat.senderName
//        self.text = protoChat.text.isEmpty ? nil : protoChat.text
//        self.mentions = protoChat.mentions.map { XMPPChatMention(index: Int($0.index), userID: $0.userID, name: $0.name) }
//        self.media = protoChat.media.compactMap { XMPPChatMedia(protoMedia: $0) }
//        self.timestamp = Date(timeIntervalSince1970: TimeInterval(pbGroupChat.timestamp))
//
//        self.chatReplyMessageID = protoChat.chatReplyMessageID.isEmpty ? nil : protoChat.chatReplyMessageID
//        self.chatReplyMessageSenderID = protoChat.chatReplyMessageSenderID.isEmpty ? nil : protoChat.chatReplyMessageSenderID
//        self.chatReplyMessageMediaIndex = protoChat.chatReplyMessageMediaIndex
    }

    var protoContainer: Clients_Container? {
        get {
            // TODO: Fix this for groupChat.
            return nil
        }
    }
//
//    var protoContainer: Clients_Container? {
//        get {
//            var ready = false
//            var protoContainer = Clients_Container()
//
//            if let clientChatContainer = clientChatContainer {
//                protoContainer.chatContainer = clientChatContainer
//                ready = true
//            }
//
//            return ready ? protoContainer : nil
//        }
//    }
}
