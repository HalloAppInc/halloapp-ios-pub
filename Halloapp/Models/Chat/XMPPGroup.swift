//
//  XMPPGroup.swift
//  HalloApp
//
//  Created by Tony Jiang on 8/18/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
import Core
import Foundation

typealias HalloGroups = XMPPGroups
typealias HalloGroup = XMPPGroup
typealias HalloGroupChatMessage = XMPPChatGroupMessage

enum ChatGroupAction: String {
    case create = "create"
    case leave = "leave"
    case delete = "delete"
    case changeName = "change_name"
    case changeAvatar = "change_avatar"
    case modifyMembers = "modify_members"
    case modifyAdmins = "modify_admins"
}

enum ChatGroupMemberType: Int {
    case admin = 0
    case member = 1
}

enum ChatGroupMemberAction: String {
    case add = "add"
    case promote = "promote"
    case demote = "demote"
    case remove = "remove"
    case leave = "leave"
    
}

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
    var avatarID: String? = nil

    private(set) var messageId: String? = nil
    private(set) var sender: UserID? = nil
    private(set) var senderName: String? = nil
    private(set) var action: ChatGroupAction? = nil // getGroupInfo has no action
    private(set) var members: [XMPPGroupMember]? = nil

    init(id: GroupID, name: String, avatarID: String? = nil) {
        self.groupId = id
        self.name = name
        self.avatarID = avatarID
    }

    // used for inbound and outbound
    init?(protoGroup: Server_GroupStanza, msgId: String? = nil) {
        // msgId used only for inbound group events
        if let msgId = msgId {
            self.messageId = msgId
        }
        self.sender = String(protoGroup.senderUid)
        self.senderName = protoGroup.senderName
        self.groupId = protoGroup.gid
        self.name = protoGroup.name
        self.avatarID = protoGroup.avatarID
        self.members = protoGroup.members.compactMap { XMPPGroupMember(protoMember: $0) }
        
        self.action = {
            switch protoGroup.action {
            case .set: return nil
            case .get: return nil
            case .create: return .create
            case .delete: return nil
            case .leave: return .leave
            case .changeAvatar: return .changeAvatar
            case .changeName: return .changeName
            case .modifyAdmins: return .modifyAdmins
            case .modifyMembers: return .modifyMembers
            case .setName: return nil
            case .autoPromoteAdmins: return nil
            case .UNRECOGNIZED(_): return nil
            }
        }()
    }
}

struct XMPPGroupMember {
    let userId: UserID
    let name: String? // getGroupInfo is not returning name in response
    let type: ChatGroupMemberType?
    
    let action: ChatGroupMemberAction? // does not need to be recorded in db

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

    // init inbound message
    init?(_ pbGroupChat: Server_GroupChat, id: String, retryCount: Int32) {
        let protoChat: Clients_ChatMessage
        if let protoContainer = try? Clients_Container(serializedData: pbGroupChat.payload),
            protoContainer.hasChatMessage
        {
            // Binary protocol
            protoChat = protoContainer.chatMessage
        } else if let decodedData = Data(base64Encoded: pbGroupChat.payload),
            let protoContainer = try? Clients_Container(serializedData: decodedData),
            protoContainer.hasChatMessage
        {
            // Legacy Base64 protocol
            protoChat = protoContainer.chatMessage
        } else {
            return nil
        }

        self.id = id
        self.retryCount = retryCount
        self.groupId = pbGroupChat.gid
        self.groupName = pbGroupChat.name
        self.userId = UserID(pbGroupChat.senderUid)
        self.userName = pbGroupChat.senderName
        self.text = protoChat.text.isEmpty ? nil : protoChat.text
        self.mentions = protoChat.mentions.map { XMPPChatMention(index: Int($0.index), userID: $0.userID, name: $0.name) }
        self.media = protoChat.media.compactMap { XMPPChatMedia(protoMedia: $0) }
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(pbGroupChat.timestamp))

        self.chatReplyMessageID = protoChat.chatReplyMessageID.isEmpty ? nil : protoChat.chatReplyMessageID
        self.chatReplyMessageSenderID = protoChat.chatReplyMessageSenderID.isEmpty ? nil : protoChat.chatReplyMessageSenderID
        self.chatReplyMessageMediaIndex = protoChat.chatReplyMessageMediaIndex
    }

    var protoContainer: Clients_Container {
        get {
            var protoChatMessage = Clients_ChatMessage()
            if let text = text {
                protoChatMessage.text = text
            }

            if let chatReplyMessageID = chatReplyMessageID, let chatReplyMessageSenderID = chatReplyMessageSenderID {
                protoChatMessage.chatReplyMessageID = chatReplyMessageID
                protoChatMessage.chatReplyMessageSenderID = chatReplyMessageSenderID
                protoChatMessage.chatReplyMessageMediaIndex = chatReplyMessageMediaIndex
            }
            
            protoChatMessage.media = orderedMedia.compactMap { $0.protoMessage }
            protoChatMessage.mentions = orderedMentions.compactMap { $0.protoMention }
            
            var protoContainer = Clients_Container()
            protoContainer.chatMessage = protoChatMessage
            return protoContainer
        }
    }
}

