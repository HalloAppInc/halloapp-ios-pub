//
//  XMPPGroup.swift
//  HalloApp
//
//  Created by Tony Jiang on 8/18/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
import Core
import Foundation
import XMPPFramework

typealias HalloGroup = XMPPGroup
typealias HalloGroupChatMessage = XMPPChatGroupMessage

enum ChatGroupAction: String {
    case create = "create"
    case leave = "leave"
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

struct XMPPGroup {
    let sender: UserID?
    let senderName: String?
    let groupId: String
    let name: String
    let action: ChatGroupAction? // getGroupInfo has not action
    let avatar: String? = nil
    let members: [XMPPGroupMember]

    // inbound
    init?(itemElement item: XMLElement) {
        self.sender = item.attributeStringValue(forName: "sender")
        self.senderName = item.attributeStringValue(forName: "sender_name")
        
        guard let groupId = item.attributeStringValue(forName: "gid") else { return nil }
        guard let name = item.attributeStringValue(forName: "name") else { return nil }
        let actionStr = item.attributeStringValue(forName: "action")
        
        let action: ChatGroupAction? = {
            switch actionStr {
            case "create": return .create
            case "leave": return .leave
            case "modify_members": return .modifyMembers
            case "modify_admins": return .modifyAdmins
            default: return nil
            }}()
        
        let membersEl = item.elements(forName: "member")
        
        self.members = membersEl.compactMap({ XMPPGroupMember(xmlElement: $0) })
        self.groupId = groupId
        self.name = name
        self.action = action
    }
}

struct XMPPGroupMember {
    let userId: UserID
    let name: String? // getGroupInfo is not returning name in response
    let type: ChatGroupMemberType?
    
    let action: ChatGroupMemberAction? // does not need to be recorded in db
    
    // inbound
    init?(xmlElement: XMLElement) {
        guard let userId = xmlElement.attributeStringValue(forName: "uid") else { return nil }
        let name = xmlElement.attributeStringValue(forName: "name")
        
        let typeStr = xmlElement.attributeStringValue(forName: "type")
        let actionStr = xmlElement.attributeStringValue(forName: "action")
        
        let type: ChatGroupMemberType? = {
            switch typeStr {
            case "admin": return .admin
            case "member": return .member
            default: return nil
            }}()

        let action: ChatGroupMemberAction? = {
            switch actionStr {
            case "add": return .add
            case "promote": return .promote
            case "demote": return .demote
            case "remove": return .remove
            case "leave": return .leave
            default: return nil
            }}()
        
        self.userId = userId
        self.name = name
        self.type = type
        self.action = action
    }
}



struct XMPPChatGroupMessage {
    let id: String
    let groupId: GroupID
    let groupName: String?
    let userId: UserID
    let userName: String?
    let text: String?
    let media: [XMPPChatMedia]
    var timestamp: Date?
    
    var orderedMedia: [ChatMediaProtocol] {
        media
    }

    // used for outbound pending chat messages
    init(chatGroupMessage: ChatGroupMessage) {
        self.id = chatGroupMessage.id
        self.groupId = chatGroupMessage.groupId
        self.userId = chatGroupMessage.userId
        self.text = chatGroupMessage.text
        self.groupName = nil
        self.userName = nil
        
        if let media = chatGroupMessage.media {
            self.media = media.sorted(by: { $0.order < $1.order }).map{ XMPPChatMedia(chatMedia: $0) }
        } else {
            self.media = []
        }
    }
    
    
    // init inbound message
    init?(itemElement item: XMLElement) {
        guard let groupChat = item.element(forName: "group_chat") else { return nil }
        guard let id = item.attributeStringValue(forName: "id") else { return nil }
        guard let groupId = groupChat.attributeStringValue(forName: "gid") else { return nil }
        guard let groupName = groupChat.attributeStringValue(forName: "name") else { return nil }
        guard let userId = groupChat.attributeStringValue(forName: "sender") else { return nil }
        guard let userName = groupChat.attributeStringValue(forName: "sender_name") else { return nil }
        
        var text: String?, media: [XMPPChatMedia] = []
        
        if let protoContainer = Proto_Container.chatMessageContainer(from: groupChat) {
            if protoContainer.hasChatMessage {
                text = protoContainer.chatMessage.text.isEmpty ? nil : protoContainer.chatMessage.text
                DDLogInfo("ChatData/group/XMPPChatGroupMessage/plainText: \(text ?? "")")
                media = protoContainer.chatMessage.media.compactMap { XMPPChatMedia(protoMedia: $0) }
            }
        }
        
        self.id = id
        self.groupId = groupId
        self.groupName = groupName
        self.userId = userId
        self.userName = userName
        self.text = text
    
        self.media = media
        
        self.timestamp = Date()
    }
    
    var xmppElement: XMPPElement {
        let message = XMPPElement(name: "message")
        message.addAttribute(withName: "to", stringValue: "s.halloapp.net")
        message.addAttribute(withName: "type", stringValue: "groupchat")
        message.addAttribute(withName: "id", stringValue: id)
        
        message.addChild({
            let groupChat = XMPPElement(name: "group_chat")
            groupChat.addAttribute(withName: "xmlns", stringValue: "halloapp:groups")
            groupChat.addAttribute(withName: "gid", stringValue: groupId)
            
            if let protobufData = try? self.protoContainer.serializedData() {
                groupChat.addChild(XMPPElement(name: "s1", stringValue: protobufData.base64EncodedString()))
            }
            return groupChat
        }())
        return message
    }
    
    var protoContainer: Proto_Container {
        get {
            var protoChatMessage = Proto_ChatMessage()
            if let text = text {
                protoChatMessage.text = text
            }

            protoChatMessage.media = orderedMedia.map { $0.protoMessage }

            var protoContainer = Proto_Container()
            protoContainer.chatMessage = protoChatMessage
            return protoContainer
        }
    }
}

