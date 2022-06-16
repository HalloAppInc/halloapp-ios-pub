//
//  CameraShutterButton.swift
//  HalloApp
//
//  Created by Tanveer on 6/8/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

class CameraShutterButton: UIControl {
    private var lineWidth: CGFloat {
        5
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 75, height: 75)
    }

    private lazy var circleLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.white.withAlphaComponent(0.9).cgColor
        return layer
    }()

    private lazy var outerRingLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.lineWidth = lineWidth
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = UIColor.white.withAlphaComponent(0.5).cgColor
        return layer
    }()

    private lazy var tapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(tapped))
        gesture.cancelsTouchesInView = false
        return gesture
    }()
    private(set) lazy var longPressGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(longPressed))
        gesture.minimumPressDuration = 0.4
        gesture.cancelsTouchesInView = false
        return gesture
    }()

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
        layer.addSublayer(outerRingLayer)

        addGestureRecognizer(tapGesture)
        addGestureRecognizer(longPressGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("CameraShutterButton coder init not implemented...")
    }

    override func layoutSubviews() {
        outerRingLayer.frame = bounds
        circleLayer.frame = bounds

        outerRingLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)).cgPath
        circleLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: lineWidth * 1.5, dy: lineWidth * 1.5)).cgPath
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
            animateButtonColor(to: .white.withAlphaComponent(0.9))
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
            animateButtonColor(to: .systemRed)
            onLongPress?(false)
        case .ended, .failed, .cancelled:
            onLongPress?(true)
        default:
            break
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
        let alpha: CGFloat = isEnabled ? 0.9 :0.5

        circleLayer.fillColor = UIColor.white.withAlphaComponent(alpha).cgColor
        isUserInteractionEnabled = isEnabled
    }
}
