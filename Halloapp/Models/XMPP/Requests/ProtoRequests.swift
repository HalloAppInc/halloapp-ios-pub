//
//  ProtoRequests.swift
//  HalloApp
//
//  Created by Garrett on 8/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import Foundation
import XMPPFramework

final class ProtoAvatarRequest: ProtoStandardRequest<AvatarInfo> {
    init(userID: UserID, completion: @escaping ServiceRequestCompletion<AvatarInfo>) {
        var avatar = Server_Avatar()
        if let uid = Int64(userID) {
            avatar.uid = uid
        } else {
            DDLogError("ProtoAvatarRequest/error invalid userID \(userID)")
        }

        super.init(
            packet: .iqPacket(type: .get, payload: .avatar(avatar)),
            transform: { response in .success((userID: userID, avatarID: response.iq.avatar.id)) },
            completion: completion)
    }
}

final class ProtoUpdateAvatarRequest: ProtoStandardRequest<String?> {
    init(data: Data?, completion: @escaping ServiceRequestCompletion<String?>) {

        var uploadAvatar = Server_UploadAvatar()
        if let data = data {
            uploadAvatar.data = data
        }

        super.init(
            packet: .iqPacket(type: .set, payload: .uploadAvatar(uploadAvatar)),
            transform: { .success($0.iq.avatar.id) },
            completion: completion)
    }
}

