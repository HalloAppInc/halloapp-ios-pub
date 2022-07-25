//
//  MediaExplorerVideoCell.swift
//  HalloApp
//
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import AVKit
import CocoaLumberjackSwift
import Core
import CoreCommon
import Combine
import Foundation
import UIKit

class MediaExplorerVideoCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    static var reuseIdentifier: String {
        return String(describing: MediaExplorerVideoCell.self)
    }

    public weak var scrollView: UIScrollView?
    private var originalOffset = CGPoint.zero
    private var scale: CGFloat = 1
    private let spaceBetweenPages: CGFloat = 20
    private var readyCancellable: AnyCancellable?
    private var progressCancellable: AnyCancellable?
    private var mediaPlaybackCancellable: AnyCancellable?
    private var streamingResourceLoaderDelegate: AVAssetResourceLoaderDelegate?
    private var videoConstraints: [NSLayoutConstraint] = []
    private var animator: UIDynamicAnimator?
    private var videoViewWidth: CGFloat = .zero
    private var videoViewHeight: CGFloat = .zero
    
    private var width: CGFloat {
        videoViewWidth * scale
    }
    private var height: CGFloat {
        videoViewHeight * scale
    }
    private var minX: CGFloat {
        video.center.x - width / 2
    }
    private var maxX: CGFloat {
        video.center.x + width / 2
    }
    private var minY: CGFloat {
        video.center.y - height / 2
    }
    private var maxY: CGFloat {
        video.center.y + height / 2
    }

    private(set) lazy var video: VideoView = {
        let view = VideoView(playbackControls: .custom)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var placeHolderView: UIImageView = {
        let placeHolderImageView = UIImageView(image: UIImage(systemName: "video"))
        placeHolderImageView.contentMode = .center
        placeHolderImageView.translatesAutoresizingMaskIntoConstraints = false
        placeHolderImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .largeTitle)
        placeHolderImageView.tintColor = .white
        placeHolderImageView.isHidden = true

        return placeHolderImageView
    }()

    private lazy var progressView: CircularProgressView = {
        let progressView = CircularProgressView()
        progressView.barWidth = 2
        progressView.progressTintColor = .lavaOrange
        progressView.trackTintColor = .white
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.isHidden = true

        return progressView
    }()
    private var looper: AVPlayerLooper?

    var isSystemUIHidden = false

    override func prepareForReuse() {
        super.prepareForReuse()

        video.player?.pause()
        video.player = nil
        media = nil
        readyCancellable?.cancel()
        progressCancellable?.cancel()
        readyCancellable = nil
        progressCancellable = nil
    }

    var media: MediaExplorerMedia? {
        didSet {
            guard let media = media else { return }

            if let url = media.url,
               let chunkedInfo = media.chunkedInfo,
               chunkedInfo.blobVersion == .chunked,
               let remoteURL = chunkedInfo.remoteURL,
               let placeholderURL = ChunkedMediaResourceLoaderDelegate.remoteURLToPlaceholderURL(from: remoteURL),
               let streamingResourceLoaderDelegate = try? ChunkedMediaResourceLoaderDelegate(chunkedInfo: chunkedInfo, fileURL: url) {
                self.streamingResourceLoaderDelegate = streamingResourceLoaderDelegate
                let videoAsset = AVURLAsset(url: placeholderURL)
                videoAsset.resourceLoader.setDelegate(streamingResourceLoaderDelegate, queue: ChunkedMediaResourceLoaderDelegate.resourceLoadingingQueue)
                show(videoAsset: videoAsset)
            } else if let url = media.url {
                show(url: url)
            } else {
                show(progress: media.progress.value)

                readyCancellable = media.ready.sink { [weak self] ready in
                    guard let self = self else { return }
                    guard ready else { return }
                    guard let url = self.media?.url else { return }
                    self.show(url: url)
                }

                progressCancellable = media.progress.sink { [weak self] value in
                    guard let self = self else { return }
                    self.progressView.setProgress(value, animated: true)
                }
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(placeHolderView)
        contentView.addSubview(progressView)
        contentView.addSubview(video)
        contentView.addSubview(video.timeSeekView)
        contentView.addSubview(video.playButton)

        NSLayoutConstraint.activate([
            placeHolderView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            placeHolderView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            progressView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            progressView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            progressView.widthAnchor.constraint(equalToConstant: 80),
            progressView.heightAnchor.constraint(equalToConstant: 80),
            video.timeSeekView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            video.timeSeekView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            video.timeSeekView.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            video.playButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            video.playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        mediaPlaybackCancellable = MainAppContext.shared.mediaDidStartPlaying.sink { [weak self] url in
            guard let self = self else { return }
            guard self.media?.url != url else { return }
            self.pause()
        }
        
        let pinchRecognizer = UIPinchGestureRecognizer(target:self, action: #selector(handlePinch(sender:)))
        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(sender:)))
        
        panRecognizer.delegate = self
        
        addGestureRecognizer(pinchRecognizer)
        addGestureRecognizer(panRecognizer)
        
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        video.player?.pause()
        video.player = nil
    }

    func show(videoAsset: AVURLAsset) {
        placeHolderView.isHidden = true
        progressView.isHidden = true
        video.isHidden = false

        computeConstraints()

        let item = AVPlayerItem(asset: videoAsset)
        let player = AVQueuePlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        looper = AVPlayerLooper(player: player, templateItem: item)
        video.player = player
    }

    func show(url: URL) {
        placeHolderView.isHidden = true
        progressView.isHidden = true
        video.isHidden = false

        computeConstraints()

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        looper = AVPlayerLooper(player: player, templateItem: item)
        video.player = player
    }

    func show(progress: Float) {
        placeHolderView.isHidden = false
        progressView.isHidden = false
        progressView.setProgress(progress, animated: false)
        video.isHidden = true
        video.player?.pause()
        video.player = nil
    }

    func play(time: CMTime = .zero) {
        MainAppContext.shared.mediaDidStartPlaying.send(media?.url)

        video.player?.seek(to: time)
        video.player?.play()
    }

    func pause() {
        video.player?.pause()
    }

    func togglePlay() {
        if !isPlaying() {
            MainAppContext.shared.mediaDidStartPlaying.send(media?.url)
        }

        video.togglePlay()
    }

    func currentTime() -> CMTime {
        guard let player = video.player else { return .zero }
        return player.currentTime()
    }

    func isPlaying() -> Bool {
        guard let player = video.player else { return false }
        return player.rate > 0
    }

    func computeConstraints() {
        guard let media = media else { return }
        media.computeSize()

        NSLayoutConstraint.deactivate(videoConstraints)

        if media.size.width > 0 && media.size.height > 0 {
            let scale = min((contentView.frame.width - spaceBetweenPages * 2) / media.size.width, contentView.frame.height / media.size.height)
            let width = media.size.width * scale
            let height = media.size.height * scale

            videoConstraints = [
                video.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                video.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                video.widthAnchor.constraint(equalToConstant: width),
                video.heightAnchor.constraint(equalToConstant: height),
            ]
        } else {
            videoConstraints = [
                video.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spaceBetweenPages),
                video.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spaceBetweenPages),
                video.topAnchor.constraint(equalTo: contentView.topAnchor),
                video.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ]
        }

        NSLayoutConstraint.activate(videoConstraints)
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer.view == otherGestureRecognizer.view && otherGestureRecognizer is UIPinchGestureRecognizer
    }
    
    @objc private func handlePinch(sender: UIPinchGestureRecognizer) {
        guard let scrollView = scrollView else { return }
        
        if sender.state == .began {
            originalOffset = scrollView.contentOffset
            
            let temp = video.center
            animator?.removeAllBehaviors()
            video.center = temp
        }
        
        if sender.state == .began || sender.state == .changed {
            guard sender.numberOfTouches > 1 else { return }

            let location = [
                sender.location(ofTouch: 0, in: contentView),
                sender.location(ofTouch: 1, in: contentView),
            ]

            let gestureCenterX = (location[0].x + location[1].x) / 2
            let gestureCenterY = (location[0].y + location[1].y) / 2
            video.center.x += (gestureCenterX - video.center.x) * (1 - sender.scale)
            video.center.y += (gestureCenterY - video.center.y) * (1 - sender.scale)

            scale *= sender.scale
            video.transform = CGAffineTransform(scaleX: scale, y: scale)

            sender.scale = 1
        }
        if sender.state == .ended {
            if scale < 1 {
                scale = 1
                animate(scale: scale, center: CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY))
            }
        }
    }
    

    @objc private func handlePan(sender: UIPanGestureRecognizer) {
        guard let scrollView = scrollView else { return }

        if sender.state == .began {
            originalOffset = scrollView.contentOffset

            let temp = video.center
            animator?.removeAllBehaviors()
            video.center = temp
        }

        if sender.state == .began || sender.state == .changed {
            var translation = sender.translation(in: window)

            // when scrolling horizontally, if page changing has begun it has priority
            if scrollView.contentOffset.x > originalOffset.x {
                let translate = min(scrollView.contentOffset.x - originalOffset.x, translation.x)
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x - translate, y: scrollView.contentOffset.y), animated: false)
                translation.x -= translate
            } else if scrollView.contentOffset.x < originalOffset.x {
                let translate = max(scrollView.contentOffset.x - originalOffset.x, translation.x)
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x - translate, y: scrollView.contentOffset.y), animated: false)
                translation.x -= translate
            }

            // translate horizontally up to the image border
            if translation.x > 0 && minX < spaceBetweenPages {
                video.center.x += min(translation.x, spaceBetweenPages - minX)
                translation.x = max(translation.x - spaceBetweenPages + minX, 0)
            } else if translation.x < 0 && maxX > contentView.bounds.maxX - spaceBetweenPages {
                video.center.x += max(translation.x, contentView.bounds.maxX - spaceBetweenPages - maxX)
                translation.x = min(translation.x - contentView.bounds.maxX + spaceBetweenPages + maxX, 0)
            }

            if translation.y > 0 && minY < 0 {
                video.center.y += min(translation.y, -minY)
            } else if translation.y < 0 && maxY > contentView.bounds.maxY {
                video.center.y += max(translation.y, contentView.bounds.maxY - maxY)
            }

            if translation.x != 0 {
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x - translation.x, y: scrollView.contentOffset.y), animated: false)
            }

            sender.setTranslation(.zero, in: window)
        } else if sender.state == .ended {
            let velocity = sender.velocity(in: window)

            if shouldScrollPage(velocity: abs(velocity.x) > abs(velocity.y) ? velocity.x : 0) {
                scale = 1
                animate(scale: scale, center: CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY))
                scrollPage(velocity: velocity.x)
            } else {
                if scale > 1 {
                    addInertialMotion(velocity: velocity)
                }

                scrollView.setContentOffset(originalOffset, animated: true)
            }
        }
    }

    private func animate(scale: CGFloat, center: CGPoint) {
        UIView.animate(withDuration: 0.35) { [weak self] in
            guard let self = self else { return }
            self.video.transform = CGAffineTransform(scaleX: scale, y: scale)
            self.video.center = center
        }
    }
    
    private func shouldScrollPage(velocity: CGFloat) -> Bool {
        guard let scrollView = scrollView else { return false }

        let offset = originalOffset.x + scrollView.frame.width * (velocity > 0 ? -1 : 1)
        if offset >= 0 && offset < scrollView.contentSize.width {
            let diff = scrollView.contentOffset.x - originalOffset.x
            return (abs(diff) > scrollView.frame.width / 2) || (abs(diff) > 0 && abs(velocity) > 200)
        }

        return false
    }

    private func scrollPage(velocity: CGFloat) {
        guard let scrollView = scrollView else { return }

        let offset = originalOffset.x + scrollView.frame.width * (velocity > 0 ? -1 : 1)

        if offset >= 0 && offset < scrollView.contentSize.width {
            let distance = scrollView.contentOffset.x - offset
            let duration = min(TimeInterval(abs(distance / velocity)), 0.3)

            UIView.animate(withDuration: duration) {
                scrollView.setContentOffset(CGPoint(x: offset, y: self.originalOffset.y), animated: false)
                scrollView.layoutIfNeeded()
            }
        }
    }
    
    private func addInertialMotion(velocity: CGPoint) {
        var imageVelocity = CGPoint.zero
        let boundMinX: CGFloat, boundMaxX: CGFloat, boundMinY: CGFloat, boundMaxY: CGFloat

        // UICollisionBehavior doesn't take into account transform scaling
        if width > bounds.width {
            boundMinX = contentView.bounds.maxX - spaceBetweenPages - width / 2 - videoViewWidth / 2
            boundMaxX = contentView.bounds.minX + spaceBetweenPages + width / 2 + videoViewWidth / 2
            imageVelocity.x = velocity.x
        } else {
            boundMinX = contentView.bounds.midX - videoViewWidth / 2
            boundMaxX = contentView.bounds.midX + videoViewWidth / 2
        }

        // UICollisionBehavior doesn't take into account transform scaling
        if height > bounds.height {
            boundMinY = contentView.bounds.maxY - height / 2 - videoViewHeight / 2
            boundMaxY = contentView.bounds.minY + height / 2 + videoViewHeight / 2
            imageVelocity.y = velocity.y
        } else {
            boundMinY = contentView.bounds.midY - videoViewHeight / 2
            boundMaxY = contentView.bounds.midY + videoViewHeight / 2
        }

        let dynamicBehavior = UIDynamicItemBehavior(items: [video])
        dynamicBehavior.addLinearVelocity(imageVelocity, for: video)
        dynamicBehavior.resistance = 10

        // UIKit Dynamics resets the transform and ignores scale
        dynamicBehavior.action = { [weak self] in
            guard let self = self else { return }
            self.video.transform = CGAffineTransform(scaleX: self.scale, y: self.scale)
        }
        animator?.addBehavior(dynamicBehavior)

        let boundaries = CGRect(x: boundMinX, y: boundMinY, width: boundMaxX - boundMinX, height: boundMaxY - boundMinY)
        let collisionBehavior = UICollisionBehavior(items: [video])
        collisionBehavior.addBoundary(withIdentifier: NSString("boundaries"), for: UIBezierPath(rect: boundaries))
        animator?.addBehavior(collisionBehavior)
    }
}
