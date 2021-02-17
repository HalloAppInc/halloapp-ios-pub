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
    private let cropToCircle: Bool
    private let maxAspectRatio: CGFloat

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    init(cropToCircle: Bool = false, mediaToEdit media: [PendingMedia], selected: Int?, maxAspectRatio: CGFloat = 5 / 4, didFinish: @escaping MediaEditViewControllerCallback) {
        self.cropToCircle = cropToCircle
        self.media = media
        self.initialSelect = selected
        self.maxAspectRatio = maxAspectRatio
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
        
        let items = media.map { MediaEdit(cropToCircle: cropToCircle, maxAspectRatio: maxAspectRatio, media: $0) }
        
        guard let selected = MediaEditViewController.firstImage(items: items, position: initialSelect) else {
            didFinish(self, [], -1, true)
            return
        }

        let mediaEditView = MediaEditView(cropToCircle: cropToCircle, maxAspectRatio: maxAspectRatio, media: MediaItems(items), selected: selected) { [weak self] media, selected, cancel in
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
    
    let type: FeedMediaType
    let media: PendingMedia
    
    private var original: UIImage?
    private var numberOfRotations = 0
    private var hFlipped = false
    private var vFlipped = false
    private var fileURL : URL?
    private var cancellable: AnyCancellable?
    private let cropToCircle: Bool
    private let maxAspectRatio: CGFloat
    
    init(cropToCircle: Bool, maxAspectRatio: CGFloat, media: PendingMedia) {
        self.cropToCircle = cropToCircle
        self.maxAspectRatio = maxAspectRatio
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
        } else {
            original = media.image
            fileURL = media.fileURL
        }
        
        load()
    }
    
    private func load() {
        switch media.type {
        case .image:
            if original == nil && fileURL != nil {
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
                updateImage()
                
                if media.edit == nil {
                    initialCrop()
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
                let cgImage: CGImage
                do {
                    cgImage = try gen.copyCGImage(at: time, actualTime: &actualTime)
                } catch {
                    return
                }
                
                image = UIImage(cgImage: cgImage)
            }
        }
    }
    
    deinit {
        cancellable?.cancel()
    }
    
    func process() -> PendingMedia {
        var edit = media.edit ?? PendingMediaEdit(image: original)
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
            url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString, isDirectory: false)
                .appendingPathExtension("jpg")
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

        let format = UIGraphicsImageRendererFormat()
        format.preferredRange = .extended

        self.image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)

            context.cgContext.scaleBy(x: vFlipped ? -1 : 1, y: hFlipped ? -1 : 1)
            context.cgContext.rotate(by: CGFloat(numberOfRotations) * CGFloat(-Double.pi) / 2)

            image.draw(at: CGPoint(x: -image.size.width / 2, y: -image.size.height / 2))
        }
    }
    
    private func initialCrop() {
        guard let image = image else { return }

        if cropToCircle {
            let size = min(image.size.width, image.size.height)
            cropRect = CGRect(x: image.size.width / 2 - size / 2, y: image.size.height / 2  - size / 2, width: size, height: size)
        } else {
            var crop = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)

            let ratio = crop.size.height / crop.size.width
            crop.size.height = crop.size.width * min(maxAspectRatio, ratio)

            cropRect = crop;
        }
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

        let ratio = cropRect.size.height / cropRect.size.width
        cropRect.size.height = cropRect.size.width * min(maxAspectRatio, ratio)
        
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

        let format = UIGraphicsImageRendererFormat()
        format.preferredRange = .extended

        return UIGraphicsImageRenderer(size: cropRect.size, format: format).image { context in
            context.cgContext.translateBy(x: contextCenterX, y: contextCenterY)
            context.cgContext.translateBy(x: -cropOffsetX, y: -cropOffsetY)
            context.cgContext.translateBy(x: offset.x, y: offset.y)
            context.cgContext.scaleBy(x: scale, y: scale)

            image.draw(at: CGPoint(x: -imgCenterX, y: -imgCenterY))
        }
    }
}

fileprivate struct CropRegion: View {

    let cropToCircle: Bool
    let region: CGRect
    
    private let borderThickness: CGFloat = 4
    private let cornerSize = CGSize(width: 15, height: 15)
    private let shadowColor = Color(red: 0, green: 0, blue: 0, opacity: 0.7)
    
    var body: some View {
        GeometryReader { geometry in
            // Shadow
            Path { path in
                path.addRect(CGRect(x: -1, y: -1, width: geometry.size.width + 2, height: geometry.size.height + 2))

                if self.cropToCircle {
                    path.addEllipse(in: region)
                } else {
                    path.addRoundedRect(in: region, cornerSize: self.cornerSize)
                }
            }
            .fill(self.shadowColor, style: FillStyle(eoFill: true))
            
            // Border
            Path { path in
                let offset = borderThickness / 2
                let region = self.region.insetBy(dx: -offset + 1, dy: -offset + 1)

                if self.cropToCircle {
                    path.addEllipse(in: region)
                } else {
                    path.addRoundedRect(in: region, cornerSize: self.cornerSize)
                }
            }
            .stroke(Color.white, lineWidth: borderThickness)
        }
    }
}

