//
//  VideoEditViewController.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import AVFoundation
import AVKit
import CocoaLumberjack
import Core
import Dispatch
import Foundation
import PhotosUI
import UIKit

private extension Localizations {

    static var processingFailedTitle: String {
        NSLocalizedString("video.processing.failed.title", value: "Processing video failed", comment: "Alert title in video edit when the processing fails.")
    }

    static var processingFailedMessage: String {
        NSLocalizedString("video.processing.failed.message", value: "Please try again or select another video", comment: "Message in video edit when the processing fails.")
    }

    static var buttonReset: String {
        NSLocalizedString("video.edit.button.reset", value: "Reset", comment: "Button title. Refers to resetting video to original version.")
    }
}

typealias VideoEditViewControllerCallback = (VideoEditViewController, PendingMedia, Bool) -> Void

class VideoEditViewController : UIViewController {
    private let thumbnailsCount = 6

    private let media: PendingMedia
    private let didFinish: VideoEditViewControllerCallback
    private var range: VideoRangeView!
    private let stack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill

        return stack
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
    private let video: VideoView = {
        let view = VideoView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var observerToken: Any?
    private var start = CGFloat(0)
    private var end = CGFloat(1)
    private var isProcessing = false
    private var startTime: CMTime {
        guard let interval = video.player?.currentItem?.duration else { return CMTime() }
        return CMTimeMultiplyByFloat64(interval, multiplier: Float64(start))
    }
    private var endTime: CMTime {
        guard let interval = video.player?.currentItem?.duration else { return CMTime() }
        return CMTimeMultiplyByFloat64(interval, multiplier: Float64(end))
    }
    private var isMuted = false {
        didSet {
            video.player?.isMuted = isMuted
            navigationItem.rightBarButtonItem?.image = muteButtonImage
        }
    }
    private var muteButtonImage: UIImage {
        if isMuted {
            return UIImage(systemName: "speaker.slash.fill", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))!
        } else {
            return UIImage(systemName: "speaker.wave.2.fill", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))!
        }
    }

    init(media: PendingMedia, didFinish: @escaping VideoEditViewControllerCallback) {
        self.media = media
        self.didFinish = didFinish

        if let edit = self.media.videoEdit {
            start = edit.start
            end = edit.end
            isMuted = edit.muted
        }

        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Use init(media:)")
    }

    func withNavigationController() -> UIViewController {
        let controller = UINavigationController(rootViewController: self)
        controller.modalPresentationStyle = .fullScreen

        return controller
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        DDLogInfo("VideoEditViewController/viewDidLoad")

        view.backgroundColor = .black

        setupNavigation()

        range = VideoRangeView(start: start, end: end) { [weak self] start, end in
            guard let self = self else { return }

            self.start = start
            self.end = end

            self.updateDuration()
            self.reset()
        }
        range.translatesAutoresizingMaskIntoConstraints = false

        let footer = makeFooter()

        view.addSubview(stack)
        view.addSubview(range)
        view.addSubview(duration)
        view.addSubview(video)
        view.addSubview(footer)

        NSLayoutConstraint.activate([
            stack.heightAnchor.constraint(equalToConstant: 44),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            range.heightAnchor.constraint(equalToConstant: 44),
            range.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            range.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            range.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            duration.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 8),
            duration.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            video.topAnchor.constraint(equalTo: duration.bottomAnchor, constant: 16),
            video.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            video.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            video.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        if let url = media.originalVideoURL {
            let asset = AVURLAsset(url: url)
            generateThumbnails(asset: asset)

            video.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            video.player?.isMuted = isMuted

            updateDuration()
            reset()
        } else {
            DDLogError("VideoEditViewController/viewDidLoad Missing PendingMedia.videoURL")
        }
    }

    private func setupNavigation() {
        navigationController?.navigationBar.overrideUserInterfaceStyle = .dark

        let backImage = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: backImage, style: .plain, target: self, action: #selector(backAction))

        navigationItem.rightBarButtonItem = UIBarButtonItem(image: muteButtonImage, style: .plain, target: self, action: #selector(muteToggleAction))
    }

    private func makeFooter() -> UIView {
        let footer = UIStackView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.axis = .horizontal
        footer.distribution = .equalSpacing

        let resetBtn = UIButton()
        resetBtn.titleLabel?.font = .gothamFont(ofFixedSize: 15, weight: .medium)
        resetBtn.setTitle(Localizations.buttonReset, for: .normal)
        resetBtn.setTitleColor(.white, for: .normal)
        resetBtn.addTarget(self, action: #selector(resetAction), for: .touchUpInside)
        footer.addArrangedSubview(resetBtn)

        let doneBtn = UIButton()
        doneBtn.titleLabel?.font = .gothamFont(ofFixedSize: 15, weight: .medium)
        doneBtn.setTitle(Localizations.buttonDone, for: .normal)
        doneBtn.setTitleColor(.blue, for: .normal)
        doneBtn.addTarget(self, action: #selector(doneAction), for: .touchUpInside)
        footer.addArrangedSubview(doneBtn)

        return footer
    }

    private func generateThumbnails(asset: AVAsset) {
        var times = [NSValue]()
        for index: Int32 in 0..<Int32(thumbnailsCount) {
            let t = CMTimeMultiplyByRatio(asset.duration, multiplier: index, divisor: Int32(thumbnailsCount))
            times.append(NSValue(time: t))
        }

        var thumbnails = [UIImage]()

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 128, height: 128)
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
                        self.stack.addArrangedSubview(UIImageView(image: image))
                    }
                }
            }
        }
    }

    private func updateDuration() {
        guard let interval = video.player?.currentItem?.duration else { return }
        duration.text = durationFormatter.string(from: interval.seconds * TimeInterval(end - start))
    }

    private func reset() {
        guard let player = video.player else { return }
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

    @objc private func backAction() {
        video.player?.pause()
        didFinish(self, media, true)
    }

    @objc private func muteToggleAction() {
        isMuted = !isMuted
    }

    @objc private func resetAction() {
        start = 0
        end = 1
        isMuted = false
        range.updateRange(start: start, end: end)
        updateDuration()
        reset()
    }

    @objc private func doneAction() {
        guard !isProcessing else { return }
        guard let original = media.originalVideoURL else { return }
        isProcessing = true

        VideoUtils.trim(start: startTime, end: endTime, url: original, mute: isMuted) {[weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isProcessing = false

                switch(result) {
                case .success(let url):
                    self.media.videoEdit = PendingVideoEdit(start: self.start, end: self.end, muted: self.isMuted)
                    self.media.videoURL = url
                    self.media.progress.send(1)
                    self.media.progress.send(completion: .finished)
                    self.media.ready.send(true)
                    self.media.ready.send(completion: .finished)
                    self.didFinish(self, self.media, false)
                case .failure(let error):
                    DDLogWarn("VideoEditViewController/trimming Unable to trim the video url=[\(original.description)] error=[\(error.localizedDescription)]")

                    let alert = UIAlertController(title: Localizations.processingFailedTitle, message: Localizations.processingFailedMessage, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default))
                    self.present(alert, animated: true)
                }
            }
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
