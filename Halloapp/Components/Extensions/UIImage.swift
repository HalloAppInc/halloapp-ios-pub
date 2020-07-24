//
//  UIImage.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Accelerate
import CocoaLumberjack
import CoreGraphics
import SwiftUI

extension UIImage {
    func resized(to targetSize: CGSize, contentMode: UIView.ContentMode, downscaleOnly: Bool, opaque removeAlpha: Bool = false) -> UIImage? {

        guard contentMode == .center || contentMode == .scaleAspectFit || contentMode == .scaleAspectFill || contentMode == .scaleToFill else {
            assert(false, "Invalid contentMode [\(contentMode)]")
            return nil
        }

        // Round the target size here to make sure the image is drawn without misaligned issue.
        var targetSize = CGSize(width: targetSize.width.rounded(), height: targetSize.height.rounded())

        guard self.size.width != 0 && self.size.height != 0 && targetSize.width != 0 && targetSize.height != 0 else { return nil }

        let imageSize = CGSize(width: self.size.width * self.scale, height: self.size.height * self.scale)
        var scaleX = targetSize.width / imageSize.width
        var scaleY = targetSize.height / imageSize.height
        switch (contentMode) {
        case .scaleAspectFit:
            let scaleFactor = min(scaleX, scaleY)
            if scaleX > scaleY {
                targetSize.width = (scaleFactor * imageSize.width).rounded()
            } else {
                targetSize.height = (scaleFactor * imageSize.height).rounded()
            }
            scaleX = scaleFactor
            scaleY = scaleFactor

        case .scaleAspectFill:
            let scaleFactor = max(scaleX, scaleY)
            scaleX = scaleFactor
            scaleY = scaleFactor

        case .center:
            scaleX = 1
            scaleY = 1

        default:
            break
        }

        if downscaleOnly && scaleX > 1 && scaleY > 1 {
            scaleX = 1
            scaleY = 1
            targetSize = imageSize
        }

        var imageDrawRect = CGRect(origin: .zero, size: imageSize)
        imageDrawRect.size.width = ceil(imageDrawRect.size.width * scaleX)
        imageDrawRect.size.height = ceil(imageDrawRect.size.height * scaleY)
        imageDrawRect.origin.x = floor(0.5 * (targetSize.width - imageDrawRect.size.width))
        imageDrawRect.origin.y = floor(0.5 * (targetSize.height - imageDrawRect.size.height))

        if self.imageOrientation == .up && self.scale == 1 && self.size == targetSize && CGRect(origin: .zero, size: self.size) == imageDrawRect {
            if !removeAlpha {
                return self
            } else {
                return self.normalized(removingAlpha: true)
            }
        }
        UIGraphicsBeginImageContextWithOptions(targetSize, removeAlpha, 1.0)
        if removeAlpha {
            UIColor.white.setFill()
            UIRectFill(imageDrawRect)
        }
        self.draw(in: imageDrawRect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        if newImage == nil {
            DDLogError("UIImage/resize/failed: size: \(NSCoder.string(for: self.size)), scale: \(self.scale), removeAlpha: \(removeAlpha)")
        }
        return newImage
    }

    func normalized(removingAlpha: Bool = false) -> UIImage {
        guard !UIImage.isNormalized(self, removingAlpha) else { return self }
        let size = CGSize(width: self.size.width * self.scale, height: self.size.height * self.scale)
        UIGraphicsBeginImageContextWithOptions(size, removingAlpha, 1)
        let rect = CGRect(origin: .zero, size: size)
        if removingAlpha {
            UIColor.white.setFill()
            UIRectFill(rect)
        }
        self.draw(in: rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image!
    }

    class func isNormalized(_ image: UIImage, _ failIfAlpha: Bool) -> Bool {
        guard image.imageOrientation == .up else { return false }
        guard image.scale == 1 else { return false }

        guard let imageRef = image.cgImage else { return false }
        guard imageRef.bitsPerPixel == 32 else { return false }
        guard imageRef.bitsPerComponent == 8 else { return false }

        let alphaInfo: CGImageAlphaInfo = imageRef.alphaInfo
        switch alphaInfo {
        case .alphaOnly:
            return false

        case .premultipliedLast, .premultipliedFirst, .last, .first:
            if failIfAlpha {
                return false
            }

        default:
                break
        }
        return true
    }

    class func singleColorImage(ofSize size: CGSize, color: UIColor) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        color.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}
