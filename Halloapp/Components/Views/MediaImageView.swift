//
//  MediaImageView.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 5/24/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjackSwift
import Combine
import Core
import UIKit

class MediaImageView: UIImageView {

    struct Configuration {
        fileprivate let progressViewSize: CGFloat
        fileprivate let playButtonSize: CGFloat
        fileprivate let maxVideoPreviewSize: CGSize
        fileprivate let useAnimatedVideoPreview: Bool
        fileprivate let videoPreviewLength: TimeInterval = 2
        
        static let groupGrid = Configuration(progressViewSize: 72,
                                             playButtonSize: 32,
                                             maxVideoPreviewSize: CGSize(width: 160, height: 160),
                                             useAnimatedVideoPreview: true)
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

    private var player: AVPlayer?
    private var audioSession: AudioSession?
    private var didPlayToEndCancellable: AnyCancellable?

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

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    // Update as a containing cell's visibility changes.
    var canPlayVideoPreviews = true {
        didSet {
            if let player = player {
                if canPlayVideoPreviews {
                    audioSession = AudioSession(category: .playSilently)
                    AudioSessionManager.beginSession(audioSession)
                    player.play()
                } else {
                    audioSession = nil
                    player.rate = 0
                }
            }
        }
    }

    override var image: UIImage? {
        didSet {
            currentMediaID = nil
            stopPlayingVideo()
            mediaLoadingCancellable?.cancel()
            downloadProgressCancellable?.cancel()
            mediaStatusCancellable?.cancel()
        }
    }

    override var animationImages: [UIImage]? {
        didSet {
            currentMediaID = nil
            stopPlayingVideo()
            mediaLoadingCancellable?.cancel()
            downloadProgressCancellable?.cancel()
            mediaStatusCancellable?.cancel()
        }
    }

    func configure(with feedMedia: FeedMedia) {
        let mediaID = feedMedia.id
        guard mediaID != currentMediaID else {
            return
        }

        currentMediaID = mediaID
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
            videoIndicator.isHidden = configuration.useAnimatedVideoPreview

            if feedMedia.isMediaAvailable, let videoURL = feedMedia.fileURL {
                if configuration.useAnimatedVideoPreview {
                    showMediaVideoLoop(videoURL: videoURL)
                } else {
                    showMediaImage(VideoUtils.videoPreviewImage(url: videoURL, size: configuration.maxVideoPreviewSize))
                }
            } else {
                showPlaceholderImage(for: .video)
                mediaLoadingCancellable = feedMedia.videoDidBecomeAvailable.receive(on: DispatchQueue.main).sink { [weak self] videoURL in
                    guard let self = self else {
                        return
                    }
                    UIView.transition(with: self, duration: 0.1, options: [.curveEaseInOut, .transitionCrossDissolve]) {
                        if self.configuration.useAnimatedVideoPreview {
                            self.showMediaVideoLoop(videoURL: videoURL)
                        } else {
                            self.showMediaImage(VideoUtils.videoPreviewImage(url: videoURL, size: self.configuration.maxVideoPreviewSize))
                        }
                    }
                }
            }
        }
    }

    private func showMediaImage(_ mediaImage: UIImage?) {
        contentMode = .scaleAspectFill
        clipsToBounds = true
        stopPlayingVideo()
        super.image = mediaImage
    }

    private func showPlaceholderImage(for type: CommonMediaType) {
        contentMode = .center
        clipsToBounds = false
        stopPlayingVideo()

        switch type {
        case .audio:
            super.image = UIImage(systemName: "mic")
        case .image:
            super.image = UIImage(systemName: "photo")
        case .video:
            super.image = UIImage(systemName: "video")
        }
    }

    private func showMediaVideoLoop(videoURL: URL) {
        super.image = nil
        clipsToBounds = true

        let asset = AVURLAsset(url: videoURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])

        // Create a custom composition to select only the parts of the video we want to play back.
        // This seems to help with load time...
        let composition = AVMutableComposition()
        let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        if let videoTrack = asset.tracks(withMediaType: .video).first {
            do {
                let duration = asset.duration
                let start = VideoUtils.getThumbnailTime(duration: duration)
                let preferredEnd = CMTimeAdd(start, CMTime(seconds: configuration.videoPreviewLength, preferredTimescale: 1))
                try track?.insertTimeRange(CMTimeRange(start: start, end: CMTimeMinimum(preferredEnd, duration)), of: videoTrack, at: .zero)
            } catch {
                DDLogError("MediaImageView/Could not insert track: \(error)")
            }
        }

        // Video compositions are a set of properties passed to the compositor.
        // We use them to scale the video and disable HDR (which looks bright enough to be out of place).
        let videoComposition = AVMutableVideoComposition(propertiesOf: asset)
        videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        let preferredSize = configuration.maxVideoPreviewSize
        let actualSize = videoComposition.renderSize
        let scale = min(preferredSize.width / actualSize.width, preferredSize.height / actualSize.height) * UIScreen.main.scale
        if scale < 1 {
            videoComposition.renderScale = Float(scale)
        }

        let playerItem = AVPlayerItem(asset: composition)
        playerItem.preferredForwardBufferDuration = 0
        playerItem.videoComposition = videoComposition
        if #available(iOS 14.0, *) {
            playerItem.appliesPerFrameHDRDisplayMetadata = false
        }

        let player: AVPlayer
        if let existingPlayer = self.player {
            player = existingPlayer
        } else {
            player = AVPlayer()
            player.actionAtItemEnd = .pause
            player.allowsExternalPlayback = false
            player.automaticallyWaitsToMinimizeStalling = false
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.isMuted = true
            let playerLayer = layer as! AVPlayerLayer
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            self.player = player
        }

        didPlayToEndCancellable = NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .receive(on: DispatchQueue.main)
            .sink { [player] _ in player.rate = player.currentTime() == CMTime.zero ? 1 : -1 }

        player.replaceCurrentItem(with: playerItem)

        if canPlayVideoPreviews {
            audioSession = AudioSession(category: .playSilently)
            AudioSessionManager.beginSession(audioSession)
            player.playImmediately(atRate: 1.0)
        }
    }

    private func stopPlayingVideo() {
        player?.replaceCurrentItem(with: nil)
        audioSession = nil
        didPlayToEndCancellable = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        videoIndicator.layer.shadowPath = UIBezierPath(ovalIn: videoIndicator.bounds).cgPath
    }

    @objc private func applicationDidBecomeActive() {
        if canPlayVideoPreviews {
            player?.play()
        }
    }

    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
}
