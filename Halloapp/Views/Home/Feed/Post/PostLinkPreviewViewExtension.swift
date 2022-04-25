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

        url = feedLinkPreview.url?.host
        title = feedLinkPreview.title

        if let media = feedLinkPreview.feedMedia {
            configureMedia(media: media)
            self.activateViewConstraints(isImagePresent: true)
        } else {
            self.activateViewConstraints(isImagePresent: false)
        }
    }

    private func configureMedia(media: FeedMedia) {
        showPlaceholderImage()
        if media.isMediaAvailable {
            if let image = media.image {
                show(image: image)
            } else {
                showPlaceholderImage()
                MainAppContext.shared.errorLogger?.logError(FeedMediaError.missingImage)
            }
        } else if imageLoadingCancellable == nil {
            showPlaceholderImage()
            // capture a strong reference to media so it is not deallocated while the image is loading
            imageLoadingCancellable = media.imageDidBecomeAvailable.sink { [weak self, media] _ in
                guard let self = self, let image = media.image else { return }
                self.imageLoadingCancellable = nil
                self.show(image: image)
            }
        }
    }
}
