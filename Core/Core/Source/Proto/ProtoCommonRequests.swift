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

        let payload: PBiq.OneOf_Payload
        switch feed {
        case .personal(let audience):
            isGroupFeedRequest = false
            payload = .feedItem(Self.pbFeedItem(post: post, audience: audience))

        case .group(let groupId):
            isGroupFeedRequest = true
            payload = .groupFeedItem(Self.pbGroupFeedItem(post: post, groupId: groupId))
        }

        let packet = PBpacket.iqPacket(type: .set, payload: payload)

        super.init(packet: packet, id: packet.iq.id)
    }

    private static func pbGroupFeedItem(post: FeedPostProtocol, groupId: GroupID) -> PBgroup_feed_item {
        var pbGroupFeedItem = PBgroup_feed_item()
        pbGroupFeedItem.action = .publish
        pbGroupFeedItem.item = .post(post.pbPost)
        pbGroupFeedItem.gid = groupId
        return pbGroupFeedItem
    }

    private static func pbFeedItem(post: FeedPostProtocol, audience: FeedAudience) -> PBfeed_item {
        var pbAudience = PBaudience()
        pbAudience.uids = audience.userIds.compactMap { Int64($0) }
        pbAudience.type = {
            switch audience.privacyListType {
            case .all: return .all
            case .blacklist: return .except
            case .whitelist: return .only
            default:
                DDLogError("ProtoPublishPostRequest/error unsupported audience type \(audience.privacyListType)")
                return .only
            }
        }()

        var pbPost = post.pbPost
        pbPost.audience = pbAudience

        var pbFeedItem = PBfeed_item()
        pbFeedItem.action = .publish
        pbFeedItem.item = .post(pbPost)
        return pbFeedItem
    }

    public override func didFinish(with response: PBpacket) {
        let pbPost = isGroupFeedRequest ? response.iq.groupFeedItem.post : response.iq.feedItem.post
        let timestamp = Date(timeIntervalSince1970: TimeInterval(pbPost.timestamp))
        self.completion(.success(timestamp))
    }

    public override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

public class ProtoPublishCommentRequest: ProtoRequest {
    private let completion: ServiceRequestCompletion<Date?>

    public init(comment: FeedCommentProtocol, completion: @escaping ServiceRequestCompletion<Date?>) {
        self.completion = completion

        var pbFeedItem = PBfeed_item()
        pbFeedItem.action = .publish
        pbFeedItem.item = comment.protoFeedItem(withData: true)

        let packet = PBpacket.iqPacket(type: .set, payload: .feedItem(pbFeedItem))

        super.init(packet: packet, id: packet.iq.id)
    }

    public override func didFinish(with response: PBpacket) {
        let ts = TimeInterval(response.iq.feedItem.comment.timestamp)
        let timestamp = Date(timeIntervalSince1970: ts)
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

        var uploadMedia = PBupload_media()
        uploadMedia.size = Int64(size)

        let packet = PBpacket.iqPacket(type: .get, payload: .uploadMedia(uploadMedia))

        super.init(packet: packet, id: packet.iq.id)
    }

    public override func didFinish(with response: PBpacket) {
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
            packet: PBpacket.iqPacket(type: .get, payload: .props(PBprops())),
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