fileprivate struct Preview: View {
    @ObservedObject var media: MediaEdit
    @Binding var selected: MediaEdit
    
    var body: some View {
        ZStack {
            if media.image != nil {
                Image(uiImage: media.image!)
                    .resizable()
                    .cornerRadius(3)
                    .aspectRatio(contentMode: .fill)
                    .overlay(selected === media ? nil : Rectangle().fill(Color.init(white: 0, opacity: 0.4)))
            }
            
            if media.type == .video {
                Image(systemName: "play.fill")
                    .foregroundColor(.white)
                    .imageScale(.large)
                    .opacity(0.6)
            }
        }
        .frame(width: 64, height: 80)
        .cornerRadius(5)
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.blue, lineWidth: selected === media ? 4 : 0))
        .onTapGesture {
            if selected !== media && media.type == .image {
                selected = media
            }
        }
    }
}

fileprivate class MediaItems : ObservableObject {
    @Published var items: [MediaEdit]

    init(_ items: [MediaEdit]) {
        self.items = items
    }
}

fileprivate struct PreviewCollection: UIViewControllerRepresentable {
    typealias UIViewControllerType = UICollectionViewController

    @ObservedObject var media: MediaItems
    @Binding var selected: MediaEdit

    func makeUIViewController(context: Context) -> UICollectionViewController {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 7
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 65, height: 80)

        let controller = UICollectionViewController(collectionViewLayout: layout)
        controller.collectionView.showsHorizontalScrollIndicator = false
        controller.collectionView.register(PreviewCell.self, forCellWithReuseIdentifier: PreviewCell.reuseIdentifier)

        controller.collectionView.dataSource = context.coordinator

        controller.installsStandardGestureForInteractiveMovement = false
        let recognizer = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongGesture(gesture:)))
        controller.collectionView.addGestureRecognizer(recognizer)

        return controller
    }

    func updateUIViewController(_ controller: UICollectionViewController, context: Context) {
        controller.collectionView.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    class Coordinator: NSObject, UICollectionViewDataSource {
        private var parent: PreviewCollection

        init(_ collection: PreviewCollection) {
            parent = collection

        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            return parent.media.items.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PreviewCell.reuseIdentifier, for: indexPath) as! PreviewCell
            cell.preview = Preview(media: parent.media.items[indexPath.row], selected: parent.$selected)
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
            parent.media.items.swapAt(sourceIndexPath.row, destinationIndexPath.row)
        }

        @objc func handleLongGesture(gesture: UILongPressGestureRecognizer) {
            guard let collectionView = gesture.view as? UICollectionView else { return }

            switch(gesture.state) {
            case .began:
                guard let indexPath = collectionView.indexPathForItem(at: gesture.location(in: collectionView)) else { return }
                collectionView.beginInteractiveMovementForItem(at: indexPath)
            case .changed:
                let location = gesture.location(in: collectionView)
                collectionView.updateInteractiveMovementTargetPosition(CGPoint(x: location.x, y: collectionView.bounds.midY))
            case .ended:
                collectionView.endInteractiveMovement()
            default:
                collectionView.cancelInteractiveMovement()
            }
        }
    }

    class PreviewCell: UICollectionViewCell {
        static var reuseIdentifier: String {
            return String(describing: PreviewCell.self)
        }

        private var controller: UIHostingController<Preview>?
        var preview: Preview? {
            didSet {
                if let preview = preview {
                    if let controller = controller {
                        controller.rootView = preview
                    } else {
                        controller = UIHostingController(rootView: preview)
                        controller!.view.frame = contentView.bounds
                        controller!.view.backgroundColor = .clear
                        contentView.addSubview(controller!.view)
                    }
                }
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            contentView.layer.cornerRadius = 5
            contentView.layer.masksToBounds = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

fileprivate struct CropGestureView: UIViewRepresentable {
    typealias UIViewType = UIView

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
            let location = sender.location(in: sender.view)
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
                    sender.location(ofTouch: 0, in: sender.view),
                    sender.location(ofTouch: 1, in: sender.view),
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
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return !(isDragRecognizer(gestureRecognizer) || isDragRecognizer(otherGestureRecognizer))
        }
    }
}

fileprivate struct CropImage: View {
    private enum CropRegionSection {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, inside, none
    }

    private let threshold = CGFloat(44)
    private let outThreshold = CGFloat(22)
    private let epsilon = CGFloat(1e-6)

    let cropToCircle: Bool
    let maxAspectRatio: CGFloat
    @ObservedObject var media: MediaEdit
    
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
        
        let isInsideVertical = (crop.minY + vThreshold) < location.y && location.y < (crop.maxY - vThreshold)
        let isInsideHorizontal = (crop.minX + hThreshold) < location.x && location.x < (crop.maxX - hThreshold)
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
        
        if (crop.size.height / crop.size.width) - maxAspectRatio > epsilon {
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
                            CropRegion(cropToCircle: self.cropToCircle, region: self.scaleCropRegion(self.media.cropRect, from: self.media.image!.size, to: inner.size))
                        })
                        .overlay(GeometryReader { inner in
                            CropGestureView()
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

                                        if self.cropToCircle {
                                            self.lastCropSection = .inside
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
            }
        }
    }
}

