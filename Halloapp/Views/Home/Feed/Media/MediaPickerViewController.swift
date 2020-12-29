//
//  MediaPickerViewController.swift
//  HalloApp
//
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import CocoaLumberjack
import Core
import Foundation
import Photos
import UIKit

private extension Localizations {
    static var defaultTitle: String {
        NSLocalizedString("picker.default.title", value: "Camera Roll", comment: "Initial picker screen title. The default source of picker photos")
    }

    static var photoAccessDeniedTitle: String {
        NSLocalizedString("picker.access.denied.title", value: "Photo Access Denied", comment: "Alert title in media picker when access is denied.")
    }

    static var photoAccessDeniedMessage: String {
        NSLocalizedString("picker.access.denied.message", value: "Please grant access from Settings", comment: "Message in media picker when access is denied.")
    }

    static var mediaLimitTitle: String {
        NSLocalizedString("picker.media.limit.title", value: "Maximum items selected", comment: "Alert title in media picker when selecting over limit.")
    }

    static func mediaLimitMessage(_ maxNumberOfPhotos: Int) -> String {
        let format = NSLocalizedString("picker.media.n.limit", comment: "Message in media picker when selecting over limit.")
        return String.localizedStringWithFormat(format, maxNumberOfPhotos)
    }
}

private struct Constants {
    static let maxNumberOfPhotos = 10
}

enum MediaPickerFilter {
    case all, image, video
}

fileprivate enum MediaPickerMode {
    case month, day, dayLarge
}

fileprivate enum TransitionState {
    case ready, inprogress, finishing
}

typealias MediaPickerViewControllerCallback = (MediaPickerViewController, [PendingMedia], Bool) -> Void

class MediaPickerViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, PHPhotoLibraryChangeObserver, PickerViewCellDelegate {

    fileprivate var mode: MediaPickerMode = .day
    fileprivate var selected = [PHAsset]()
    fileprivate var multiselect: Bool
    
    private let didFinish: MediaPickerViewControllerCallback
    private let camera: Bool
    private let filter: MediaPickerFilter
    private let snapshotManager: MediaPickerSnapshotManager
    private var dataSource: UICollectionViewDiffableDataSource<Int, PickerItem>!
    private var collectionView: UICollectionView!
    private var transitionLayout: UICollectionViewTransitionLayout?
    private var initialTransitionVelocity: CGFloat = 0
    private var transitionState: TransitionState = .ready
    private var preview: UIView?
    private var updatingSnapshot = false
    private var nextInProgress = false
    private var originalMedia: [PendingMedia] = []
    
    init(filter: MediaPickerFilter = .all, multiselect: Bool = true, camera: Bool = false, selected: [PendingMedia] = [] , didFinish: @escaping MediaPickerViewControllerCallback) {
        self.originalMedia.append(contentsOf: selected)
        self.selected.append(contentsOf: selected.filter { $0.asset != nil }.map { $0.asset! })
        self.didFinish = didFinish
        self.camera = camera
        self.multiselect = multiselect
        self.filter = filter
        self.snapshotManager = MediaPickerSnapshotManager(filter: filter)

        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Use init(didFinish:)")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupNavigationBar()
        collectionView = makeCollectionView(layout: makeLayout())
        dataSource = makeDataSource(collectionView)

        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leftAnchor.constraint(equalTo: view.leftAnchor),
            collectionView.rightAnchor.constraint(equalTo: view.rightAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        setupZoom()
        setupPreviews()

        PHPhotoLibrary.shared().register(self)
        fetchAssets()
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    private func fetchAssets(album: PHAssetCollection? = nil) {
        switch(PHPhotoLibrary.authorizationStatus()) {
        case .authorized, .limited:
            break
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.fetchAssets(album: album)
                }
            }
            return
        case .denied, .restricted:
            let alert = UIAlertController(title: Localizations.photoAccessDeniedTitle, message: Localizations.photoAccessDeniedMessage, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default))
            self.present(alert, animated: true)
            return
        default:
            break
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            if let album = album {
                // Unable to filter album assets by type, will filter them in snapshot manager
                self.snapshotManager.reset(with: PHAsset.fetchAssets(in: album, options: options))
            } else {
                switch self.filter {
                case .all:
                    self.snapshotManager.reset(with: PHAsset.fetchAssets(with: options))
                case .image:
                    self.snapshotManager.reset(with: PHAsset.fetchAssets(with: .image, options: options))
                case .video:
                    self.snapshotManager.reset(with: PHAsset.fetchAssets(with: .video, options: options))
                }

            }
            
            let snapshot = self.snapshotManager.next()
            
            DispatchQueue.main.async {
                self.dataSource.apply(snapshot)
            }
        }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let snapshot = self.snapshotManager.update(change: changeInstance) else { return }

