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
    var url: URL { get }
    var title: String { get }
    var description: String { get }
    var previewImages: [FeedMediaData] { get }
}

public struct LinkPreviewData: LinkPreviewProtocol {

    public var url: URL

    public var title: String

    public var description: String

    public var previewImages: [FeedMediaData]

    public init?(url: String, title: String, description: String, previewImages: [FeedMediaData]) {
        guard let url = URL(string: url) else {
            DDLogError("LinkPreviewData/error invalid url [\(url)]")
            return nil
        }
        self.init(url: url, title: title, description: description, previewImages: previewImages)
    }

    public init?(url: URL?, title: String, description: String, previewImages: [FeedMediaData]) {
        guard let url = url else {
            DDLogError("LinkPreviewData/error invalid url")
            return nil
        }
        self.url = url
        self.title = title
        self.description = description
        self.previewImages = previewImages
    }
}
