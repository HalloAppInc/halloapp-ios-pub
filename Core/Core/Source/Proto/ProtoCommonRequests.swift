//
//  ProtoCommonRequests.swift
//  Core
//
//  Created by Garrett on 8/28/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

enum ProtoRequestError: Error {
    case apiResponseMissingMediaURL
}

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
            switch audience.privacyListType {
            case .all: return .all
            case .blacklist: return .except
            case .whitelist: return .only
            default:
                DDLogError("ProtoPublishPostRequest/error unsupported audience type \(audience.privacyListType)")
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

public final class ProtoMediaUploadURLRequest: ProtoRequest<MediaURLInfo> {

    public init(size: Int, completion: @escaping Completion) {
        var uploadMedia = Server_UploadMedia()
        uploadMedia.size = Int64(size)
        let packet = Server_Packet.iqPacket(type: .get, payload: .uploadMedia(uploadMedia))

        super.init(
            iqPacket: packet,
            transform: { (iq) in
                guard iq.uploadMedia.hasURL else {
                    return .failure(ProtoRequestError.apiResponseMissingMediaURL)
                }
                let urls = iq.uploadMedia.url
                if let getURL = URL(string: urls.get), let putURL = URL(string: urls.put) {
                    return .success(.getPut(getURL, putURL))
                } else if let patchURL = URL(string: urls.patch) {
                    return .success(.patch(patchURL))
                } else {
                    return .failure(ProtoRequestError.apiResponseMissingMediaURL)
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

    public init(messageID: String, fromUserID: UserID, toUserID: UserID, identityKey: Data, completion: @escaping Completion) {
        var rerequest = Server_Rerequest()
        rerequest.id = messageID
        rerequest.identityKey = identityKey

        super.init(
            iqPacket: .msgPacket(from: fromUserID, to: toUserID, type: .chat, payload: .rerequest(rerequest)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

public final class ProtoLoggingRequest: ProtoRequest<Void> {

    public init(events: [CountableEvent], completion: @escaping Completion) {
        var clientLog = Server_ClientLog()
        clientLog.counts = events.map { event in
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
        
        super.init(
            iqPacket: .iqPacket(type: .set, payload: .clientLog(clientLog)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}
