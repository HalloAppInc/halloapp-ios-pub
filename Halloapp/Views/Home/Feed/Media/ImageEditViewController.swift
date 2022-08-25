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

    init(_ media: MediaEdit, config: MediaEditConfig) {
        super.init(rootView: ImageEditView(media: media, config: config))
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
    let config: MediaEditConfig

    @State private var isDragging = false
    @State private var startingOffset = CGPoint.zero
    @State private var lastLocation = CGPoint.zero
    @State private var currentCropSection: CropRegionSection = .none
    @State private var currentPath: [CGPoint] = []
    @State private var currentText = ""
    @State private var currentLayerIdx: Int?
    @State private var deleteBinFrame: CGRect = .zero
    @State private var isOverDeleteBin = false

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

        if let maxAspectRatio = config.maxAspectRatio, (crop.size.height / crop.size.width) - maxAspectRatio > epsilon {
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

    private func onDragCropRegion(_ location: CGPoint, in region: CGSize) {
        guard let imageSize = media.image?.size else { return }

        var crop = Scaler.scale(crop: media.cropRect, from: imageSize, to: region)

        if currentCropSection == .none {
            lastLocation = location
            currentCropSection = findCropSection(crop, location: location)

            guard currentCropSection != .none else { return }

            switch config.cropRegion {
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

        media.cropRect = Scaler.scale(crop: crop, from: region, to: imageSize)
    }

    func onDragCropRegionEnd() {
        currentCropSection = .none
    }

    var deleteBin: some View {
        Image("NavbarTrashBinWithLid")
            .resizable()
            .renderingMode(.template)
            .foregroundColor(isOverDeleteBin ? .white : Color.lavaOrange)
            .aspectRatio(contentMode: .fit)
            .frame(width: 22, height: 22)
            .padding(8)
            .background(isOverDeleteBin ? Color.lavaOrange : Color.clear)
            .cornerRadius(19)
            .overlay(
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .onAppear {
                            deleteBinFrame = geometry.frame(in: .global)
                        }
                }
            )
            .animation(.spring(), value: isOverDeleteBin)
    }

    var body: some View {
        if let image = media.image {
            GeometryReader { outer in
                ZStack {
                    if media.isDraggingAnnotation {
                        deleteBin
                            .offset(x: 4, y: -50)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }

                    VStack {
                        Spacer()
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .allowsHitTesting(false)
                            .scaleEffect(media.scale)
                            .offset(Scaler.scale(offset: media.offset, containerSize: outer.size, imageSize: image.size))
                            .clipped()
                            .cornerRadius(10)
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
                                            let offset = Scaler.scale(offset: media.offset, containerSize: outer.size, imageSize: image.size)
                                            let x = (media.scale - 1) * (inner.size.width / 2) + location.x - offset.width
                                            let y = (media.scale - 1) * (inner.size.height / 2) + location.y - offset.height

                                            currentPath.append(CGPoint(x: x / media.scale, y: y / media.scale))
                                        } else if config.canCrop {
                                            onDragCropRegion(location, in: inner.size)
                                        }
                                    }
                                    .onDragEnded { v in
                                        isDragging = false

                                        if media.isDrawing {
                                            let width = media.drawingLineWidth / media.scale
                                            let path = PendingLayer.Path(points: currentPath, color: media.drawingColor, width: width)
                                            media.layers.append(.path(Scaler.scale(path: path, by: image.size.width / inner.size.width)))
                                            media.undoStack.append(.remove)
                                            currentPath = []
                                        } else if config.canCrop {
                                            onDragCropRegionEnd()
                                        }
                                    }
                                    .offset(x: -outThreshold, y: -outThreshold)
                                    .frame(width: inner.size.width + outThreshold * 2, height: inner.size.height + outThreshold * 2)
                            })
                            .overlay(
                                DrawingBoard(
                                    media: media,
                                    currentPath: currentPath,
                                    currentText: $currentText,
                                    currentLayerIdx: $currentLayerIdx,
                                    deleteBinFrame: deleteBinFrame,
                                    isOverDeleteBin: $isOverDeleteBin
                                )
                                .offset(Scaler.scale(offset: media.offset, containerSize: outer.size, imageSize: image.size))
                                .clipped()
                            )
                            .overlay(GeometryReader { inner in
                                CropRegion(
                                    cropRegion: config.cropRegion,
                                    region: Scaler.scale(crop: media.cropRect, from: image.size, to: inner.size),
                                    canCrop: !media.isDrawing && !media.isAnnotating && config.canCrop,
                                    isDragging: isDragging
                                )
                                .allowsHitTesting(false)
                            })
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)

                    if media.isAnnotating {
                        Color.black.opacity(0.7).edgesIgnoringSafeArea(.all)

                        TextView(text: $currentText, font: $media.annotationFont, color: $media.drawingColor)
                            .frame(height: TextView.height(for: currentText, font: media.annotationFont, width: outer.size.width))
                            .onTapGesture {
                                // do nothing
                                // makes the tap below be recognized only outside of text
                            }
                            .offset(y: -100)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let text = currentText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                media.isAnnotating = false
                                currentText = ""

                                if let idx = currentLayerIdx {
                                    currentLayerIdx = nil

                                    if text.isEmpty {
                                        let layer = media.layers.remove(at: idx)
                                        media.undoStack.append(.insert((idx, layer)))
                                        return
                                    }

                                    guard case .annotation(var annotation) = media.layers[idx] else { return }
                                    annotation.text = text
                                    annotation.color = media.drawingColor

                                    media.undoStack.append(.restore((idx, media.layers[idx])))
                                    media.layers[idx] = .annotation(annotation)
                                } else {
                                    guard !text.isEmpty else { return }

                                    let scale = min(1, min(outer.size.width / image.size.width, outer.size.height / image.size.height))
                                    let offset = Scaler.scale(offset: media.offset, containerSize: outer.size, imageSize: image.size)
                                    let x = (media.scale * scale * image.size.width / 2 - offset.width) / media.scale
                                    let y = (media.scale * scale * image.size.height / 2 - offset.height) / media.scale
                                    let font = Scaler.scale(font: media.annotationFont, by: 1 / media.scale)

                                    let annotation = PendingLayer.Annotation(
                                        text: text,
                                        font: font ?? media.annotationFont,
                                        color: media.drawingColor,
                                        location: CGPoint(x: x, y: y))

                                    media.layers.append(.annotation(Scaler.scale(annotation: annotation, by: 1 / scale)))
                                    media.undoStack.append(.remove)
                                }
                            }
                    }

                    if (media.isDrawing || media.isAnnotating) && !isDragging {
                        ColorPicker(color: $media.drawingColor)
                            .offset(x: -30, y: 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
            }

            .edgesIgnoringSafeArea(.bottom)
            .background(config.dark ? Color.black.edgesIgnoringSafeArea(.all) : Color.feedBackground.edgesIgnoringSafeArea(.all))
        }
    }
}

