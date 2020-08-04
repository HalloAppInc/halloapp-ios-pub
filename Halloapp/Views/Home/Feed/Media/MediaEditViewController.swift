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
    @Published var hFlipped = false
    @Published var vFlipped = false
    
    let type :FeedMediaType
    
    private let media: PendingMedia
    private var numberOfRotations = 0
    private var fileURL : URL?
    private var cancellable: AnyCancellable?
    
    init(media: PendingMedia) {
        self.media = media
        self.type = media.type
        
        if let edit = media.edit {
            self.image = edit.image
            self.cropRect = edit.cropRect
            self.hFlipped = edit.hFlipped
            self.vFlipped = edit.vFlipped
            self.numberOfRotations = edit.numberOfRotations
            self.fileURL = edit.originalURL
        } else {
            self.image = media.image
            self.fileURL = media.fileURL
        }
        
        load()
    }
    
    private func load() {
        switch media.type {
        case .image:
            if image == nil && self.fileURL != nil {
                cancellable = URLSession.shared.dataTaskPublisher(for: media.fileURL!)
                    .map { UIImage(data: $0.data) }
                    .replaceError(with: nil)
                    .receive(on: DispatchQueue.main)
                    .sink { image in
                        self.image = image
                        
                        if self.media.edit == nil {
                            self.initialCrop()
                        } else {
                            self.initTransformations()
                        }
                    }
            } else if self.media.edit == nil {
                self.initialCrop()
            } else {
                self.initTransformations()
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
    
    func initTransformations() {
        guard let image = image else { return }
        
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
    
    func process() -> PendingMedia {
        var edit = self.media.edit ?? PendingMediaEdit(originalURL: media.fileURL, image: self.media.image)
        edit.cropRect = self.cropRect
        edit.hFlipped = self.hFlipped
        edit.vFlipped = self.vFlipped
        edit.numberOfRotations = self.numberOfRotations
        
        let image = self.crop()
        guard let data = image?.jpegData(compressionQuality: 0.8) else { return media }
        
        var url: URL;
        if self.media.edit != nil {
            url = self.media.fileURL!
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
        media.fileURL = url
        media.edit = edit
        
        return media
    }
    
    func initialCrop() {
        guard let image = image else { return }
        
        var offset: CGFloat = 40
        if image.size.width < 120 || image.size.height < 120 {
            offset = CropRegion.borderThickness / 2
        }
        
        var crop = CGRect(x: offset, y: offset, width: image.size.width - 2 * offset, height: image.size.height - 2 * offset)
        
        let ratio = crop.size.height / crop.size.width
        crop.size.height = crop.size.width * min(CropRegion.maxAspectRatio, ratio)
        
        self.cropRect = crop;
    }
    
    func reset() {
        guard let image = image else { return }
        
        let size = (numberOfRotations % 2) == 0 ? image.size : CGSize(width: image.size.height, height: image.size.width)
        
        UIGraphicsBeginImageContext(size)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.rotate(by: CGFloat(numberOfRotations) * CGFloat(Double.pi) / 2)
        context.scaleBy(x: vFlipped ? -1 : 1, y: hFlipped ? -1 : 1)
        
        image.draw(at: CGPoint(x: -image.size.width / 2, y: -image.size.height / 2))
        let result = context.makeImage()
        UIGraphicsEndImageContext()
        
        if let result = result {
            self.image = UIImage(cgImage: result)
            numberOfRotations = 0
            vFlipped = false
            hFlipped = false
            
            initialCrop()
        }
    }
    
    func rotate() {
        guard let image = image else { return }
        
        let size = CGSize(width: image.size.height, height: image.size.width)
        
        UIGraphicsBeginImageContext(size)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.rotate(by: CGFloat(-Double.pi) / 2)
        
        image.draw(at: CGPoint(x: -image.size.width / 2, y: -image.size.height / 2))
        let result = context.makeImage()
        UIGraphicsEndImageContext()
        
        if let result = result {
            self.image = UIImage(cgImage: result)
            numberOfRotations = (numberOfRotations + 1) % 4
            
            swap(&vFlipped,  &hFlipped)
            
            let w = cropRect.size.width
            let h = cropRect.size.height
            let x = cropRect.origin.x
            let y = cropRect.origin.y
            
            cropRect.size.width = h
            cropRect.size.height = w
            cropRect.origin.x = y
            cropRect.origin.y = self.image!.size.height - w - x
        }
    }
    
    func flip() {
        guard let image = image else { return }
        
        UIGraphicsBeginImageContext(image.size)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.translateBy(x: image.size.width / 2, y: image.size.height / 2)
        context.scaleBy(x: -1, y: 1)

        image.draw(at: CGPoint(x: -image.size.width / 2, y: -image.size.height / 2))
        let result = context.makeImage()
        UIGraphicsEndImageContext()
        
        if let result = result {
            self.image = UIImage(cgImage: result)
            
            vFlipped.toggle()
            cropRect.origin.x = image.size.width - cropRect.size.width - cropRect.origin.x
        }
    }
    
    func crop() -> UIImage? {
        guard let cropped = image?.cgImage?.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped)
    }
}

fileprivate struct CropRegion: View {
    private enum DragSection {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, inside, none
    }
    
    static let maxAspectRatio: CGFloat = 5/4
    static let borderThickness: CGFloat = 8
    
    private let threshold = CGFloat(44)
    private let cornerSize = CGSize(width: 15, height: 15)
    private let shadowColor = Color(red: 0, green: 0, blue: 0, opacity: 0.5)
    
    let fullSize: CGSize
    @Binding var cropRect: CGRect
    
    @State private var isDragging = false
    @State private var prevDragLocation = CGPoint.zero
    @State private var dragSection: DragSection = .none
    
    private func findDragSection(_ crop: CGRect, location: CGPoint) -> DragSection {
        let isTop = (crop.minY < location.y) && (location.y < (crop.minY + threshold))
        let isBottom = ((crop.maxY - threshold) < location.y) && (location.y < crop.maxY)
        let isLeft = (crop.minX < location.x) && (location.x < (crop.minX + threshold))
        let isRight = ((crop.maxX - threshold) < location.x) && (location.x < crop.maxX)
        
        if isTop && isLeft {
            return .topLeft
        }
        
        if isTop && isRight {
            return .topRight
        }
        
        if isBottom && isRight {
            return .bottomRight
        }
        
        if isBottom && isLeft {
            return .bottomLeft
        }
        
        if isTop {
            return .top
        }
        
        if isRight {
            return .right
        }
        
        if isBottom {
            return .bottom
        }
        
        if isLeft {
            return .left
        }
        
        let isInsideVertical = (crop.minY + threshold) < location.y && location.y < (crop.maxY - threshold)
        let isInsideHorizontal = (crop.minX + threshold) < location.x && location.x < (crop.maxX - threshold)
        if isInsideVertical && isInsideHorizontal {
            return .inside
        }
        
        return .none
    }
    
    private func updateCropRegion(_ crop: CGRect, deltaX: CGFloat = 0, deltaY: CGFloat = 0) -> CGRect {
        var crop = crop
        
        switch dragSection {
        case .top, .topLeft, .topRight:
            crop.origin.y += deltaY
            crop.size.height -= deltaY
        case .bottom, .bottomLeft, .bottomRight:
            crop.size.height += deltaY
        default:
            break
        }
        
        switch dragSection {
        case .left, .bottomLeft, .topLeft:
            crop.origin.x += deltaX
            crop.size.width -= deltaX
        case .right, .bottomRight, .topRight:
            crop.size.width += deltaX
        default:
            break
        }
            
        if dragSection == .inside {
            crop.origin.x += deltaX
            crop.origin.y += deltaY
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
    
    private func isAllowedAspectRatio(_ crop: CGRect) -> Bool {
        return (crop.size.height / crop.size.width) <= CropRegion.maxAspectRatio
    }
    
    private func isValid(_ crop: CGRect, limit: CGSize) -> Bool {
        return isCropRegionWithinLimit(crop, limit: limit) &&
            isAllowedAspectRatio(crop) &&
            isCropRegionMinSize(crop)
    }
    
    private func scale(crop: CGRect, from: CGSize, to: CGSize) -> CGRect {
        let scale = to.height / from.height
        return crop.applying(CGAffineTransform(scaleX: scale, y: scale))
    }
    
    var body: some View {
        GeometryReader { geometry in
            // Shadow
            Path { path in
                let region = self.scale(crop: self.cropRect, from: self.fullSize, to: geometry.size)
                path.addRect(CGRect(x: 0, y: 0, width: geometry.size.width, height: geometry.size.height))
                path.addRoundedRect(in: region, cornerSize: self.cornerSize)
            }
            .fill(self.shadowColor, style: FillStyle(eoFill: true))
            
            // Border
            Path { path in
                let region = self.scale(crop: self.cropRect, from: self.fullSize, to: geometry.size)
                path.addRoundedRect(in: region, cornerSize: self.cornerSize)
            }
            .stroke(Color.white, lineWidth: CropRegion.borderThickness)
            .contentShape(Rectangle()) // Apply gesture on the whole region and not just the border
            .gesture(DragGesture()
                .onChanged { v in
                    var crop = self.scale(crop: self.cropRect, from: self.fullSize, to: geometry.size)
                    
                    if (!self.isDragging) {
                        guard crop.contains(v.location) else { return }
                        self.dragSection = self.findDragSection(crop, location: v.location)
                        self.prevDragLocation = v.location
                        self.isDragging = true
                    }
                    
                    let deltaX = v.location.x - self.prevDragLocation.x
                    let deltaY = v.location.y - self.prevDragLocation.y
                    self.prevDragLocation = v.location
                    
                    var result = self.updateCropRegion(crop, deltaX: deltaX)
                    if self.isValid(result, limit: geometry.size) {
                        crop = result
                    }
                    
                    result = self.updateCropRegion(crop, deltaY: deltaY)
                    if self.isValid(result, limit: geometry.size) {
                        crop = result
                    }
                    
                    self.cropRect = self.scale(crop: crop, from: geometry.size, to: self.fullSize)
                }
                .onEnded { _ in
                    self.isDragging = false
                }
            )
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

fileprivate struct CropImage: View {
    @ObservedObject var media: MediaEdit
    
    var body: some View {
        Group {
            if media.image != nil {
                Image(uiImage: media.image!)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay(CropRegion(fullSize: media.image!.size, cropRect: $media.cropRect))
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
        ZStack {
            HStack {
                Button(action: { self.showDiscardSheet = true }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                        .imageScale(.large)
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
                
                Button(action: { self.selected.reset() }) {
                    Text("Reset")
                        .foregroundColor(.white)
                        .padding()
                }
            }
            
            Text("Edit")
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
    }
    
    var bottomBar: some View {
        HStack {
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
            
            ZStack {
                CropImage(media: selected)
                
                VStack {
                    topBar
                    Spacer()
                    previews
                    bottomBar
                    Spacer()
                        .frame(height: 30)
                }
            }
        }
        .background(Color.black)
        .edgesIgnoringSafeArea(.bottom)
    }
}