            DispatchQueue.main.async {
                self.dataSource.apply(snapshot, animatingDifferences: true)
            }
        }
    }
    
    private func setupNavigationBar(title: String? = nil) {
        navigationController?.navigationBar.standardAppearance = .translucentAppearance
        navigationController?.navigationBar.isTranslucent = true
        
        let titleBtn = UIButton(type: .system)
        titleBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleBtn.widthAnchor.constraint(equalToConstant: 160),
            titleBtn.heightAnchor.constraint(equalToConstant: 44),
        ])
        titleBtn.setTitle(title ?? Localizations.defaultTitle, for: .normal)
        titleBtn.setImage(UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)), for: .normal)
        titleBtn.semanticContentAttribute = .forceRightToLeft // Workaround to move the image on the right side
        titleBtn.addTarget(self, action: #selector(openAlbumsAction), for: .touchUpInside)
        titleBtn.titleEdgeInsets.right = 10
        
        titleBtn.titleLabel?.font = UIFont.gothamFont(ofFixedSize: 17, weight: .medium)
        navigationItem.titleView = titleBtn
        
        updateNavigationBarButtons()
    }
    
    public func reset(selected: [PendingMedia]) {
        originalMedia.removeAll()
        originalMedia.append(contentsOf: selected)

        self.selected.removeAll()
        self.selected.append(contentsOf: selected.filter { $0.asset != nil }.map { $0.asset! })
        
        for cell in collectionView.visibleCells {
            guard let cell = cell as? AssetViewCell else { continue }
            cell.prepare()
        }
        
        updateNavigationBarButtons()
    }
    
    private func updateNavigationBarButtons() {
        let backIcon = UIImage(systemName: selected.count > 0 ? "xmark" : "chevron.left", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: backIcon, style: .plain, target: self, action: #selector(cancelAction))

        var buttons = [UIBarButtonItem]()

        if multiselect {
            let nextButton = UIBarButtonItem(title: Localizations.buttonNext, style: .done, target: self, action: #selector(nextAction))
            nextButton.tintColor = selected.count > 0 ? .systemBlue : .systemGray
            buttons.append(nextButton)
        }

        if camera {
            let cameraIcon = UIImage(systemName: "camera.fill", withConfiguration: UIImage.SymbolConfiguration(scale: .large))
            let cameraButton = UIBarButtonItem(image: cameraIcon, style: .done, target: self, action: #selector(cameraAction))
            buttons.append(cameraButton)
        }

        navigationItem.rightBarButtonItems = buttons
    }
    
    private func setupZoom() {
        let zoomRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(self.onZoom(sender:)))
        collectionView.addGestureRecognizer(zoomRecognizer)
    }
    
    @objc func onZoom(sender: UIPinchGestureRecognizer) {
        if transitionState == .finishing {
            return
        }
        
        if sender.state == .began || sender.state == .changed {
            if transitionState == .ready {
                if (sender.velocity > 0) {
                    switch mode {
                    case .month:
                        mode = .day
                    case .day:
                        mode = .dayLarge
                    default:
                        return
                    }
                } else {
                    switch mode {
                    case .dayLarge:
                        mode = .day
                    case .day:
                        mode = .month
                    default:
                        return
                    }
                }
                
                for cell in collectionView.visibleCells {
                    guard let cell = cell as? AssetViewCell else { continue }
                    cell.prepare()
                }
                
                transitionState = .inprogress
                initialTransitionVelocity = sender.velocity
                transitionLayout = collectionView.startInteractiveTransition(to: makeLayout()) { completed, finish in
                    self.transitionLayout = nil
                    self.transitionState = .ready
                }
            }
            
            if initialTransitionVelocity * sender.velocity > 0 {
                transitionLayout?.transitionProgress += 0.02
            } else {
                transitionLayout?.transitionProgress -= 0.02
            }
            
            transitionLayout?.invalidateLayout()
        } else if sender.state == .ended {
            if transitionState == .inprogress {
                transitionState = .finishing
                collectionView.finishInteractiveTransition()
            }
        }
    }
    
    private func setupPreviews() {
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(onDisplayPreview(sender:)))
        collectionView.addGestureRecognizer(longPressRecognizer)
    }
    
    @objc func onDisplayPreview(sender: UILongPressGestureRecognizer) {
        if sender.state == .began {
            let p = sender.location(in: collectionView)
            guard let indexPath = collectionView.indexPathForItem(at: p) else { return }
            guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
            guard item.type == .asset else { return }
            guard let asset = item.asset else { return }
            guard self.preview == nil else { return }
            
            let manager = PHImageManager.default()
            
            if asset.mediaType == .image {
                let options = PHImageRequestOptions()
                options.isSynchronous = true
                options.isNetworkAccessAllowed = true

                manager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) {[weak self] image, _ in
                    guard let self = self else { return }
                    guard let image = image else { return }
                    guard self.preview == nil else { return }
                    
                    self.makeImagePreview(image)
                    self.showPreview()
                }
            } else if asset.mediaType == .video {
                let options = PHVideoRequestOptions()
                options.isNetworkAccessAllowed = true
                
                manager.requestPlayerItem(forVideo: asset, options: options) {[weak self] playerItem, _ in
                    guard let self = self else { return }
                    guard let playerItem = playerItem else { return }
                    guard self.preview == nil else { return }
                    
                    self.makeVideoPreview(playerItem)
                    self.showPreview()
                }
            }
        } else if self.preview != nil && sender.state == .ended {
            hidePreview()
        }
    }
    
    private func makeImagePreview(_ image: UIImage) {
        guard let window = view.window else { return }

        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.backgroundColor = UIColor.init(red: 0, green: 0, blue: 0, alpha: 0.6)
        window.addSubview(content)
        
        let iView = UIImageView()
        iView.translatesAutoresizingMaskIntoConstraints = false
        iView.contentMode = .scaleAspectFit
        iView.layer.cornerRadius = 15
        iView.clipsToBounds = true
        iView.image = image
        content.addSubview(iView)
        
        preview = content

        let spacing = CGFloat(20)
        let widthRatio = (view.bounds.width - 2 * spacing) / image.size.width
        let heightRatio = (view.bounds.height - 2 * spacing) / image.size.height
        let scale = min(widthRatio, heightRatio, 1)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: window.topAnchor),
            content.leftAnchor.constraint(equalTo: window.leftAnchor),
            content.rightAnchor.constraint(equalTo: window.rightAnchor),
            content.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            iView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            iView.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            iView.widthAnchor.constraint(equalToConstant: image.size.width * scale),
            iView.heightAnchor.constraint(equalToConstant: image.size.height * scale),
        ])
    }
    
    private func makeVideoPreview(_ item: AVPlayerItem) {
        let content = UIView()
        content.backgroundColor = UIColor.init(red: 0, green: 0, blue: 0, alpha: 0.4)
        content.frame = view.bounds
        
        let player = AVPlayer(playerItem: item)
        let playerView = PlayerPreviewView()
        playerView.player = player
        playerView.frame = view.bounds.insetBy(dx: 40, dy: 40)
        content.addSubview(playerView)
        
        player.play()
        
        preview = content
        view.window?.addSubview(content)
    }
    
    private func showPreview() {
        guard let preview = self.preview else { return }
        
        preview.alpha = 0
        UIView.animate(withDuration: 0.3) {
            preview.alpha = 1
        }
    }
    
    private func hidePreview() {
        guard let preview = self.preview else { return }
        self.preview = nil
        
        UIView.animate(withDuration: 0.3, animations: {
            preview.alpha = 0
        }, completion: { finished in
            preview.removeFromSuperview()
        })
    }
    
    private func makeCollectionView(layout: UICollectionViewFlowLayout) -> UICollectionView {
        let collectionView = UICollectionView(frame: view.frame, collectionViewLayout: layout)
        collectionView.delegate = self
        collectionView.backgroundColor = .feedBackground
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.allowsMultipleSelection = true
        collectionView.register(AssetViewCell.self, forCellWithReuseIdentifier: AssetViewCell.reuseIdentifier)
        collectionView.register(LabelViewCell.self, forCellWithReuseIdentifier: LabelViewCell.reuseIdentifier)
        collectionView.register(PlaceHolderViewCell.self, forCellWithReuseIdentifier: PlaceHolderViewCell.reuseIdentifier)
        
        return collectionView
    }
    
    private func makeLayout() -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        
        return layout
    }
    
    private func makeDataSource(_ collectionView: UICollectionView) -> UICollectionViewDiffableDataSource<Int, PickerItem> {
        let source = UICollectionViewDiffableDataSource<Int, PickerItem>(collectionView: collectionView) { [weak self] collectionView, indexPath, asset in
            guard let self = self else { return nil }
            guard let source = self.dataSource else { return nil }
            guard let item = source.itemIdentifier(for: indexPath) else { return nil }
            
            switch item.type {
            case .asset:
                guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AssetViewCell.reuseIdentifier, for: indexPath) as? AssetViewCell else {
                    return nil
                }
                
                cell.delegate = self
                cell.item = item

                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = true
                PHImageManager.default().requestImage(for: item.asset!, targetSize: CGSize(width: 256, height: 256), contentMode: .aspectFill, options: options) { image, _ in
                    guard cell.item?.asset?.localIdentifier == item.asset?.localIdentifier else { return }
                    cell.image.image = image
                    cell.prepare()
                }
                
                return cell
            case .day, .month:
                guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: LabelViewCell.reuseIdentifier, for: indexPath) as? LabelViewCell else { return nil }
                cell.title.text = item.label
                return cell
            case .placeholderDay, .placeholderMonth, .placeholderDayLarge:
                return collectionView.dequeueReusableCell(withReuseIdentifier: PlaceHolderViewCell.reuseIdentifier, for: indexPath)
            }
        }
        
        return source
    }

    @objc private func cameraAction() {
        let controller = CameraViewController(
            showCancelButton: false,
            didFinish: { [weak self] in self?.dismiss(animated: true) },
            didPickImage: { [weak self] image in
                guard let self = self else { return }
                self.dismiss(animated: true)

                let media = PendingMedia(type: .image)
                media.order = 1
                media.image = image
                media.size = image.size

                self.didFinish(self, [media], false)
            },
            didPickVideo: { [weak self] url in
                guard let self = self else { return }
                self.dismiss(animated: true)

                let media = PendingMedia(type: .video)
                media.order = 1
                media.videoURL = url

                if let size = VideoUtils.resolutionForLocalVideo(url: url) {
                    media.size = size
                }

                self.didFinish(self, [media], false)
            }
        )

        self.present(controller, animated: true)
    }
    
    @objc private func nextAction() {
        guard selected.count > 0 else { return }
        guard !nextInProgress else { return }
        nextInProgress = true
        
        var result = [PendingMedia]()
        self.selected.sort {
            if let d0 = $0.creationDate, let d1 = $1.creationDate {
                return d0 < d1
            }

            return false
        }
        
        let manager = PHImageManager.default()
        let group = DispatchGroup()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            for i in 0..<self.selected.count {
                let asset = self.selected[i]

                if let media = self.originalMedia.first(where: { $0.asset == asset }) {
                    result.append(media)
                    continue
                }
                
                switch asset.mediaType {
                case .image:
                    let media = PendingMedia(type: .image)
                    media.asset = asset
                    media.order = i + 1
                    media.size = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
                    
                    let options = PHImageRequestOptions()
                    options.isSynchronous = true
                    options.isNetworkAccessAllowed = true
                    
                    group.enter()
                    manager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .default, options: options) { image, _ in
                        media.image = image
                        group.leave()
                    }
                    
                    result.append(media)
                case .video:
                    let media = PendingMedia(type: .video)
                    media.asset = asset
                    media.order = i + 1

                    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    media.videoURL = base.appendingPathComponent("video-\(UUID().uuidString).mp4")

                    let options = PHVideoRequestOptions()
                    options.isNetworkAccessAllowed = true

                    group.enter()
                    manager.requestAVAsset(forVideo: asset, options: options) { avasset, _, _ in
                        let video = avasset as! AVURLAsset
                        media.videoURL = video.url

                        if let size = VideoUtils.resolutionForLocalVideo(url: media.videoURL!) {
                            media.size = size
                        }

                        group.leave()
                    }
                    
                    result.append(media)
                default:
                    continue
                }
            }
            
            group.notify(queue: .main) { [weak self] in
                guard let self = self else { return }

                if !self.multiselect {
                    self.selected.removeAll()
                }

                self.nextInProgress = false
                self.didFinish(self, result, false)
            }
        }
    }
    
    @objc private func cancelAction() {
        if selected.count > 0 {
            selected.removeAll()
            
            for cell in collectionView.visibleCells {
                guard let cell = cell as? AssetViewCell else { continue }
                cell.prepare()
            }
            
            updateNavigationBarButtons()
        }

        didFinish(self, [], true)
    }
    
    @objc private func openAlbumsAction() {
        let controller = MediaAlbumsViewController() {[weak self] controller, album, cancel in
            guard let self = self else { return }
            
            controller.dismiss(animated: true)
            
            if !cancel {
                self.setupNavigationBar(title: album?.localizedTitle)
                self.fetchAssets(album: album)
            }
        }
        self.present(controller, animated: true)
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !updatingSnapshot else { return }
        guard let row = collectionView.indexPathsForVisibleItems.last?.row else { return }
        guard dataSource.snapshot().numberOfItems > 0 else { return }
        
        
        if (Float(row) / Float(dataSource.snapshot().numberOfItems)) > 0.4 {
            updatingSnapshot = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                let snapshot = self.snapshotManager.next()
                
                DispatchQueue.main.async {
                    self.updatingSnapshot = false
                    self.dataSource.apply(snapshot)
                }
            }
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return CGSize.zero }
        
        switch (item.type, mode) {
        case (.asset, .month), (.placeholderMonth, .month):
            let size = (UIScreen.main.bounds.width - 0.1) * 0.2
            return CGSize(width: size, height: size)
        case (.asset, .day), (.placeholderDay, .day):
            let size = UIScreen.main.bounds.width * 0.25
            return CGSize(width: size, height: size)
        case (.asset, .dayLarge) where (item.indexInDay % 5) < 2:
            let size = UIScreen.main.bounds.width * 0.5
            return CGSize(width: size, height: size * 1.27)
        case (.placeholderDayLarge, .dayLarge) where (item.indexInDay % 5) < 2:
            let size = UIScreen.main.bounds.width * 0.5
            return CGSize(width: size, height: size * 1.27)
        case (.asset, .dayLarge), (.placeholderDayLarge, .dayLarge):
            let size = UIScreen.main.bounds.width * 0.3333
            return CGSize(width: size, height: size * 1.42)
        case (.day, .day), (.day, .dayLarge), (.month, .month):
            return CGSize(width: UIScreen.main.bounds.width, height: 50)
        default:
            return CGSize.zero
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 0
    }
    
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let cell = collectionView.cellForItem(at: indexPath) as? AssetViewCell else { return false }
        guard let asset = cell.item?.asset else { return false }

        if selected.contains(asset) {
            deselect(collectionView, cell: cell, asset: asset)
        } else if selected.count >= Constants.maxNumberOfPhotos {
            let alert = UIAlertController(title: Localizations.mediaLimitTitle,
                                          message: Localizations.mediaLimitMessage(Constants.maxNumberOfPhotos),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default))
            self.present(alert, animated: true)
        } else {
            select(collectionView, cell: cell, asset: asset)
        }
        
        return false
    }
    
    private func select(_ collectionView: UICollectionView, cell: AssetViewCell, asset: PHAsset) {
        if !multiselect {
            selected.append(asset)
            nextAction()
            return
        }

        selected.append(asset)
        updateNavigationBarButtons()

        UIView.animateKeyframes(withDuration: 0.2, delay: 0, options: [], animations: {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5, animations: {
                cell.image.layer.cornerRadius = 15
                cell.image.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
                cell.prepareIndicator()
            })
            
            UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5, animations: {
                cell.image.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            })
        }, completion: { _ in
            cell.prepare()
        })
    }
    
    private func deselect(_ collectionView: UICollectionView, cell: AssetViewCell, asset: PHAsset) {
        guard let idx = self.selected.firstIndex(of: asset) else { return }
        self.selected.remove(at: idx)
        self.updateNavigationBarButtons()

        UIView.animateKeyframes(withDuration: 0.2, delay: 0, options: [], animations: {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5, animations: {
                cell.image.layer.cornerRadius = 0
                cell.image.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                cell.prepareIndicator()
            })
            
            UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5, animations: {
                cell.image.transform = CGAffineTransform.identity
            })
        }, completion: { _ in
            for cell in collectionView.visibleCells {
                guard let cell = cell as? AssetViewCell else { continue }
                cell.prepare()
            }
        })
    }
}

