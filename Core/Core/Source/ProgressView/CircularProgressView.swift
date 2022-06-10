//
//  CircularProgressView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 7/20/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

fileprivate class DownloadProgressArcLayer : CALayer {
    @NSManaged var progress: Float

    override class func needsDisplay(forKey key: String) -> Bool {
        return key == "progress"
    }
}

public class CircularProgressView : UIView {

    public var barWidth: CGFloat = 1
    public var progressTintColor: UIColor?
    public var trackTintColor: UIColor?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    public override class var layerClass: AnyClass {
        get { DownloadProgressArcLayer.self }
    }

    private func presentationValueForProgress() -> Float {
        var layer = self.layer as! DownloadProgressArcLayer
        if layer.animationKeys()?.contains("progress") ?? false {
            // If the layer is animating, use the property values in presentationLayer instead.
            layer = layer.presentation() ?? layer
        }
        return layer.progress
    }

    public var progress: Float {
        get {
            let layer = self.layer as! DownloadProgressArcLayer
            return layer.progress
        }
        set {
            setProgress(newValue, animated: false)
        }
    }

    public func setProgress(_ progress: Float, animated: Bool) {
        setProgress(progress, withAnimationDuration:animated ? 0.1 : 0.0)
    }

    func setProgress(_ progress: Float, withAnimationDuration duration: TimeInterval, completion: (() -> Void)? = nil) {
        guard  let layer = self.layer as? DownloadProgressArcLayer else { return }
        if duration > 0 && progress > 0 {
            let currentProgress = self.presentationValueForProgress()
            // Don't update the visual progress state if it is going backwards by a small amount.
            // This may happen when resuming an existing upload.
            if currentProgress > progress && fabsf(currentProgress - progress) < 0.3 && currentProgress < 1.0 && currentProgress > 0.0 {
                return
            }
            CATransaction.begin()
            if completion != nil {
                CATransaction.setCompletionBlock(completion)
            }
            let animation = CABasicAnimation(keyPath: "progress")
            animation.fromValue = currentProgress
            animation.toValue = progress
            animation.duration = duration
            self.layer.add(animation, forKey: "progress")
            CATransaction.commit()
        }
        layer.progress = progress
    }

    public override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        let center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        let radius = 0.5 * self.bounds.height
        let angle = self.presentationValueForProgress() * 2.0 * Float.pi - Float.pi/2 + Float.ulpOfOne
        // filled path
        let filledPath = UIBezierPath(arcCenter: center, radius: radius, startAngle: CGFloat(-Float.pi/2), endAngle: CGFloat(angle), clockwise: true)
        filledPath.addArc(withCenter: center, radius: radius - barWidth, startAngle: CGFloat(angle), endAngle: CGFloat(-Float.pi/2), clockwise: false)
        let progressColor = progressTintColor ?? self.tintColor!
        progressColor.set()
        filledPath.fill()
        // not filled path
        if let trackColor = self.trackTintColor, angle < 1.5 * Float.pi {
            let trackPath = UIBezierPath(arcCenter: center, radius: radius, startAngle: CGFloat(angle), endAngle: CGFloat(1.5*Float.pi), clockwise: true)
            trackPath.addArc(withCenter: center, radius: radius - barWidth, startAngle: CGFloat(1.5*Float.pi), endAngle: CGFloat(angle), clockwise: false)
            trackColor.set()
            trackPath.fill()
        }
    }

    public override var intrinsicContentSize: CGSize {
        get { CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) }
    }

}
