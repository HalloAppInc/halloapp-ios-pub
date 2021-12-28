//
//  UIImageView.swift
//  Core
//
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import UIKit

extension UIImageView {
    /// Sets a mask on the layer in order to round image corners based on current bounds. Assumes image has already been set and `contentMode` is `scaleAspectFit`.
    public func roundCorner(_ radius: CGFloat) {
        guard let imageRect = getImageRect() else { return }

        let mask = CAShapeLayer()
        mask.path = UIBezierPath(roundedRect: imageRect, cornerRadius: radius).cgPath
        layer.mask = mask
    }

    public func getImageRect() -> CGRect? {
        guard let image = image else { return nil }
        let viewSize = bounds.size
        let imageSize = image.size
        let boundsScale = viewSize.width / viewSize.height
        let imageScale = imageSize.width / imageSize.height

        var imageRect = bounds

        if boundsScale > imageScale {
            let width = viewSize.height * imageScale
            imageRect.size.width = width
            imageRect.origin.x = (viewSize.width - width) / CGFloat(2)
        } else {
            let height = viewSize.width / imageScale
            imageRect.size.height = height
            imageRect.origin.y = (viewSize.height - height) / CGFloat(2)
        }
        return imageRect
    }
}
