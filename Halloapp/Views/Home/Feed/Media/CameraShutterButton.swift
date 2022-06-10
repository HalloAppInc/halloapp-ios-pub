//
//  CameraShutterButton.swift
//  HalloApp
//
//  Created by Tanveer on 6/8/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

private extension CameraShutterButton {
    var lineWidth: CGFloat {
        5
    }
}

class CameraShutterButton: UIControl {
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

    override var isHighlighted: Bool {
        didSet {
            if oldValue != isHighlighted { updateButtonState() }
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
    }

    required init?(coder: NSCoder) {
        fatalError("CameraShutterButton coder init not implemented...")
    }

    override func layoutSubviews() {
        outerRingLayer.frame = bounds
        outerRingLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)).cgPath

        circleLayer.frame = bounds
        circleLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: lineWidth * 1.5, dy: lineWidth * 1.5)).cgPath
    }

    func updateProgress() {
        // TODO: animate the outer ring to reflect the video duration limit
    }

    private func updateButtonState() {
        // TODO: animate the scale of the button when pressed
    }
}
