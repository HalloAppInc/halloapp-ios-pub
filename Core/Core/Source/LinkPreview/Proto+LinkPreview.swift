//
//  Proto+LinkPreview.swift
//  Core
//
//  Created by Nandini Shetty on 9/29/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation

public extension Clients_Text {
    var linkPreviewData: [LinkPreviewData] {
        get {
            var linkPreviewData = [LinkPreviewData]()
            if hasLink {
                var previewImages = [FeedMediaData]()
                link.preview.forEach { preview in
                    if let previewImage = FeedMediaData(id: "", clientImage: preview) {
                        previewImages.append(previewImage)
                    }
                }
                if let linkPreview = LinkPreviewData(url: link.url, title: link.title, description: link.description_p, previewImages: previewImages) { linkPreviewData.append(linkPreview) }
            }
            return linkPreviewData
        }
        set {}
    }
}
