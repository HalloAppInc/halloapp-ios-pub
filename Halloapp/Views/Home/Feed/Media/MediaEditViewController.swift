//
//  MediaEditViewController.swift
//  HalloApp
//
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import Combine
import Core
import Dispatch
import Foundation
import SwiftUI
import UIKit

typealias MediaEditViewControllerCallback = (MediaEditViewController, [PendingMedia], Int, Bool) -> Void

class MediaEditViewController: UIViewController {
    
    private let media: [PendingMedia]
    private let initialSelect: Int?
    private let didFinish: MediaEditViewControllerCallback
    
    init(mediaToEdit media: [PendingMedia], selected: Int?, didFinish: @escaping MediaEditViewControllerCallback) {
        self.media = media
        self.initialSelect = selected
        self.didFinish = didFinish
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Use init(mediaEdit:)")
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let items = media.map { MediaEdit(media: $0) }
        
        guard let selected = MediaEditViewController.firstImage(items: items, position: initialSelect) else {
            didFinish(self, [], -1, true)
            return
        }
        
        let mediaEditView = MediaEditView(media: items, selected: selected) { [weak self] media, selected, cancel in
            guard let self = self else { return }
            self.didFinish(self, media.map { $0.process() }, selected, cancel)
        }
        let hostingController = UIHostingController(rootView: mediaEditView)
        
        self.addChild(hostingController)
        self.view.addSubview(hostingController.view)
        
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        hostingController.view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        hostingController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        hostingController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
    }
    
    fileprivate static func firstImage(items: [MediaEdit], position: Int? = nil) -> MediaEdit? {
        if let position = position {
            if 0 <= position && position < items.count && items[position].type == .image {
                return items[position]
            }
        }
        
        for item in items {
            if item.type == .image {
                return item
            }
        }
        
        return nil
    }
}

