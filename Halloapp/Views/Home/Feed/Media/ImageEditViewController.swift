//
//  ImageEditViewController.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation

import AVKit
import Combine
import Core
import CoreCommon
import Dispatch
import Foundation
import SwiftUI
import UIKit

class ImageEditViewController: UIHostingController<ImageEditView> {

    init(_ media: MediaEdit, cropRegion: MediaEditCropRegion = .any, maxAspectRatio: CGFloat? = nil) {
        super.init(rootView: ImageEditView(media: media, cropRegion: cropRegion, maxAspectRatio: maxAspectRatio))
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(mediaEdit:)")
    }
}

struct ImageEditView: View {
    private enum CropRegionSection {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, inside, none
    }

    private let threshold = CGFloat(44)
    private let outThreshold = CGFloat(22)
    private let epsilon = CGFloat(1e-6)

    @ObservedObject var media: MediaEdit
    let cropRegion: MediaEditCropRegion
    let maxAspectRatio: CGFloat?

    @State private var isDragging = false
    @State private var startingOffset = CGPoint.zero
    @State private var lastLocation = CGPoint.zero
    @State private var currentCropSection: CropRegionSection = .none
    @State private var currentPath: [CGPoint] = []

    private func findCropSection(_ crop: CGRect, location: CGPoint) -> CropRegionSection {
        let vThreshold = min(threshold, crop.width / 3)
        let hThreshold = min(threshold, crop.height / 3)
        let isTop = (crop.minY - outThreshold < location.y) && (location.y < (crop.minY + vThreshold))
        let isBottom = ((crop.maxY - vThreshold) < location.y) && (location.y < crop.maxY + outThreshold)
        let isLeft = (crop.minX - outThreshold < location.x) && (location.x < (crop.minX + hThreshold))
        let isRight = ((crop.maxX - hThreshold) < location.x) && (location.x < crop.maxX + outThreshold)

        switch (isLeft, isTop, isRight, isBottom) {
        case (true, true, _, _):
            return .topLeft
        case (_, true, true, _):
            return .topRight
        case (_, _, true, true):
            return .bottomRight
        case (true, _, _, true):
            return .bottomLeft
        case (_, true, _, _):
            return .top
        case (_, _, _, true):
            return .bottom
        case (true, _, _, _):
            return .left
        case (_, _, true, _):
            return .right
        default:
            break
        }

        let isInsideVertical = crop.minY <= location.y && location.y <= crop.maxY
        let isInsideHorizontal = crop.minX <= location.x && location.x <= crop.maxX
        if isInsideVertical && isInsideHorizontal {
            return .inside
        }

        return .none
    }

    private func newCropRegion(_ crop: CGRect, deltaX: CGFloat = 0, deltaY: CGFloat = 0) -> CGRect {
        var crop = crop

        switch currentCropSection {
        case .top, .topLeft, .topRight:
            crop.origin.y += deltaY
            crop.size.height -= deltaY
        case .bottom, .bottomLeft, .bottomRight:
            crop.size.height += deltaY
        default:
            break
        }

        switch currentCropSection {
        case .left, .bottomLeft, .topLeft:
            crop.origin.x += deltaX
            crop.size.width -= deltaX
        case .right, .bottomRight, .topRight:
            crop.size.width += deltaX
        default:
            break
        }

        if currentCropSection == .inside {
            crop.origin.x += deltaX
            crop.origin.y += deltaY
        }

        if let maxAspectRatio = maxAspectRatio, (crop.size.height / crop.size.width) - maxAspectRatio > epsilon {
            switch currentCropSection {
            case .none, .inside:
                break
            case .left, .right:
                let height = maxAspectRatio * crop.size.width
                crop.origin.y -= (height - crop.size.height) / 2
                crop.size.height = height
            default:
                let width = crop.size.height / maxAspectRatio
                crop.origin.x -= (width - crop.size.width) / 2
                crop.size.width = width
            }
        }

        return crop
    }

    private func isCropRegionWithinLimit(_ crop: CGRect, limit: CGSize) -> Bool {
        return crop.minX >= -epsilon && crop.minY >= -epsilon && crop.maxX <= limit.width + epsilon && crop.maxY <= limit.height + epsilon
    }

    private func isCropRegionMinSize(_ crop: CGRect) -> Bool {
        return crop.size.height > threshold && crop.size.width > threshold
    }

    private func isCropRegionValid(_ crop: CGRect, limit: CGSize) -> Bool {
        return isCropRegionWithinLimit(crop, limit: limit) && isCropRegionMinSize(crop)
    }

