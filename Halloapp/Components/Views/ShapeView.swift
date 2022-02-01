//
//  ShapeView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/20/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import QuartzCore
import UIKit

class ShapeView: UIView {

    override class var layerClass: AnyClass {
        get {
            return CAShapeLayer.self
        }
    }

    var shapeLayer: CAShapeLayer {
        get {
            return layer as! CAShapeLayer
        }
    }

    var fillColor: UIColor? {
        didSet {
            shapeLayer.fillColor = fillColor?.cgColor
        }
    }

    var strokeColor: UIColor? {
        didSet {
            shapeLayer.strokeColor = strokeColor?.cgColor
        }
    }

    var lineWidth: CGFloat {
        get {
            return shapeLayer.lineWidth
        }
        set {
            shapeLayer.lineWidth = newValue
        }
    }

    var path: UIBezierPath? {
        get {
            guard let cgPath = shapeLayer.path else {
                return nil
            }
            return UIBezierPath(cgPath: cgPath)
        }
        set {
            shapeLayer.path = newValue?.cgPath
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // It is necessary to re-apply fill and stroke colors when user interface changes between dark and light mode
        // because CALayer doesn't understand dynamic colors.
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            shapeLayer.fillColor = fillColor?.resolvedColor(with: traitCollection).cgColor
            shapeLayer.strokeColor = strokeColor?.resolvedColor(with: traitCollection).cgColor
        }
    }
}

class CircleView: ShapeView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        if frame != .zero {
            path = UIBezierPath(ovalIn: bounds)
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var bounds: CGRect {
        didSet {
            if oldValue != bounds {
                path = UIBezierPath(ovalIn: bounds)
            }
        }
    }

    override var frame: CGRect {
        didSet {
            if oldValue != frame {
                path = UIBezierPath(ovalIn: bounds)
            }
        }
    }
}

class PillView: ShapeView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        if frame != .zero {
            reloadPath()
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var bounds: CGRect {
        didSet {
            if oldValue != bounds {
                reloadPath()
            }
        }
    }

    override var frame: CGRect {
        didSet {
            if oldValue != frame {
                reloadPath()
            }
        }
    }

    private func reloadPath() {
        let radius = round(min(bounds.height, bounds.width) / CGFloat(2))
        path = UIBezierPath(roundedRect: bounds, cornerRadius: radius)
    }
}

class RingView: ShapeView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        if frame != .zero {
            reloadPath()
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var bounds: CGRect {
        didSet {
            if oldValue != bounds {
                reloadPath()
            }
        }
    }

    override var frame: CGRect {
        didSet {
            if oldValue != frame {
                reloadPath()
            }
        }
    }

    private func reloadPath() {
        let radius = (min(bounds.height, bounds.width) - lineWidth) / CGFloat(2)
        path = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: 2*CGFloat.pi, clockwise: true)
    }

}

class RoundedRectView: ShapeView {

    var cornerRadius: CGFloat = 0 {
        didSet { reloadPath() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        if frame != .zero {
            reloadPath()
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var bounds: CGRect {
        didSet {
            if oldValue != bounds {
                reloadPath()
            }
        }
    }

    override var frame: CGRect {
        didSet {
            if oldValue != frame {
                reloadPath()
            }
        }
    }

    private func reloadPath() {
        path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
    }
}

