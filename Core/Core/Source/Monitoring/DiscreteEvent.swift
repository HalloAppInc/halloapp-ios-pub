//
//  DiscreteEvent.swift
//  Core
//
//  Created by Garrett on 1/20/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation

public enum DiscreteEvent {
    case mediaUpload(postID: String, duration: TimeInterval, numPhotos: Int, numVideos: Int, totalSize: Int)
    case mediaDownload(postID: String, duration: TimeInterval, numPhotos: Int, numVideos: Int, totalSize: Int)
    case pushReceived(id: String, timestamp: Date)
    case decryptionReport(id: String, result: String, clientVersion: String, sender: UserAgent, rerequestCount: Int, timeTaken: TimeInterval, isSilent: Bool)
    case groupDecryptionReport(id: String, gid: String, contentType: String, error: String, clientVersion: String, sender: UserAgent?, rerequestCount: Int, timeTaken: TimeInterval)
    case callReport(id: String, peerUserID: UserID, type: String, direction: String, networkType: String, answered: Bool, connected: Bool, duration_ms: Int, endCallReason: String, localEndCall: Bool, webrtcStats: String)
}

extension DiscreteEvent: Codable {

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let eventType = try container.decode(EventType.self, forKey: .eventType)

        switch eventType {
        case .mediaUpload:
            let postID = try container.decode(String.self, forKey: .id)
            let duration = try container.decode(TimeInterval.self, forKey: .duration)
            let numPhotos = try container.decode(Int.self, forKey: .numPhotos)
            let numVideos = try container.decode(Int.self, forKey: .numVideos)
            let totalSize = try container.decode(Int.self, forKey: .totalSize)
            self = .mediaUpload(postID: postID, duration: duration, numPhotos: numPhotos, numVideos: numVideos, totalSize: totalSize)
        case .mediaDownload:
            let postID = try container.decode(String.self, forKey: .id)
            let duration = try container.decode(TimeInterval.self, forKey: .duration)
            let numPhotos = try container.decode(Int.self, forKey: .numPhotos)
            let numVideos = try container.decode(Int.self, forKey: .numVideos)
            let totalSize = try container.decode(Int.self, forKey: .totalSize)
            self = .mediaDownload(postID: postID, duration: duration, numPhotos: numPhotos, numVideos: numVideos, totalSize: totalSize)
        case .pushReceived:
            let id = try container.decode(String.self, forKey: .id)
            let timestamp = try container.decode(Date.self, forKey: .timestamp)
            self = .pushReceived(id: id, timestamp: timestamp)
        case .decryptionReport:
            let id = try container.decode(String.self, forKey: .id)
            let result = try container.decode(String.self, forKey: .result)
            let clientVersion = try container.decode(String.self, forKey: .version)
            let sender = try container.decode(UserAgent.self, forKey: .sender)
            let rerequestCount = try container.decode(Int.self, forKey: .count)
            let timeTaken = try container.decode(TimeInterval.self, forKey: .duration)
            let isSilent = try container.decode(Bool.self, forKey: .silent)
            self = .decryptionReport(id: id, result: result, clientVersion: clientVersion, sender: sender, rerequestCount: rerequestCount, timeTaken: timeTaken, isSilent: isSilent)
        case .groupDecryptionReport:
            let id = try container.decode(String.self, forKey: .id)
            let gid = try container.decode(String.self, forKey: .gid)
            let contentType = try container.decode(String.self, forKey: .contentType)
            let error = try container.decode(String.self, forKey: .error)
            let clientVersion = try container.decode(String.self, forKey: .version)
            let sender = try container.decode(UserAgent.self, forKey: .sender)
            let rerequestCount = try container.decode(Int.self, forKey: .count)
            let timeTaken = try container.decode(TimeInterval.self, forKey: .duration)
            self = .groupDecryptionReport(id: id, gid: gid, contentType: contentType, error: error, clientVersion: clientVersion, sender: sender, rerequestCount: rerequestCount, timeTaken: timeTaken)
        case .callReport:
            let id = try container.decode(String.self, forKey: .id)
            let peerUserID = try container.decode(String.self, forKey: .peerUserID)
            let type = try container.decode(String.self, forKey: .type)
            let direction = try container.decode(String.self, forKey: .direction)
            let networkType = try container.decode(String.self, forKey: .networkType)
            let answered = try container.decode(Bool.self, forKey: .answered)
            let connected = try container.decode(Bool.self, forKey: .connected)
            let duration_ms = try container.decode(Int.self, forKey: .duration)
            let endCallReason = try container.decode(String.self, forKey: .endCallReason)
            let localEndCall = try container.decode(Bool.self, forKey: .localEndCall)
            let webrtcStats = try container.decode(String.self, forKey: .webrtcStats)
            self = .callReport(id: id, peerUserID: peerUserID, type: type, direction: direction, networkType: networkType, answered: answered, connected: connected, duration_ms: duration_ms, endCallReason: endCallReason, localEndCall: localEndCall, webrtcStats: webrtcStats)

        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .mediaDownload(let postID, let duration, let numPhotos, let numVideos, let totalSize):
            try container.encode(EventType.mediaDownload, forKey: .eventType)
            try container.encode(postID, forKey: .id)
            try container.encode(duration, forKey: .duration)
            try container.encode(numPhotos, forKey: .numPhotos)
            try container.encode(numVideos, forKey: .numVideos)
            try container.encode(totalSize, forKey: .totalSize)
        case .mediaUpload(let postID, let duration, let numPhotos, let numVideos, let totalSize):
            try container.encode(EventType.mediaUpload, forKey: .eventType)
            try container.encode(postID, forKey: .id)
            try container.encode(duration, forKey: .duration)
            try container.encode(numPhotos, forKey: .numPhotos)
            try container.encode(numVideos, forKey: .numVideos)
            try container.encode(totalSize, forKey: .totalSize)
        case .pushReceived(let id, let timestamp):
            try container.encode(EventType.pushReceived, forKey: .eventType)
            try container.encode(id, forKey: .id)
            try container.encode(timestamp, forKey: .timestamp)
        case .decryptionReport(let id, let result, let clientVersion, let sender, let rerequestCount, let timeTaken, let isSilent):
            try container.encode(EventType.decryptionReport, forKey: .eventType)
            try container.encode(id, forKey: .id)
            try container.encode(clientVersion, forKey: .version)
            try container.encode(result, forKey: .result)
            try container.encode(sender, forKey: .sender)
            try container.encode(rerequestCount, forKey: .count)
            try container.encode(timeTaken, forKey: .duration)
            try container.encode(isSilent, forKey: .silent)
        case .groupDecryptionReport(let id, let gid, let contentType, let error, let clientVersion, let sender, let rerequestCount, let timeTaken):
            try container.encode(EventType.groupDecryptionReport, forKey: .eventType)
            try container.encode(id, forKey: .id)
            try container.encode(gid, forKey: .gid)
            try container.encode(contentType, forKey: .contentType)
            try container.encode(error, forKey: .error)
            try container.encode(clientVersion, forKey: .version)
            try container.encode(sender, forKey: .sender)
            try container.encode(rerequestCount, forKey: .count)
            try container.encode(timeTaken, forKey: .duration)
        case .callReport(let id, let peerUserID, let type, let direction, let networkType, let answered, let connected, let duration_ms, let endCallReason, let localEndCall, let webrtcStats):
            try container.encode(EventType.callReport, forKey: .eventType)
            try container.encode(id, forKey: .id)
            try container.encode(peerUserID, forKey: .peerUserID)
            try container.encode(type, forKey: .type)
            try container.encode(direction, forKey: .direction)
            try container.encode(networkType, forKey: .networkType)
            try container.encode(answered, forKey: .answered)
            try container.encode(connected, forKey: .connected)
            try container.encode(duration_ms, forKey: .duration)
            try container.encode(endCallReason, forKey: .endCallReason)
            try container.encode(localEndCall, forKey: .localEndCall)
            try container.encode(webrtcStats, forKey: .webrtcStats)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case count
        case duration
        case eventType
        case id
        case numPhotos
        case numVideos
        case result
        case sender
        case timestamp
        case totalSize
        case version
        case silent
        case error
        case contentType
        case gid
        case peerUserID
        case type
        case direction
        case networkType
        case answered
        case connected
        case endCallReason
        case localEndCall
        case webrtcStats
    }

    private enum EventType: String, Codable {
        case mediaDownload
        case mediaUpload
        case pushReceived
        case decryptionReport
        case groupDecryptionReport
        case callReport
    }
}