fileprivate class Scaler {
    static func scale(crop: CGRect, from: CGSize, to: CGSize) -> CGRect {
        let scale = to.height / from.height
        var scaledCrop = crop.applying(CGAffineTransform(scaleX: scale, y: scale))

        scaledCrop.origin.x = max(0, scaledCrop.origin.x)
        scaledCrop.origin.y = max(0, scaledCrop.origin.y)
        scaledCrop.size.width -= max(0, scaledCrop.maxX - to.width)
        scaledCrop.size.height -= max(0, scaledCrop.maxY - to.height)

        return scaledCrop
    }

    static func scale(offset: CGPoint, containerSize: CGSize, imageSize: CGSize) -> CGSize {
        var scale: CGFloat = 1.0
        if imageSize.width > containerSize.width || imageSize.height > containerSize.height {
            scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        }

        return CGSize(width: offset.x * scale, height: offset.y * scale)
    }

    static func scale(path: PendingLayer.Path, by scale: CGFloat) -> PendingLayer.Path {
        let points = path.points.map {
            $0.applying(CGAffineTransform(scaleX: scale, y: scale))
        }

        return PendingLayer.Path(points: points, color: path.color, width: path.width * scale)
    }

    static func scale(annotation: PendingLayer.Annotation, by scale: CGFloat) -> PendingLayer.Annotation {
        let location = annotation.location.applying(CGAffineTransform(scaleX: scale, y: scale))
        let font = Scaler.scale(font: annotation.font, by: scale) ?? annotation.font

        return PendingLayer.Annotation(
            text: annotation.text,
            font: font,
            color: annotation.color,
            location: location,
            rotation: annotation.rotation)
    }

    static func scale(font: UIFont, by scale: CGFloat) -> UIFont? {
        return UIFont(name: font.fontName, size: font.pointSize * scale)
    }
}

