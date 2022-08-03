//
//  ProtoRequests.swift
//  HalloApp
//
//  Created by Garrett on 8/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import Foundation

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

final class ProtoPushTokenRequest: ProtoRequest<Void> {

    init(type: Server_PushToken.TokenType, token: String, langID: String?, completion: @escaping Completion) {
        var pushToken = Server_PushToken()
        pushToken.token = token
        pushToken.tokenType = type
        var pushRegister = Server_PushRegister()
        pushRegister.pushToken = pushToken
        if let langID = langID {
            pushRegister.langID = langID
        }

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

final class ProtoRetractPostRequest: ProtoRequest<Void> {

    init(id: FeedPostID, completion: @escaping Completion) {
        var post = Server_Post()
        post.id = id

        var serverFeedItem = Server_FeedItem()
        serverFeedItem.item = .post(post)
        serverFeedItem.action = .retract

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .feedItem(serverFeedItem)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

final class ProtoRetractCommentRequest: ProtoRequest<Void> {

    init(id: FeedPostCommentID, postID: FeedPostID, completion: @escaping Completion) {
        var comment = Server_Comment()
        comment.id = id
        comment.postID = postID

        var serverFeedItem = Server_FeedItem()
        serverFeedItem.item = .comment(comment)
        serverFeedItem.action = .retract

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .feedItem(serverFeedItem)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

final class ProtoRetractGroupPostRequest: ProtoRequest<Void> {

    init(id: FeedPostID, in groupID: GroupID, completion: @escaping Completion) {
        var post = Server_Post()
        post.id = id

        var serverGroupFeedItem = Server_GroupFeedItem()
        serverGroupFeedItem.item = .post(post)
        serverGroupFeedItem.action = .retract
        serverGroupFeedItem.gid = groupID

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .groupFeedItem(serverGroupFeedItem)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

final class ProtoRetractGroupCommentRequest: ProtoRequest<Void> {

    init(id: FeedPostCommentID, postID: FeedPostID, in groupID: GroupID, completion: @escaping Completion) {
        var comment = Server_Comment()
        comment.id = id
        comment.postID = postID

        var serverGroupFeedItem = Server_GroupFeedItem()
        serverGroupFeedItem.item = .comment(comment)
        serverGroupFeedItem.action = .retract
        serverGroupFeedItem.gid = groupID

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .groupFeedItem(serverGroupFeedItem)),
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


final class ProtoGroupCreateRequest: ProtoRequest<String> {

    init(name: String, expiryType: Server_ExpiryInfo.ExpiryType, expiryTime: Int64, members: [UserID], completion: @escaping Completion) {
        var group = Server_GroupStanza()
        group.action = .create
        group.name = name
        group.members = members.compactMap { Server_GroupMember(userID: $0) }

        var expiryInfo = Server_ExpiryInfo()
        expiryInfo.expiryType = expiryType
        switch expiryType {
        case .expiresInSeconds:
            expiryInfo.expiresInSeconds = expiryTime
        case .never:
            // No additional fields to update
            break
        case .customDate:
            expiryInfo.expiryTimestamp = expiryTime
        case .UNRECOGNIZED(_):
            break
        }
        group.expiryInfo = expiryInfo

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .groupStanza(group)),
            transform: { (iq) in
                guard let group = HalloGroup(protoGroup: iq.groupStanza) else {
                    return .failure(RequestError.malformedResponse)
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
                    return .failure(RequestError.malformedResponse)
                }
                return .success(group) },
            completion: completion)
    }
}


final class ProtoGroupInviteLinkRequest: ProtoRequest<Server_GroupInviteLink> {

    init(groupID: GroupID, completion: @escaping Completion) {
        var groupInviteLink = Server_GroupInviteLink()
        groupInviteLink.gid = groupID
        groupInviteLink.action = .get

        super.init(
            iqPacket: .iqPacket(type: .get, payload: .groupInviteLink(groupInviteLink)),
            transform: { (iq) in
                return .success(iq.groupInviteLink) },
            completion: completion)
    }
}


final class ProtoResetGroupInviteLinkRequest: ProtoRequest<Server_GroupInviteLink> {

    init(groupID: GroupID, completion: @escaping Completion) {
        var groupInviteLink = Server_GroupInviteLink()
        groupInviteLink.gid = groupID
        groupInviteLink.action = .reset

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .groupInviteLink(groupInviteLink)),
            transform: { (iq) in
                return .success(iq.groupInviteLink) },
            completion: completion)
    }
}


final class ProtoGroupsListRequest: ProtoRequest<HalloGroups> {

    init(completion: @escaping Completion) {
        var groups = Server_GroupsStanza()
        groups.action = .get

        super.init(
            iqPacket: .iqPacket(type: .get, payload: .groupsStanza(groups)),
            transform: { (iq) in
                guard let groups = HalloGroups(protoGroups: iq.groupsStanza) else {
                    return .failure(RequestError.malformedResponse)
                }
                return .success(groups) },
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

final class ProtoGroupAddMemberRequest: ProtoRequest<Void> {

    init(groupID: GroupID, members: [UserID], historyResend: Server_HistoryResend? = nil, completion: @escaping Completion) {
        var group = Server_GroupStanza()
        group.gid = groupID
        group.action = .init(.modifyMembers)
        group.members = members.compactMap { Server_GroupMember(userID: $0, action: .init(.add)) }
        if let historyResend = historyResend {
            group.historyResend = historyResend
        }

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

    init(groupID: GroupID, data: Data?, completion: @escaping Completion) {
        var uploadAvatar = Server_UploadGroupAvatar()
        uploadAvatar.gid = groupID
        uploadAvatar.data = data ?? Data()

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .groupAvatar(uploadAvatar)),
            transform: { (iq) in
                guard let group = HalloGroup(protoGroup: iq.groupStanza), let avatarID = group.avatarID else {
                    return .failure(RequestError.malformedResponse)
                }
                return .success(avatarID) },
            completion: completion)
    }
}

final class ProtoChangeGroupDescriptionRequest: ProtoRequest<String> {

    init(groupID: GroupID, description: String, completion: @escaping Completion) {
        var group = Server_GroupStanza()
        group.gid = groupID
        group.action = .changeDescription
        group.description_p = description

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .groupStanza(group)),
            transform: { iq in
                guard let group = HalloGroup(protoGroup: iq.groupStanza), let description = group.description else {
                    return .failure(RequestError.malformedResponse)
                }
                return .success((description))
            },
            completion: completion)
            
    }
}

final class ProtoSetGroupBackgroundRequest: ProtoRequest<Void> {

    init(groupID: GroupID, background: Int32, completion: @escaping Completion) {
        var group = Server_GroupStanza()
        group.gid = groupID
        group.action = .setBackground

        var protoBackground = Clients_Background()
        protoBackground.theme = background

        if let payload = try? protoBackground.serializedData() {
            group.background = String(decoding: payload, as: UTF8.self)
        }

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .groupStanza(group)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

final class ProtoChangeGroupExpiryRequest: ProtoRequest<Void> {

    init(groupID: GroupID, expiryType: Server_ExpiryInfo.ExpiryType, expirationTime: Int64, completion: @escaping Completion) {
        var groupStanza = Server_GroupStanza()
        groupStanza.gid = groupID
        groupStanza.action = .changeExpiry

        var expiryInfo = Server_ExpiryInfo()
        switch expiryType {
        case .never:
            expiryInfo.expiryType = .never
            // no need to set other fields
            break
        case .expiresInSeconds:
            expiryInfo.expiryType = .expiresInSeconds
            expiryInfo.expiresInSeconds = expirationTime
        case .customDate:
            expiryInfo.expiryType = .customDate
            expiryInfo.expiryTimestamp = expirationTime
        case .UNRECOGNIZED(_):
            break
        }
        groupStanza.expiryInfo = expiryInfo

        super.init(iqPacket: .iqPacket(type: .set, payload: .groupStanza(groupStanza)), transform: { _ in .success(()) }, completion: completion)
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

final class ProtoGetDataExportStatusRequest: ProtoRequest<Server_ExportData> {
    init(isSetRequest: Bool = false, completion: @escaping Completion) {
        let iqPacket: Server_Packet = .iqPacket(type: isSetRequest ? .set : .get, payload: .exportData(Server_ExportData()))
        
        super.init(iqPacket: iqPacket, transform: { response in
            return .success(response.exportData)
        }, completion: completion)

    }
}

final class ProtoDeleteAccountRequest: ProtoRequest<Void> {
    init(phoneNumber: String, feedback: String?, completion: @escaping Completion) {
        var payload = Server_DeleteAccount()
        payload.phone = phoneNumber
        if let feedback = feedback, !feedback.isEmpty {
            payload.feedback = feedback
        }
        let iqPacket: Server_Packet = .iqPacket(type: .set, payload: .deleteAccount(payload))
        
        super.init(iqPacket: iqPacket, transform: { _ in .success(()) }, completion: completion)
    }
}

final class ProtoGetCallServersRequest: ProtoRequest<Server_GetCallServersResult> {
    init(id callID: CallID, for peerUid: Int64, callType: Server_CallType, completion: @escaping Completion) {
        var getCallServersRequest = Server_GetCallServers()
        getCallServersRequest.callID = callID
        getCallServersRequest.callType = callType
        getCallServersRequest.peerUid = peerUid
        let iqPacket: Server_Packet = .iqPacket(type: .get, payload: .getCallServers(getCallServersRequest))
        super.init(iqPacket: iqPacket, transform: { response in return .success(response.getCallServersResult) }, completion: completion)
    }
}

final class ProtoStartCallRequest: ProtoRequest<Server_StartCallResult> {
    init(id callID: CallID, to peerUid: Int64, callType: Server_CallType,
         webRtcOffer: Server_WebRtcSessionDescription, callCapabilities: Server_CallCapabilities, completion: @escaping Completion) {
        var startCallRequest = Server_StartCall()
        startCallRequest.callType = callType
        startCallRequest.callID = callID
        startCallRequest.webrtcOffer = webRtcOffer
        startCallRequest.peerUid = peerUid
        startCallRequest.callCapabilities = callCapabilities
        let iqPacket: Server_Packet = .iqPacket(type: .set, payload: .startCall(startCallRequest))
        super.init(iqPacket: iqPacket, transform: { response in return .success(response.startCallResult) }, completion: completion)
    }
}

final class ProtoExternalShareStoreRequest: ProtoRequest<String> {

    init(encryptedPostData: Data, expiry: Date, ogTagInfo: Server_OgTagInfo, completion: @escaping Completion) {
        var externalSharePost = Server_ExternalSharePost()
        externalSharePost.action = .store
        externalSharePost.blob = encryptedPostData
        externalSharePost.expiresInSeconds = Int64(expiry.timeIntervalSinceNow)
        externalSharePost.ogTagInfo = ogTagInfo
        let iqPacket: Server_Packet = .iqPacket(type: .set, payload: .externalSharePost(externalSharePost))
        super.init(iqPacket: iqPacket, transform: { .success($0.externalSharePost.blobID) }, completion: completion)
    }
}

final class ProtoExternalShareRevokeRequest: ProtoRequest<Void> {

    init(blobID: String, completion: @escaping Completion) {
        var externalSharePost = Server_ExternalSharePost()
        externalSharePost.action = .delete
        externalSharePost.blobID = blobID
        let iqPacket: Server_Packet = .iqPacket(type: .set, payload: .externalSharePost(externalSharePost))
        super.init(iqPacket: iqPacket, transform: { _ in .success(()) }, completion: completion)
    }
}

final class ProtoExternalShareGetRequest: ProtoRequest<Server_ExternalSharePostContainer> {

    init(blobID: String, completion: @escaping Completion) {
        var externalSharePost = Server_ExternalSharePost()
        externalSharePost.blobID = blobID
        externalSharePost.action = .get
        let iqPacket: Server_Packet = .iqPacket(type: .get, payload: .externalSharePost(externalSharePost))
        super.init(iqPacket: iqPacket, transform: { .success($0.externalSharePostContainer) }, completion: completion)
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
        case .get: self = .get
        case .create: self = .create
        case .join: self = .join
        case .leave: self = .leave
        case .delete: self = .delete
        case .changeName: self = .changeName
        case .changeDescription: self = .changeDescription
        case .changeAvatar: self = .changeAvatar
        case .setBackground: self = .setBackground
        case .modifyAdmins: self = .modifyAdmins
        case .modifyMembers: self = .modifyMembers
        case .changeExpiry: self = .changeExpiry
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
        case .join: self = .join
        }
    }
}
