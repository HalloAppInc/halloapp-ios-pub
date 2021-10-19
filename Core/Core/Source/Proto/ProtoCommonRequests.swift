//
//  ProtoCommonRequests.swift
//  Core
//
//  Created by Garrett on 8/28/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
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

    public init(size: Int, downloadURL: URL?, completion: @escaping Completion) {
        var uploadMedia = Server_UploadMedia()
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

public final class ProtoGetServerPropertiesRequest: ProtoRequest<ServerPropertiesResponse> {

    public init(completion: @escaping Completion) {
        super.init(
            iqPacket: .iqPacket(type: .get, payload: .props(Server_Props())),
            transform: { (iq) in
                let version = iq.props.hash.toHexString()
                let properties: [String: String] = Dictionary(
                    uniqueKeysWithValues: iq.props.props.map { ($0.name, $0.value) }
                )
                return .success((version: version, properties: properties))
            },
            completion: completion)
    }
}

public final class ProtoMessageRerequest: ProtoRequest<Void> {

    public init(messageID: String, fromUserID: UserID, toUserID: UserID, rerequestData: RerequestData, completion: @escaping Completion) {
        var rerequest = Server_Rerequest()
        rerequest.id = messageID
        rerequest.identityKey = rerequestData.identityKey
        rerequest.signedPreKeyID = Int64(rerequestData.signedPreKeyID)
        rerequest.oneTimePreKeyID = Int64(rerequestData.oneTimePreKeyID ?? 0)
        rerequest.sessionSetupEphemeralKey = rerequestData.sessionSetupEphemeralKey
        rerequest.messageEphemeralKey = rerequestData.messageEphemeralKey ?? Data()

        super.init(
            iqPacket: .msgPacket(from: fromUserID, to: toUserID, type: .chat, payload: .rerequest(rerequest)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

public final class ProtoGroupFeedRerequest: ProtoRequest<Void> {

    public init(groupID: String, contentId: String, fromUserID: UserID, toUserID: UserID, rerequestType: GroupFeedRerequestType, completion: @escaping Completion) {
        var rerequest = Server_GroupFeedRerequest()
        rerequest.gid = groupID
        rerequest.id = contentId
        rerequest.rerequestType = rerequestType

        super.init(
            iqPacket: .msgPacket(from: fromUserID, to: toUserID, type: .groupchat, payload: .groupFeedRerequest(rerequest)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

public final class ProtoLoggingRequest: ProtoRequest<Void> {

    public init(countableEvents: [CountableEvent], discreteEvents: [DiscreteEvent], completion: @escaping Completion) {
        var clientLog = Server_ClientLog()
        clientLog.counts = countableEvents.map { event in
            var count = Server_Count()
            count.namespace = event.namespace
            count.metric = event.metric
            count.count = Int64(event.count)
            count.dims = event.dimensions.map { (name, value) in
                var dim = Server_Dim()
                dim.name = name
                dim.value = value
                return dim
            }
            return count
        }
        clientLog.events = discreteEvents.map { $0.eventData }
        
        super.init(
            iqPacket: .iqPacket(type: .set, payload: .clientLog(clientLog)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

public final class ProtoSendNameRequest: ProtoRequest<Void> {

    public init(name: String, completion: @escaping Completion) {
        var serverName = Server_Name()
        serverName.name = name

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .name(serverName)),
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

public final class ProtoGroupPreviewWithLinkRequest: ProtoRequest<Server_GroupInviteLink> {

    public init(inviteLink: String, completion: @escaping Completion) {
        var groupInviteLink = Server_GroupInviteLink()
        groupInviteLink.action = .preview
        groupInviteLink.link = inviteLink

        super.init(
            iqPacket: .iqPacket(type: .get, payload: .groupInviteLink(groupInviteLink)),
            transform: { (iq) in
                return .success(iq.groupInviteLink) },
            completion: completion)
    }
}

public final class ProtoJoinGroupWithLinkRequest: ProtoRequest<Server_GroupInviteLink> {

    public init(inviteLink: String, completion: @escaping Completion) {
        var groupInviteLink = Server_GroupInviteLink()
        groupInviteLink.action = .join
        groupInviteLink.link = inviteLink

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .groupInviteLink(groupInviteLink)),
            transform: { (iq) in
                return .success(iq.groupInviteLink) },
            completion: completion)
    }
}

private extension DiscreteEvent {
    var eventData: Server_EventData {
        var eventData = Server_EventData()
        eventData.edata = eData
        eventData.platform = .ios
        eventData.version = AppContext.appVersionForService
        return eventData
    }

    private var eData: Server_EventData.OneOf_Edata {
        switch self {
        case .mediaUpload(let postID, let duration, let numPhotos, let numVideos, let totalSize):
            var upload = Server_MediaUpload()
            upload.id = postID
            upload.durationMs = UInt32(duration * 1000)
            upload.numPhotos = UInt32(numPhotos)
            upload.numVideos = UInt32(numVideos)
            upload.totalSize = UInt32(totalSize)
            return .mediaUpload(upload)

        case .mediaDownload(let postID, let duration, let numPhotos, let numVideos, let totalSize):
            var download = Server_MediaDownload()
            download.id = postID
            download.durationMs = UInt32(duration * 1000)
            download.numPhotos = UInt32(numPhotos)
            download.numVideos = UInt32(numVideos)
            download.totalSize = UInt32(totalSize)
            return .mediaDownload(download)

        case .pushReceived(let id, let timestamp):
            var push = Server_PushReceived()
            push.id = id
            push.clientTimestamp = UInt64(timestamp.timeIntervalSince1970)
            return .pushReceived(push)

        case .decryptionReport(let id, let result, let clientVersion, let sender, let rerequestCount, let timeTaken, let isSilent):
            var report = Server_DecryptionReport()
            report.msgID = id
            if result == "success" {
                report.result = .ok
            } else {
                report.result = .fail
                report.reason = result
            }
            report.originalVersion = clientVersion
            report.senderVersion = sender.version
            report.senderPlatform = sender.platform.serverPlatform
            report.rerequestCount = UInt32(rerequestCount)
            report.timeTakenS = UInt32(timeTaken)
            report.isSilent = isSilent
            return .decryptionReport(report)

        case .groupDecryptionReport(let id, let gid, let contentType, let error, let clientVersion, let sender, let rerequestCount, let timeTaken):
            var report = Server_GroupDecryptionReport()
            // This is contentID
            report.contentID = id
            report.gid = gid
            if contentType == "post" {
                report.itemType = .post
            } else {
                report.itemType = .comment
            }
            if error.isEmpty {
                report.result = .ok
            } else {
                report.result = .fail
                report.reason = error
            }
            report.senderVersion = sender?.version ?? ""
            report.senderPlatform = sender?.platform.serverPlatform ?? Server_Platform.unknown
            report.originalVersion = clientVersion
            report.rerequestCount = UInt32(rerequestCount)
            report.timeTakenS = UInt32(timeTaken)
            return .groupDecryptionReport(report)

        }
    }
}

extension UserAgent.Platform {
    var serverPlatform: Server_Platform {
        switch self {
        case .android: return .android
        case .ios: return .ios
        }
    }
}