class PlayerPreviewView: UIView {
    var player: AVPlayer? {
        get {
            return playerLayer.player
        }
        set {
            playerLayer.player = newValue
            playerLayer.player?.currentItem?.addObserver(self, forKeyPath: "status", options: [], context: nil)
        }
    }
    
    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }
    
    // Override UIView property
    override static var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    private func makeVideoRounded() {
        let maskLayer = CAShapeLayer()
        maskLayer.path = UIBezierPath(roundedRect: playerLayer.videoRect, cornerRadius: 15).cgPath
        playerLayer.mask = maskLayer
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status" {
            guard let status = playerLayer.player?.currentItem?.status, status == .readyToPlay else { return }
            makeVideoRounded()
            return
        }
        
        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }
}

fileprivate protocol PickerViewCellDelegate: class {
    var mode: MediaPickerMode {get}
    var selected: [PHAsset] {get}
    var multiselect: Bool {get}
}

enum PickerItemType {
    case asset, day, month, placeholderMonth, placeholderDay, placeholderDayLarge
}

struct PickerItem: Hashable {
    let indexInMonth: Int
    let indexInDay: Int
    let type: PickerItemType
    let label: String?
    let asset: PHAsset?
    
    init(type: PickerItemType, indexInMonth: Int, indexInDay: Int) {
        self.type = type
        self.label = UUID().uuidString
        self.asset = nil
        self.indexInMonth = indexInMonth
        self.indexInDay = indexInDay
    }
    