fileprivate struct DrawingBoard: View {
    @ObservedObject var media: MediaEdit
    var currentPath: [CGPoint]
    @Binding var currentText: String
    @Binding var currentLayerIdx: Int?
    var deleteBinFrame: CGRect
    @Binding var isOverDeleteBin: Bool


    @State private var isRotating = false
    @State private var initialRotation: CGFloat = 0
    @State private var isDraging = false
    @State private var initialLocation = CGPoint.zero
    @State private var isScaling = false
    @State private var initialSize: CGFloat = 0

    @ViewBuilder
    private func draw(path: PendingLayer.Path) -> some View {
        draw(path: path.points, color: Color(path.color), width: path.width)
    }

    @ViewBuilder
    private func draw(path points: [CGPoint], color: Color, width: CGFloat) -> some View {
        Path { path in
            guard points.count > 1 else { return }
            path.move(to: points[0])
            points.forEach { path.addLine(to: $0) }
        }
        .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        .scaleEffect(media.scale)
        .allowsHitTesting(false)
    }

    var body: some View {
        GeometryReader { inner in
            if let imageSize = media.image?.size {
                ForEach((0..<media.layers.count), id: \.self) { idx in
                    switch media.layers[idx] {
                    case .path(let path):
                        draw(path: Scaler.scale(path: path, by: inner.size.width / imageSize.width))
                    case .annotation(let annotation):
                        let scaled = Scaler.scale(annotation: annotation, by: inner.size.width / imageSize.width)
                        let x = media.scale * (scaled.location.x - inner.size.width / 2)
                        let y = media.scale * (scaled.location.y - inner.size.height / 2)
                        let textFont = Scaler.scale(font: scaled.font, by: media.scale) ?? scaled.font

                        Text(scaled.text)
                            .fixedSize()
                            .font(Font(textFont as CTFont))
                            .foregroundColor(Color(annotation.color))
                            .frame(minWidth: 128, minHeight: 128)
                            .contentShape(Rectangle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .rotationEffect(.degrees(scaled.rotation))
                            .offset(x: x, y: y)
                            .onTapGesture {
                                guard !media.isDrawing else { return }
                                guard case .annotation(let annotation) = media.layers[idx] else { return }

                                currentLayerIdx = idx
                                currentText = annotation.text
                                media.drawingColor = annotation.color
                                media.isAnnotating = true
                            }
                            .simultaneousGesture(
                                DragGesture(coordinateSpace: .global)
                                    .onChanged {
                                        guard !media.isDrawing else { return }
                                        guard case .annotation(let annotation) = media.layers[idx] else { return }
                                        var scaled = Scaler.scale(annotation: annotation, by: inner.size.width / imageSize.width)

                                        if !isDraging {
                                            initialLocation = scaled.location

                                            isDraging = true
                                            withAnimation {
                                                media.isDraggingAnnotation = true
                                            }
                                        }

                                        scaled.location.x = initialLocation.x + $0.translation.width / media.scale
                                        scaled.location.y = initialLocation.y + $0.translation.height / media.scale

                                        media.layers[idx] = .annotation(Scaler.scale(annotation: scaled, by: imageSize.width / inner.size.width))

                                        isOverDeleteBin = deleteBinFrame.insetBy(dx: -24, dy: -24).contains($0.location)
                                    }
                                    .onEnded { _ in
                                        isDraging = false
                                        media.isDraggingAnnotation = false

                                        guard case .annotation(let annotation) = media.layers[idx] else { return }

                                        var scaled = Scaler.scale(annotation: annotation, by: inner.size.width / imageSize.width)
                                        let isInside = CGRect(origin: .zero, size: inner.size).contains(scaled.location)
                                        scaled.location = initialLocation

                                        let layer: PendingLayer = .annotation(Scaler.scale(annotation: scaled, by: imageSize.width / inner.size.width))

                                        if isOverDeleteBin {
                                            isOverDeleteBin = false
                                            media.layers.remove(at: idx)
                                            media.undoStack.append(.insert((idx, layer)))
                                        } else if isInside {
                                            media.undoStack.append(.restore((idx, layer)))
                                        } else {
                                            media.layers[idx] = layer
                                        }
                                    }
                            )
                            .simultaneousGesture(
                                MagnificationGesture()
                                    .onChanged {
                                        guard !media.isDrawing else { return }
                                        guard case .annotation(let annotation) = media.layers[idx] else { return }
                                        var scaled = Scaler.scale(annotation: annotation, by: inner.size.width / imageSize.width)

                                        if !isScaling {
                                            initialSize = scaled.font.pointSize
                                        }
                                        isScaling = true

                                        guard let font = UIFont(name: scaled.font.fontName, size: initialSize * $0) else { return }
                                        scaled.font = font

                                        media.layers[idx] = .annotation(Scaler.scale(annotation: scaled, by: imageSize.width / inner.size.width))
                                    }
                                    .onEnded { _ in
                                        isScaling = false
                                    }
                            )
                            .simultaneousGesture(
                                RotationGesture()
                                    .onChanged {
                                        guard case .annotation(var annotation) = media.layers[idx] else { return }

                                        if !isRotating {
                                            initialRotation = annotation.rotation
                                        }

                                        isRotating = true
                                        annotation.rotation = initialRotation + $0.degrees

                                        media.layers[idx] = .annotation(annotation)
                                    }
                                    .onEnded { _ in
                                        isRotating = false

                                        // rotation & scaling always end at the same time
                                        guard case .annotation(let annotation) = media.layers[idx] else { return }
                                        var scaled = Scaler.scale(annotation: annotation, by: inner.size.width / imageSize.width)

                                        guard let font = UIFont(name: scaled.font.fontName, size: initialSize) else { return }
                                        scaled.font = font
                                        scaled.rotation = initialRotation

                                        let layer: PendingLayer = .annotation(Scaler.scale(annotation: scaled, by: imageSize.width / inner.size.width))
                                        media.undoStack.append(.restore((idx, layer)))
                                    }
                            )
                    }
                }
            }

            draw(path: currentPath, color: Color(media.drawingColor), width: media.drawingLineWidth / media.scale)
        }
    }
}


fileprivate struct ColorPicker: View {
    @Binding var color: UIColor

    private let height: CGFloat = 193
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
            .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 1)
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
            .frame(width: 15, height: height)
    }
}

