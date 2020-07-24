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
    public func resized(to size: CGSize) -> UIImage? {
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
}