    init(type: PickerItemType, label: String) {
        self.type = type
        self.label = label
        self.asset = nil
        indexInMonth = 0
        indexInDay = 0
    }
    
    init(asset: PHAsset, indexInMonth: Int, indexInDay: Int) {
        self.type = .asset
        self.label = nil
        self.asset = asset
        self.indexInMonth = indexInMonth
        self.indexInDay = indexInDay
    }
}

fileprivate class PlaceHolderViewCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: PlaceHolderViewCell.self)
    }
}

fileprivate class LabelViewCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: LabelViewCell.self)
    }
    
    lazy var title: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .left
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .feedBackground
        contentView.addSubview(title)
        contentView.clipsToBounds = true
        
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            title.topAnchor.constraint(equalTo: contentView.topAnchor),
            title.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

fileprivate class AssetViewCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: AssetViewCell.self)
    }
    
    weak var delegate: PickerViewCellDelegate?
    var item: PickerItem?

    static private let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .dropTrailing
        formatter.allowedUnits = [.second, .minute]

        return formatter
    }()
    private var activeConstraints = [NSLayoutConstraint]()

    lazy var indicatorMark: UIImageView = {
        let mark = UIImageView()
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.contentMode = .scaleAspectFit
        mark.image = UIImage(named: "SelectMark")?.withTintColor(.white, renderingMode: .alwaysOriginal)

        return mark
    }()

    lazy var indicator: UIView = {
        let indicator = UIView()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.layer.cornerRadius = 10
        indicator.layer.borderWidth = 2.5
        indicator.layer.masksToBounds = true

        indicator.addSubview(indicatorMark)

        NSLayoutConstraint.activate([
            indicatorMark.topAnchor.constraint(equalTo: indicator.topAnchor, constant: 1),
            indicatorMark.bottomAnchor.constraint(equalTo: indicator.bottomAnchor, constant: -1),
            indicatorMark.leadingAnchor.constraint(equalTo: indicator.leadingAnchor, constant: 1),
            indicatorMark.trailingAnchor.constraint(equalTo: indicator.trailingAnchor, constant: -1),
        ])

        return indicator
    }()
    
    lazy var image: UIImageView = {
        let image = UIImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        
        return image
    }()

    lazy var duration: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .right
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white

        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.addSubview(image)
        contentView.addSubview(indicator)
        contentView.addSubview(duration)
        contentView.clipsToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func calculateSpacing() -> (CGFloat, CGFloat, CGFloat) {
        guard let delegate = delegate else { return (0, 0, 0) }
        guard let item = item else { return (0, 0, 0) }
        
        let spacing = CGFloat(1)
        
        var column: CGFloat
        var columnCount: CGFloat
        
        switch delegate.mode {
        case .month:
            column = CGFloat(item.indexInMonth % 5)
            columnCount = 5
        case .day:
            column = CGFloat(item.indexInDay % 4)
            columnCount = 4
        case .dayLarge:
            let indexInBlock = item.indexInDay % 5
            
            if indexInBlock < 2 {
                column = CGFloat(indexInBlock)
                columnCount = 2
            } else {
                column = CGFloat((indexInBlock - 2) % 3)
                columnCount = 3
            }
        }
        
        return (spacing, column * spacing / columnCount, spacing - ((column + 1) * spacing / columnCount))
    }
    
    func prepare() {
        let (spacingBottom, spacingLead, spacingTrail) = calculateSpacing()
        
        NSLayoutConstraint.deactivate(activeConstraints)
        
        activeConstraints = [
            image.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacingLead),
            image.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacingTrail),
            image.topAnchor.constraint(equalTo: contentView.topAnchor),
            image.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -spacingBottom),
            indicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            indicator.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            indicator.widthAnchor.constraint(equalToConstant: 20),
            indicator.heightAnchor.constraint(equalToConstant: 20),
            duration.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            duration.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -6),
        ]
        
        NSLayoutConstraint.activate(activeConstraints)

        if let asset = item?.asset, delegate?.selected.contains(asset) == true {
            image.layer.cornerRadius = 15
            image.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        } else {
            image.layer.cornerRadius = 0
            image.transform = CGAffineTransform.identity
        }

        if item?.asset?.mediaType == .video, let interval = item?.asset?.duration {
            duration.isHidden = false
            duration.text = Self.durationFormatter.string(from: interval)
        } else {
            duration.isHidden = true
        }

        prepareIndicator()

        setNeedsLayout()
    }

    func prepareIndicator() {
        if let asset = item?.asset, delegate?.selected.contains(asset) == true {
            indicator.layer.borderColor = UIColor.lavaOrange.cgColor
            indicator.backgroundColor = .lavaOrange
            indicatorMark.isHidden = false
        } else {
            indicator.layer.borderColor = CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.7)
            indicator.backgroundColor = .clear
            indicatorMark.isHidden = true
        }

        if let multiselect = delegate?.multiselect, !multiselect {
            indicator.isHidden = true
        }
    }
}