private extension Localizations {

    static var voiceOverButtonClose: String {
        NSLocalizedString("media.voiceover.button.close", value: "Close", comment: "Accessibility label for X (Close) button in media editor.")
    }

    static var voiceOverButtonRotate: String {
        NSLocalizedString("media.voiceover.button.rotate", value: "Rotate", comment: "Accessibility label for a button in media composer. Refers to photo / video editing action.")
    }

    static var voiceOverButtonFlip: String {
        NSLocalizedString("media.voiceover.button.flip", value: "Flip", comment: "Accessibility label for a button in media composer. Refers to photo / video editing action.")
    }

    static var discardConfirmationPrompt: String {
        NSLocalizedString("media.discard.confirmation", value: "Would you like to discard your edits?", comment: "Confirmation prompt in media composer.")
    }

    static var buttonDiscard: String {
        NSLocalizedString("media.button.discard", value: "Discard", comment: "Button title. Refers to discarding photo/video edits in media composer.")
    }

    static var buttonReset: String {
        NSLocalizedString("media.button.reset", value: "Reset", comment: "Button title. Refers to resetting photo / video to original version.")
    }
}

fileprivate struct MediaEditView : View {
    let cropToCircle: Bool
    let maxAspectRatio: CGFloat
    @State var media: MediaItems
    @State var selected: MediaEdit
    var complete: (([MediaEdit], Int, Bool) -> Void)?

    @State private var showDiscardSheet = false
    
    var topBar: some View {
        HStack {
            Button(action: { self.showDiscardSheet = true }) {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
                    .font(.system(size: 22, weight: .medium))
                    .accessibility(label: Text(Localizations.voiceOverButtonClose))
                    .padding()
            }
            .actionSheet(isPresented: $showDiscardSheet) {
                ActionSheet(
                    title: Text(Localizations.discardConfirmationPrompt),
                    message: nil,
                    buttons: [.destructive(Text(Localizations.buttonDiscard)) { self.complete?([], -1, true) }, .cancel()]
                )
            }
            
            Spacer()
            
            Button(action: { self.selected.rotate() }) {
                Image("Rotate")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(.white)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 22)
                    .accessibility(label: Text(Localizations.voiceOverButtonRotate))
                    .padding()
            }
            
            Button(action: { self.selected.flip() }) {
                Image("Flip")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(.white)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 22)
                    .accessibility(label: Text(Localizations.voiceOverButtonFlip))
                    .padding()
            }
        }
    }
    
    var bottomBar: some View {
        HStack {
            Spacer()
                .frame(width: 40)

            Button(action: {
                self.selected.reset()
                self.media.items.sort { $0.media.order < $1.media.order }
            }) {
                Text(Localizations.buttonReset)
                    .font(.gotham(fixedSize: 15, weight: .medium))
                    .foregroundColor(.white)
                    .padding()
            }
            
            Spacer()
            
            Button(action: {
                guard let index = self.media.items.firstIndex(where: { $0 === self.selected }) else { return }
                self.complete?(self.media.items, index, false)
            }) {
                Text(Localizations.buttonDone)
                    .font(.gotham(fixedSize: 15, weight: .medium))
                    .foregroundColor(.blue)
                    .padding()
            }

            Spacer()
                .frame(width: 40)
        }
    }

    var body: some View {
        ZStack {
            Rectangle()
                .foregroundColor(.black)
                .edgesIgnoringSafeArea(.all)

            VStack {
                topBar
                CropImage(cropToCircle: cropToCircle, maxAspectRatio: maxAspectRatio, media: selected)
                    .padding(8)
                PreviewCollection(media: media, selected: $selected)
                    .frame(height: 80)
                Spacer()
                    .frame(height: 30)
                bottomBar
            }
        }
    }
}
