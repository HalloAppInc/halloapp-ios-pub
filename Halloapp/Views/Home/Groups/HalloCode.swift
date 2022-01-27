//
//  HalloCode.swift
//  HalloApp
//
//  Created by Tanveer on 1/17/22.
//

import UIKit

/// A custom QR code that incorporates HalloApp's design language.
class HalloCode: UIImageView {
    let string: String
    //let cg: CGImage
    private let reader: ModuleReader
    /// The width of one QR code module, scaled accordingly.
    private let moduleWidth: CGFloat
    /// The bounds for the code excluding its margin.
    private let innerRect: CGRect
    
    
    init?(frame: CGRect, string: String) {
        self.string = string
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        
        let data = string.data(using: .utf8)
        let ec = "H"
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(ec, forKey: "inputCorrectionLevel")
        
        guard let output = filter.outputImage else {
            return nil
        }
        
        let context = CIContext(options: nil)
        guard
            let cg = context.createCGImage(output, from: output.extent),
            let reader = ModuleReader(cg)
        else {
            return nil
        }

        self.reader = reader
        
        let moduleDiameter = floor(frame.width / CGFloat(cg.width))
        let inner = CGRect(origin: .zero,
                             size: frame.size).insetBy(dx: 3 * moduleDiameter, dy: 3 * moduleDiameter)
        self.innerRect = inner
        self.moduleWidth = inner.width / CGFloat(cg.width)
        
        super.init(frame: frame)
        self.image = drawCode()
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
}


// MARK: - computed properties for drawing

extension HalloCode {
    /// The code's margin that we use as an offset when drawing.
    private var drawingOffset: CGFloat {
        return innerRect.minX
    }
    /// The area that is used to prevent modules from being drawn where the icon will be.
    private var iconExclusion: CGRect? {
        guard let iconModuleCount = iconModuleCount else {
            return nil
        }
        
        let exclusionWidth = moduleWidth * iconModuleCount
        let difference = (bounds.width - exclusionWidth) / 2
        return bounds.insetBy(dx: difference, dy: difference)
    }
    /// The area where the icon is located.
    private var iconFrame: CGRect? {
        return iconExclusion?.insetBy(dx: moduleWidth, dy: moduleWidth)
    }
    /// The width and height of the icon, measured in modules. `nil` if no icon should be displayed.
    private var iconModuleCount: CGFloat? {
        let moduleCount = CGFloat(reader.context.width)
        if moduleCount < 32 {
            return nil
        } else if moduleCount < 34 {
            return 10
        } else if moduleCount < 36 {
            return 12
        } else if moduleCount < 41 {
            return 14
        } else if moduleCount < 51 {
            return 16
        } else {
            return 20
        }
    }
    ///
    var cornerRadius: CGFloat {
        return 3.5
    }
}


// MARK: - drawing methods

extension HalloCode {
    private func drawCode() -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let image = renderer.image { context in
            self.drawModules(context.cgContext)
            self.drawPatterns(context.cgContext)
            self.drawIcon(context.cgContext)
        }
        
        return image
    }
    
    private func drawModules(_ context: CGContext) {
        let exclusion = iconExclusion
        UIColor.white.setFill()
        context.fill(self.bounds)
        
        for i in 0..<reader.context.width {
            for j in 0..<reader.context.height {
                let x = CGFloat(j)
                let y = CGFloat(i)
                let moduleRect = CGRect(x: (x * moduleWidth) + drawingOffset,
                                        y: (y * moduleWidth) + drawingOffset,
                                    width: moduleWidth,
                                   height: moduleWidth).insetBy(dx: 0.1 * moduleWidth, dy: 0.1 * moduleWidth)
                
                guard !(exclusion?.intersects(moduleRect) ?? false) else {
                    // don't draw modules where the icon will eventually be
                    continue
                }
                
                let isOn = reader.moduleValue(at: CGPoint(x: x, y: y))
                let color = isOn ? UIColor.black : UIColor.white
                color.setFill()
                context.fillEllipse(in: moduleRect)
            }
        }
    }
    
    private func drawPatterns(_ context: CGContext) {
        let size = CGSize(width: CGFloat(reader.context.width), height: CGFloat(reader.context.height))
        
        removeExistingFinders(context, size)
        drawFinderPatterns(context, size)
        drawInnerFinderPatterns(context, size)
    }
    
    private func removeExistingFinders(_ context: CGContext, _ size: CGSize) {
        let finderWidth = 7 * moduleWidth
        let f1 = CGRect(x: moduleWidth + drawingOffset,
                        y: moduleWidth + drawingOffset,
                    width: finderWidth,
                   height: finderWidth)

        let f2 = CGRect(x: (moduleWidth) + drawingOffset,
                        y: ((size.height * moduleWidth) - (8 * moduleWidth)) + drawingOffset,
                    width: finderWidth,
                   height: finderWidth)
        
        let f3 = CGRect(x: ((size.width * moduleWidth) - (8 * moduleWidth)) + drawingOffset,
                        y: moduleWidth + drawingOffset,
                    width: finderWidth,
                   height: finderWidth)
        
        UIColor.white.setFill()
        context.fill(f1)
        context.fill(f2)
        context.fill(f3)
    }
    
