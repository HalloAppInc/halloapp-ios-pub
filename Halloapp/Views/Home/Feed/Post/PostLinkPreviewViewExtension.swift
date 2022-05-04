//
//  PostLinkPreviewViewExtension.swift
//  HalloApp
//
//  Created by Nandini Shetty on 4/19/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//
import Core
import UIKit
import Foundation

extension PostLinkPreviewView {
    func configure(feedLinkPreview: LinkPreviewDisplayable) {
        if feedLinkPreview.url != linkPreviewURL {
            imageLoadingCancellable?.cancel()
            imageLoadingCancellable = nil
        }
        linkPreviewURL = feedLinkPreview.url
        linkPreviewData = LinkPreviewData(id: feedLinkPreview.id, url: feedLinkPreview.url, title: feedLinkPreview.title ?? "", description: feedLinkPreview.desc ?? "", previewImages: [])
        if let media = feedLinkPreview.feedMedia {
            configureView(mediaSize: feedLinkPreview.feedMedia?.size)
            configureMedia(media: media)
        } else {
            configureView()
        }
    }

    private func configureMedia(media: FeedMedia) {
        if media.isMediaAvailable {
            if let image = media.image {
                show(image: image)
            } else {
                MainAppContext.shared.errorLogger?.logError(FeedMediaError.missingImage)
            }
        } else if imageLoadingCancellable == nil {
            // capture a strong reference to media so it is not deallocated while the image is loading
            imageLoadingCancellable = media.imageDidBecomeAvailable.sink { [weak self] _ in
                guard let self = self, let image = media.image else { return }
                self.show(image: image)
            }
        }
    }
}