    private func scaleCropRegion(_ crop: CGRect, from: CGSize, to: CGSize) -> CGRect {
        let scale = to.height / from.height
        var scaledCrop = crop.applying(CGAffineTransform(scaleX: scale, y: scale))

        scaledCrop.origin.x = max(0, scaledCrop.origin.x)
        scaledCrop.origin.y = max(0, scaledCrop.origin.y)
        scaledCrop.size.width -= max(0, scaledCrop.maxX - to.width)
        scaledCrop.size.height -= max(0, scaledCrop.maxY - to.height)

        return scaledCrop
    }

    private func scaleOffset(_ offset: CGPoint, containerSize: CGSize, imageSize: CGSize) -> CGSize {
        var scale: CGFloat = 1.0
        if imageSize.width > containerSize.width || imageSize.height > containerSize.height {
            scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        }

        return CGSize(width: offset.x * scale, height: offset.y * scale)
    }

    private func scale(path: PendingPath, from: CGSize, to: CGSize) -> PendingPath {
        let baseScale = to.width / from.width
        let points = path.points.map {
            $0.applying(CGAffineTransform(scaleX: baseScale, y: baseScale))
        }

        return PendingPath(points: points, color: path.color, width: path.width * baseScale)
    }

    private func onDragCropRegion(_ location: CGPoint, in region: CGSize) {
        guard let imageSize = media.image?.size else { return }

        var crop = scaleCropRegion(media.cropRect, from: imageSize, to: region)

        if currentCropSection == .none {
            lastLocation = location
            currentCropSection = findCropSection(crop, location: location)

            guard currentCropSection != .none else { return }

            switch cropRegion {
            case .circle, .square:
                currentCropSection = .inside
            case .any:
                break
            }
        } else {
            let valid = crop.insetBy(dx: -2 * outThreshold, dy: -2 * outThreshold)
            if !valid.contains(location) {
                return
            }
        }

        let deltaX = location.x - lastLocation.x
        let deltaY = location.y - lastLocation.y
        lastLocation = location

        var result = newCropRegion(crop, deltaX: deltaX)
        if isCropRegionValid(result, limit: region) {
            crop = result
        }

        result = newCropRegion(crop, deltaY: deltaY)
        if isCropRegionValid(result, limit: region) {
            crop = result
        }

        media.cropRect = scaleCropRegion(crop, from: region, to: imageSize)
    }

    func onDragCropRegionEnd() {
        currentCropSection = .none
    }

    @ViewBuilder
    private func draw(path: PendingPath) -> some View {
        draw(path: path.points, color: Color(path.color), width: path.width)
    }

