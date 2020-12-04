//
//  ZoomableImageView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/11/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

class ZoomableImageView: UIImageView {
    private var zoomHandler: ZoomGestureHandler!

    var minimumZoomScale: CGFloat {
        get { zoomHandler.minimumZoomScale }
        set { zoomHandler.minimumZoomScale = newValue }
    }
    var maximumZoomScale: CGFloat {
        get { zoomHandler.maximumZoomScale }
        set { zoomHandler.maximumZoomScale = newValue }
    }
    var isZooming: Bool {
        get { zoomHandler.isZooming }
    }
    var isZoomEnabled: Bool {
        get { zoomHandler.isEnabled }
        set { zoomHandler.isEnabled = newValue }
    }
    var cornerRadius: CGFloat = 0 {
        didSet { applyCornerRadius() }
    }
    var borderColor: UIColor? = nil {
        didSet { applyBorder() }
    }
    var borderWidth: CGFloat = 0 {
        didSet { applyBorder() }
    }
    override var image: UIImage? {
        didSet { applyCornerRadius() }
    }
    override var frame: CGRect {
        didSet {
            if oldValue.size != frame.size {
                applyCornerRadius()
                applyBorder()
            }
        }
    }
    override var bounds: CGRect {
        didSet {
            if oldValue.size != bounds.size {
                applyCornerRadius()
                applyBorder()
            }
        }
    }
    override var contentMode: UIView.ContentMode {
        didSet {
            if oldValue != contentMode {
                applyCornerRadius()
                applyBorder()
            }
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
        self.isUserInteractionEnabled = true
        self.clipsToBounds = true

        zoomHandler = ZoomGestureHandler(self)
    }

    private func applyCornerRadius() {
        if cornerRadius == 0 {
            self.layer.mask = nil
            return
        }
        if let image = self.image {
            let frameAspectRatio = self.bounds.width / self.bounds.height
            let imageAspectRatio = image.size.width / image.size.height

            var rect = self.bounds
            // Add calculations for other content modes when it is needed.
            if self.contentMode == .scaleAspectFit {
                if frameAspectRatio > imageAspectRatio {
                    rect.size.width = ceil(rect.height * imageAspectRatio)
                    rect.origin.x = (self.bounds.width - rect.width) / 2
                } else {
                    rect.size.height = ceil(rect.width / imageAspectRatio)
                    rect.origin.y = (self.bounds.height - rect.height) / 2
                }
            }
            let maskLayer = CAShapeLayer()
            maskLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).cgPath
            self.layer.mask = maskLayer
        }
    }

    private var borderLayer: CAShapeLayer? = nil
    private func applyBorder() {
        // No border
        if borderColor == nil || borderWidth == 0 {
            if let borderLayer = borderLayer {
                borderLayer.removeFromSuperlayer()
                self.borderLayer = nil
            }
            return
        }

        // Border
        let borderLayer: CAShapeLayer
        if let existingBorderLayer = self.borderLayer {
            borderLayer = existingBorderLayer
        } else {
            borderLayer = CAShapeLayer()
            borderLayer.fillColor = UIColor.clear.cgColor
            layer.addSublayer(borderLayer)
            self.borderLayer = borderLayer
        }
        if let maskLayer = layer.mask as? CAShapeLayer, let maskLayerPath = maskLayer.path {
            borderLayer.path = maskLayerPath
        } else {
            borderLayer.path = UIBezierPath(rect: bounds).cgPath
        }
        borderLayer.strokeColor = borderColor?.cgColor
        borderLayer.lineWidth = borderWidth
    }
}

