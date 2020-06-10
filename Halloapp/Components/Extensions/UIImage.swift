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
import Core

extension UIImage {
    
    func getNewSize(res: Int) -> UIImage? {
        // TODO: check if this can be made faster
        guard let imageData = self.pngData() else { return nil }

        //    print("orig: \(imageData.count/1000)")

        let options = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: res] as CFDictionary

        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        guard let imageReference = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }

        //    let temp = UIImage(cgImage: imageReference)
        //    let temp2 = temp.pngData()
        //    print("thumb: \(temp2!.count/1000)")
        //    print("percent: \(Float(temp2!.count) / Float(imageData.count))")

        return UIImage(cgImage: imageReference)

    }

    func resized(to size: CGSize) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }

        let originalSize = CGSize(width: self.size.width * self.scale, height: self.size.height * self.scale)

        DDLogDebug("UIImage/resize/from [\(NSCoder.string(for: originalSize))] to [\(NSCoder.string(for: size))]")
        var resizedBufferWidth: vImagePixelCount, resizedBufferHeight: vImagePixelCount
        let widthCG = cgImage.width
        let heightCG = cgImage.height
        if (widthCG >= heightCG && originalSize.width >= originalSize.height) || (widthCG <= heightCG && originalSize.width <= originalSize.height) {
            resizedBufferWidth = vImagePixelCount(size.width)
            resizedBufferHeight = vImagePixelCount(size.height)
        } else {
            // UIImage has a 90-degree transform
            resizedBufferWidth = vImagePixelCount(size.height)
            resizedBufferHeight = vImagePixelCount(size.width)
        }
        var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: nil,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )
        var inBuffer = vImage_Buffer()
        let inError = vImageBuffer_InitWithCGImage(&inBuffer, &format, nil, cgImage, vImage_Flags(kvImageNoFlags))
        guard inError == kvImageNoError else {
            DDLogError("UIImage/resize/in/error: [\(inError)]")
            return nil
        }
        var outBuffer = vImage_Buffer()
        let outError = vImageBuffer_Init(&outBuffer, resizedBufferHeight, resizedBufferWidth, 32, vImage_Flags(kvImageNoFlags))
        guard outError == kvImageNoError else {
            DDLogError("UIImage/resize/out/error: [\(outError)]")
            free(inBuffer.data)
            return nil
        }
        vImageScale_ARGB8888(&inBuffer, &outBuffer, nil, vImage_Flags(kvImageNoFlags))
        free(inBuffer.data)

        var needsUprighting = false
        var backColor: UInt8 = 0
        if self.imageOrientation == .up {
            // We're done
        } else if self.imageOrientation == .right {
            var rotatedBuffer = vImage_Buffer()
            let error = vImageBuffer_Init(&rotatedBuffer, resizedBufferWidth, resizedBufferHeight, 32, vImage_Flags(kvImageNoFlags))
            if error != kvImageNoError {
                DDLogError("UIImage/resize/rotate-buffer/error: [\(error)]")
            } else {
                vImageRotate90_ARGB8888(&outBuffer, &rotatedBuffer, 3, &backColor, vImage_Flags(kvImageNoFlags))
            }
            free(outBuffer.data)
            outBuffer = rotatedBuffer
        } else if self.imageOrientation == .left {
            var rotatedBuffer = vImage_Buffer()
            let error = vImageBuffer_Init(&rotatedBuffer, resizedBufferWidth, resizedBufferHeight, 32, vImage_Flags(kvImageNoFlags))
            if error != kvImageNoError {
                DDLogError("UIImage/resize/rotate-buffer/error: [\(error)]")
            } else {
                vImageRotate90_ARGB8888(&outBuffer, &rotatedBuffer, 1, &backColor, vImage_Flags(kvImageNoFlags))
            }
            free(outBuffer.data)
            outBuffer = rotatedBuffer
        } else if self.imageOrientation == .down {
            var rotatedBuffer = vImage_Buffer()
            let error = vImageBuffer_Init(&rotatedBuffer, resizedBufferHeight, resizedBufferWidth, 32, vImage_Flags(kvImageNoFlags))
            if error != kvImageNoError {
                DDLogError("UIImage/resize/rotate-buffer/error: [\(error)]")
            } else {
                vImageRotate90_ARGB8888(&outBuffer, &rotatedBuffer, 2, &backColor, vImage_Flags(kvImageNoFlags))
            }
            free(outBuffer.data)
            outBuffer = rotatedBuffer
        } else {
            needsUprighting = true
        }
        guard outBuffer.data != nil else { return nil }

        var convertError: vImage_Error = 0
        let imageCG = vImageCreateCGImageFromBuffer(&outBuffer, &format, nil, nil, vImage_Flags(kvImageNoFlags), &convertError)
        if convertError != kvImageNoError {
            DDLogError("UIImage/resize/cgimage/error: [\(convertError)]")
        }
        free(outBuffer.data)
        guard let cgImageResult = imageCG?.takeUnretainedValue() else { return nil }
        var image = UIImage(cgImage: cgImageResult, scale: 1, orientation: needsUprighting ? self.imageOrientation : .up)
        imageCG?.release()

        // For the more exotic image orientations, we use UIKit to upright the image. Note that this has
        // a fairly severe performance penalty for large images.
        if image.imageOrientation != .up {
            UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
            image.draw(at: .zero)
            if let img = UIGraphicsGetImageFromCurrentImageContext() {
                image = img
            }
            UIGraphicsEndImageContext()
        }
        return image
    }

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
