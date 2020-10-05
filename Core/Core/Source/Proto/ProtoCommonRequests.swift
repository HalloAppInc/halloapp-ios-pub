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

public class ProtoPublishPostRequest: ProtoRequest {
    private let completion: ServiceRequestCompletion<Date?>
    private let isGroupFeedRequest: Bool

    public init(post: FeedPostProtocol, feed: Feed, completion: @escaping ServiceRequestCompletion<Date?>) {
        self.completion = completion

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

        super.init(packet: packet, id: packet.iq.id)
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

    public override func didFinish(with response: Server_Packet) {
        let serverPost = isGroupFeedRequest ? response.iq.groupFeedItem.post : response.iq.feedItem.post
        let timestamp = Date(timeIntervalSince1970: TimeInterval(serverPost.timestamp))
        self.completion(.success(timestamp))
    }

    public override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

public class ProtoPublishCommentRequest: ProtoRequest {
    private let completion: ServiceRequestCompletion<Date?>
    private let isGroupFeedRequest: Bool

    public init(comment: FeedCommentProtocol, groupId: GroupID?, completion: @escaping ServiceRequestCompletion<Date?>) {
        self.completion = completion

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

        super.init(packet: packet, id: packet.iq.id)
    }

    public override func didFinish(with response: Server_Packet) {
        let serverComment = isGroupFeedRequest ? response.iq.groupFeedItem.comment : response.iq.feedItem.comment
        let timestamp = Date(timeIntervalSince1970: TimeInterval(serverComment.timestamp))
        self.completion(.success(timestamp))
    }

    public override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

public class ProtoMediaUploadURLRequest: ProtoRequest {

    private let completion: ServiceRequestCompletion<MediaURLInfo>

    public init(size: Int, completion: @escaping ServiceRequestCompletion<MediaURLInfo>) {
        self.completion = completion

        var uploadMedia = Server_UploadMedia()
        uploadMedia.size = Int64(size)

        let packet = Server_Packet.iqPacket(type: .get, payload: .uploadMedia(uploadMedia))

        super.init(packet: packet, id: packet.iq.id)
    }

    public override func didFinish(with response: Server_Packet) {
        guard response.iq.uploadMedia.hasURL else {
            completion(.failure(ProtoRequestError.apiResponseMissingMediaURL))
            return
        }
        let urls = response.iq.uploadMedia.url
        if let getURL = URL(string: urls.get), let putURL = URL(string: urls.put) {
            completion(.success(.getPut(getURL, putURL)))
        } else if let patchURL = URL(string: urls.patch) {
            completion(.success(.patch(patchURL)))
        } else {
            completion(.failure(ProtoRequestError.apiResponseMissingMediaURL))
        }
    }

    public override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

public class ProtoGetServerPropertiesRequest: ProtoStandardRequest<ServerPropertiesResponse> {
    public init(completion: @escaping ServiceRequestCompletion<ServerPropertiesResponse>) {
        super.init(
            packet: Server_Packet.iqPacket(type: .get, payload: .props(Server_Props())),
            transform: { response in
                let version = response.iq.props.hash.toHexString()
                let properties: [String: String] = Dictionary(
                    uniqueKeysWithValues: response.iq.props.props.map { ($0.name, $0.value) }
                )
                return .success((version: version, properties: properties))
            },
            completion: completion)
    }
}

