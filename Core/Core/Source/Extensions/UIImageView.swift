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
        guard let image = image else { return }
        let boundsScale = bounds.size.width / bounds.size.height
        let imageScale = image.size.width / image.size.height

        var rect: CGRect = bounds

        if boundsScale > imageScale {
            rect.size.width =  rect.size.height * imageScale
            rect.origin.x = (bounds.size.width - rect.size.width) / 2
        } else {
            rect.size.height = rect.size.width / imageScale
            rect.origin.y = (bounds.size.height - rect.size.height) / 2
        }

        let mask = CAShapeLayer()
        mask.path = UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath
        layer.mask = mask
    }
}
