//
//  MediaEdit.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import AVKit
import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import Foundation
import UIKit

class MediaEdit : ObservableObject {
    // Common properties
    @Published var image: UIImage?

    let media: PendingMedia
    var type: CommonMediaType { media.type }
    private var cancellable: AnyCancellable?

    // Video properties
    @Published var muted = false
    @Published var start: CGFloat = 0
    @Published var end: CGFloat = 1

    // Image properties
    @Published var cropRect = CGRect.zero
    @Published var scale: CGFloat = 1.0
    @Published var offset = CGPoint.zero

    // Drawing properties
    @Published var isDrawing = false
    @Published var isAnnotating = false
    @Published var isDraggingAnnotation = false
    @Published var drawingColor = UIColor.red
    @Published var drawingLineWidth: CGFloat = 8
    @Published var annotationFont = UIFont.gothamFont(ofFixedSize: 32, weight: .medium)
    @Published var layers = [PendingLayer]()

    @Published var undoStack: [PendingUndo] = []

    private var original: UIImage?
    private var numberOfRotations = 0
    private var hFlipped = false
    private var vFlipped = false

    private let config: MediaEditConfig

    init(config: MediaEditConfig, media: PendingMedia) {
        self.config = config
        self.media = media

        if let edit = media.edit {
            original = edit.image
            cropRect = edit.cropRect
            hFlipped = edit.hFlipped
            vFlipped = edit.vFlipped
            numberOfRotations = edit.numberOfRotations
            scale = edit.scale
            offset = edit.offset
            layers.append(contentsOf: edit.layers)
            undoStack.append(contentsOf: edit.undoStack)
        } else {
            original = media.image
        }

        if let edit = media.videoEdit {
            muted = edit.muted
            start = edit.start
            end = edit.end
        }

        load()
    }

    deinit {
        cancellable?.cancel()
    }

    private func load() {
        switch type {
        case .image:
            if media.ready.value {
                updateImage()

                if media.edit == nil {
                    cropRect = initialCrop()
                }
            } else {
                cancellable = media.ready.sink { [weak self] ready in
                    guard let self = self else { return }
                    guard ready else { return }

                    self.original = self.media.image
                    self.updateImage()

                    if self.media.edit == nil {
                        self.cropRect = self.initialCrop()
                    }
                }
            }
        case .video:
            if let url = media.fileURL {
                let asset = AVURLAsset(url: url, options: nil)
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true

                let time = CMTimeMakeWithSeconds(0.0, preferredTimescale: 600)
                var actualTime = CMTimeMake(value: 0, timescale: 0)
                let cgImage: CGImage
                do {
                    cgImage = try gen.copyCGImage(at: time, actualTime: &actualTime)
                } catch {
                    return
                }

                image = UIImage(cgImage: cgImage)
            }
        case .audio:
            break // audio edit is not currently suported
        }
    }

    func hasChanges() -> Bool {
        switch type {
        case .image:
            if let edit = media.edit {
                return edit.cropRect != cropRect
                    || edit.hFlipped != hFlipped
                    || edit.vFlipped != vFlipped
                    || edit.numberOfRotations != numberOfRotations
                    || edit.scale != scale
                    || edit.offset != offset
                    || edit.layers != layers
            }

            return initialCrop() != cropRect
                || hFlipped
                || vFlipped
                || numberOfRotations != 0
                || scale != 1.0
                || offset != .zero
                || layers.count > 0
        case .video:
            if let edit = media.videoEdit {
                return edit.muted != muted || edit.start != start || edit.end != end
            }

            return muted || start != 0.0 || end != 1.0
        case .audio:
            return false // audio edit is not currently suported
        }
    }

    func shouldProcess() -> Bool {
        return type == .image && config.cropRegion != .any
    }

