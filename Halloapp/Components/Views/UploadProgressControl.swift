//
//  UploadProgressControl.swift
//  HalloApp
//
//  Created by Tanveer on 6/28/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import Core
import CoreCommon
import CocoaLumberjackSwift

/// A circular progress indicator that tracks the upload of a media post and also
/// offers the ability to retry in the event of a failure.
class UploadProgressControl: UIControl {
    private enum State { case uploading, success, failure }

    private var progressState: State = .uploading

    private(set) var feedPost: FeedPost?
    private var processingCancellable: AnyCancellable?
    private var uploadingCancellable: AnyCancellable?
    private var postStatusCancellable: AnyCancellable?

    private lazy var progressIndicator: ProgressViewContainer = {
        let view = ProgressViewContainer()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Displays either the checkmark or the retry arrow. When it's the latter, the control
    /// is selectable and will fire `onRetry`.
    private lazy var statusIndicator: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.image = statusImage
        view.alpha = 0
        view.preferredSymbolConfiguration = UIImage.SymbolConfiguration(weight: .medium)
        view.contentMode = .scaleAspectFit
        return view
    }()

    private var statusImage: UIImage? {
        switch progressState {
        case .uploading:
            return nil
        case .success where !showSuccessIndicator:
            return nil
        case .success:
            return UIImage(systemName: "checkmark")?.withRenderingMode(.alwaysTemplate)
        case .failure:
            return UIImage(systemName: "arrow.clockwise")?.withRenderingMode(.alwaysTemplate)
        }
    }

    /// When `true`, the control will show a image indicating a successful upload. If `false`,
    /// nothing will be shown.
    var showSuccessIndicator = false
    /// The retry action for when the post fails to upload.
    ///
    /// Since we're directly observing the status of `feedPost`, you should be able to just retry
    /// the upload and have this view refresh automatically.
    var onRetry: (() -> Void)?

    private var progress: Float? {
        didSet {
            updateProgress()
        }
    }

    var lineWidth: CGFloat {
        get { progressIndicator.circleLayer.lineWidth }
        set { progressIndicator.circleLayer.lineWidth = newValue }
    }

    override var isHighlighted: Bool {
        didSet {
            if oldValue != isHighlighted { updateHighlightState() }
        }
    }

    override var tintColor: UIColor! {
        didSet {
            // TODO: switch to tintColorDidChange
            progressIndicator.circleLayer.strokeColor = tintColor.cgColor
            statusIndicator.tintColor = tintColor
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(progressIndicator)
        addSubview(statusIndicator)

        NSLayoutConstraint.activate([
            statusIndicator.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusIndicator.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusIndicator.topAnchor.constraint(equalTo: topAnchor),
            statusIndicator.bottomAnchor.constraint(equalTo: bottomAnchor),

            progressIndicator.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressIndicator.topAnchor.constraint(equalTo: topAnchor),
            progressIndicator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("UploadProgressControl coder init not implemented...")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            progressIndicator.circleLayer.strokeColor = tintColor.cgColor
        }
    }

    func configure(with post: FeedPost) {
        guard post.mediaCount > 0 else {
            DDLogError("UploadProgressControl/configure/feed post with no media")
            return
        }

        feedPost = post
        let postID = post.id
        let mediaCount = post.mediaCount
        let uploader = MainAppContext.shared.feedData.mediaUploader
        let imageServer = ImageServer.shared

        if case .sent = post.status {
            updateState(to: .success)
            return
        }

        updateState(to: .uploading)
        let initialProgress = totalProgress(for: post.id, count: post.mediaCount)
        progress = initialProgress > 0 ? initialProgress : 0.05

        processingCancellable = imageServer.progress
            .compactMap { [weak self] (id: FeedPostID) -> Float? in
                return id != postID ? nil : self?.totalProgress(for: id, count: mediaCount)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.progress = progress
            }

        uploadingCancellable = uploader.uploadProgressDidChange
            .compactMap { [weak self] (id: FeedPostID) -> Float? in
                return id != postID ? nil : self?.totalProgress(for: id, count: mediaCount)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.progress = progress
            }

        postStatusCancellable = post.publisher(for: \.statusValue)
            .sink { [weak self] _ in
                switch post.status {
                case .sending:
                    self?.updateState(to: .uploading, animate: true)
                case .sendError:
                    self?.updateState(to: .failure, animate: true)
                case .sent:
                    self?.updateState(to: .success, animate: true)
                default:
                    break
                }
            }
    }

    private func totalProgress(for postID: FeedPostID, count: Int) -> Float {
        guard count > 0 else {
            return 0
        }

        let count = Float(count)
        let uploader = MainAppContext.shared.feedData.mediaUploader
        let imageServer = ImageServer.shared

        var (processCount, processProgress) = imageServer.progress(for: postID)
        var (uploadCount, uploadProgress) = uploader.uploadProgress(forGroupId: postID)

        processProgress = processProgress * Float(processCount) / count
        uploadProgress = uploadProgress * Float(uploadCount) / count

        return (processProgress + uploadProgress) / 2
    }

    private func updateState(to newState: State, animate: Bool = false) {
        progressState = newState
        var delay: TimeInterval = .zero

        switch animate {
        case true where newState == .success:
            // first fill the circle before hiding it
            delay = 0.3
            animateProgress(to: 1)
            fallthrough
        case true:
            return UIView.animate(withDuration: 0.3, delay: delay) { self.updateState(to: newState, animate: false) }
        case false:
            refreshViewsAfterStateChange()
        }
    }

    private func refreshViewsAfterStateChange() {
        statusIndicator.image = statusImage

        let progressOpacity: CGFloat = progressState == .uploading ? 1 : 0
        let indicatorOpacity: CGFloat = progressState == .uploading ? 0 : 1

        progressIndicator.alpha = progressOpacity
        statusIndicator.alpha = indicatorOpacity
    }

    private func updateHighlightState() {
        guard case .failure = progressState else {
            // this control only works as a button for retries
            return
        }

        statusIndicator.tintColor = isHighlighted ? tintColor.withAlphaComponent(0.75) : tintColor
    }

    private func updateProgress() {
        guard
            let post = feedPost,
            var progress = progress
        else {
            progressIndicator.circleLayer.strokeEnd = 0
            return
        }

        // don't go beyond a certain point if the post isn't uploaded
        let threshold: Float = 0.9
        progress = progress >= threshold && post.status != .sent ? threshold : progress

        animateProgress(to: progress)
    }

    private func animateProgress(to value: Float) {
        let value = CGFloat(value)

        let animation = CABasicAnimation(keyPath: "strokeEnd")

        animation.fromValue = progressIndicator.circleLayer.strokeEnd
        animation.toValue = value
        animation.duration = 0.2
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        progressIndicator.circleLayer.add(animation, forKey: nil)
        progressIndicator.circleLayer.strokeEnd = value
    }

    @objc
    private func retryTapped(_ sender: UIControl) {
        if case .failure = progressState {
            onRetry?()
        }
    }
}

// MARK: - ProgressViewContainer implementation

/// - note: We use this wrapper so that we can animate its `alpha` value in a `UIView` animation block.
fileprivate class ProgressViewContainer: UIView {
    private(set) lazy var circleLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = tintColor.cgColor
        layer.lineWidth = 4
        layer.lineCap = .round
        layer.transform = CATransform3DRotate(layer.transform, -.pi / 2, 0, 0, 1)
        layer.strokeEnd = 0
        return layer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(circleLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("ProgressViewContainer coder init not implemented...")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        circleLayer.frame = bounds
        circleLayer.path = UIBezierPath(ovalIn: bounds).cgPath
    }
}
