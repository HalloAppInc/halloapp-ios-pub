//
//  MediaImageView.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 5/24/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import Core

class MediaImageView: UIImageView {

    struct Configuration {
        fileprivate let progressViewSize: CGFloat
        fileprivate let playButtonSize: CGFloat

        static let groupGrid = Configuration(progressViewSize: 72, playButtonSize: 32)
    }

    private lazy var videoIndicator: UIImageView = {
        let videoIndicator = UIImageView(image: UIImage(systemName: "play.fill"))
        videoIndicator.contentMode = .center
        videoIndicator.layer.shadowColor = UIColor.black.cgColor
        videoIndicator.layer.shadowOffset = CGSize(width: 0, height: 1)
        videoIndicator.layer.shadowOpacity = 0.3
        videoIndicator.layer.shadowRadius = 4
        videoIndicator.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: configuration.playButtonSize)
        videoIndicator.tintColor = .white
        return videoIndicator
    }()

    private lazy var progressView: CircularProgressView = {
        let progressView = CircularProgressView()
        progressView.barWidth = 2
        progressView.trackTintColor = .systemGray3
        return progressView
    }()

    private let configuration: Configuration

    private var currentMediaID: String?
    private var mediaStatusCancellable: AnyCancellable?
    private var downloadProgressCancellable: AnyCancellable?
    private var mediaLoadingCancellable: AnyCancellable?

    init(configuration: Configuration) {
        self.configuration = configuration
        super.init(frame: .zero)

        videoIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(videoIndicator)

        progressView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressView)

        NSLayoutConstraint.activate([
            videoIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            videoIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressView.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressView.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressView.widthAnchor.constraint(equalToConstant: configuration.progressViewSize),
            progressView.heightAnchor.constraint(equalToConstant: configuration.progressViewSize),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(with feedMedia: FeedMedia) {
        guard feedMedia.id != currentMediaID else {
            return
        }

        currentMediaID = feedMedia.id
        mediaLoadingCancellable?.cancel()
        downloadProgressCancellable?.cancel()
        mediaStatusCancellable?.cancel()

        let onMediaStatusChange: (FeedMedia) -> Void = { [weak self] feedMedia in
            guard let self = self else {
                return
            }
            if feedMedia.isDownloadRequired {
                self.progressView.isHidden = false
                if let progress = feedMedia.progress {
                    self.progressView.setProgress(progress.value, animated: false)
                    self.downloadProgressCancellable = progress
                        .receive(on: DispatchQueue.main)
                        .sink(receiveValue: { [weak self] progress in
                            self?.progressView.setProgress(progress, animated: true)
                        })
                } else {
                    // Download task might not be set up yet if feed post has been received and made visible immediately.
                    self.progressView.setProgress(0, animated: false)
                }
            } else {
                self.progressView.isHidden = true
                self.downloadProgressCancellable = nil
            }
        }
        onMediaStatusChange(feedMedia)
        mediaStatusCancellable = feedMedia.mediaStatusDidChange.sink(receiveValue: onMediaStatusChange)

        switch feedMedia.type {
        case .audio:
            videoIndicator.isHidden = true
            showPlaceholderImage(for: .audio)
            #if DEBUG
            fatalError("MediaImageView cannot support audio")
            #endif
        case .image:
            videoIndicator.isHidden = true
            if feedMedia.isMediaAvailable, let image = feedMedia.image {
                showMediaImage(image)
            } else {
                showPlaceholderImage(for: .image)
                mediaLoadingCancellable = feedMedia.imageDidBecomeAvailable.receive(on: DispatchQueue.main).sink { [weak self] image in
                    guard let self = self else {
                        return
                    }
                    UIView.transition(with: self, duration: 0.1, options: [.curveEaseInOut, .transitionCrossDissolve]) {
                        self.showMediaImage(image)
                    }
                }
            }
        case .video:
            videoIndicator.isHidden = false
            if feedMedia.isMediaAvailable, let videoURL = feedMedia.fileURL {
                showMediaImage(VideoUtils.videoPreviewImage(url: videoURL))
            } else {
                showPlaceholderImage(for: .video)
                mediaLoadingCancellable = feedMedia.videoDidBecomeAvailable.receive(on: DispatchQueue.main).sink { [weak self] videoURL in
                    guard let self = self else {
                        return
                    }
                    UIView.transition(with: self, duration: 0.1, options: [.curveEaseInOut, .transitionCrossDissolve]) {
                        self.showMediaImage(VideoUtils.videoPreviewImage(url: videoURL))
                    }
                }
            }
        }
    }

    private func showMediaImage(_ image: UIImage?) {
        contentMode = .scaleAspectFill
        clipsToBounds = true
        self.image = image
    }

    private func showPlaceholderImage(for type: CommonMediaType) {
        contentMode = .center
        clipsToBounds = false

        switch type {
        case .audio:
            image = UIImage(systemName: "mic")
        case .image:
            image = UIImage(systemName: "photo")
        case .video:
            image = UIImage(systemName: "video")
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        videoIndicator.layer.shadowPath = UIBezierPath(ovalIn: videoIndicator.bounds).cgPath
    }
}
