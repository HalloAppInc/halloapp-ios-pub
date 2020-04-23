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
            return self.layer as! CAShapeLayer
        }
    }

    var fillColor: UIColor? {
        get {
            guard let cgColor = self.shapeLayer.fillColor else {
                return nil
            }
            return UIColor(cgColor: cgColor)
        }
        set {
            self.shapeLayer.fillColor = newValue?.cgColor
        }
    }

    var strokeColor: UIColor? {
        get {
            guard let cgColor = self.shapeLayer.strokeColor else {
                return nil
            }
            return UIColor(cgColor: cgColor)
        }
        set {
            self.shapeLayer.strokeColor = newValue?.cgColor
        }

    }

    var lineWidth: CGFloat {
        get {
            return self.shapeLayer.lineWidth
        }
        set {
            self.shapeLayer.lineWidth = newValue
        }
    }

    var path: UIBezierPath? {
        get {
            guard let cgPath = self.shapeLayer.path else {
                return nil
            }
            return UIBezierPath(cgPath: cgPath)
        }
        set {
            self.shapeLayer.path = newValue?.cgPath
        }
    }
}

class CircleView: ShapeView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        if frame != .zero {
            self.path = UIBezierPath(ovalIn: self.bounds)
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var bounds: CGRect {
        didSet {
            if oldValue != self.bounds {
                self.path = UIBezierPath(ovalIn: self.bounds)
            }
        }
    }

    override var frame: CGRect {
        didSet {
            if oldValue != self.frame {
                self.path = UIBezierPath(ovalIn: self.bounds)
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
            if oldValue != self.bounds {
                reloadPath()
            }
        }
    }

    override var frame: CGRect {
        didSet {
            if oldValue != self.frame {
                reloadPath()
            }
        }
    }

    private func reloadPath() {
        self.path = UIBezierPath(roundedRect: self.bounds, cornerRadius: min(self.bounds.height / 2, self.bounds.width / 2).rounded())
    }
}
