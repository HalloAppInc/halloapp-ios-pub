//
//  ProtoCommonRequests.swift
//  Core
//
//  Created by Garrett on 8/28/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//
import CocoaLumberjackSwift
import CoreCommon
import Foundation

public final class ProtoPublishCommentRequest: ProtoRequest<Date> {

    public init?(comment: CommentData, groupId: GroupID?, completion: @escaping Completion) {
        guard let serverComment = comment.serverComment else {
            return nil
        }
        var isGroupFeedRequest: Bool

        let payload: Server_Iq.OneOf_Payload
        if let groupId = groupId {
            isGroupFeedRequest = true

            var pbGroupFeedItem = Server_GroupFeedItem()
            pbGroupFeedItem.action = .publish
            pbGroupFeedItem.item = .comment(serverComment)
            pbGroupFeedItem.gid = groupId

            payload = .groupFeedItem(pbGroupFeedItem)
        } else {
            isGroupFeedRequest = false

            var pbFeedItem = Server_FeedItem()
            pbFeedItem.action = .publish
            pbFeedItem.item = .comment(serverComment)

            payload = .feedItem(pbFeedItem)
        }
        
        let packet = Server_Packet.iqPacket(type: .set, payload: payload)

        super.init(
            iqPacket: packet,
            transform: { (iq) in
                let serverComment = isGroupFeedRequest ? iq.groupFeedItem.comment : iq.feedItem.comment
                let timestamp = Date(timeIntervalSince1970: TimeInterval(serverComment.timestamp))
                return .success(timestamp)
            },
            completion: completion)
    }
}

public final class ProtoMediaUploadURLRequest: ProtoRequest<(MediaURLInfo?)> {

    public init(type: Server_UploadMedia.TypeEnum, size: Int, downloadURL: URL?, completion: @escaping Completion) {
        var uploadMedia = Server_UploadMedia()
        uploadMedia.type = type
        uploadMedia.size = Int64(size)
        uploadMedia.downloadURL = downloadURL?.absoluteString ?? ""
        let packet = Server_Packet.iqPacket(type: .get, payload: .uploadMedia(uploadMedia))

        super.init(
            iqPacket: packet,
            transform: { (iq) in
                guard iq.uploadMedia.hasURL || !iq.uploadMedia.downloadURL.isEmpty else {
                    return .failure(RequestError.malformedResponse)
                }

                let urls = iq.uploadMedia.url

                if let downloadURL = URL(string: iq.uploadMedia.downloadURL) {
                    return .success(.download(downloadURL))
                } else if let getURL = URL(string: urls.get), let putURL = URL(string: urls.put) {
                    return .success(.getPut(getURL, putURL))
                } else if let patchURL = URL(string: urls.patch) {
                    return .success(.patch(patchURL))
                } else {
                    return .failure(RequestError.malformedResponse)
                }
            },
            completion: completion)
    }
}

final class ProtoGroupInfoRequest: ProtoRequest<XMPPGroup> {

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

public final class ProtoGroupFeedRerequest: ProtoRequest<Void> {

    public init(groupID: String, contentId: String, fromUserID: UserID, toUserID: UserID, rerequestType: GroupFeedRerequestType, contentType: GroupFeedRerequestContentType, completion: @escaping Completion) {
        // TODO: change this to be a message stanza asap.
        var rerequest = Server_GroupFeedRerequest()
        rerequest.gid = groupID
        rerequest.id = contentId
        rerequest.rerequestType = rerequestType
        rerequest.contentType = contentType

        super.init(
            iqPacket: .msgPacket(from: fromUserID, to: toUserID, type: .groupchat, payload: .groupFeedRerequest(rerequest)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

final class ProtoGroupMemberKeysRequest: ProtoRequest<Server_GroupStanza> {

    init(groupID: GroupID, completion: @escaping Completion) {
        var group = Server_GroupStanza()
        group.gid = groupID
        group.action = .getMemberIdentityKeys

        super.init(
            iqPacket: .iqPacket(type: .get, payload: .groupStanza(group)),
            transform: { (iq) in return .success(iq.groupStanza) },
            completion: completion)
    }
}

final class ProtoWhisperCollectionKeysRequest: ProtoRequest<Server_WhisperKeysCollection> {

    init(members: [UserID], completion: @escaping Completion) {
        let memberWhisperKeys: [Server_WhisperKeys] = members.map { memberUserID in
            var whisperKeys = Server_WhisperKeys()
            whisperKeys.action = .get
            if let uid = Int64(memberUserID) {
                whisperKeys.uid = uid
            }
            return whisperKeys
        }

        var collection = Server_WhisperKeysCollection()
        collection.collection = memberWhisperKeys
        super.init(
            iqPacket: .iqPacket(type: .get, payload: .whisperKeysCollection(collection)),
            transform: { (iq) in return .success(iq.whisperKeysCollection) },
            completion: completion)
    }
}
