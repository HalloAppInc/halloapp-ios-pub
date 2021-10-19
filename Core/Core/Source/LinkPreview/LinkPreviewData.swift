//
//  LinkPreviewData.swift
//  Core
//
//  Created by Nandini Shetty on 9/29/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Foundation

public protocol LinkPreviewProtocol {
    var id: FeedLinkPreviewID? { get }
    var url: URL { get }
    var title: String { get }
    var description: String { get }
    var previewImages: [FeedMediaData] { get }
}

public struct LinkPreviewData: LinkPreviewProtocol {

    public var id: FeedLinkPreviewID?
    public var url: URL

    public var title: String

    public var description: String

    public var previewImages: [FeedMediaData]


    public init?(id: FeedLinkPreviewID?, url: String, title: String, description: String, previewImages: [FeedMediaData]) {
        guard let url = URL(string: url) else {
            DDLogError("LinkPreviewData/error invalid url [\(url)]")
            return nil
        }
        self.init(id: id, url: url, title: title, description: description, previewImages: previewImages)
    }

    public init?(id: FeedLinkPreviewID?, url: URL?, title: String, description: String, previewImages: [FeedMediaData]) {
        guard let url = url else {
            DDLogError("LinkPreviewData/error invalid url")
            return nil
        }

        self.id = id
        self.url = url
        self.title = title
        self.description = description
        self.previewImages = previewImages
    }
}

public extension LinkPreviewProtocol {
    var mediaCounters: MediaCounters {
        var counters = MediaCounters()
        previewImages.forEach { mediaItem in
            switch mediaItem.type {
            case .image:
                counters.numImages += 1
            case .video:
                counters.numVideos += 1
            case .audio:
                counters.numAudio += 1
            }
        }
        return counters
    }
}
