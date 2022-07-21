//
//  GroupGridProgressControl.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 7/7/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

class GroupGridProgressView: UIView {

    private struct Constants {
        static let indicatorSize: CGFloat = 50
    }

    enum State {
        case hidden, uploading, failed
    }

    private(set) var progress: CGFloat = 0
    private(set) var state: State = .hidden

    var cancelAction: (() -> Void)?
    var retryAction: (() -> Void)?
    var deleteAction: (() -> Void)?

    private let cancelButton: UIButton = {
        let cancelButton = UIButton(type: .system)
        cancelButton.setImage(UIImage(systemName: "xmark")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)), for: .normal)
        cancelButton.tintColor = .white
        return cancelButton
    }()

    private let retryButton: UIButton = {
        let retryIcon = UIImage(systemName: "arrow.clockwise")
        let retryButton = UIButton(type: .system)
        retryButton.imageEdgeInsets = UIEdgeInsets(top: -2, left: 0, bottom: 2, right: 0)
        retryButton.setImage(retryIcon?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)), for: .normal)
        retryButton.tintColor = .white
        return retryButton
    }()

    private let deleteButton: UIButton = {
        let deleteButton = RoundedRectButton()
        deleteButton.backgroundTintColor = .lavaOrange
        deleteButton.tintColor = .white
        deleteButton.setImage(UIImage(systemName: "trash.fill"), for: .normal)
        return deleteButton
    }()

    private let progressIndicator = GroupGridProgressIndicator()

    private let backgroundView: UIVisualEffectView = {
        let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        backgroundView.clipsToBounds = true
        backgroundView.layer.cornerRadius = Constants.indicatorSize * 0.5
        return backgroundView
    }()

    private let postFailedLabel: UILabel = {
        let postFailedLabel = UILabel()
        postFailedLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        postFailedLabel.text = Localizations.groupGridPostFailed
        postFailedLabel.textColor = .white
        return postFailedLabel
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = UIColor.black.withAlphaComponent(0.4)

        cancelButton.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        retryButton.addTarget(self, action: #selector(retryButtonTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteButtonTapped), for: .touchUpInside)
        progressIndicator.setProgress(0)

        [backgroundView, postFailedLabel, cancelButton, progressIndicator, deleteButton, retryButton].forEach { view in
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            backgroundView.centerXAnchor.constraint(equalTo: centerXAnchor),
            backgroundView.centerYAnchor.constraint(equalTo: centerYAnchor),
            backgroundView.widthAnchor.constraint(equalToConstant: 50),
            backgroundView.heightAnchor.constraint(equalToConstant: 50),

            cancelButton.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            cancelButton.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

            retryButton.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            retryButton.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            retryButton.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            retryButton.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

            progressIndicator.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            progressIndicator.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            progressIndicator.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

            postFailedLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            postFailedLabel.bottomAnchor.constraint(equalTo: backgroundView.topAnchor, constant: -12),
            postFailedLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),

            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            deleteButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            deleteButton.widthAnchor.constraint(equalToConstant: 32),
            deleteButton.heightAnchor.constraint(equalToConstant: 32),
        ])

        updateState()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func setState(_ state: State, animated: Bool) {
        let previousState = self.state
        guard state != previousState else {
            return
        }
        self.state = state

        if animated {
            let updateStateAnimated = {
                UIView.animate(withDuration: 0.1, delay: 0.0, options: [.allowAnimatedContent, .beginFromCurrentState], animations: self.updateState)
            }
            switch (previousState, state) {
            case (.uploading, .hidden):
                progressIndicator.setProgress(1.0, animated: true) {
                    updateStateAnimated()
                }
            default:
                updateStateAnimated()
            }
        } else {
            updateState()
        }
    }

    private func updateState() {
        var selfAlpha: CGFloat = 1.0
        var uploadViewAlpha: CGFloat = 0.0
        var failedViewAlpha: CGFloat = 0.0

        switch state {
        case .uploading:
            uploadViewAlpha = 1.0
        case .failed:
            failedViewAlpha = 1.0
        case .hidden:
            selfAlpha = 0.0
        }

        cancelButton.alpha = uploadViewAlpha
        progressIndicator.alpha = uploadViewAlpha
        deleteButton.alpha = failedViewAlpha
        retryButton.alpha = failedViewAlpha
        postFailedLabel.alpha = failedViewAlpha
        alpha = selfAlpha
    }

    func setProgress(_ progress: Float, animated: Bool = false) {
        progressIndicator.setProgress(CGFloat(progress), animated: animated)
    }

    @objc private func cancelButtonTapped() {
        cancelAction?()
    }

    @objc private func retryButtonTapped() {
        retryAction?()
    }

    @objc private func deleteButtonTapped() {
        deleteAction?()
    }
}

// MARK: - GroupGridProgressControl

private class GroupGridProgressIndicator: UIView {

    private struct Constants {
        static let progressColor = UIColor.lavaOrange
        static let trackColor = UIColor.white.withAlphaComponent(0.7)
        static let lineWidth: CGFloat = 4
    }

    private let trackShapeLayer: CAShapeLayer = {
        let trackShapeLayer = CAShapeLayer()
        trackShapeLayer.fillColor = UIColor.clear.cgColor
        trackShapeLayer.lineCap = .square
        trackShapeLayer.lineWidth = Constants.lineWidth
        return trackShapeLayer
    }()

    private let progressShapeLayer: CAShapeLayer = {
        let progressShapeLayer = CAShapeLayer()
        progressShapeLayer.fillColor = UIColor.clear.cgColor
        progressShapeLayer.lineCap = .square
        progressShapeLayer.lineWidth = Constants.lineWidth
        return progressShapeLayer
    }()

    func setProgress(_ progress: CGFloat, animated: Bool = false, completion: (() -> Void)? = nil) {
        guard progressShapeLayer.strokeEnd != progress else {
            completion?()
            return
        }

        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        CATransaction.setDisableActions(!animated)
        progressShapeLayer.strokeEnd = progress
        CATransaction.commit()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = false

        layer.addSublayer(trackShapeLayer)
        layer.addSublayer(progressShapeLayer)
        updateLayerColors()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let path = UIBezierPath(arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
                                radius: (min(bounds.width, bounds.height) - Constants.lineWidth) / 2.0,
                                startAngle: -0.5 * .pi,
                                endAngle: 1.5 * .pi,
                                clockwise: true)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackShapeLayer.frame = bounds
        trackShapeLayer.path = path.cgPath
        progressShapeLayer.frame = bounds
        progressShapeLayer.path = path.cgPath
        CATransaction.commit()
    }

    private func updateLayerColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackShapeLayer.strokeColor = Constants.trackColor.cgColor
        progressShapeLayer.strokeColor = Constants.progressColor.cgColor
        CATransaction.commit()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateLayerColors()
        }
    }
}

private extension Localizations {

    static var groupGridPostFailed: String {
        NSLocalizedString("groupGrid.post.failed", value: "Failed to post", comment: "Shown when post fails or is canceled.")
    }
}
