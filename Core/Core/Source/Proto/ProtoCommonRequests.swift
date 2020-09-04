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

    public init(post: FeedPostProtocol, audience: FeedAudience, completion: @escaping ServiceRequestCompletion<Date?>) {
        self.completion = completion

        var pbFeedItem = PBfeed_item()
        pbFeedItem.action = .publish
        pbFeedItem.item = post.protoFeedItem(withData: true)

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

        let packet = PBpacket.iqPacket(type: .set, payload: .feedItem(pbFeedItem))

        super.init(packet: packet, id: packet.iq.id)
    }

    public override func didFinish(with response: PBpacket) {
        var timestamp: Date?
        if let ts: TimeInterval = TimeInterval(response.iq.payload.feedItem.post.timestamp) {
            timestamp = Date(timeIntervalSince1970: ts)
        }
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
        var timestamp: Date?
        if let ts: TimeInterval = TimeInterval(response.iq.payload.feedItem.comment.timestamp) {
            timestamp = Date(timeIntervalSince1970: ts)
        }
        self.completion(.success(timestamp))
    }

    public override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

public class ProtoMediaUploadURLRequest: ProtoRequest {

    private let completion: ServiceRequestCompletion<MediaURL>

    public init(size: Int, completion: @escaping ServiceRequestCompletion<MediaURL>) {
        self.completion = completion

        var uploadMedia = PBupload_media()
        uploadMedia.size = Int64(size)

        let packet = PBpacket.iqPacket(type: .get, payload: .uploadMedia(uploadMedia))

        super.init(packet: packet, id: packet.iq.id)
    }

    public override func didFinish(with response: PBpacket) {
        let urls = response.iq.payload.uploadMedia.url
        guard response.iq.payload.uploadMedia.hasURL,
            let getURL = URL(string: urls.get), let putURL = URL(string: urls.put) else
        {
            completion(.failure(ProtoRequestError.apiResponseMissingMediaURL))
            return
        }
        completion(.success(MediaURL(get: getURL, put: putURL)))
    }

    public override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

public class ProtoGetServerPropertiesRequest: ProtoRequest {
    public typealias ServerPropsResponse = (String, [String:String])

    private let completion: ServiceRequestCompletion<ServerPropsResponse>

    public init(completion: @escaping ServiceRequestCompletion<ServerPropsResponse>) {
        self.completion = completion

        // TODO (waiting for schema)
        var packet = PBpacket.iqPacketWithID()

        super.init(packet: packet, id: packet.iq.id)
    }

    public override func didFinish(with response: PBpacket) {
        completion(.failure(ProtoServiceCoreError.unimplemented))
    }

    public override func didFail(with error: Error) {
        completion(.failure(error))
    }
}