fileprivate class MediaEdit : ObservableObject {
    @Published var image: UIImage?
    @Published var cropRect = CGRect.zero
    @Published var scale: CGFloat = 1.0
    @Published var offset = CGPoint.zero
    
    let type :FeedMediaType
    
    private let media: PendingMedia
    private var original: UIImage?
    private var numberOfRotations = 0
    private var hFlipped = false
    private var vFlipped = false
    private var fileURL : URL?
    private var cancellable: AnyCancellable?
    
    init(media: PendingMedia) {
        self.media = media
        self.type = media.type
        
        if let edit = media.edit {
            original = edit.image
            cropRect = edit.cropRect
            hFlipped = edit.hFlipped
            vFlipped = edit.vFlipped
            numberOfRotations = edit.numberOfRotations
            scale = edit.scale
            offset = edit.offset
            fileURL = edit.originalURL
        } else {
            original = media.image
            self.fileURL = media.fileURL
        }
        
        load()
    }
    
    private func load() {
        switch media.type {
        case .image:
            if original == nil && self.fileURL != nil {
                cancellable = URLSession.shared.dataTaskPublisher(for: media.fileURL!)
                    .map { UIImage(data: $0.data) }
                    .replaceError(with: nil)
                    .receive(on: DispatchQueue.main)
                    .sink { image in
                        self.original = image
                        self.updateImage()
                        
                        if self.media.edit == nil {
                            self.initialCrop()
                        }
                    }
            } else {
                self.updateImage()
                
                if media.edit == nil {
                    self.initialCrop()
                }
            }
        case .video:
            let url = media.fileURL ?? media.videoURL
            if url != nil {
                let asset = AVURLAsset(url: url!, options: nil)
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                
                let time = CMTimeMakeWithSeconds(0.0, preferredTimescale: 600)
                var actualTime = CMTimeMake(value: 0, timescale: 0)
                let image: CGImage
                do {
                    image = try gen.copyCGImage(at: time, actualTime: &actualTime)
                } catch {
                    return
                }
                
                self.image = UIImage(cgImage: image)
            }
        }
    }
    
    deinit {
        cancellable?.cancel()
    }
    
    func process() -> PendingMedia {
        var edit = media.edit ?? PendingMediaEdit(originalURL: fileURL, image: original)
        edit.cropRect = cropRect
        edit.hFlipped = hFlipped
        edit.vFlipped = vFlipped
        edit.numberOfRotations = numberOfRotations
        edit.scale = scale
        edit.offset = offset
        
        let image = crop()
        guard let data = image?.jpegData(compressionQuality: 0.8) else { return media }
        
        var url: URL;
        if media.edit != nil {
            url = media.fileURL!
        } else {
            let name = UUID().uuidString + ".jpg"
            let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            url = base.appendingPathComponent(name)
        }
        
        do {
            try data.write(to: url)
        } catch {
            return media
        }
        
        media.image = image
        media.size = image!.size
        media.fileURL = url
        media.edit = edit
        
        return media
    }
    
    func updateImage() {
        guard let image = original else { return }
        
        let size = (numberOfRotations % 2) == 0 ? image.size : CGSize(width: image.size.height, height: image.size.width)
        
        UIGraphicsBeginImageContext(size)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        context.translateBy(x: size.width / 2, y: size.height / 2)
        
        context.scaleBy(x: vFlipped ? -1 : 1, y: hFlipped ? -1 : 1)
        context.rotate(by: CGFloat(numberOfRotations) * CGFloat(-Double.pi) / 2)
        
        image.draw(at: CGPoint(x: -image.size.width / 2, y: -image.size.height / 2))
        let result = context.makeImage()
        UIGraphicsEndImageContext()
        
        if let result = result {
            self.image = UIImage(cgImage: result)
        }
    }
    
    private func initialCrop() {
        guard let image = image else { return }
        
        var offset: CGFloat = 40
        if image.size.width < 120 || image.size.height < 120 {
            offset = CropRegion.borderThickness / 2
        }
        
        var crop = CGRect(x: offset, y: offset, width: image.size.width - 2 * offset, height: image.size.height - 2 * offset)
        
        let ratio = crop.size.height / crop.size.width
        crop.size.height = crop.size.width * min(CropImage.maxAspectRatio, ratio)
        
        self.cropRect = crop;
    }
    
    func reset() {
        numberOfRotations = 0
        vFlipped = false
        hFlipped = false
        scale = 1.0
        offset = CGPoint.zero
        
        updateImage()
        initialCrop()
    }
    
    func rotate() {
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
        
        updateImage()
    }
    
    func flip() {
        guard let image = image else { return }
        
        vFlipped.toggle()
        cropRect.origin.x = image.size.width - cropRect.size.width - cropRect.origin.x
        offset.x = -offset.x
        
        updateImage()
    }
    
    func zoom(_ scale: CGFloat) {
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
        guard let image = image else { return nil }
        
        let contextCenterX = cropRect.size.width / 2
        let contextCenterY = cropRect.size.height / 2
        let imgCenterX = image.size.width / 2
        let imgCenterY = image.size.height / 2
        let cropOffsetX = cropRect.midX - imgCenterX
        let cropOffsetY = cropRect.midY - imgCenterY
        
        UIGraphicsBeginImageContext(cropRect.size)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.translateBy(x: contextCenterX, y: contextCenterY)
        context.translateBy(x: -cropOffsetX, y: -cropOffsetY)
        context.translateBy(x: offset.x, y: offset.y)
        context.scaleBy(x: scale, y: scale)

        image.draw(at: CGPoint(x: -imgCenterX, y: -imgCenterY))
        let result = context.makeImage()
        UIGraphicsEndImageContext()
        
        guard result != nil else { return nil }
        
        return UIImage(cgImage: result!)
    }
}

fileprivate struct CropRegion: View {
    
    let region: CGRect
    
    static let borderThickness: CGFloat = 8
    private let cornerSize = CGSize(width: 15, height: 15)
    private let shadowColor = Color(red: 0, green: 0, blue: 0, opacity: 0.5)
    
    var body: some View {
        GeometryReader { geometry in
            // Shadow
            Path { path in
                path.addRect(CGRect(x: 0, y: 0, width: geometry.size.width, height: geometry.size.height))
                path.addRoundedRect(in: self.region, cornerSize: self.cornerSize)
            }
            .fill(self.shadowColor, style: FillStyle(eoFill: true))
            
            // Border
            Path { path in
                path.addRoundedRect(in: self.region, cornerSize: self.cornerSize)
            }
            .stroke(Color.white, lineWidth: CropRegion.borderThickness)
            .contentShape(Rectangle()) // Apply gesture on the whole region and not just the border
        }
    }
}

