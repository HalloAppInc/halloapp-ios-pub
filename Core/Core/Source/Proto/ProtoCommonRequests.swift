//
//  ProtoCommonRequests.swift
//  Core
//
//  Created by Garrett on 8/28/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjack
import Foundation

public final class ProtoPublishPostRequest: ProtoRequest<Date> {

    public init(post: FeedPostProtocol, feed: Feed, completion: @escaping Completion) {
        var isGroupFeedRequest: Bool
        let payload: Server_Iq.OneOf_Payload
        switch feed {
        case .personal(let audience):
            isGroupFeedRequest = false
            payload = .feedItem(Self.pbFeedItem(post: post, audience: audience))

        case .group(let groupId):
            isGroupFeedRequest = true
            payload = .groupFeedItem(Self.pbGroupFeedItem(post: post, groupId: groupId))
        }

        let packet = Server_Packet.iqPacket(type: .set, payload: payload)

        super.init(
            iqPacket: packet,
            transform: { (iq) in
                let serverPost = isGroupFeedRequest ? iq.groupFeedItem.post : iq.feedItem.post
                let timestamp = Date(timeIntervalSince1970: TimeInterval(serverPost.timestamp))
                return .success(timestamp)
            },
            completion: completion)
    }

    private static func pbGroupFeedItem(post: FeedPostProtocol, groupId: GroupID) -> Server_GroupFeedItem {
        var pbGroupFeedItem = Server_GroupFeedItem()
        pbGroupFeedItem.action = .publish
        pbGroupFeedItem.item = .post(post.serverPost)
        pbGroupFeedItem.gid = groupId
        return pbGroupFeedItem
    }

    private static func pbFeedItem(post: FeedPostProtocol, audience: FeedAudience) -> Server_FeedItem {
        var serverAudience = Server_Audience()
        serverAudience.uids = audience.userIds.compactMap { Int64($0) }
        serverAudience.type = {
            switch audience.audienceType {
            case .all: return .all
            case .blacklist: return .except
            case .whitelist: return .only
            default:
                DDLogError("ProtoPublishPostRequest/error unsupported audience type \(audience.audienceType)")
                return .only
            }
        }()

        var serverPost = post.serverPost
        serverPost.audience = serverAudience

        var pbFeedItem = Server_FeedItem()
        pbFeedItem.action = .publish
        pbFeedItem.item = .post(serverPost)
        return pbFeedItem
    }
}

public final class ProtoPublishCommentRequest: ProtoRequest<Date> {

    public init(comment: FeedCommentProtocol, groupId: GroupID?, completion: @escaping Completion) {
        var isGroupFeedRequest: Bool

        let payload: Server_Iq.OneOf_Payload
        if let groupId = groupId {
            isGroupFeedRequest = true

            var pbGroupFeedItem = Server_GroupFeedItem()
            pbGroupFeedItem.action = .publish
            pbGroupFeedItem.item = .comment(comment.serverComment)
            pbGroupFeedItem.gid = groupId

            payload = .groupFeedItem(pbGroupFeedItem)
        } else {
            isGroupFeedRequest = false

            var pbFeedItem = Server_FeedItem()
            pbFeedItem.action = .publish
            pbFeedItem.item = .comment(comment.serverComment)

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

public final class ProtoMediaUploadURLRequest: ProtoRequest<(MediaURLInfo?, URL?)> {

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
                    return .success((nil, downloadURL))
                } else if let getURL = URL(string: urls.get), let putURL = URL(string: urls.put) {
                    return .success((.getPut(getURL, putURL), nil))
                } else if let patchURL = URL(string: urls.patch) {
                    return .success((.patch(patchURL), nil))
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
