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

final class ProtoAvatarRequest: ProtoRequest<AvatarInfo> {

    init(userID: UserID, completion: @escaping Completion) {
        var avatar = Server_Avatar()
        if let uid = Int64(userID) {
            avatar.uid = uid
        } else {
            DDLogError("ProtoAvatarRequest/error invalid userID \(userID)")
        }

        super.init(
            iqPacket: .iqPacket(type: .get, payload: .avatar(avatar)),
            transform: { (iq) in .success((userID: userID, avatarID: iq.avatar.id)) },
            completion: completion)
    }
}


final class ProtoUpdateAvatarRequest: ProtoRequest<String?> {

    init(data: Data?, completion: @escaping Completion) {
        var uploadAvatar = Server_UploadAvatar()
        if let data = data {
            uploadAvatar.data = data
        }

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .uploadAvatar(uploadAvatar)),
            transform: { (iq) in .success(iq.avatar.id) },
            completion: completion)
    }
}


final class ProtoPushTokenRequest: ProtoRequest<Void> {

    init(token: String, completion: @escaping Completion) {
        var pushToken = Server_PushToken()
        pushToken.token = token
        
        #if DEBUG
        pushToken.os = .iosDev
        #else
        pushToken.os = .ios
        #endif
        
        var pushRegister = Server_PushRegister()
        pushRegister.pushToken = pushToken

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .pushRegister(pushRegister)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}


final class ProtoSharePostsRequest: ProtoRequest<Void> {

    init(postIDs: [FeedPostID], userID: UserID, completion: @escaping Completion) {
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
            iqPacket: .iqPacket(type: .set, payload: .feedItem(item)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}


final class ProtoRetractItemRequest: ProtoRequest<Void> {

    init(feedItem: FeedItemProtocol, completion: @escaping Completion) {
        var serverFeedItem = Server_FeedItem()
        serverFeedItem.item = feedItem.protoFeedItem(withData: false)
        serverFeedItem.action = .retract

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .feedItem(serverFeedItem)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}


final class ProtoContactSyncRequest: ProtoRequest<[HalloContact]> {

    init<T: Sequence>(
        with contacts: T,
        type: ContactSyncRequestType,
        syncID: String,
        batchIndex: Int? = nil,
        isLastBatch: Bool? = nil,
        completion: @escaping Completion) where T.Iterator.Element == HalloContact
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
            iqPacket: .iqPacket(type: .set, payload: .contactList(contactList)),
            transform: { (iq) in
                let contacts = iq.contactList.contacts
                return .success(contacts.compactMap { HalloContact($0) }) },
            completion: completion)
    }
}

final class ProtoSendReceipt: ProtoRequest<Void> {

    init(
        messageID: String? = nil,
        itemID: String,
        thread: HalloReceipt.Thread,
        type: HalloReceipt.`Type`,
        fromUserID: UserID,
        toUserID: UserID,
        completion: @escaping Completion)
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

        super.init(iqPacket: packet, transform: { _ in .success(()) }, completion: completion)
    }
}


final class ProtoSendNameRequest: ProtoRequest<Void> {

    init(name: String, completion: @escaping Completion) {
        var serverName = Server_Name()
        serverName.name = name

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .name(serverName)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}


final class ProtoClientVersionCheck: ProtoRequest<TimeInterval> {

    init(version: String, completion: @escaping Completion) {
        var clientVersion = Server_ClientVersion()
        clientVersion.version = "HalloApp/iOS\(version)"

        super.init(
            iqPacket: .iqPacket(type: .get, payload: .clientVersion(clientVersion)),
            transform: { (iq) in
                let expiresInSeconds = iq.clientVersion.expiresInSeconds
                return .success(TimeInterval(expiresInSeconds)) },
            completion: completion)
    }
}


final class ProtoGroupCreateRequest: ProtoRequest<String> {

    init(name: String, members: [UserID], completion: @escaping Completion) {
        var group = Server_GroupStanza()
        group.action = .create
        group.name = name
        group.members = members.compactMap { Server_GroupMember(userID: $0) }

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .groupStanza(group)),
            transform: { (iq) in
                guard let group = HalloGroup(protoGroup: iq.groupStanza) else {
                    return .failure(ProtoServiceError.unexpectedResponseFormat)
                }
                return .success(group.groupId) },
            completion: completion)
    }
}


final class ProtoGroupInfoRequest: ProtoRequest<HalloGroup> {

    init(groupID: GroupID, completion: @escaping Completion) {
        var group = Server_GroupStanza()
        group.gid = groupID
        group.action = .get

        super.init(
            iqPacket: .iqPacket(type: .get, payload: .groupStanza(group)),
            transform: { (iq) in
                guard let group = HalloGroup(protoGroup: iq.groupStanza) else {
                    return .failure(ProtoServiceError.unexpectedResponseFormat)
                }
                return .success(group) },
            completion: completion)
    }
}


final class ProtoGroupLeaveRequest: ProtoRequest<Void> {

    init(groupID: GroupID, completion: @escaping Completion) {
        var group = Server_GroupStanza()
        group.gid = groupID
        group.action = .leave

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .groupStanza(group)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}


final class ProtoGroupModifyRequest: ProtoRequest<Void> {

    init(groupID: GroupID, members: [UserID], groupAction: ChatGroupAction, action: ChatGroupMemberAction, completion: @escaping Completion) {
        var group = Server_GroupStanza()
        group.gid = groupID
        group.action = .init(groupAction)
        group.members = members.compactMap { Server_GroupMember(userID: $0, action: .init(action)) }

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .groupStanza(group)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}


final class ProtoChangeGroupNameRequest: ProtoRequest<Void> {

    init(groupID: GroupID, name: String, completion: @escaping Completion) {
        var group = Server_GroupStanza()
        group.gid = groupID
        group.action = .setName
        group.name = name
        
        super.init(
            iqPacket: .iqPacket(type: .set, payload: .groupStanza(group)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}


final class ProtoChangeGroupAvatarRequest: ProtoRequest<String> {

    init(groupID: GroupID, data: Data, completion: @escaping Completion) {
        var uploadAvatar = Server_UploadGroupAvatar()
        uploadAvatar.gid = groupID
        uploadAvatar.data = data
        
        super.init(
            iqPacket: .iqPacket(type: .set, payload: .groupAvatar(uploadAvatar)),
            transform: { (iq) in
                guard let group = HalloGroup(protoGroup: iq.groupStanza), let avatarID = group.avatarID else {
                    return .failure(ProtoServiceError.unexpectedResponseFormat)
                }
                return .success(avatarID) },
            completion: completion)
    }
}


final class ProtoUpdateNotificationSettingsRequest: ProtoRequest<Void> {

    init(settings: [NotificationSettings.ConfigKey: Bool], completion: @escaping Completion) {
        var prefs = Server_NotificationPrefs()
        prefs.pushPrefs = settings.map {
            var pref = Server_PushPref()
            pref.name = .init($0.key)
            pref.value = $0.value
            return pref
        }
        super.init(iqPacket: .iqPacket(type: .set, payload: .notificationPrefs(prefs)), transform: { _ in .success(()) }, completion: completion)
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