    @ViewBuilder
    private func draw(path points: [CGPoint], color: Color, width: CGFloat) -> some View {
        Path { path in
            guard points.count > 1 else { return }

            path.move(to: points[0])

            MediaEdit.curves(points).forEach { path.addCurve(to: $0.to, control1: $0.control1, control2: $0.control2) }
        }.stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    var body: some View {
        if let image = media.image {
            GeometryReader { outer in
                ZStack {
                    VStack {
                        Spacer()
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .allowsHitTesting(false)
                            .scaleEffect(media.scale)
                            .offset(scaleOffset(media.offset, containerSize: outer.size, imageSize: image.size))
                            .clipped()
                            .overlay(
                                GeometryReader { inner in
                                    ForEach((0..<media.drawnItems.count), id: \.self) { idx in
                                        draw(path: scale(path: media.drawnItems[idx], from: image.size, to: inner.size))
                                    }

                                    draw(path: currentPath, color: Color(media.drawingColor), width: media.drawingLineWidth / media.scale)
                                }
                                .scaleEffect(media.scale)
                                .offset(scaleOffset(media.offset, containerSize: outer.size, imageSize: image.size))
                                .clipped()
                            )
                            .overlay(GeometryReader { inner in
                                CropRegion(cropRegion: cropRegion, region: scaleCropRegion(media.cropRect, from: image.size, to: inner.size))
                            })
                            .overlay(GeometryReader { inner in
                                CropGestureView(outThreshold: outThreshold)
                                    .onZoomChanged { scale, location in
                                        let baseScale = image.size.width / inner.size.width
                                        let zoomCenter = location.applying(CGAffineTransform(scaleX: baseScale, y: baseScale))
                                        let translationX = (zoomCenter.x - image.size.width / 2 - media.offset.x) * (1 - scale)
                                        let translationY = (zoomCenter.y - image.size.height / 2 - media.offset.y) * (1 - scale)

                                        media.zoom(media.scale * scale)
                                        media.move(CGPoint(x: media.offset.x + translationX, y: media.offset.y + translationY))
                                    }
                                    .onPinchDragChanged { translation in
                                        let baseScale = image.size.width / inner.size.width
                                        let scaled = translation.applying(CGAffineTransform(scaleX: baseScale, y: baseScale))

                                        media.move(CGPoint(x: media.offset.x + scaled.x, y: media.offset.y + scaled.y))
                                    }
                                    .onDragChanged { location in
                                        isDragging = true

                                        if media.isDrawing {
                                            let offset = scaleOffset(media.offset, containerSize: outer.size, imageSize: image.size)
                                            let x = (media.scale - 1) * (inner.size.width / 2) + location.x - offset.width
                                            let y = (media.scale - 1) * (inner.size.height / 2) + location.y - offset.height

                                            currentPath.append(CGPoint(x: x / media.scale, y: y / media.scale))
                                        } else {
                                            onDragCropRegion(location, in: inner.size)
                                        }
                                    }
                                    .onDragEnded { v in
                                        isDragging = false

                                        if media.isDrawing {
                                            let path = PendingPath(points: currentPath, color: media.drawingColor, width: media.drawingLineWidth / media.scale)
                                            media.drawnItems.append(scale(path: path, from: inner.size, to: image.size))
                                            media.undoStack.append(.removeDrawing)
                                            currentPath = []
                                        } else {
                                            onDragCropRegionEnd()
                                        }
                                    }
                                    .offset(x: -outThreshold, y: -outThreshold)
                                    .frame(width: inner.size.width + outThreshold * 2, height: inner.size.height + outThreshold * 2)
                            })
                        Spacer()
                    }.frame(maxWidth: .infinity)

                    if media.isDrawing && !isDragging {
                        ColorPicker(color: $media.drawingColor)
                            .offset(x: -14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
            }.padding(8)
        }
    }
}

fileprivate struct ColorPicker: View {
    @Binding var color: UIColor

    private let height: CGFloat = 322
    private let colors: [UIColor] = [
        UIColor(red: 1, green: 0.271, blue: 0, alpha: 1),
        UIColor(red: 1, green: 0.54, blue: 0, alpha: 1),
        UIColor(red: 0.944, green: 0.954, blue: 0.469, alpha: 1),
        UIColor(red: 0.549, green: 0.863, blue: 0.302, alpha: 1),
        UIColor(red: 0.333, green: 0.825, blue: 0.796, alpha: 1),
        UIColor(red: 0.249, green: 0.467, blue: 0.892, alpha: 1),
        UIColor(red: 0.938, green: 0.195, blue: 0.641, alpha: 1),
        UIColor(red: 0.871, green: 0.201, blue: 0.929, alpha: 1),
        UIColor(red: 0.133, green: 0.133, blue: 0.133, alpha: 1),
        .white,
    ]
    private let locations: [CGFloat] = [0, 0.11, 0.21, 0.35, 0.48, 0.62, 0.72, 0.79, 0.89, 0.96]

    var body: some View {
        RoundedRectangle(cornerRadius: 19)
            .fill(.linearGradient(stops: zip(colors, locations).map { Gradient.Stop(color: Color($0.0), location: $0.1) }, startPoint: .bottom, endPoint: .top))
            .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 0)
            .gesture(DragGesture(minimumDistance: 0).onChanged {
                let position = (height - min(height, max(0, $0.location.y))) / height
                var index = 0
                for (i, loc) in locations.enumerated() {
                    if loc > position {
                        break
                    }
                    index = i
                }
                index = min(index, locations.count - 2)

                let prcnt = (position - locations[index]) / (locations[index + 1] - locations[index])

                let color1 = colors[index]
                let color2 = colors[index + 1]

                var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
                var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)

                guard color1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1) else { return }
                guard color2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return }

                color = UIColor(red: r1 + (r2 - r1) * prcnt, green: g1 + (g2 - g1) * prcnt, blue: b1 + (b2 - b1) * prcnt, alpha: a1 + (a2 - a1) * prcnt)
            })
            .frame(width: 38, height: height)
    }
}

fileprivate struct CropRegion: View {

    let cropRegion: MediaEditCropRegion
    let region: CGRect

    private let borderThickness: CGFloat = 4
    private let cornerSize = CGSize(width: 15, height: 15)
    private let shadowColor = Color(red: 0, green: 0, blue: 0, opacity: 0.7)

    var body: some View {
        GeometryReader { geometry in
            // Shadow
            Path { path in
                path.addRect(CGRect(x: -1, y: -1, width: geometry.size.width + 2, height: geometry.size.height + 2))

                switch cropRegion {
                case .circle:
                    path.addEllipse(in: region)
                case .square, .any:
                    path.addRoundedRect(in: region, cornerSize: cornerSize)
                }
            }
            .fill(shadowColor, style: FillStyle(eoFill: true))

            // Border
            Path { path in
                let offset = borderThickness / 2
                let region = self.region.insetBy(dx: -offset + 1, dy: -offset + 1)

                switch cropRegion {
                case .circle:
                    path.addEllipse(in: region)
                case .square, .any:
                    path.addRoundedRect(in: region, cornerSize: cornerSize)
                }
            }
            .stroke(Color.white, lineWidth: borderThickness)
        }
    }
}

