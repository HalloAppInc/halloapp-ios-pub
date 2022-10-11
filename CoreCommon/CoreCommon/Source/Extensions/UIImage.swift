//
//  UIImage.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Accelerate
import CocoaLumberjackSwift
import CoreGraphics
import SwiftUI

extension UIImage {

    public func fastResized(to size: CGSize) -> UIImage? {
        if AppContextCommon.shared.isAppExtension {
            return self.resized(to: size, contentMode: .scaleToFill, downscaleOnly: false)
        }

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
            colorSpace: cgImage.colorSpace != nil ? Unmanaged.passRetained(cgImage.colorSpace!) : nil,
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

    public func simpleResized(to size: CGSize) -> UIImage? {
        guard let image = self.cgImage else { return nil }

        let scaleX: CGFloat
        let scaleY: CGFloat
        let targetRect: CGRect
        let imageSize = CGSize(width: image.width, height: image.height)

        switch self.imageOrientation {
        case .left, .right:
            scaleX = size.width / imageSize.height
            scaleY = size.height / imageSize.width
            targetRect = CGRect(x: 0, y: 0, width: size.height, height: size.width)
        default:
            scaleX = size.width / imageSize.width
            scaleY = size.height / imageSize.height
            targetRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        }

        let output = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        guard let resized = CIContext().createCGImage(output, from: targetRect, format: .RGBA8, colorSpace: image.colorSpace) else {
            return nil
        }

        return UIImage(cgImage: resized, scale: 1, orientation: self.imageOrientation)
    }

    public func resized(to targetSize: CGSize, contentMode: UIView.ContentMode, downscaleOnly: Bool, opaque removeAlpha: Bool = false) -> UIImage? {

        guard contentMode == .center || contentMode == .scaleAspectFit || contentMode == .scaleAspectFill || contentMode == .scaleToFill else {
            assert(false, "Invalid contentMode [\(contentMode)]")
            return nil
        }

        // Round the target size here to make sure the image is drawn without misaligned issue.
        var targetSize = CGSize(width: round(targetSize.width), height: round(targetSize.height))

        guard self.size.width != 0 && self.size.height != 0 && targetSize.width != 0 && targetSize.height != 0 else { return nil }

        let imageSize = CGSize(width: self.size.width * self.scale, height: self.size.height * self.scale)
        var scaleX = targetSize.width / imageSize.width
        var scaleY = targetSize.height / imageSize.height
        switch (contentMode) {
        case .scaleAspectFit:
            let scaleFactor = min(scaleX, scaleY)
            if scaleX > scaleY {
                targetSize.width = round(scaleFactor * imageSize.width)
            } else {
                targetSize.height = round(scaleFactor * imageSize.height)
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

    public func save(to url: URL) -> Bool {
        guard let cgImage = cgImage else { return false }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return false }
        let orientation = CGImagePropertyOrientation(imageOrientation)
        let options = [kCGImagePropertyOrientation: orientation.rawValue,
                       kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary

        CGImageDestinationAddImage(destination, cgImage, options)

        return CGImageDestinationFinalize(destination)
    }

    public func normalized(removingAlpha: Bool = false) -> UIImage {
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

    public class func isNormalized(_ image: UIImage, _ failIfAlpha: Bool) -> Bool {
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

    public class func singleColorImage(ofSize size: CGSize, color: UIColor) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        color.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }

    public static func qrCodeImage(for data: Data, size: CGSize? = nil) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(data, forKey: "inputMessage")
        guard let qrCodeImage = filter.outputImage else {
            return nil
        }
        let transform: CGAffineTransform = {
            guard let size = size, size.width > 0, size.height > 0, !qrCodeImage.extent.isEmpty else {
                return .identity
            }
            return CGAffineTransform(
                scaleX: size.width / qrCodeImage.extent.width,
                y: size.height / qrCodeImage.extent.height)
        }()
        return UIImage(ciImage: qrCodeImage.transformed(by: transform))
    }

    public static func thumbnail(contentsOf url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        let thumbnailOptions =  [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                  kCGImageSourceShouldCacheImmediately: true,
                                  kCGImageSourceCreateThumbnailWithTransform: true,
                                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize] as CFDictionary

        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }

        return UIImage(cgImage: thumbnail)
    }

    public static func thumbnail(forText text: String?) -> UIImage? {
        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 300, height: 100))
        label.numberOfLines = 2
        label.text = text
        label.font = .systemFont(ofSize: 33)

        let view = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 120))
        view.addSubview(label)
        view.backgroundColor = .systemBackground

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120))
        return renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
    }

    /// Combines `leading` and `trailing` into one image with a 1:1 aspect ratio.
    public static func combine(leading: UIImage, trailing: UIImage) -> UIImage? {
        var direction: Locale.LanguageDirection?
        if #available(iOSApplicationExtension 16, *) {
            direction = Locale.current.language.characterDirection
        } else if let preferred = Locale.preferredLanguages.first {
            direction = Locale.characterDirection(forLanguage: preferred)
        }

        let isLeftToRight = direction ?? .leftToRight == .leftToRight
        return isLeftToRight ? combine(left: leading, right: trailing) : combine(left: trailing, right: leading)
    }

    private static func combine(left: UIImage, right: UIImage) -> UIImage? {
        let size = CGSize(width: left.size.height, height: left.size.height)
        UIGraphicsBeginImageContext(size)

        left.draw(in: .init(origin: .zero, size: left.size))
        right.draw(in: .init(origin: .init(x: left.size.width, y: 0), size: right.size))
        let result = UIGraphicsGetImageFromCurrentImageContext()

        UIGraphicsEndImageContext()
        return result
    }
}

private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
            case .up: self = .up
            case .upMirrored: self = .upMirrored
            case .down: self = .down
            case .downMirrored: self = .downMirrored
            case .left: self = .left
            case .leftMirrored: self = .leftMirrored
            case .right: self = .right
            case .rightMirrored: self = .rightMirrored
            default: self = .up
        }
    }
}

extension UIImage.Orientation {
    init(_ cgOrientation: CGImagePropertyOrientation) {
        switch cgOrientation {
            case .up: self = .up
            case .upMirrored: self = .upMirrored
            case .down: self = .down
            case .downMirrored: self = .downMirrored
            case .left: self = .left
            case .leftMirrored: self = .leftMirrored
            case .right: self = .right
            case .rightMirrored: self = .rightMirrored
            default: self = .up
        }
    }
}