fileprivate struct Preview: View {
    @ObservedObject var media: MediaEdit
    let selected: Bool
    
    var body: some View {
        ZStack {
            if media.image != nil {
                Image(uiImage: media.image!)
                    .resizable()
                    .cornerRadius(3)
                    .aspectRatio(contentMode: .fit)
                    .padding(4)
                    .opacity(selected ? 1.0 : 0.6)
            }
            
            if media.type == .video {
                Image(systemName: "play.fill")
                    .foregroundColor(.white)
                    .imageScale(.large)
                    .opacity(0.6)
            }
        }
        .frame(width: 65, height: 80)
        .background(Color(white: 1.0, opacity: selected ? 1.0 : 0.2))
        .cornerRadius(5)
        .padding(5)
        
    }
}

fileprivate struct CropGestureView: UIViewRepresentable {
    private var view = UIView()
    
    var dragChangedAction: ((CGPoint) -> Void)?
    var dragEndedAction: ((CGPoint) -> Void)?
    var pinchDragChangedAction: ((CGPoint) -> Void)?
    var pinchDragEndedAction: ((CGPoint) -> Void)?
    var zoomChangedAction: ((CGFloat) -> Void)?
    var zoomEndedAction: ((CGFloat) -> Void)?
    
    func onZoomChanged(_ action: ((CGFloat) -> Void)?) -> CropGestureView {
        var copy = self;
        copy.zoomChangedAction = action;
        return copy;
    }
    
    func onZoomEnded(_ action: ((CGFloat) -> Void)?) -> CropGestureView {
        var copy = self;
        copy.zoomEndedAction = action
        return copy
    }
    
    func onPinchDragChanged(_ action: ((CGPoint) -> Void)?) -> CropGestureView {
        var copy = self
        copy.pinchDragChangedAction = action
        return copy
    }
    
    func onPinchDragEnded(_ action: ((CGPoint) -> Void)?) -> CropGestureView {
        var copy = self
        copy.pinchDragEndedAction = action
        return copy
    }
    
    func onDragChanged(_ action: ((CGPoint) -> Void)?) -> CropGestureView {
        var copy = self
        copy.dragChangedAction = action
        return copy
    }
    
    func onDragEnded(_ action: ((CGPoint) -> Void)?) -> CropGestureView {
        var copy = self
        copy.dragEndedAction = action
        return copy
    }
    
    func makeUIView(context: Context) -> UIView {
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
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self, view: view)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let parent: CropGestureView
        private let view: UIView
        
        init(_ parent: CropGestureView, view: UIView) {
            self.parent = parent
            self.view = view
            super.init()
        }
        
        @objc func onDrag(sender: UIPanGestureRecognizer) {
            let location = sender.location(in: view)
            if sender.state == .began || sender.state == .changed {
                parent.dragChangedAction?(location)
            } else if sender.state == .ended {
                parent.dragEndedAction?(location)
            }
        }
        
        @objc func onPinchDrag(sender: UIPanGestureRecognizer) {
            let translation = sender.translation(in: view)
            if sender.state == .began || sender.state == .changed {
                parent.pinchDragChangedAction?(translation)
            } else if sender.state == .ended {
                parent.pinchDragEndedAction?(translation)
            }
        }
        
        @objc func onZoom(sender: UIPinchGestureRecognizer) {
            if sender.state == .began || sender.state == .changed {
                parent.zoomChangedAction?(sender.scale)
            } else if sender.state == .ended {
                parent.zoomEndedAction?(sender.scale)
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
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return !(isDragRecognizer(gestureRecognizer) || isDragRecognizer(otherGestureRecognizer))
        }
    }
}

