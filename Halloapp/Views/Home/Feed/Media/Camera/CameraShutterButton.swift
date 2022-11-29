//
//  CameraShutterButton.swift
//  HalloApp
//
//  Created by Tanveer on 6/8/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

extension CameraShutterButton {

    private static let primaryWhite = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            return .white.withAlphaComponent(0.9)
        default:
            return .feedPostBackground
        }
    }

    private static let primaryGray = UIColor(red: 0.19, green: 0.19, blue: 0.19, alpha: 0.7)
    private static let outerRingWidth: CGFloat = 6
}


class CameraShutterButton: UIControl {

    enum State { case normal, recording }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 75, height: 75)
    }

    private lazy var feedbackGenerator: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        return generator
    }()

    private lazy var circleLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = Self.primaryWhite.cgColor
        return layer
    }()

    private lazy var tapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(tapped))
        gesture.cancelsTouchesInView = false
        return gesture
    }()

    private lazy var longPressGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(longPressed))
        gesture.minimumPressDuration = 0.4
        gesture.cancelsTouchesInView = false
        return gesture
    }()

    var allowsLongPress = true

    var onTap: (() -> Void)?
    /// - Parameter ended: `true` if the gesture has ended.
    var onLongPress: ((Bool) -> Void)?

    override var isHighlighted: Bool {
        didSet {
            if oldValue != isHighlighted { refreshHighlightState() }
        }
    }

    override var isEnabled: Bool {
        didSet {
            if oldValue != isEnabled { refreshEnabledState() }
        }
    }

    var progress: CGFloat = 0 {
        didSet {
            updateProgress()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        layer.addSublayer(circleLayer)

        addGestureRecognizer(tapGesture)
        addGestureRecognizer(longPressGesture)

        updateStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("CameraShutterButton coder init not implemented...")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateStyle()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        layer.cornerRadius = bounds.height / 2
        circleLayer.frame = bounds

        let inset: CGFloat
        switch traitCollection.userInterfaceStyle {
        case .dark:
            inset = Self.outerRingWidth * 1.75
        default:
            inset = Self.outerRingWidth
        }

        circleLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset)).cgPath
    }

    private func updateStyle() {
        let borderWidth: CGFloat
        let borderColor: UIColor?
        let backgroundColor: UIColor?

        switch traitCollection.userInterfaceStyle {
        case .dark:
            borderWidth = Self.outerRingWidth
            borderColor = Self.primaryWhite
            backgroundColor = nil
        default:
            borderWidth = .zero
            borderColor = nil
            backgroundColor = Self.primaryGray
        }

        layer.borderWidth = borderWidth
        layer.borderColor = borderColor?.cgColor
        self.backgroundColor = backgroundColor
        circleLayer.fillColor = Self.primaryWhite.cgColor

        setNeedsLayout()
    }

    func updateProgress() {
        // TODO: animate the outer ring to reflect the video duration limit
    }

    private func refreshHighlightState() {
        let scale: CGFloat = isHighlighted ? 0.75 : 1.0
        let animation = CABasicAnimation(keyPath: "transform.scale")

        animation.toValue = scale
        animation.duration = 0.2
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        circleLayer.add(animation, forKey: nil)
        circleLayer.transform = CATransform3DMakeScale(scale, scale, scale)

        if !isHighlighted {
            animateButtonColor(to: Self.primaryWhite)
        } else {
            feedbackGenerator.impactOccurred(intensity: 0.75)
        }
    }

    @objc
    private func tapped(_ gesture: UITapGestureRecognizer) {
        onTap?()
    }

    @objc
    private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            onLongPress?(false)
        case .ended, .failed, .cancelled:
            onLongPress?(true)
        default:
            break
        }
    }

    func setState(_ state: State, animated: Bool = false) {
        let color: UIColor
        switch state {
        case .normal:
            color = Self.primaryWhite
        case .recording:
            color = .systemRed
        }

        if animated {
            animateButtonColor(to: color)
        } else {
            circleLayer.fillColor = color.cgColor
        }
    }

    private func animateButtonColor(to color: UIColor) {
        let color = color.cgColor
        let animation = CABasicAnimation(keyPath: "fillColor")

        animation.toValue = color
        animation.duration = 0.2
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        circleLayer.add(animation, forKey: nil)
        circleLayer.fillColor = color
    }

    private func refreshEnabledState() {
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) { [isEnabled] in
            self.alpha = isEnabled ? 1 : 0.5
        }

        tapGesture.isEnabled = isEnabled
        longPressGesture.isEnabled = isEnabled && allowsLongPress
    }
}
