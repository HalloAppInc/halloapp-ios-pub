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
    var type: FeedMediaType { media.type }
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
    @Published var drawingColor = UIColor.red
    @Published var drawingLineWidth: CGFloat = 8
    @Published var drawnItems: [PendingPath] = []

    @Published var undoStack: [PendingUndo] = []

    private var original: UIImage?
    private var numberOfRotations = 0
    private var hFlipped = false
    private var vFlipped = false

    private let cropRegion: MediaEditCropRegion
    private let maxAspectRatio: CGFloat?

    init(cropRegion: MediaEditCropRegion, maxAspectRatio: CGFloat?, media: PendingMedia) {
        self.cropRegion = cropRegion
        self.maxAspectRatio = maxAspectRatio
        self.media = media

        if let edit = media.edit {
            original = edit.image
            cropRect = edit.cropRect
            hFlipped = edit.hFlipped
            vFlipped = edit.vFlipped
            numberOfRotations = edit.numberOfRotations
            scale = edit.scale
            offset = edit.offset
            drawnItems.append(contentsOf: edit.drawnItems)
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
                    || edit.drawnItems != drawnItems
            }

            return initialCrop() != cropRect
                || hFlipped
                || vFlipped
                || numberOfRotations != 0
                || scale != 1.0
                || offset != .zero
                || drawnItems.count > 0
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
        return type == .image && cropRegion != .any
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
            edit.drawnItems = drawnItems
            edit.undoStack = undoStack

            media.edit = edit

            // Keeps reference to self, otherwise cropping might not happen
            PendingMedia.queue.async {
                guard let image = self.crop() else {
                    return self.media.error.send(PendingMediaError.processingError)
                }
                self.media.image = image
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
            drawnItems = []

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
        guard let image = original?.cgImage else { return }

        var rotations = numberOfRotations

        switch original?.imageOrientation {
        case .right:
            rotations += 3
        case .left:
            rotations += 1
        case .down:
            rotations += 2
        default:
            break
        }

        let size = (rotations % 2) == 0 ? CGSize(width: image.width, height: image.height) : CGSize(width: image.height, height: image.width)

        let transform = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
            .scaledBy(x: vFlipped ? -1 : 1, y: hFlipped ? -1 : 1)
            .rotated(by: CGFloat(rotations) * .pi / 2)
            .translatedBy(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2)

        let ciimage = CIImage(cgImage: image).transformed(by: transform)
        guard let transformed = CIContext().createCGImage(ciimage, from: CGRect(x: 0, y: 0, width: size.width, height: size.height), format: .RGBA8, colorSpace: image.colorSpace) else {
            self.image = nil
            return
        }

        self.image = UIImage(cgImage: transformed)
    }

    private func initialCrop() -> CGRect {
        guard type == .image else { return .zero }
        guard let image = original else { return .zero }

        switch cropRegion {
        case .circle, .square:
            let size = min(image.size.width, image.size.height)
            return CGRect(x: image.size.width / 2 - size / 2, y: image.size.height / 2  - size / 2, width: size, height: size)
        case .any:
            var crop = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)

            if let maxAspectRatio = maxAspectRatio, crop.size.height / crop.size.width > maxAspectRatio {
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

        if let maxAspectRatio = maxAspectRatio {
            let ratio = cropRect.size.height / cropRect.size.width
            cropRect.size.height = cropRect.size.width * min(maxAspectRatio, ratio)
        }

        drawnItems = drawnItems.map {
            let points = $0.points.map { CGPoint(x: $0.y, y: image.size.width - $0.x) }
            return PendingPath(points: points, color: $0.color, width: $0.width)
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

        drawnItems = drawnItems.map {
            let points = $0.points.map { CGPoint(x: image.size.width - $0.x, y: $0.y) }
            return PendingPath(points: points, color: $0.color, width: $0.width)
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
        guard let image = image?.cgImage else { return nil }

        let contextCenterX = cropRect.size.width / 2
        let contextCenterY = cropRect.size.height / 2
        let imgCenterX = CGFloat(image.width) / 2
        let imgCenterY = CGFloat(image.height) / 2
        let cropOffsetX = cropRect.midX - imgCenterX
        let cropOffsetY = (CGFloat(image.height) - cropRect.midY) - imgCenterY

        let transformImage = CGAffineTransform(translationX: contextCenterX, y: contextCenterY)
            .translatedBy(x: -cropOffsetX, y: -cropOffsetY)
            .translatedBy(x: offset.x, y: -offset.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -imgCenterX, y: -imgCenterY)

        let transformDrawing = CGAffineTransform(translationX: contextCenterX, y: contextCenterY)
            .translatedBy(x: -cropOffsetX, y: cropOffsetY)
            .translatedBy(x: offset.x, y: offset.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -imgCenterX, y: -imgCenterY)


        return UIGraphicsImageRenderer(size: cropRect.size).image { ctx in
            ctx.cgContext.saveGState()
            // fix coordinate system
            ctx.cgContext.translateBy(x: 0, y: cropRect.size.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)

            ctx.cgContext.concatenate(transformImage)
            ctx.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            ctx.cgContext.restoreGState()

            ctx.cgContext.saveGState()
            ctx.cgContext.concatenate(transformDrawing)
            ctx.cgContext.setLineCap(.round)
            ctx.cgContext.setLineJoin(.round)
            for item in drawnItems {
                guard item.points.count > 0 else { return }
                ctx.cgContext.setStrokeColor(item.color.cgColor)
                ctx.cgContext.setLineWidth(item.width)
                ctx.cgContext.beginPath()

                ctx.cgContext.move(to: item.points[0])
                MediaEdit.curves(item.points).forEach { ctx.cgContext.addCurve(to: $0.to, control1: $0.control1, control2: $0.control2) }

                ctx.cgContext.strokePath()
            }
            ctx.cgContext.restoreGState()
        }
    }

    func undo() {
        guard let item = undoStack.popLast() else { return }

        switch item {
        case .removeDrawing:
            drawnItems.removeLast()
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

