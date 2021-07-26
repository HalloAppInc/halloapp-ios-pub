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
    @State private var lastCropSection: CropRegionSection = .none

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

        switch lastCropSection {
        case .top, .topLeft, .topRight:
            crop.origin.y += deltaY
            crop.size.height -= deltaY
        case .bottom, .bottomLeft, .bottomRight:
            crop.size.height += deltaY
        default:
            break
        }

        switch lastCropSection {
        case .left, .bottomLeft, .topLeft:
            crop.origin.x += deltaX
            crop.size.width -= deltaX
        case .right, .bottomRight, .topRight:
            crop.size.width += deltaX
        default:
            break
        }

        if lastCropSection == .inside {
            crop.origin.x += deltaX
            crop.origin.y += deltaY
        }

        if let maxAspectRatio = maxAspectRatio, (crop.size.height / crop.size.width) - maxAspectRatio > epsilon {
            switch lastCropSection {
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

    var body: some View {
        if media.image != nil {
            GeometryReader { outer in
                VStack {
                    Spacer()
                    Image(uiImage: self.media.image!)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .allowsHitTesting(false)
                        .scaleEffect(self.media.scale)
                        .offset(self.scaleOffset(self.media.offset, containerSize: outer.size, imageSize: self.media.image!.size))
                        .clipped()
                        .overlay(GeometryReader { inner in
                            CropRegion(cropRegion: self.cropRegion, region: self.scaleCropRegion(self.media.cropRect, from: self.media.image!.size, to: inner.size))
                        })
                        .overlay(GeometryReader { inner in
                            CropGestureView(outThreshold: outThreshold)
                                .onZoomChanged { scale, location in
                                    let baseScale = self.media.image!.size.width / inner.size.width
                                    let zoomCenter = location.applying(CGAffineTransform(scaleX: baseScale, y: baseScale))
                                    let translationX = (zoomCenter.x - self.media.image!.size.width / 2 - self.media.offset.x) * (1 - scale)
                                    let translationY = (zoomCenter.y - self.media.image!.size.height / 2 - self.media.offset.y) * (1 - scale)

                                    self.media.zoom(self.media.scale * scale)
                                    self.media.move(CGPoint(x: self.media.offset.x + translationX, y: self.media.offset.y + translationY))
                                }
                                .onPinchDragChanged { translation in
                                    let baseScale = self.media.image!.size.width / inner.size.width
                                    let scaled = translation.applying(CGAffineTransform(scaleX: baseScale, y: baseScale))

                                    self.media.move(CGPoint(x: self.media.offset.x + scaled.x, y: self.media.offset.y + scaled.y))
                                }
                                .onDragChanged { location in
                                    var crop = self.scaleCropRegion(self.media.cropRect, from: self.media.image!.size, to: inner.size)

                                    if !self.isDragging {
                                        self.lastLocation = location
                                        self.lastCropSection = self.findCropSection(crop, location: location)

                                        if self.lastCropSection != .none {
                                            self.isDragging = true
                                        } else {
                                            return
                                        }

                                        switch self.cropRegion {
                                        case .circle, .square:
                                            self.lastCropSection = .inside
                                        case .any:
                                            break
                                        }
                                    } else {
                                        let valid = crop.insetBy(dx: -2 * outThreshold, dy: -2 * outThreshold)
                                        if !valid.contains(location) {
                                            return
                                        }
                                    }

                                    let deltaX = location.x - self.lastLocation.x
                                    let deltaY = location.y - self.lastLocation.y
                                    self.lastLocation = location

                                    var result = self.newCropRegion(crop, deltaX: deltaX)
                                    if self.isCropRegionValid(result, limit: inner.size) {
                                        crop = result
                                    }

                                    result = self.newCropRegion(crop, deltaY: deltaY)
                                    if self.isCropRegionValid(result, limit: inner.size) {
                                        crop = result
                                    }

                                    self.media.cropRect = self.scaleCropRegion(crop, from: inner.size, to: self.media.image!.size)
                                }
                                .onDragEnded { v in
                                    self.isDragging = false
                                }
                                .offset(x: -outThreshold, y: -outThreshold)
                                .frame(width: inner.size.width + outThreshold * 2, height: inner.size.height + outThreshold * 2)
                        })
                    Spacer()
                }.frame(maxWidth: .infinity)
            }.padding(8)
        }
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
                    path.addRoundedRect(in: region, cornerSize: self.cornerSize)
                }
            }
            .fill(self.shadowColor, style: FillStyle(eoFill: true))

            // Border
            Path { path in
                let offset = borderThickness / 2
                let region = self.region.insetBy(dx: -offset + 1, dy: -offset + 1)

                switch cropRegion {
                case .circle:
                    path.addEllipse(in: region)
                case .square, .any:
                    path.addRoundedRect(in: region, cornerSize: self.cornerSize)
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