    func process() -> PendingMedia {
        guard hasChanges() || shouldProcess() else { return media }
        media.resetProgress()

        switch type {
        case .image:
            var edit = PendingMediaEdit(image: original, url: media.fileURL)
            edit.cropRect = cropRect
            edit.hFlipped = hFlipped
            edit.vFlipped = vFlipped
            edit.numberOfRotations = numberOfRotations
            edit.scale = scale
            edit.offset = offset
            edit.layers = layers
            edit.undoStack = undoStack

            media.edit = edit

            // Keeps reference to self, otherwise cropping might not happen
            PendingMedia.queue.async {
                autoreleasepool {
                    guard let image = self.crop() else {
                        return self.media.error.send(PendingMediaError.processingError)
                    }
                    self.media.image = image
                }
            }
        case .video:
            guard let originalVideoURL = media.originalVideoURL else { return media }
            media.videoEdit = PendingVideoEdit(start: start, end: end, muted: muted)

            let duration = AVURLAsset(url: originalVideoURL).duration
            guard duration.isNumeric else { return media }

            let startTime = CMTimeMultiplyByFloat64(duration, multiplier: Float64(start))
            let endTime = CMTimeMultiplyByFloat64(duration, multiplier: Float64(end))

            // Keeps reference to self, otherwise cropping might not happen
            VideoUtils.trim(start: startTime, end: endTime, url: originalVideoURL, mute: muted) { result in
                switch(result) {
                case .success(let url):
                    self.media.fileURL = url
                case .failure(let error):
                    DDLogWarn("MediaEdit/process trimming failed url=[\(originalVideoURL.description)] error=[\(error.localizedDescription)]")
                    self.media.error.send(error)
                }
            }
        case .audio:
            break // audio edit is not currently suported
        }

        return media
    }

    func reset() {
        switch type {
        case .image:
            numberOfRotations = 0
            vFlipped = false
            hFlipped = false
            scale = 1.0
            offset = .zero
            cropRect = initialCrop()
            layers = []

            updateImage()
        case .video:
            muted = false
            start = 0.0
            end = 1.0
        case .audio:
            break // audio edit is not currently suported
        }

        undoStack = []
    }

    func updateImage() {
        guard type == .image else { return }
        guard var orientation = original?.imageOrientation else { return }
        guard let cgImage = original?.cgImage else { return }

        if numberOfRotations >= 1 {
            for _ in 1...numberOfRotations {
                switch orientation {
                case .up:
                    orientation = .left
                case .down:
                    orientation = .right
                case .left:
                    orientation = .down
                case .right:
                    orientation = .up
                case .upMirrored:
                    orientation = .leftMirrored
                case .downMirrored:
                    orientation = .rightMirrored
                case .leftMirrored:
                    orientation = .downMirrored
                case .rightMirrored:
                    orientation = .upMirrored
                default:
                    break
                }
            }
        }

        if vFlipped {
            switch orientation {
            case .up:
                orientation = .upMirrored
            case .down:
                orientation = .downMirrored
            case .left:
                orientation = .rightMirrored
            case .right:
                orientation = .leftMirrored
            case .upMirrored:
                orientation = .up
            case .downMirrored:
                orientation = .down
            case .leftMirrored:
                orientation = .right
            case .rightMirrored:
                orientation = .left
            default:
                break
            }
        }

        if hFlipped {
            switch orientation {
            case .up:
                orientation = .downMirrored
            case .down:
                orientation = .upMirrored
            case .left:
                orientation = .leftMirrored
            case .right:
                orientation = .rightMirrored
            case .upMirrored:
                orientation = .down
            case .downMirrored:
                orientation = .up
            case .leftMirrored:
                orientation = .left
            case .rightMirrored:
                orientation = .right
            default:
                break
            }
        }

        image = UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }

