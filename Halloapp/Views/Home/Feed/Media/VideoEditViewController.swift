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
import Combine
import Dispatch
import Foundation
import PhotosUI
import UIKit

class VideoEditViewController : UIViewController {
    private let thumbnailsCount = 6

    private let media: MediaEdit
    private var rangeView: VideoRangeView!
    private let thumbnailsView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill
        stack.clipsToBounds = true

        return stack
    }()
    private let videoView: VideoView = {
        let view = VideoView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let duration: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        label.textColor = .white

        return label
    }()
    private let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .dropTrailing
        formatter.allowedUnits = [.second, .minute]

        return formatter
    }()

    private var observerToken: Any?
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

    init(_ media: MediaEdit) {
        self.media = media

        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Use init(media:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        DDLogInfo("VideoEditViewController/viewDidLoad")

        rangeView = VideoRangeView(start: media.start, end: media.end) { [weak self] start, end in
            guard let self = self else { return }
            guard self.media.start != start || self.media.end != end else { return }

            self.media.start = start
            self.media.end = end
        }
        rangeView.translatesAutoresizingMaskIntoConstraints = false

        view.backgroundColor = .black
        view.addSubview(thumbnailsView)
        view.addSubview(rangeView)
        view.addSubview(duration)
        view.addSubview(videoView)

        NSLayoutConstraint.activate([
            thumbnailsView.heightAnchor.constraint(equalToConstant: 44),
            thumbnailsView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            thumbnailsView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            thumbnailsView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            rangeView.heightAnchor.constraint(equalToConstant: 44),
            rangeView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            rangeView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            rangeView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            duration.topAnchor.constraint(equalTo: thumbnailsView.bottomAnchor, constant: 8),
            duration.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            videoView.topAnchor.constraint(equalTo: duration.bottomAnchor, constant: 16),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        guard let url = media.media.originalVideoURL else {
            DDLogError("VideoEditViewController/viewDidLoad Missing PendingMedia.originalVideoURL")
            return
        }

        let asset = AVURLAsset(url: url)
        generateThumbnails(asset: asset)

        videoView.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        videoView.player?.isMuted = media.muted

        updateDuration()
        reset()

        cancellableSet.insert(media.$muted.sink { [weak self] in
            guard let self = self else { return }
            self.videoView.player?.isMuted = $0
        })

        cancellableSet.insert(media.$start.sink { [weak self] start in
            guard let self = self else { return }

            self.rangeView.updateRange(start: start, end: self.media.end)
            self.updateDuration()
            self.reset()
        })

        cancellableSet.insert(media.$end.sink { [weak self] end in
            guard let self = self else { return }

            self.rangeView.updateRange(start: self.media.start, end: end)
            self.updateDuration()
            self.reset()
        })
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
        duration.text = durationFormatter.string(from: interval.seconds * TimeInterval(media.end - media.start))
    }

    private func reset() {
        guard let player = videoView.player else { return }
        guard player.currentItem != nil else { return }

        player.pause()
        player.seek(to: startTime)

        if let token = observerToken {
            player.removeTimeObserver(token)
        }

        var endTimes = [NSValue]()
        endTimes.append(NSValue(time: endTime))
        observerToken = player.addBoundaryTimeObserver(forTimes: endTimes, queue: nil) { [weak self] in
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

    private let borderWidth = CGFloat(2)
    private let shadowColor = UIColor.black.withAlphaComponent(0.7)
    private let threshold = CGFloat(44)

    private var start: CGFloat
    private var end: CGFloat
    private var dragRegion = DragRegion.none
    private var onChange: (CGFloat, CGFloat) -> Void

    init(start: CGFloat, end: CGFloat, onChange: @escaping (CGFloat, CGFloat) -> Void) {
        self.start = start
        self.end = end
        self.onChange = onChange

        super.init(frame: .zero)

        backgroundColor = .clear

        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(onDrag(sender:)))
        recognizer.maximumNumberOfTouches = 1
        addGestureRecognizer(recognizer)

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func updateRange(start: CGFloat, end: CGFloat) {
        self.start = start
        self.end = end
        setNeedsDisplay()
    }

    @objc private func onDrag(sender: UIPanGestureRecognizer) {
        let location = sender.location(in: self)

        switch sender.state {
        case .began:
            let startDistance = abs(bounds.width * start - location.x)
            let endDistance = abs(bounds.width * end - location.x)

            if startDistance < threshold && endDistance > threshold {
                dragRegion = .start
            } else if startDistance > threshold && endDistance < threshold {
                dragRegion = .end
            } else if startDistance < threshold && endDistance < threshold {
                dragRegion = startDistance < endDistance ? .start : .end
            }
        case .changed:
            switch dragRegion {
            case .start:
                start = max(0, min(end, location.x / bounds.width))
                setNeedsDisplay()
                onChange(start, end)
            case .end:
                end = min(1, max(start, location.x / bounds.width))
                setNeedsDisplay()
                onChange(start, end)
            default:
                break
            }
        case .ended, .cancelled:
            dragRegion = .none
        default:
            break
        }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        drawShadow(rect)
        drawBorder(rect)
    }

    private func drawShadow(_ rect: CGRect) {
        let shadowCut = rect.inset(by: UIEdgeInsets(top: 0, left: rect.width * start, bottom: 0, right: rect.width * (1 - end)))
        let path = UIBezierPath(rect: rect)
        path.append(UIBezierPath(rect: shadowCut))
        path.usesEvenOddFillRule = true
        shadowColor.setFill()
        path.fill()
    }

    private func drawBorder(_ rect: CGRect) {
        let borderRect = rect.inset(by: UIEdgeInsets(top: borderWidth / 2, left: rect.width * start, bottom: borderWidth / 2, right: rect.width * (1 - end)))

        let borderPath = UIBezierPath(rect: borderRect)
        borderPath.lineWidth = borderWidth
        UIColor.white.setStroke()
        borderPath.stroke()

        let leftHandleCenter = CGPoint(x: borderRect.minX, y: borderRect.height / 2)
        let leftHandlePath = UIBezierPath(arcCenter: leftHandleCenter, radius: 6, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        UIColor.white.setFill()
        leftHandlePath.fill()

        let rightHandleCenter = CGPoint(x: borderRect.maxX, y: borderRect.height / 2)
        let rightHandlePath = UIBezierPath(arcCenter: rightHandleCenter, radius: 6, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        UIColor.white.setFill()
        rightHandlePath.fill()
    }
}
