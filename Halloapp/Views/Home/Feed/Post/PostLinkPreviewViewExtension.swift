//
//  PostLinkPreviewViewExtension.swift
//  HalloApp
//
//  Created by Nandini Shetty on 4/19/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//
import CocoaLumberjackSwift
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
            configureMedia(feedMedia: media)
        } else {
            configureView()
        }
    }

    private func configureMedia(feedMedia: FeedMedia) {
        feedMedia.loadImage()
        setupMedia(feedMedia: feedMedia)
        if feedMedia.isMediaAvailable {
            if let image = feedMedia.image {
                show(image: image)
            } else {
                showPlaceholderImage()
                MainAppContext.shared.errorLogger?.logError(FeedMediaError.missingImage)
            }
        } else if imageLoadingCancellable == nil {
            showPlaceholderImage()
            // capture a strong reference to media so it is not deallocated while the image is loading
            imageLoadingCancellable = feedMedia.imageDidBecomeAvailable.receive(on: DispatchQueue.main).sink { [weak self] image in
                guard let self = self else {
                    return
                }
                self.show(image: image)
            }
        }
    }

    private func setupMedia(feedMedia: FeedMedia) {
        feedMedia.loadImage()
        let onMediaStatusChange: (FeedMedia) -> Void = { [weak self] feedMedia in
            guard let self = self else {
                return
            }
            if feedMedia.isDownloadRequired {
                self.showProgressView()
                if let progress = feedMedia.progress {
                    self.setProgress(progress.value, animated: false)
                    self.downloadProgressCancellable = progress
                        .receive(on: DispatchQueue.main)
                        .sink(receiveValue: { [weak self] progress in
                            self?.setProgress(progress, animated: true)
                        })
                } else {
                    // Download task might not be set up yet if feed post has been received and made visible immediately.
                    self.setProgress(0, animated: false)
                }
            } else {
                self.hideProgressView()
                self.downloadProgressCancellable = nil
            }
        }
        onMediaStatusChange(feedMedia)
        mediaStatusCancellable = feedMedia.mediaStatusDidChange.receive(on: DispatchQueue.main).sink(receiveValue: onMediaStatusChange)
    }
}