    private func initialCrop() -> CGRect {
        guard type == .image else { return .zero }
        guard let image = original else { return .zero }

        switch config.cropRegion {
        case .circle, .square:
            let size = min(image.size.width, image.size.height)
            return CGRect(x: image.size.width / 2 - size / 2, y: image.size.height / 2  - size / 2, width: size, height: size)
        case .any:
            var crop = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)

            if let maxAspectRatio = config.maxAspectRatio, crop.size.height / crop.size.width > maxAspectRatio {
                crop.size.height = (crop.size.width * maxAspectRatio).rounded()
                crop.origin.y = image.size.height / 2 - crop.size.height / 2
            }

            return crop
        }
    }

    func rotate(withUndo: Bool = true) {
        guard type == .image else { return }
        guard let image = image else { return }

        numberOfRotations = (numberOfRotations + 1) % 4

        swap(&vFlipped,  &hFlipped)

        let w = cropRect.size.width
        let h = cropRect.size.height
        let x = cropRect.origin.x
        let y = cropRect.origin.y
        let ox = offset.x
        let oy = offset.y

        cropRect.size.width = h
        cropRect.size.height = w
        cropRect.origin.x = y
        cropRect.origin.y = image.size.width - w - x
        offset.x = oy
        offset.y = -ox

        if let maxAspectRatio = config.maxAspectRatio {
            let ratio = cropRect.size.height / cropRect.size.width
            cropRect.size.height = cropRect.size.width * min(maxAspectRatio, ratio)
        }

        layers = layers.map {
            switch $0 {
            case .path(var path):
                path.points = path.points.map { CGPoint(x: $0.y, y: image.size.width - $0.x) }
                return .path(path)
            case .annotation(var annotation):
                annotation.location = CGPoint(x: annotation.location.y, y: image.size.width - annotation.location.x)
                annotation.rotation -= 90
                return .annotation(annotation)
            }
        }

        updateImage()

        if withUndo {
            undoStack.append(.rotateReverse)
        }
    }

    func flip(withUndo: Bool = true) {
        guard type == .image else { return }
        guard let image = image else { return }

        vFlipped.toggle()
        cropRect.origin.x = image.size.width - cropRect.size.width - cropRect.origin.x
        offset.x = -offset.x

        layers = layers.map {
            switch $0 {
            case .path(var path):
                path.points = path.points.map { CGPoint(x: image.size.width - $0.x, y: $0.y) }
                return .path(path)
            case .annotation(var annotation):
                annotation.location.x = image.size.width - annotation.location.x
                return .annotation(annotation)
            }
        }

        updateImage()

        if withUndo {
            undoStack.append(.flip)
        }
    }

    func zoom(_ scale: CGFloat) {
        guard type == .image else { return }
        guard let image = image else { return }
        guard 1.0 <= scale && scale <= 10.0 else { return }
        self.scale = scale

        let w = image.size.width
        let h = image.size.height

        let minX = (1 - scale) * (w / 2) + offset.x
        let minY = (1 - scale) * (h / 2) + offset.y
        let maxX = minX + scale * w
        let maxY = minY + scale * h

        if minX > 0 {
            offset.x = (scale - 1) * (w / 2)
        } else if maxX < w {
            offset.x = (1 - scale) * (w / 2)
        }

        if minY > 0 {
            offset.y = (scale - 1) * (h / 2)
        } else if maxY < h {
            offset.y = (1 - scale) * (h / 2)
        }
    }

    func move(_ offset: CGPoint) {
        guard type == .image else { return }
        guard let image = image else { return }
        let w = image.size.width
        let h = image.size.height

        let minX = (1 - scale) * (w / 2) + offset.x
        let minY = (1 - scale) * (h / 2) + offset.y
        let maxX = minX + scale * w
        let maxY = minY + scale * h

        guard minX <= 0 else { return }
        guard minY <= 0 else { return }
        guard maxX >= w else { return }
        guard maxY >= h else { return }

        self.offset = offset
    }

    func crop() -> UIImage? {
        guard type == .image else { return nil }
        guard let image = image else { return nil }

        let contextCenterX = cropRect.size.width / 2
        let contextCenterY = cropRect.size.height / 2
        let imgCenterX = CGFloat(image.size.width) / 2
        let imgCenterY = CGFloat(image.size.height) / 2
        let cropOffsetX = cropRect.midX - imgCenterX
        let cropOffsetY = (CGFloat(image.size.height) - cropRect.midY) - imgCenterY

        let transformImage = CGAffineTransform(translationX: contextCenterX, y: contextCenterY)
            .translatedBy(x: -cropOffsetX, y: cropOffsetY)
            .translatedBy(x: offset.x, y: offset.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -imgCenterX, y: -imgCenterY)

        let transformDrawing = CGAffineTransform(translationX: contextCenterX, y: contextCenterY)
            .translatedBy(x: -cropOffsetX, y: cropOffsetY)
            .translatedBy(x: offset.x, y: offset.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -imgCenterX, y: -imgCenterY)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        return UIGraphicsImageRenderer(size: cropRect.size, format: format).image { ctx in
            ctx.cgContext.saveGState()
            ctx.cgContext.concatenate(transformImage)
            image.draw(at: .zero)
            ctx.cgContext.restoreGState()

            for item in layers {
                switch item {
                case .path(let path):
                    guard path.points.count > 0 else { continue }
                    ctx.cgContext.saveGState()
                    ctx.cgContext.concatenate(transformDrawing)
                    ctx.cgContext.setLineCap(.round)
                    ctx.cgContext.setLineJoin(.round)

                    ctx.cgContext.setStrokeColor(path.color.cgColor)
                    ctx.cgContext.setLineWidth(path.width)
                    ctx.cgContext.beginPath()

                    ctx.cgContext.move(to: path.points[0])
                    MediaEdit.curves(path.points).forEach { ctx.cgContext.addCurve(to: $0.to, control1: $0.control1, control2: $0.control2) }

                    ctx.cgContext.strokePath()

                    ctx.cgContext.restoreGState()
                case .annotation(let annotation):
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.alignment = .center

                    let attrs = [
                        NSAttributedString.Key.paragraphStyle: paragraphStyle,
                        NSAttributedString.Key.font: annotation.font,
                        NSAttributedString.Key.foregroundColor: annotation.color,
                    ]

                    ctx.cgContext.saveGState()
                    ctx.cgContext.concatenate(transformDrawing)
                    ctx.cgContext.translateBy(x: annotation.location.x, y: annotation.location.y)
                    ctx.cgContext.rotate(by: annotation.rotation * CGFloat.pi / 180)

                    let width = CGFloat(image.size.width)
                    let height = CGFloat(image.size.height)
                    let frame = CGRect(x:  -width / 2, y:  -annotation.font.pointSize / 2, width: width, height: height)
                    annotation.text.draw(with: frame, options: .usesLineFragmentOrigin, attributes: attrs, context: nil)

                    ctx.cgContext.restoreGState()
                }
            }

        }
    }

    func undo() {
        guard let item = undoStack.popLast() else { return }

        switch item {
        case .remove:
            layers.removeLast()
        case .restore((let idx, let layer)):
            layers[idx] = layer
        case .insert((let idx, let layer)):
            layers.insert(layer, at: idx)
        case .flip:
            flip(withUndo: false)
        case .rotateReverse:
            rotate(withUndo: false)
            rotate(withUndo: false)
            rotate(withUndo: false)
        }
    }

    // Hermite splines
    // https://spin.atomicobject.com/2014/05/28/ios-interpolating-points/
    static func curves(_ rawPoints: [CGPoint]) -> [(to: CGPoint, control1: CGPoint, control2: CGPoint)] {
        let points = sample(points: rawPoints)

        guard points.count > 1 else { return [] }

        var curves: [(to: CGPoint, control1: CGPoint, control2: CGPoint)] = []
        var previous = CGPoint.zero
        var current = points[0]
        var next = points[1]

        for index in 0 ..< points.count - 1 {
            let end = next

            var mx: CGFloat
            var my: CGFloat

            if index > 0 {
                mx = (next.x - current.x) * 0.5 + (current.x - previous.x)*0.5
                my = (next.y - current.y) * 0.5 + (current.y - previous.y)*0.5
            } else {
                mx = (next.x - current.x) * 0.5
                my = (next.y - current.y) * 0.5
            }

            let ctrlPt1 = CGPoint(x: current.x + mx / 3.0, y: current.y + my / 3.0)

            previous = current
            current = next
            let nextIndex = index + 2

            if nextIndex < points.count {
                next = points[nextIndex]

                mx = (next.x - current.x) * 0.5 + (current.x - previous.x) * 0.5
                my = (next.y - current.y) * 0.5 + (current.y - previous.y) * 0.5
            } else {
                mx = (current.x - previous.x) * 0.5
                my = (current.y - previous.y) * 0.5
            }

            let ctrlPt2 = CGPoint(x: current.x - mx / 3.0, y: current.y - my / 3.0)

            curves.append((to: end, control1: ctrlPt1, control2: ctrlPt2))

            if nextIndex >= points.count {
                break
            }
        }

        return curves
    }

    static func sample(points: [CGPoint]) -> [CGPoint] {
        guard points.count > 1 else { return [] }

        let mindistsq: CGFloat = 24 * 24
        var sampled: [CGPoint] = [points[0]]

        for p in points {
            guard let current = sampled.last else { break }

            let distsq = (current.x - p.x) * (current.x - p.x) + (current.y - p.y) * (current.y - p.y)
            if distsq > mindistsq {
                sampled.append(p)
            }
        }

        if points.last != sampled.last, let last = points.last {
            sampled.append(last)
        }

        return sampled
    }
}

