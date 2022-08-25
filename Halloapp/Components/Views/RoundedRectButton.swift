//
//  RoundedRectButton.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 5/18/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

class RoundedRectButton: UIButton {

    var backgroundTintColor: UIColor = .lavaOrange {
        didSet {
            updateState(animated: false)
        }
    }

    private var shouldAnimateStateUpdates = false
    private var backgroundLayer = CAShapeLayer()

    override var isHighlighted: Bool {
        didSet {
            updateState(animated: shouldAnimateStateUpdates)
        }
    }

    override var isEnabled: Bool {
        didSet {
            updateState(animated: shouldAnimateStateUpdates)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        adjustsImageWhenDisabled = false
        adjustsImageWhenHighlighted = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        animateStateUpdates {
            super.touchesBegan(touches, with: event)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        animateStateUpdates {
            super.touchesMoved(touches, with: event)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        animateStateUpdates {
            super.touchesEnded(touches, with: event)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        animateStateUpdates {
            super.touchesCancelled(touches, with: event)
        }
    }

    private func animateStateUpdates(_ block: () -> Void) {
        let previousValue = shouldAnimateStateUpdates
        shouldAnimateStateUpdates = true
        block()
        shouldAnimateStateUpdates = previousValue
    }

    private func updateState(animated: Bool) {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        // This works well with lavaOrange, but it may need to be adjusted for other colors.
        var resolvedBackgroundColor = backgroundTintColor.resolvedColor(with: traitCollection)
        if resolvedBackgroundColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            if !isEnabled {
                saturation = 0.10
                brightness -= 0.24
            } else if isHighlighted {
                brightness -= 0.2
            }
            resolvedBackgroundColor = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        backgroundLayer.fillColor = resolvedBackgroundColor.cgColor
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Always make sure we are below any other subviews
        layer.insertSublayer(backgroundLayer, at: 0)

        let backgroundFrame = backgroundRect(forBounds: bounds)
        let cornerRadius = min(backgroundFrame.width, backgroundFrame.height) / 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayer.frame = backgroundFrame
        backgroundLayer.path = UIBezierPath(roundedRect: backgroundLayer.bounds, cornerRadius: cornerRadius).cgPath
        layer.shadowPath = UIBezierPath(roundedRect: backgroundFrame, cornerRadius: cornerRadius).cgPath
        CATransaction.commit()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateState(animated: false)
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return super.point(inside: point, with: event) || bounds.insetBy(dx: min(0, bounds.width - 44) / 2,
                                                                         dy: min(0, bounds.width - 44) / 2).contains(point)
    }
}