final class ProtoPushTokenRequest: ProtoStandardRequest<Void> {
    init(token: String, completion: @escaping ServiceRequestCompletion<Void>) {

        var pushToken = Server_PushToken()
        pushToken.token = token
        pushToken.os = .ios

        var pushRegister = Server_PushRegister()
        pushRegister.pushToken = pushToken

        super.init(
            packet: .iqPacket(type: .set, payload: .pushRegister(pushRegister)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

final class ProtoSharePostsRequest: ProtoStandardRequest<Void> {
    init(postIDs: [FeedPostID], userID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {

        var share = Server_ShareStanza()
        share.postIds = postIDs
        if let uid = Int64(userID) {
            share.uid = uid
        } else {
            DDLogError("ProtoSharePostsRequest/error invalid userID \(userID)")
        }

        var item = Server_FeedItem()
        item.action = .share
        item.shareStanzas = [share]

        super.init(
            packet: .iqPacket(type: .set, payload: .feedItem(item)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

final class ProtoRetractItemRequest: ProtoStandardRequest<Void> {
    init(feedItem: FeedItemProtocol, completion: @escaping ServiceRequestCompletion<Void>) {

        var serverFeedItem = Server_FeedItem()
        serverFeedItem.item = feedItem.protoFeedItem(withData: false)
        serverFeedItem.action = .retract

        super.init(
            packet: .iqPacket(type: .set, payload: .feedItem(serverFeedItem)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

final class ProtoContactSyncRequest: ProtoStandardRequest<[HalloContact]> {
    init<T: Sequence>(
        with contacts: T,
        type: ContactSyncRequestType,
        syncID: String,
        batchIndex: Int? = nil,
        isLastBatch: Bool? = nil,
        completion: @escaping ServiceRequestCompletion<[HalloContact]>) where T.Iterator.Element == HalloContact
    {

        var contactList = Server_ContactList()
        contactList.type = {
            switch type {
            case .full:
                return .full
            case .delta:
                return .delta
            }
        }()
        contactList.syncID = syncID
        if let batchIndex = batchIndex {
            contactList.batchIndex = Int32(batchIndex)
        }
        if let isLastBatch = isLastBatch {
            contactList.isLast = isLastBatch
        }
        contactList.contacts = contacts.map { contact in
            var serverContact = Server_Contact()
            serverContact.action = contact.isDeletedContact ? .delete : .add
            if let raw = contact.raw { serverContact.raw = raw }
            if let normalized = contact.normalized { serverContact.normalized = normalized }
            if let userID = contact.userid, let numericID = Int64(userID) { serverContact.uid = numericID }
            return serverContact
        }

        super.init(
            packet: .iqPacket(type: .set, payload: .contactList(contactList)),
            transform: {
                let contacts = $0.iq.contactList.contacts
                return .success(contacts.compactMap { HalloContact($0) }) },
            completion: completion)
    }
}

final class ProtoPresenceSubscribeRequest: ProtoStandardRequest<Void> {
    init(userID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {

        var presence = Server_Presence()
        presence.id = UUID().uuidString
        presence.type = .subscribe
        if let uid = Int64(userID) {
            presence.uid = uid
        }

        var packet = Server_Packet()
        packet.stanza = .presence(presence)

        super.init(packet: packet, transform: { _ in .success(())}, completion: completion)
    }
}

final class ProtoPresenceUpdate: ProtoStandardRequest<Void> {
    init(status: PresenceType, completion: @escaping ServiceRequestCompletion<Void>) {

        var presence = Server_Presence()
        presence.id = UUID().uuidString
        presence.type = {
            switch status {
            case .away:
                return .away
            case .available:
                return .available
            }
        }()
        if let uid = Int64(AppContext.shared.userData.userId) {
            presence.uid = uid
        }

        var packet = Server_Packet()
        packet.presence = presence

        super.init(packet: packet, transform: { _ in .success(()) }, completion: completion)
    }
}

final class ProtoSendReceipt: ProtoStandardRequest<Void> {
    init(
        messageID: String? = nil,
        itemID: String,
        thread: HalloReceipt.Thread,
        type: HalloReceipt.`Type`,
        fromUserID: UserID,
        toUserID: UserID,
        completion: @escaping ServiceRequestCompletion<Void>)
    {
        let threadID: String = {
            switch thread {
            case .group(let threadID): return threadID
            case .feed: return "feed"
            case .none: return ""
            }
        }()

        let payloadContent: Server_Msg.OneOf_Payload = {
            switch type {
            case .delivery:
                var receipt = Server_DeliveryReceipt()
                receipt.id = itemID
                receipt.threadID = threadID
                return .deliveryReceipt(receipt)
            case .read:
                var receipt = Server_SeenReceipt()
                receipt.id = itemID
                receipt.threadID = threadID
                return .seenReceipt(receipt)
            }
        }()

        let typeString: String = {
            switch type {
            case .delivery: return "delivery"
            case .read: return "seen"
            }
        }()

        let packet = Server_Packet.msgPacket(
            from: fromUserID,
            to: toUserID,
            id: messageID ?? "\(typeString)-\(itemID)",
            payload: payloadContent)

        super.init(packet: packet, transform: { _ in .success(()) }, completion: completion)
    }
}

final class ProtoSendNameRequest: ProtoStandardRequest<Void> {
    init(name: String, completion: @escaping ServiceRequestCompletion<Void>) {

        var serverName = Server_Name()
        serverName.name = name

        super.init(
            packet: .iqPacket(type: .set, payload: .name(serverName)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

final class ProtoClientVersionCheck: ProtoStandardRequest<TimeInterval> {
    init(version: String, completion: @escaping ServiceRequestCompletion<TimeInterval>) {

        var clientVersion = Server_ClientVersion()
        clientVersion.version = "HalloApp/iOS\(version)"

        super.init(
            packet: .iqPacket(type: .get, payload: .clientVersion(clientVersion)),
            transform: {
                let expiresInSeconds = $0.iq.clientVersion.expiresInSeconds
                return .success(TimeInterval(expiresInSeconds)) },
            completion: completion)
    }
}

final class ProtoGroupCreateRequest: ProtoStandardRequest<Void> {
    init(name: String, members: [UserID], completion: @escaping ServiceRequestCompletion<Void>) {

        var group = Server_GroupStanza()
        group.action = .create
        group.name = name
        group.members = members.compactMap { Server_GroupMember(userID: $0) }

        super.init(
            packet: .iqPacket(type: .set, payload: .groupStanza(group)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

final class ProtoGroupInfoRequest: ProtoStandardRequest<HalloGroup> {
    init(groupID: GroupID, completion: @escaping ServiceRequestCompletion<HalloGroup>) {

        var group = Server_GroupStanza()
        group.gid = groupID
        group.action = .get

        super.init(
            packet: .iqPacket(type: .get, payload: .groupStanza(group)),
            transform: {
                guard let group = HalloGroup(protoGroup: $0.iq.groupStanza) else {
                    return .failure(ProtoServiceError.unexpectedResponseFormat)
                }
                return .success(group) },
            completion: completion)
    }
}

final class ProtoGroupLeaveRequest: ProtoStandardRequest<Void> {
    init(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Void>) {

        var group = Server_GroupStanza()
        group.gid = groupID
        group.action = .leave

        super.init(
            packet: .iqPacket(type: .set, payload: .groupStanza(group)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

final class ProtoGroupModifyRequest: ProtoStandardRequest<Void> {
    init(groupID: GroupID, members: [UserID], groupAction: ChatGroupAction, action: ChatGroupMemberAction, completion: @escaping ServiceRequestCompletion<Void>) {

        var group = Server_GroupStanza()
        group.gid = groupID
        group.action = .init(groupAction)
        group.members = members.compactMap { Server_GroupMember(userID: $0, action: .init(action)) }

        super.init(
            packet: .iqPacket(type: .set, payload: .groupStanza(group)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

final class ProtoChangeGroupNameRequest: ProtoStandardRequest<Void> {
    init(groupID: GroupID, name: String, completion: @escaping ServiceRequestCompletion<Void>) {

        var group = Server_GroupStanza()
        group.gid = groupID
        group.action = .changeName
        group.name = name
        
        super.init(
            packet: Server_Packet.iqPacket(type: .set, payload: .groupStanza(group)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

final class ProtoChangeGroupAvatarRequest: ProtoStandardRequest<String> {
    init(groupID: GroupID, data: Data, completion: @escaping ServiceRequestCompletion<String>) {

        var group = Server_GroupStanza()
        group.gid = groupID
        group.action = .changeAvatar
        
        super.init(
            packet: .iqPacket(type: .get, payload: .groupStanza(group)),
            transform: {
                guard let group = HalloGroup(protoGroup: $0.iq.groupStanza), let avatarID = group.avatarID else {
                    return .failure(ProtoServiceError.unexpectedResponseFormat)
                }
                return .success(avatarID) },
            completion: completion)
        
//        super.init(
//            packet: Server_Packet.iqPacket(type: .set, payload: .groupStanza(group)),
//            transform: { _ in .success(()) },
//            completion: completion)
    }
}

final class ProtoUpdateNotificationSettingsRequest: ProtoStandardRequest<Void> {
    init(settings: [NotificationSettings.ConfigKey: Bool], completion: @escaping ServiceRequestCompletion<Void>) {
        var prefs = Server_NotificationPrefs()
        prefs.pushPrefs = settings.map {
            var pref = Server_PushPref()
            pref.name = .init($0.key)
            pref.value = $0.value
            return pref
        }
        super.init(packet: .iqPacket(type: .set, payload: .notificationPrefs(prefs)), transform: { _ in .success(()) }, completion: completion)
    }
}

extension Server_PushPref.Name {
    init(_ configKey: NotificationSettings.ConfigKey) {
        switch configKey {
        case .post: self = .post
        case .comment: self = .comment
        }
    }
}

extension Server_GroupStanza.Action {
    init(_ groupAction: ChatGroupAction) {
        switch groupAction {
        case .create: self = .create
        case .leave: self = .leave
        case .delete: self = .delete
        case .changeName: self = .changeName
        case .changeAvatar: self = .changeAvatar
        case .modifyAdmins: self = .modifyAdmins
        case .modifyMembers: self = .modifyMembers
        }
    }
}

extension Server_GroupMember {
    init?(userID: UserID, action: Action? = nil) {
        guard let uid = Int64(userID) else { return nil }
        self.init()
        self.uid = uid
        if let action = action {
            self.action = action
        }
    }
}

extension Server_GroupMember.Action {
    init(_ memberAction: ChatGroupMemberAction) {
        switch memberAction {
        case .add: self = .add
        case .demote: self = .demote
        case .leave: self = .leave
        case .promote: self = .promote
        case .remove: self = .remove
        }
    }
}