fileprivate class ZoomGestureHandler {
    private weak var imageView: UIImageView?
    private var dimmerView: UIView = {
        let dimmerView = UIView()
        dimmerView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        return dimmerView
    }()
    private var zoomingImageView: UIImageView!
    private(set) var isZooming: Bool = false
    private var initialRect: CGRect = CGRect.zero
    private var previousTouchLocation: CGPoint = CGPoint.zero
    private var previousNumberOfTouches: Int?

    // MARK: Configurable
    var minimumZoomScale: CGFloat = 1.0
    var maximumZoomScale: CGFloat = 5.0
    var isEnabled: Bool = true

    init(_ imageView: UIImageView) {
        self.imageView = imageView

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(gesture:)))
        pinchGesture.cancelsTouchesInView = false
        self.imageView?.addGestureRecognizer(pinchGesture)
    }

    static func appWindow() -> UIWindow? {
        if let windowScene = UIApplication.shared.connectedScenes.randomElement() as? UIWindowScene {
            return windowScene.windows.last
        }
        return nil
    }

    @objc private func handlePinch(gesture: UIPinchGestureRecognizer) {
        guard let originalImageView = imageView else { return }

        func cancelHandling(gesture: UIGestureRecognizer) {
            gesture.isEnabled = false
            gesture.isEnabled = true
        }

        switch gesture.state {
        case .began:

            guard isEnabled else {
                cancelHandling(gesture: gesture)
                return
            }
            guard let imageViewOrigin = originalImageView.superview?.convert(originalImageView.frame.origin, to: nil),
                  let window = Self.appWindow() else {
                cancelHandling(gesture: gesture)
                return
            }

            dimmerView.frame = window.bounds
            dimmerView.alpha = 0.0
            window.addSubview(dimmerView)
            UIView.animate(withDuration: 0.1) {
                self.dimmerView.alpha = 1.0
            }

            initialRect = CGRect(origin: imageViewOrigin, size: originalImageView.frame.size)
            previousTouchLocation = gesture.location(in: originalImageView)

            zoomingImageView = UIImageView(image: originalImageView.image)
            zoomingImageView.contentMode = originalImageView.contentMode
            zoomingImageView.frame = initialRect

            let anchorPoint = CGPoint(x: previousTouchLocation.x/initialRect.size.width, y: previousTouchLocation.y/initialRect.size.height)
            zoomingImageView.layer.anchorPoint = anchorPoint
            zoomingImageView.center = previousTouchLocation
            zoomingImageView.frame = initialRect

            originalImageView.alpha = 0.0
            window.addSubview(zoomingImageView)

            isZooming = true
            previousNumberOfTouches = gesture.numberOfTouches

        case .changed:
            if gesture.numberOfTouches != previousNumberOfTouches {
                previousTouchLocation = gesture.location(in: self.imageView)
            }

            let scale = zoomingImageView.frame.width / initialRect.width
            let newScale = scale * gesture.scale

            guard !scale.isNaN && scale != CGFloat.infinity && CGFloat.nan != initialRect.width else { return }

            let imageViewCenter = zoomingImageView.center

            let effectiveScale = min(maximumZoomScale, max(minimumZoomScale, newScale))
            zoomingImageView.frame = CGRect(x: zoomingImageView.frame.origin.x, y: zoomingImageView.frame.origin.y,
                                            width: initialRect.width * effectiveScale, height: initialRect.height * effectiveScale)

            let xOffset = previousTouchLocation.x - gesture.location(in: originalImageView).x
            let yOffset = previousTouchLocation.y - gesture.location(in: originalImageView).y
            zoomingImageView.center = CGPoint(x: imageViewCenter.x - xOffset, y: imageViewCenter.y - yOffset)
            gesture.scale = 1.0

            previousNumberOfTouches = gesture.numberOfTouches
            previousTouchLocation = gesture.location(in: originalImageView)

        case .ended, .cancelled, .failed:
            reset()
            
        default:
            break
        }
    }

    private func reset() {
        guard zoomingImageView != nil else { return }
        
        UIView.animate(withDuration: 0.35, animations: {
            self.zoomingImageView.frame = self.initialRect
            self.dimmerView.alpha = 0.0
        }) { (_) in
            self.dimmerView.removeFromSuperview()
            self.zoomingImageView.removeFromSuperview()
            self.imageView?.alpha = 1.0
            self.dimmerView.alpha = 1.0
            self.initialRect = .zero
            self.previousTouchLocation = .zero
            self.isZooming = false
        }
    }
}
