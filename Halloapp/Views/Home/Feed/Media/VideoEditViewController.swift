//
//  VideoEditViewController.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import AVFoundation
import AVKit
import CocoaLumberjackSwift
import Core
import CoreCommon
import Combine
import Dispatch
import Foundation
import PhotosUI
import UIKit

class VideoEditViewController : UIViewController {
    private let thumbnailsCount = 6

    private let config: MediaEditConfig
    private let media: MediaEdit

    private lazy var rangeView: VideoRangeView = {
        let rangeView = VideoRangeView(start: media.start, end: media.end) { [weak self] in
            guard let self = self else { return }

            self.updateDuration()

            if self.media.start == self.rangeView.start && self.media.end != self.rangeView.end {
                self.reset(toStart: false)
            } else {
                self.reset(toStart: true)
            }

            self.media.start = self.rangeView.start
            self.media.end = self.rangeView.end
        }

        rangeView.translatesAutoresizingMaskIntoConstraints = false

        return rangeView
    }()

    private lazy var thumbnailsView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill
        stack.clipsToBounds = true
        stack.layer.cornerRadius = 2
        stack.layer.masksToBounds = true

        return stack
    }()

    private lazy var videoView: VideoView = {
        let view = VideoView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.roundCorner(20)

        return view
    }()

    private lazy var trimTimesView: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = self.config.dark ? .white : .label.withAlphaComponent(0.5)

        return label
    }()

    private lazy var playbackView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .primaryBlue

        return view
    }()

    private lazy var playbackPosition: NSLayoutConstraint = {
        playbackView.leadingAnchor.constraint(equalTo: rangeView.leadingAnchor, constant: rangeView.handleRadius - 1)
    }()

    private var endObserverToken, playbackObserverToken: Any?
    private var startTime: CMTime {
        guard let interval = videoView.player?.currentItem?.duration else { return CMTime() }
        guard interval.isNumeric else { return CMTime() }
        return CMTimeMultiplyByFloat64(interval, multiplier: Float64(media.start))
    }
    private var endTime: CMTime {
        guard let interval = videoView.player?.currentItem?.duration else { return CMTime() }
        guard interval.isNumeric else { return CMTime() }
        return CMTimeMultiplyByFloat64(interval, multiplier: Float64(media.end))
    }
    private var cancellableSet: Set<AnyCancellable> = []

    init(_ media: MediaEdit, config: MediaEditConfig) {
        self.media = media
        self.config = config

        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Use init(media:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        DDLogInfo("VideoEditViewController/viewDidLoad")

        view.backgroundColor = config.dark ? .black : .feedBackground
        view.addSubview(trimTimesView)
        view.addSubview(thumbnailsView)
        view.addSubview(playbackView)
        view.addSubview(rangeView)
        view.addSubview(videoView)

        NSLayoutConstraint.activate([
            thumbnailsView.heightAnchor.constraint(equalToConstant: 44),
            thumbnailsView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            thumbnailsView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10 + rangeView.handleRadius),
            thumbnailsView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10 - rangeView.handleRadius),
            rangeView.heightAnchor.constraint(equalToConstant: 44),
            rangeView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            rangeView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            rangeView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            trimTimesView.topAnchor.constraint(equalTo: thumbnailsView.bottomAnchor, constant: 6),
            trimTimesView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            videoView.topAnchor.constraint(equalTo: trimTimesView.bottomAnchor, constant: 9),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            playbackView.centerYAnchor.constraint(equalTo: rangeView.centerYAnchor),
            playbackView.widthAnchor.constraint(equalToConstant: 2),
            playbackView.heightAnchor.constraint(equalTo: rangeView.heightAnchor),
            playbackPosition,
        ])

        guard let url = media.media.originalVideoURL else {
            DDLogError("VideoEditViewController/viewDidLoad Missing PendingMedia.originalVideoURL")
            return
        }

        let asset = AVURLAsset(url: url)
        generateThumbnails(asset: asset)

        videoView.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        videoView.player?.isMuted = media.muted

        observePlayback()
        updateDuration()
        reset()

        cancellableSet.insert(media.$muted.sink { [weak self] in
            guard let self = self else { return }
            self.videoView.player?.isMuted = $0
        })

        cancellableSet.insert(media.$start.sink { [weak self] start in
            guard let self = self else { return }
            guard self.rangeView.start != start else { return }

            DispatchQueue.main.async {
                self.rangeView.updateRange(start: start, end: self.media.end)
                self.updateDuration()
                self.reset()
            }
        })

        cancellableSet.insert(media.$end.sink { [weak self] end in
            guard let self = self else { return }
            guard self.rangeView.end != end else { return }

            DispatchQueue.main.async {
                self.rangeView.updateRange(start: self.media.start, end: end)
                self.updateDuration()
                self.reset()
            }
        })
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateDuration()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        videoView.player?.pause()
        videoView.player = nil
    }

    private func generateThumbnails(asset: AVAsset) {
        guard asset.duration.isNumeric else { return }

        var times = [NSValue]()
        for index: Int32 in 0..<Int32(thumbnailsCount) {
            let t = CMTimeMultiplyByRatio(asset.duration, multiplier: index, divisor: Int32(thumbnailsCount))
            times.append(NSValue(time: t))
        }

        var thumbnails = [UIImage]()

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 256, height: 256)
        generator.generateCGImagesAsynchronously(forTimes: times) { [weak self] _, image, _, result, _ in
            guard let self = self else { return }
            guard result == .succeeded else {
                DDLogWarn("VideoEditViewController/makeThumbnails/warning No thumbnail")
                return
            }
            guard let image = image else { return }

            thumbnails.append(UIImage(cgImage: image))

            if thumbnails.count == self.thumbnailsCount {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    for image in thumbnails {
                        let imageView = UIImageView(image: image)
                        imageView.contentMode = .scaleAspectFill
                        self.thumbnailsView.addArrangedSubview(imageView)
                    }
                }
            }
        }
    }

    private func updateDuration() {
        guard let interval = videoView.player?.currentItem?.duration else { return }
        guard interval.isNumeric else { return }

        parent?.title = TimeInterval(endTime.seconds - startTime.seconds).formatted
        trimTimesView.text = TimeInterval(startTime.seconds).formattedPrecise + " - " + TimeInterval(endTime.seconds).formattedPrecise
    }

    private func observePlayback() {
        guard let player = videoView.player else { return }
        guard let interval = player.currentItem?.duration else { return }
        guard interval.isNumeric else { return }

        playbackObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60), queue: .main) { [weak self] time in
            guard let self = self, player.rate > 0 else { return }

            let currentTime = CGFloat(player.currentTime().seconds)
            let startTime = CGFloat(self.startTime.seconds)
            let endTime = CGFloat(self.endTime.seconds)
            let handleRadius = self.rangeView.handleRadius
            let availableWidth = self.rangeView.frame.width - handleRadius

            let left = availableWidth * self.media.start + handleRadius - 1.0
            let right = availableWidth * self.media.end - 1.0
            let current = (currentTime - startTime) / (endTime - startTime)

            self.playbackPosition.constant = (right - left) * min(max(current, 0.0), 1.0) + left
        }
    }

    private func reset(toStart: Bool = true) {
        guard let player = videoView.player else { return }
        guard player.currentItem != nil else { return }

        player.pause()
        player.seek(to: toStart ? startTime : endTime)

        if let token = endObserverToken {
            player.removeTimeObserver(token)
        }

        var endTimes = [NSValue]()
        endTimes.append(NSValue(time: endTime))
        endObserverToken = player.addBoundaryTimeObserver(forTimes: endTimes, queue: nil) { [weak self] in
            guard let self = self else { return }
            player.pause()
            player.seek(to: self.startTime)
        }
    }
}