fileprivate struct TextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var font: UIFont
    @Binding var color: UIColor

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.isUserInteractionEnabled = true
        textView.backgroundColor = UIColor.clear
        textView.textAlignment = .center
        textView.textColor = color
        textView.text = text

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context)  {
        uiView.font = font
        uiView.textColor = color
        uiView.text = text

        if !context.coordinator.hasTextViewLoaded {
            uiView.becomeFirstResponder()
            context.coordinator.hasTextViewLoaded = true
        }
    }

    static func height(for text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let textView = UITextView()
        textView.font = font
        textView.text = text

        let limit = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        return min(textView.sizeThatFits(limit).height, 320)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextView
        var hasTextViewLoaded = false

        init(_ textView: TextView) {
            parent = textView
        }

        // MARK: UITextViewDelegate

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
        }
    }
}

fileprivate struct CropRegion: View {

    let cropRegion: MediaEditCropRegion
    let region: CGRect
    let canCrop: Bool
    let isDragging: Bool

    private let borderThickness: CGFloat = 3
    private let cornerSize = CGSize(width: 15, height: 15)
    private let shadowColor = Color(red: 0, green: 0, blue: 0, opacity: 0.7)

    var body: some View {
        GeometryReader { geometry in
            // Shadow
            Path { path in
                path.addRoundedRect(in: CGRect(x: -1, y: -1, width: geometry.size.width + 2, height: geometry.size.height + 2), cornerSize: cornerSize)

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
                guard canCrop else { return }
                let offset = borderThickness / 2
                let region = self.region.insetBy(dx: -offset + 1, dy: -offset + 1)

                switch cropRegion {
                case .circle:
                    path.addEllipse(in: region)
                case .square, .any:
                    path.addRoundedRect(in: region, cornerSize: cornerSize)
                }
            }
            .stroke(Color.lavaOrange, lineWidth: borderThickness)

            // Border Handles
            Path { path in
                guard canCrop else { return }
                guard cropRegion == .any else { return }

                let radius: CGFloat = 15
                let top = self.region.minY + radius
                let left = self.region.minX + radius
                let bottom = self.region.maxY - radius
                let right = self.region.maxX - radius

                let topLeft = CGPoint(x: left, y: top)
                path.move(to: CGPoint(x: left, y: self.region.minY))
                path.addArc(center: topLeft, radius: radius, startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)

                let topRight = CGPoint(x: right, y: top)
                path.move(to: CGPoint(x: self.region.maxX, y: top))
                path.addArc(center: topRight, radius: radius, startAngle: .degrees(0), endAngle: .degrees(270), clockwise: true)

                let bottomRight = CGPoint(x: right, y: bottom)
                path.move(to: CGPoint(x: right, y: self.region.maxY))
                path.addArc(center: bottomRight, radius: radius, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)

                let bottomLeft = CGPoint(x: left, y: bottom)
                path.move(to: CGPoint(x: self.region.minX, y: bottom))
                path.addArc(center: bottomLeft, radius: radius, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)

            }
            .stroke(Color.lavaOrange, lineWidth: borderThickness * 2)

            // Grid
            Path { path in
                guard canCrop && isDragging else { return }
                guard cropRegion == .any else { return }

                path.move(to: CGPoint(x: self.region.minX + self.region.width / 3, y: self.region.minY))
                path.addLine(to: CGPoint(x: self.region.minX + self.region.width / 3, y: self.region.maxY))

                path.move(to: CGPoint(x: self.region.minX + self.region.width * 2 / 3, y: self.region.minY))
                path.addLine(to: CGPoint(x: self.region.minX + self.region.width * 2 / 3, y: self.region.maxY))

                path.move(to: CGPoint(x: self.region.minX, y: self.region.minY + self.region.height / 3))
                path.addLine(to: CGPoint(x: self.region.maxX, y: self.region.minY + self.region.height / 3))

                path.move(to: CGPoint(x: self.region.minX, y: self.region.minY + self.region.height * 2 / 3))
                path.addLine(to: CGPoint(x: self.region.maxX, y: self.region.minY + self.region.height * 2 / 3))
            }
            .stroke(Color.lavaOrange, lineWidth: 1)
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
        context.coordinator.dragRecognizer = dragRecognizer

        let pinchDragRecognizer = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onPinchDrag))
        pinchDragRecognizer.delegate = context.coordinator
        pinchDragRecognizer.minimumNumberOfTouches = 2
        view.addGestureRecognizer(pinchDragRecognizer)
        context.coordinator.pinchDragRecognizer = pinchDragRecognizer

        let zoomRecognizer = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onZoom(sender:)))
        zoomRecognizer.delegate = context.coordinator
        view.addGestureRecognizer(zoomRecognizer)
        context.coordinator.zoomRecognizer = zoomRecognizer

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

        var dragRecognizer: UIPanGestureRecognizer?
        var pinchDragRecognizer: UIPanGestureRecognizer?
        var zoomRecognizer: UIPinchGestureRecognizer?
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
            return (gestureRecognizer == zoomRecognizer && otherGestureRecognizer == pinchDragRecognizer) ||
                   (gestureRecognizer == pinchDragRecognizer && otherGestureRecognizer == zoomRecognizer)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return otherGestureRecognizer != zoomRecognizer && otherGestureRecognizer != pinchDragRecognizer && otherGestureRecognizer != dragRecognizer
        }
    }
}