fileprivate struct CropImage: View {
    private enum CropRegionSection {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, inside, none
    }
    
    static let maxAspectRatio: CGFloat = 5/4
    private let threshold = CGFloat(44)
    
    @ObservedObject var media: MediaEdit
    
    @State private var isDragging = false
    @State private var isPinchDragging = false
    @State private var isZooming = false
    @State private var startingScale: CGFloat = 1.0
    @State private var startingOffset = CGPoint.zero
    @State private var lastLocation = CGPoint.zero
    @State private var lastCropSection: CropRegionSection = .none
    
    private func findCropSection(_ crop: CGRect, location: CGPoint) -> CropRegionSection {
        let isTop = (crop.minY < location.y) && (location.y < (crop.minY + threshold))
        let isBottom = ((crop.maxY - threshold) < location.y) && (location.y < crop.maxY)
        let isLeft = (crop.minX < location.x) && (location.x < (crop.minX + threshold))
        let isRight = ((crop.maxX - threshold) < location.x) && (location.x < crop.maxX)
        
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
        
        let isInsideVertical = (crop.minY + threshold) < location.y && location.y < (crop.maxY - threshold)
        let isInsideHorizontal = (crop.minX + threshold) < location.x && location.x < (crop.maxX - threshold)
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
        
        if (crop.size.height / crop.size.width) > CropImage.maxAspectRatio {
            switch lastCropSection {
            case .left, .right:
                let height = CropImage.maxAspectRatio * crop.size.width
                crop.origin.y -= (height - crop.size.height) / 2
                crop.size.height = height
            default:
                let width = crop.size.height / CropImage.maxAspectRatio
                crop.origin.x -= (width - crop.size.width) / 2
                crop.size.width = width
            }
        }
        
        return crop
    }
    
    private func isCropRegionWithinLimit(_ crop: CGRect, limit: CGSize) -> Bool {
        let offset = CropRegion.borderThickness / 2
        let width = limit.width - offset
        let height = limit.height - offset
        return crop.minX >= offset && crop.minY >= offset && crop.maxX < width && crop.maxY < height
    }
    
    private func isCropRegionMinSize(_ crop: CGRect) -> Bool {
        let width = threshold * 4
        let height = threshold * 4
        return crop.size.height > height && crop.size.width > width
    }
    
    private func isCropRegionValid(_ crop: CGRect, limit: CGSize) -> Bool {
        return isCropRegionWithinLimit(crop, limit: limit) &&
            isCropRegionMinSize(crop)
    }
    
    private func scaleCropRegion(_ crop: CGRect, from: CGSize, to: CGSize) -> CGRect {
        let scale = to.height / from.height
        return crop.applying(CGAffineTransform(scaleX: scale, y: scale))
    }
    
    private func scaleOffset(_ offset: CGPoint, containerSize: CGSize, imageSize: CGSize) -> CGSize {
        var scale: CGFloat = 1.0
        if imageSize.width > containerSize.width || imageSize.height > containerSize.height {
            scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        }
        
        return CGSize(width: offset.x * scale, height: offset.y * scale)
    }
    
    var body: some View {
        media.image.map { image in
            GeometryReader { outer in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(self.media.scale)
                    .offset(self.scaleOffset(self.media.offset, containerSize: outer.size, imageSize: image.size))
                    .clipped()
                    .overlay(GeometryReader { inner in
                        CropRegion(region: self.scaleCropRegion(self.media.cropRect, from: image.size, to: inner.size))
                    })
                    .overlay(GeometryReader { inner in
                        CropGestureView()
                            .onZoomChanged { v in
                                if !self.isZooming {
                                    self.isZooming = true
                                    self.startingScale = self.media.scale
                                }
                                
                                self.media.zoom(self.startingScale * v)
                            }
                            .onZoomEnded { v in
                                self.isZooming = false
                            }
                            .onPinchDragChanged { v in
                                if !self.isPinchDragging {
                                    self.isPinchDragging = true
                                    self.startingOffset = self.media.offset
                                }
                                
                                let scale = image.size.width / inner.size.width
                                let real = v.applying(CGAffineTransform(scaleX: scale, y: scale))
                                let offset = self.startingOffset.applying(CGAffineTransform(translationX: real.x, y: real.y))

                                self.media.move(offset)
                            }
                            .onPinchDragEnded { v in
                                self.isPinchDragging = false
                            }
                            .onDragChanged { v in
                                var crop = self.scaleCropRegion(self.media.cropRect, from: image.size, to: inner.size)
                                
                                if !self.isDragging {
                                    self.lastLocation = v
                                    self.lastCropSection = self.findCropSection(crop, location: v)
                                    
                                    if self.lastCropSection != .none {
                                        self.isDragging = true
                                    } else {
                                        return
                                    }
                                }
                                
                                let deltaX = v.x - self.lastLocation.x
                                let deltaY = v.y - self.lastLocation.y
                                self.lastLocation = v
                                
                                var result = self.newCropRegion(crop, deltaX: deltaX)
                                if self.isCropRegionValid(result, limit: inner.size) {
                                    crop = result
                                }
                                
                                result = self.newCropRegion(crop, deltaY: deltaY)
                                if self.isCropRegionValid(result, limit: inner.size) {
                                    crop = result
                                }
                                
                                self.media.cropRect = self.scaleCropRegion(crop, from: inner.size, to: image.size)
                            }
                            .onDragEnded { v in
                                self.isDragging = false
                            }
                    })
            }
        }
    }
}