    private func drawFinderPatterns(_ context: CGContext, _ size: CGSize) {
        let strokeWidth = moduleWidth * 0.64
        let finderWidth = 7 * moduleWidth
        let finderInset = strokeWidth / 2
        let outerRadius = finderWidth / cornerRadius
        
        context.setLineWidth(strokeWidth)
        context.setStrokeColor(UIColor.black.cgColor)
        context.setFillColor(UIColor.black.cgColor)
        
        // finder 1
        var rect = CGRect(x: moduleWidth + drawingOffset,
                          y: moduleWidth + drawingOffset,
                      width: finderWidth,
                     height: finderWidth).insetBy(dx: finderInset, dy: finderInset)
        var rounded = UIBezierPath.init(roundedRect: rect, cornerRadius: outerRadius)
        context.addPath(rounded.cgPath)
        context.strokePath()

        // finder 2
        rect = CGRect(x: moduleWidth + drawingOffset,
                      y: ((size.height * moduleWidth) - (8 * moduleWidth)) + drawingOffset,
                  width: finderWidth,
                 height: finderWidth).insetBy(dx: finderInset, dy: finderInset)
        rounded = UIBezierPath.init(roundedRect: rect, cornerRadius: outerRadius)
        context.addPath(rounded.cgPath)
        context.strokePath()
        
        // finder 3
        rect = CGRect(x: ((size.width * moduleWidth) - (8 * moduleWidth)) + drawingOffset,
                      y: moduleWidth + drawingOffset,
                  width: finderWidth,
                 height: finderWidth).insetBy(dx: finderInset, dy: finderInset)
        rounded = UIBezierPath.init(roundedRect: rect, cornerRadius: outerRadius)
        context.addPath(rounded.cgPath)
        context.strokePath()
    }
    
    private func drawInnerFinderPatterns(_ context: CGContext, _ size: CGSize) {
        guard let outlineImage = UIImage(named: "QRIconOutline") else {
            return
        }
        
        let innerWidth = 3 * moduleWidth
        let oldHeight = innerWidth
        let newWidth = oldHeight
        let newHeight = (outlineImage.size.height * newWidth) / outlineImage.size.width
        let innerFinderOffset = (newHeight - oldHeight) / 2
        
        // inner finder 1
        var rect = CGRect(x: innerWidth + drawingOffset,
                          y: innerWidth + drawingOffset,
                      width: innerWidth,
                     height: innerWidth)
        
        rect.size = CGSize(width: newWidth, height: newHeight)
        rect.origin.y -= innerFinderOffset
        context.draw(outlineImage.cgImage!, in: rect)
        
        // inner finder 2
        rect = CGRect(x: innerWidth + drawingOffset,
                      y: ((size.height * moduleWidth) - (6 * moduleWidth)) + drawingOffset,
                  width: innerWidth,
                 height: innerWidth)

        rect.size = CGSize(width: newWidth, height: newHeight)
        rect.origin.y -= innerFinderOffset
        context.draw(outlineImage.cgImage!, in: rect)
        
        // inner finder 3
        rect = CGRect(x: ((size.width * moduleWidth) - (6 * moduleWidth)) + drawingOffset,
                      y: innerWidth + drawingOffset,
                  width: innerWidth,
                 height: innerWidth)

        rect.size = CGSize(width: newWidth, height: newHeight)
        rect.origin.y -= innerFinderOffset
        context.draw(outlineImage.cgImage!, in: rect)
    }
    
    private func drawIcon(_ context: CGContext) {
        guard
            let iconFrame = iconFrame,
            let iconImage = UIImage(named: "QRIcon")
        else {
            return
        }

        let iconView = UIImageView(image: iconImage)
        iconView.frame = iconFrame
        iconView.contentMode = .scaleAspectFit

        let radius = iconView.bounds.width / cornerRadius
        let size = CGSize(width: radius, height: radius)
        let path = UIBezierPath(roundedRect: iconView.bounds, byRoundingCorners: .allCorners, cornerRadii: size)
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        iconView.layer.mask = mask
        
        context.translateBy(x: iconFrame.minX, y: iconFrame.minY)
        iconView.layer.render(in: context)
    }
}


// MARK: - Module Reader implementation
//
// inspired by https://stackoverflow.com/a/34596653

/// A helper class for determining the value of a specific QR code module.
fileprivate class ModuleReader {
    let context: CGContext
    private let ptr: UnsafeMutablePointer<UInt32>
    
    init?(_ cg: CGImage) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * cg.width
        let bitsPerComponent = 8
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        
        guard
            let context = CGContext(data: nil,
                                   width: cg.width,
                                  height: cg.height,
                        bitsPerComponent: bitsPerComponent,
                             bytesPerRow: bytesPerRow,
                                   space: colorSpace,
                              bitmapInfo: bitmapInfo),
            let ptr = context.data?.bindMemory(to: UInt32.self, capacity: cg.height * cg.width)
        else {
            return nil
        }
        
        self.context = context
        self.ptr = ptr
        self.context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    }
    
    func moduleValue(at point: CGPoint) -> Bool {
        let i = context.width * Int(point.y) + Int(point.x)
        let pixel = UInt8(ptr[i] & 255)

        return pixel == 0
    }
}
