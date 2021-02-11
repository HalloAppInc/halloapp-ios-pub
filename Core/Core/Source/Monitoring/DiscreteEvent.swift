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
        }
    }

    private enum CodingKeys: String, CodingKey {
        case duration
        case eventType
        case id
        case numPhotos
        case numVideos
        case timestamp
        case totalSize
    }

    private enum EventType: String, Codable {
        case mediaDownload
        case mediaUpload
        case pushReceived
    }
}