fileprivate struct MediaEditView : View {
    @State var media: [MediaEdit]
    @State var selected: MediaEdit
    var complete: (([MediaEdit], Int, Bool) -> Void)?
    
    @State private var showDiscardSheet = false
    
    var topBar: some View {
        HStack {
            Button(action: { self.showDiscardSheet = true }) {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
                    .font(.system(size: 22, weight: .medium))
                    .accessibility(label: Text("Close"))
                    .padding()
            }
            .actionSheet(isPresented: $showDiscardSheet) {
                ActionSheet(
                    title: Text("Would you like to discard your edits?"),
                    message: nil,
                    buttons: [.destructive(Text("Discard")) { self.complete?([], -1, true) }, .cancel()]
                )
            }
            
            Spacer()
            
            Button(action: {
                self.media.removeAll { $0 === self.selected }
                
                guard let selected = MediaEditViewController.firstImage(items: self.media) else {
                    self.complete?([], -1, false)
                    return
                }
                
                self.selected = selected
            }) {
                Image(systemName: "trash.fill")
                    .foregroundColor(.white)
                    .accessibility(label: Text("Remove"))
                    .padding()
            }
            
            Button(action: { self.selected.rotate() }) {
                Image("Rotate")
                    .foregroundColor(.white)
                    .imageScale(.large)
                    .accessibility(label: Text("Rotate"))
                    .padding()
            }
            
            Button(action: { self.selected.flip() }) {
                Image("Flip")
                    .foregroundColor(.white)
                    .imageScale(.large)
                    .accessibility(label: Text("Flip"))
                    .padding()
            }
        }
    }
    
    var bottomBar: some View {
        HStack {
            Button(action: { self.selected.reset() }) {
                Text("Reset")
                    .foregroundColor(.white)
                    .padding()
            }
            
            Spacer()
            
            Button(action: {
                guard let index = self.media.firstIndex(where: { $0 === self.selected }) else { return }
                self.complete?(self.media, index, false)
            }) {
                Text("Done")
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
                    .padding()
            }
        }
    }
    
    var previews: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<media.count, id: \.self) { i in
                    Preview(media: self.media[i], selected: self.selected === self.media[i])
                    .onTapGesture {
                        if self.media[i].type == .image && self.selected !== self.media[i] {
                            self.selected = self.media[i]
                        }
                    }
                }
            }
        }
    }
    
    var body: some View {
        VStack {
            Rectangle()
                .foregroundColor(.black)
                .edgesIgnoringSafeArea(.top)
                .frame(height: -10)
            
            
            
            
            VStack {
                topBar
                
                CropImage(media: selected)
                
                previews
                bottomBar
                Spacer()
                    .frame(height: 30)
            }
            
        }
        .background(Color.black)
        .edgesIgnoringSafeArea(.bottom)
    }
}