fileprivate struct CropGestureView: UIViewRepresentable {
    typealias UIViewType = UIView

    var outThreshold: CGFloat

    init(outThreshold: CGFloat) {
        self.outThreshold = outThreshold
    }

    private var actions = Actions()

    func onZoomChanged(_ action: @escaping (CGFloat, CGPoint) -> Void) -> CropGestureView {
        actions.zoomChangedAction = action
        return self
    }

    func onZoomEnded(_ action: @escaping () -> Void) -> CropGestureView {
        actions.zoomEndedAction = action
        return self
    }

    func onPinchDragChanged(_ action: @escaping (CGPoint) -> Void) -> CropGestureView {
        actions.pinchDragChangedAction = action
        return self
    }

    func onPinchDragEnded(_ action: @escaping (CGPoint) -> Void) -> CropGestureView {
        actions.pinchDragEndedAction = action
        return self
    }

    func onDragChanged(_ action: @escaping (CGPoint) -> Void) -> CropGestureView {
        actions.dragChangedAction = action
        return self
    }

    func onDragEnded(_ action: @escaping (CGPoint) -> Void) -> CropGestureView {
        actions.dragEndedAction = action
        return self
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()

        let dragRecognizer = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onDrag))
        dragRecognizer.delegate = context.coordinator
        dragRecognizer.maximumNumberOfTouches = 1
        view.addGestureRecognizer(dragRecognizer)

        let pinchDragRecognizer = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onPinchDrag))
        pinchDragRecognizer.delegate = context.coordinator
        pinchDragRecognizer.minimumNumberOfTouches = 2
        view.addGestureRecognizer(pinchDragRecognizer)

        let zoomRecognizer = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onZoom(sender:)))
        zoomRecognizer.delegate = context.coordinator
        view.addGestureRecognizer(zoomRecognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.actions = actions
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    class Actions: NSObject {
        var dragChangedAction: ((CGPoint) -> Void)?
        var dragEndedAction: ((CGPoint) -> Void)?
        var pinchDragChangedAction: ((CGPoint) -> Void)?
        var pinchDragEndedAction: ((CGPoint) -> Void)?
        var zoomChangedAction: ((CGFloat, CGPoint) -> Void)?
        var zoomEndedAction: (() -> Void)?
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let parent: CropGestureView

        var actions: Actions?

        init(_ view: CropGestureView) {
            parent = view
        }

        @objc func onDrag(sender: UIPanGestureRecognizer) {
            let location = convert(sender.location(in: sender.view))

            if sender.state == .began || sender.state == .changed {
                actions?.dragChangedAction?(location)
            } else if sender.state == .ended {
                actions?.dragEndedAction?(location)
            }
        }

        @objc func onPinchDrag(sender: UIPanGestureRecognizer) {
            let translation = sender.translation(in: sender.view)
            if sender.state == .began || sender.state == .changed {
                actions?.pinchDragChangedAction?(translation)
            } else if sender.state == .ended {
                actions?.pinchDragEndedAction?(translation)
            }
            sender.setTranslation(.zero, in: sender.view)
        }

        @objc func onZoom(sender: UIPinchGestureRecognizer) {
            if sender.state == .began || sender.state == .changed {
                guard sender.numberOfTouches > 1 else { return }

                let locations = [
                    convert(sender.location(ofTouch: 0, in: sender.view)),
                    convert(sender.location(ofTouch: 1, in: sender.view)),
                ]

                let zoomLocation = CGPoint(x: (locations[0].x + locations[1].x) / 2, y: (locations[0].y + locations[1].y) / 2)

                actions?.zoomChangedAction?(sender.scale, zoomLocation)
                sender.scale = 1
            } else if sender.state == .ended {
                actions?.zoomEndedAction?()
            }
        }

        private func isDragRecognizer(_ recognizer: UIGestureRecognizer) -> Bool {
            if let recognizer = recognizer as? UIPanGestureRecognizer {
                if recognizer.maximumNumberOfTouches == 1 {
                    return true
                }
            }

            return false
        }

        private func convert(_ location: CGPoint) -> CGPoint {
            return CGPoint(x: location.x - parent.outThreshold, y: location.y - parent.outThreshold)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return !(isDragRecognizer(gestureRecognizer) || isDragRecognizer(otherGestureRecognizer))
        }
    }
}