private class VideoRangeView : UIView {
    enum DragRegion {
        case start, end, none
    }

    let handleRadius = CGFloat(6)
    let borderWidth = CGFloat(2)
    let borderRadius = CGFloat(2)
    let shadowColor = UIColor.black.withAlphaComponent(0.7)
    let threshold = CGFloat(44)

    private(set) var start: CGFloat
    private(set) var end: CGFloat
    private var dragRegion = DragRegion.none
    private var onChange: () -> Void

    init(start: CGFloat, end: CGFloat, onChange: @escaping () -> Void) {
        self.start = start
        self.end = end
        self.onChange = onChange

        super.init(frame: .zero)

        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func updateRange(start: CGFloat, end: CGFloat) {
        self.start = start
        self.end = end
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard dragRegion == .none else { return }
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        let startDistance = abs(bounds.width * start - location.x)
        let endDistance = abs(bounds.width * end - location.x)

        if startDistance < threshold && endDistance > threshold {
            dragRegion = .start
        } else if startDistance > threshold && endDistance < threshold {
            dragRegion = .end
        } else if startDistance < threshold && endDistance < threshold {
            dragRegion = startDistance < endDistance ? .start : .end
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard dragRegion != .none else { return }
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        let minInterval = 2 * (borderWidth + handleRadius) / bounds.width

        switch dragRegion {
        case .start:
            start = max(0, min(end - minInterval, location.x / bounds.width))
            setNeedsDisplay()
            onChange()
        case .end:
            end = min(1, max(start + minInterval, location.x / bounds.width))
            setNeedsDisplay()
            onChange()
        case .none:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragRegion = .none
        onChange()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragRegion = .none
        onChange()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        drawShadow(rect)
        drawBorder(rect)
    }

    private func drawShadow(_ rect: CGRect) {
        let shadowRect = rect.inset(by: UIEdgeInsets(
            top: 0,
            left: handleRadius,
            bottom: 0,
            right: handleRadius
        ))
        let shadowCutRect = rect.inset(by: UIEdgeInsets(
            top: 0,
            left: (rect.width - handleRadius) * start + handleRadius,
            bottom: 0,
            right: (rect.width - handleRadius) * (1 - end) + handleRadius
        ))
        let path = UIBezierPath(roundedRect: shadowRect, cornerRadius: borderRadius)
        path.append(UIBezierPath(roundedRect: shadowCutRect, cornerRadius: borderRadius))
        path.usesEvenOddFillRule = true
        shadowColor.setFill()
        path.fill()
    }

    private func drawBorder(_ rect: CGRect) {
        let borderRect = rect.inset(by: UIEdgeInsets(
            top: borderWidth / 2,
            left: (rect.width - handleRadius) * start + handleRadius,
            bottom: borderWidth / 2,
            right: (rect.width - handleRadius) * (1 - end) + handleRadius
        ))

        let borderPath = UIBezierPath(roundedRect: borderRect, cornerRadius: borderRadius)
        borderPath.lineWidth = borderWidth
        UIColor.lavaOrange.setStroke()
        borderPath.stroke()

        let leftHandleCenter = CGPoint(x: borderRect.minX, y: borderRect.height / 2)
        let leftHandlePath = UIBezierPath(arcCenter: leftHandleCenter, radius: handleRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        UIColor.lavaOrange.setFill()
        leftHandlePath.fill()

        let rightHandleCenter = CGPoint(x: borderRect.maxX, y: borderRect.height / 2)
        let rightHandlePath = UIBezierPath(arcCenter: rightHandleCenter, radius: handleRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        UIColor.lavaOrange.setFill()
        rightHandlePath.fill()
    }
}
