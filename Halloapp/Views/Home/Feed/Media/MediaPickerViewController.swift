//
//  MediaPickerViewController.swift
//  HalloApp
//
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import CocoaLumberjackSwift
import Core
import CoreCommon
import Foundation
import PhotosUI
import UIKit
import AuthenticationServices
import Combine

private extension Localizations {
    static var photoAccessDeniedTitle: String {
        NSLocalizedString("picker.access.denied.title", value: "Photo Access Denied", comment: "Alert title in media picker when access is denied.")
    }

    static var photoAccessDeniedMessage: String {
        NSLocalizedString("picker.access.denied.message", value: "Please grant access from Settings", comment: "Message in media picker when access is denied.")
    }

    static var photoAccessDeniedSettings: String {
        NSLocalizedString("picker.access.denied.settings", value: "Settings", comment: "An option to give access from settings")
    }

    static var limitedAccessMessage: String {
        NSLocalizedString("picker.access.limited.message", value: "You've given HalloApp access to a selected number of photos and videos.", comment: "Message shown only limited access to media.")
    }

    static var limitedAccessButton: String {
        NSLocalizedString("picker.media.limit.button", value: "Update", comment: "Button shown to update limited access to media.")
    }

    static var limitedAccessUpdateSelection: String {
        NSLocalizedString("picker.media.limit.updateSelection", value: "Update image & video selection", comment: "An option to update limited access.")
    }

    static var limitedAccessChangeSettings: String {
        NSLocalizedString("picker.media.limit.settings", value: "Change settings", comment: "An option to update limited access.")
    }

    static var mediaLimitTitle: String {
        NSLocalizedString("picker.media.limit.title", value: "Maximum items selected", comment: "Alert title in media picker when selecting over limit.")
    }

    static func mediaLimitMessage(_ maxNumberOfPhotos: Int) -> String {
        let format = NSLocalizedString("picker.media.n.limit", comment: "Message in media picker when selecting over limit.")
        return String.localizedStringWithFormat(format, maxNumberOfPhotos)
    }

    static var mediaFailTitle: String {
        NSLocalizedString("picker.media.fail.title", value: "Failed to load media", comment: "Alert title in media picker when unable to load media file.")
    }

    static var mediaFailMessage: String {
        NSLocalizedString("picker.media.fail.message", value: "Please try again or select different photo or video.", comment: "Alert message in media picker when unable to load media file.")
    }

    static var last24Hours: String {
        NSLocalizedString("picker.last.24.hours.title",
                   value: "Last 24 Hours",
                 comment: "Title for a screen that displays items from the last 24 hours.")
    }
}

enum MediaPickerFilter {
    case all, image, video
}

fileprivate enum MediaPickerMode: Int {
    case  day, dayLarge, month
}

fileprivate enum TransitionState {
    case ready, inprogress, finishing
}

struct MediaPickerConfig {
    var destination: ShareDestination?
    var filter: MediaPickerFilter = .all
    var allowsMultipleSelection = true
    var isCameraEnabled = false
    var onlyRecentItems = false
    var maxNumberOfItems = ServerProperties.maxPostMediaItems

    static func config(with destination: ShareDestination) -> MediaPickerConfig {
        switch destination {
        case .feed:
            return .feed
        case .group:
            return .group(destination: destination)
        case .user:
            return .chat(destination: destination)
        }
    }

    static var feed: MediaPickerConfig {
        MediaPickerConfig(destination: .feed(.all), filter: .all, allowsMultipleSelection: true, isCameraEnabled: true)
    }

    static func group(destination: ShareDestination) -> MediaPickerConfig {
        MediaPickerConfig(destination: destination, filter: .all, allowsMultipleSelection: true, isCameraEnabled: true)
    }

    static func chat(destination: ShareDestination) -> MediaPickerConfig {
        MediaPickerConfig(destination: destination, filter: .all, allowsMultipleSelection: true, isCameraEnabled: true, maxNumberOfItems: ServerProperties.maxChatMediaItems)
    }

    static var comments: MediaPickerConfig {
        MediaPickerConfig(destination: nil, filter: .all, allowsMultipleSelection: false, isCameraEnabled: true)
    }

    static var moment: MediaPickerConfig {
        let onlyRecentItems: Bool
        // Allow simulators to post moments from any picture
#if targetEnvironment(simulator)
        onlyRecentItems = false
#else
        onlyRecentItems = true
#endif
        return MediaPickerConfig(destination: nil, filter: .image, allowsMultipleSelection: false, isCameraEnabled: false, onlyRecentItems: onlyRecentItems)
    }

    static var image: MediaPickerConfig {
        MediaPickerConfig(destination: nil, filter: .image, allowsMultipleSelection: false, isCameraEnabled: true)
    }

    static var avatar: MediaPickerConfig {
        MediaPickerConfig(destination: nil, filter: .image, allowsMultipleSelection: false, isCameraEnabled: true, maxNumberOfItems: 1)
    }

    static var more: MediaPickerConfig {
        MediaPickerConfig(destination: nil,filter: .all, allowsMultipleSelection: true, isCameraEnabled: true)
    }
}

typealias MediaPickerViewControllerCallback = (MediaPickerViewController, ShareDestination?, [PendingMedia], Bool) -> Void

class MediaPickerViewController: UIViewController {

    private struct UserDefaultsKey {
        static let MediaPickerMode = "MediaPickerMode"
    }

    private var mode: MediaPickerMode
    private var selected = [PendingMedia]()
    private var config: MediaPickerConfig
    private let didFinish: MediaPickerViewControllerCallback
    private var assets: PHFetchResult<PHAsset>?
    private var transitionLayout: UICollectionViewTransitionLayout?
    private var initialTransitionVelocity: CGFloat = 0
    private var transitionState: TransitionState = .ready
    private var preview: MediaPickerPreview?
    private var updatingSnapshot = false
    private var nextInProgress = false
    private var highlightedAssetCollection: PHAssetCollection?
    private var mediaAssetInfo: AssetInfoMap?

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: view.frame, collectionViewLayout: makeLayout())
        collectionView.delegate = self
        collectionView.backgroundColor = .feedBackground
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.allowsMultipleSelection = true
        collectionView.register(AssetViewCell.self, forCellWithReuseIdentifier: AssetViewCell.reuseIdentifier)
        collectionView.dataSource = self
        collectionView.alwaysBounceVertical = true

        return collectionView
    }()

    private lazy var nextButton: UIButton = {
        var nextButtonConfiguration = UIButton.Configuration.filled()
        nextButtonConfiguration.baseBackgroundColor = .lavaOrange
        nextButtonConfiguration.baseForegroundColor = .white
        nextButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: -1.5, leading: 32, bottom: 0, trailing: 38)
        nextButtonConfiguration.cornerStyle = .capsule
        nextButtonConfiguration.imagePadding = 12
        nextButtonConfiguration.imagePlacement = .trailing
        nextButtonConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        nextButtonConfiguration.titleAlignment = .leading
        nextButtonConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributeContainer in
            var updatedAttributeContainer = attributeContainer
            updatedAttributeContainer.font = .systemFont(ofSize: 17, weight: .semibold)
            updatedAttributeContainer.kern = 0.5
            updatedAttributeContainer.foregroundColor = .white
            return updatedAttributeContainer
        }

        let button = UIButton(type: .system)
        button.configuration = nextButtonConfiguration
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "chevron.forward"), for: .normal)
        button.setTitle(Localizations.buttonNext, for: .normal)

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 44),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
        ])

        button.addTarget(self, action: #selector(nextAction), for: .touchUpInside)

        return button
    }()

    private lazy var albumsButton: UIButton = {
        var albumsButtonBackgroundConfiguration = UIBackgroundConfiguration.clear()
        albumsButtonBackgroundConfiguration.visualEffect = UIBlurEffect(style: .systemMaterial)

        var albumsButtonConfiguration = UIButton.Configuration.filled()
        albumsButtonConfiguration.background = albumsButtonBackgroundConfiguration
        albumsButtonConfiguration.baseBackgroundColor = .primaryWhiteBlack.withAlphaComponent(0.5)
        albumsButtonConfiguration.baseForegroundColor = .primaryBlackWhite
        albumsButtonConfiguration.cornerStyle = .capsule
        albumsButtonConfiguration.imagePlacement = .trailing
        albumsButtonConfiguration.imagePadding = 8
        albumsButtonConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        albumsButtonConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributeContainer in
            var updatedAttributes = attributeContainer
            updatedAttributes.font = .systemFont(ofSize: 14, weight: .medium)
            return updatedAttributes
        }

        let button = UIButton(type: .system)
        button.configuration = albumsButtonConfiguration
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.5
        button.layer.shadowRadius = 10
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.addTarget(self, action: #selector(openAlbumsAction), for: .touchUpInside)

        return button
    }()

    private lazy var actionsContainerView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .feedBackground
        container.addSubview(nextButton)
        container.addSubview(cameraButton)

        cameraButton.isHidden = !config.isCameraEnabled

        NSLayoutConstraint.activate([
            nextButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            nextButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            cameraButton.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor),
            cameraButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -40),
        ])

        return container
    }()

    private lazy var limitedAccessBubble: UIView = {
        let bubble = UIView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = .NUX
        bubble.layer.cornerRadius = 10
        bubble.layer.shadowColor = UIColor.black.cgColor
        bubble.layer.shadowOpacity = 0.25
        bubble.layer.shadowRadius = 4
        bubble.layer.shadowOffset = .init(width: 0, height: 4)
        bubble.isHidden = true

        let close = UIButton(type: .system)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)), for: .normal)
        close.tintColor = UIColor.white
        close.alpha = 0.7
        close.addTarget(self, action: #selector(closeLimitedAccessBuble), for: .touchUpInside)
        bubble.addSubview(close)

        let msg = UILabel()
        msg.translatesAutoresizingMaskIntoConstraints = false
        msg.text = Localizations.limitedAccessMessage
        msg.textColor = UIColor.white
        msg.numberOfLines = 0
        bubble.addSubview(msg)

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(Localizations.limitedAccessButton, for: .normal)
        button.tintColor = UIColor.white
        button.alpha = 0.7
        button.addTarget(self, action: #selector(askForLimitedAccessUpdate), for: .touchUpInside)
        bubble.addSubview(button)

        NSLayoutConstraint.activate([
            close.widthAnchor.constraint(equalToConstant: 13),
            close.heightAnchor.constraint(equalToConstant: 13),
            close.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            close.rightAnchor.constraint(equalTo: bubble.rightAnchor, constant: -8),
            msg.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 4),
            msg.leftAnchor.constraint(equalTo: bubble.leftAnchor, constant: 20),
            msg.rightAnchor.constraint(equalTo: bubble.rightAnchor, constant: -20),
            button.topAnchor.constraint(equalTo: msg.bottomAnchor),
            button.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            button.rightAnchor.constraint(equalTo: bubble.rightAnchor, constant: -20),
        ])

        return bubble
    }()

    private lazy var cameraButton: UIButton = {
        let imageConfig = UIImage.SymbolConfiguration(pointSize: 44, weight: .bold)
        let image = UIImage(systemName: "camera.circle.fill", withConfiguration: imageConfig)?
                    .withTintColor(.primaryBlue, renderingMode: .alwaysOriginal)

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(image, for: .normal)
        button.addTarget(self, action: #selector(cameraAction), for: .touchUpInside)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])

        return button
    }()

    private lazy var debugButtonItem: UIBarButtonItem = {
        let imageConfig = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(systemName: "list.clipboard", withConfiguration: imageConfig)
        return  UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(toggleDebugInfo))
    }()

    private lazy var backButtonItem: UIBarButtonItem = {
        let imageConfig = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(systemName: "chevron.down", withConfiguration: imageConfig)?
                    .withTintColor(.primaryBlue, renderingMode: .alwaysOriginal)

        return  UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(cancelAction))
    }()

    private var isAnyCallOngoingCancellable: AnyCancellable?

    init(config: MediaPickerConfig,
         selected: [PendingMedia] = [],
         highlightedAssetCollection: PHAssetCollection? = nil,
         mediaAssetInfo: AssetInfoMap? = nil,
         didFinish: @escaping MediaPickerViewControllerCallback) {
        self.config = config
        self.selected.append(contentsOf: selected)
        self.highlightedAssetCollection = highlightedAssetCollection
        self.mediaAssetInfo = mediaAssetInfo
        self.didFinish = didFinish

        let modeRawValue = MainAppContext.shared.userDefaults.integer(forKey: UserDefaultsKey.MediaPickerMode)
        mode = MediaPickerMode(rawValue: modeRawValue) ?? .day

        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Use init(didFinish:)")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .feedBackground

        view.addSubview(collectionView)
        view.addSubview(albumsButton)
        view.addSubview(actionsContainerView)
        view.addSubview(limitedAccessBubble)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: actionsContainerView.topAnchor),
            actionsContainerView.heightAnchor.constraint(equalToConstant: 90),
            actionsContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            actionsContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionsContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            limitedAccessBubble.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 20),
            limitedAccessBubble.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -20),
            limitedAccessBubble.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            albumsButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            albumsButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
        ])


        navigationItem.leftBarButtonItem = backButtonItem
        if let mediaAssetInfo, !mediaAssetInfo.isEmpty, ServerProperties.isInternalUserOrDebugBuild {
            navigationItem.rightBarButtonItem = debugButtonItem
        }

        title = config.onlyRecentItems ? Localizations.last24Hours : Localizations.fabAccessibilityPhotoLibrary
        albumsButton.isHidden = config.onlyRecentItems

        updateNavigation()
        albumsButton.setTitle("", for: .normal)

        setupZoom()
        setupPreviews()

        PHPhotoLibrary.shared().register(self)
        fetchAssets(album: highlightedAssetCollection)

        isAnyCallOngoingCancellable = MainAppContext.shared.callManager.isAnyCallOngoing.sink { [weak self] activeCall in
            let isVideoCallOngoing = activeCall?.isVideoCall ?? false
            self?.cameraButton.isEnabled = !isVideoCallOngoing
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        albumsButton.layer.shadowPath = UIBezierPath(roundedRect: albumsButton.bounds,
                                                     cornerRadius: min(albumsButton.bounds.width, albumsButton.bounds.height) * 0.5).cgPath
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if navigationController?.isNavigationBarHidden == true {
            navigationController?.isNavigationBarHidden = false
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard let navigationController = navigationController else { return }

        // iOS will leak this view controller if we access a full screen
        // navigation controller's presentation controller: http://www.openradar.me/FB7621238

        let isFullscreen = navigationController.view.bounds == UIScreen.main.bounds
        if !isFullscreen {
            navigationController.presentationController?.delegate = self
        }

        if let highlightedAssetCollection, let mediaAssetInfo {
            let highlightedAssetIDCount = PHAsset.fetchAssets(in: highlightedAssetCollection, options: nil).count
            let rankedAssetIDCount = mediaAssetInfo.filter { (_, mediaAssetInfo) in mediaAssetInfo.isSelected }.count

            Analytics.openScreen(.postComposerPhotoSelector, properties: [
                .numPhotoSuggestions: highlightedAssetIDCount,
                .numRankedPhotos: rankedAssetIDCount,
            ])
        }
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    private func fetchAssets(album: PHAssetCollection? = nil) {
        switch (PhotoPermissionsHelper.authorizationStatus(for: .readWrite)) {
        case .notDetermined:
            PhotoPermissionsHelper.requestAuthorization(for: .readWrite) { _ in
                DispatchQueue.main.async {
                    self.fetchAssets(album: album)
                }
            }
            return
        case .denied, .restricted:
            let alert = UIAlertController(title: Localizations.photoAccessDeniedTitle, message: Localizations.photoAccessDeniedMessage, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Localizations.photoAccessDeniedSettings, style: .default, handler: { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }))
            alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default))
            self.present(alert, animated: true)
            return
        default:
            break
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let recent = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil).firstObject
            let isHighlightedAssetCollection = album != nil && album === highlightedAssetCollection

            let assets: PHFetchResult<PHAsset>
            let options = PHFetchOptions()

            if let album = album ?? recent {
                switch self.config.filter {
                case .all:
                    options.predicate = self.makeFetchPredicates(for: nil)
                case .image:
                    options.predicate = self.makeFetchPredicates(for: .image)
                case .video:
                    options.predicate = self.makeFetchPredicates(for: .video)
                }

                assets = PHAsset.fetchAssets(in: album, options: options)
            } else {
                options.predicate = self.makeFetchPredicates(for: nil)
                switch self.config.filter {
                case .all:
                    assets = PHAsset.fetchAssets(with: options)
                case .image:
                    assets = PHAsset.fetchAssets(with: .image, options: options)
                case .video:
                    assets = PHAsset.fetchAssets(with: .video, options: options)
                }
            }
            
            DispatchQueue.main.async {
                self.assets = assets
                if isHighlightedAssetCollection {
                    // reset to large view for the highlighted asset collection
                    self.mode = .dayLarge
                }
                self.collectionView.reloadData()
                if self.selected.isEmpty {
                    self.scrollToBottom()
                } else {
                    self.scrollToFirstSelectedItem()
                }
                self.updateNavigation()
                self.albumsButton.setTitle((album ?? recent)?.localizedTitle ?? "", for: .normal)
                self.showLimitedAccessBubbleIfNecessary()
            }
        }
    }

    private func makeFetchPredicates(for mediaType: PHAssetMediaType?) -> NSPredicate {
        var predicates = [NSPredicate]()
        if let mediaType = mediaType {
            predicates.append(NSPredicate(format: "mediaType == %i", mediaType.rawValue))
        }

        if config.onlyRecentItems, let date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
            predicates.append(NSPredicate(format: "creationDate >= %@ ", date as NSDate))
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    func showLimitedAccessBubbleIfNecessary() {
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited {
            limitedAccessBubble.isHidden = false
        } else {
            limitedAccessBubble.isHidden = true
        }
    }
    

    public func reset(destination: ShareDestination?, selected: [PendingMedia]) {
        self.selected.removeAll()
        self.selected.append(contentsOf: selected)
        
        for cell in collectionView.visibleCells {
            guard let cell = cell as? AssetViewCell else { continue }
            self.prepareCell(cell)
        }

        config.destination = destination

        updateNavigation()
    }
    
    private func updateNavigation() {
        nextButton.isHidden = !config.allowsMultipleSelection
        nextButton.isEnabled = selected.count > 0

        if config.isCameraEnabled {
            let isVideoCallOngoing = MainAppContext.shared.callManager.activeCall?.isVideoCall ?? false
            cameraButton.isEnabled = !isVideoCallOngoing
        }
    }

    private func prepareCell(_ cell: AssetViewCell) {
        let assetInfo = showDebugInfo ? mediaAssetInfo : nil
        cell.prepare(config: config, mode: mode, selection: selected, highlightedAssetCollection: highlightedAssetCollection, assetInfo: assetInfo)
    }

    private var showDebugInfo = false
    @objc private func toggleDebugInfo() {
        showDebugInfo = !showDebugInfo
        collectionView.reloadData()
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
                    self.prepareCell(cell)
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
                MainAppContext.shared.userDefaults.set(mode.rawValue, forKey: UserDefaultsKey.MediaPickerMode)
            }
        }
    }
    
    private func setupPreviews() {
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(onDisplayPreview(sender:)))
        collectionView.addGestureRecognizer(longPressRecognizer)
    }
    
    @objc func onDisplayPreview(sender: UILongPressGestureRecognizer) {
        if sender.state == .began && preview == nil {
            let location = sender.location(in: collectionView)

            guard let indexPath = collectionView.indexPathForItem(at: location) else { return }
            guard let asset = assets?[indexPath.row] else { return }
            guard let window = view.window else { return }

            preview = MediaPickerPreview(asset: asset, parent: window)
            preview?.show()
        } else if sender.state == .ended || sender.state == .cancelled {
            preview?.hide()
            preview = nil
        }
    }
    
    private func makeLayout() -> UICollectionViewFlowLayout {
        let layout = MediaPickerFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        
        return layout
    }

    @objc private func cameraAction() {
        let controller = CameraViewController(
            configuration: .init(showCancelButton: false),
            didFinish: { [weak self] in self?.dismiss(animated: true) },
            didPickImage: { [weak self] image in
                guard let self = self else { return }
                self.dismiss(animated: true)

                let media = PendingMedia(type: .image)
                media.image = image.correctlyOrientedImage()

                self.selected.append(media)
                self.nextAction()
            },
            didPickVideo: { [weak self] url in
                guard let self = self else { return }
                self.dismiss(animated: true)

                let media = PendingMedia(type: .video)
                media.originalVideoURL = url
                media.fileURL = url

                self.selected.append(media)
                self.nextAction()
            }
        )

        self.present(controller, animated: true)
    }
    
    @objc private func nextAction() {
        guard selected.count > 0 else { return }
        guard !nextInProgress else { return }
        nextInProgress = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            for i in 0..<self.selected.count {
                let media = self.selected[i]
                media.order = i

                guard media.asset != nil && !media.ready.value else { continue }
                
                switch media.type {
                case .image:
                    self.request(image: media)
                case .video:
                    self.request(video: media)
                case .audio, .document:
                    continue
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                self.didFinish(self, self.config.destination, self.selected, false)
                self.nextInProgress = false
            }
        }
    }

    private func request(image media: PendingMedia, retriesLeft: Int = 3) {
        guard let asset = media.asset else { return }

        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.progressHandler = { progress, error, stop, _ in
            DDLogInfo("MediaPickerViewController/request/image/progress [\(progress)] asset=[\(asset)]")
            media.progress.send(Float(progress))

            if let error = error {
                DDLogError("MediaPickerViewController/request/image error=[\(error)] asset=[\(asset)]")
            }
        }

        PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .default, options: options) { image, _ in
            guard let image = image else {
                if retriesLeft > 0 {
                    DDLogWarn("MediaPickerViewController/request/image retry \(retriesLeft) asset=[\(asset)]")

                    let delay = Double((4 - retriesLeft) * 2)
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.request(image: media, retriesLeft: retriesLeft - 1)
                    }
                } else {
                    DDLogWarn("MediaPickerViewController/request/image Unable to fetch image asset=[\(asset)]")
                    media.error.send(PendingMediaError.loadingError)
                }

                return
            }

            media.image = image
        }
    }

    private func request(video media: PendingMedia, retriesLeft: Int = 3) {
        guard let asset = media.asset else { return }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.progressHandler = { progress, error, stop, _ in
            DDLogInfo("MediaPickerViewController/request/video/progress [\(progress)] asset=[\(asset)]")

            if progress < 1.0 {
                media.progress.send(Float(progress))
            }

            if let error = error {
                DDLogError("MediaPickerViewController/request/video error=[\(error)] asset=[\(asset)]")
            }
        }

        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avasset, _, _ in
            // Sometimes NextLevelSessionExporterError/AVAssetReader is unable to process videos if they are not copied first
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString, isDirectory: false)
                .appendingPathExtension("mp4")

            if let video = avasset as? AVURLAsset {
                do {
                    try FileManager.default.copyItem(at: video.url, to: url)
                } catch {
                    DDLogError("MediaPickerViewController/request/video/copy/error [\(error)] url=[\(video.url.description)] tmp=[\(url.description)]")
                    return media.error.send(PendingMediaError.loadingError)
                }

                DDLogInfo("MediaPickerViewController/request/video/copy/ready  Temporary url: [\(url.description)] url=[\(video.url.description)] original order=[\(media.order)]")

                media.originalVideoURL = url
                media.fileURL = url
            } else if let composition = avasset as? AVComposition {
                let slowMotion = (asset.mediaSubtypes.rawValue & PHAssetMediaSubtype.videoHighFrameRate.rawValue) != 0

                VideoUtils.save(composition: composition, to: url, slowMotion: slowMotion) { result in
                    DispatchQueue.main.async {
                        switch(result) {
                        case .success(let url):
                            DDLogInfo("MediaPickerViewController/request/video/copy/ready  Temporary url: [\(url.description)] order=[\(media.order)]")
                            media.originalVideoURL = url
                            media.fileURL = url
                        case .failure(let error):
                            DDLogError("MediaPickerViewController/request/video/copy/error Failed to save [\(error)] tmp=[\(url.description)]")
                            media.error.send(PendingMediaError.loadingError)
                        }
                    }
                }
            } else {
                if retriesLeft > 0 {
                    DDLogWarn("MediaPickerViewController/request/video retry \(retriesLeft) asset=[\(asset)]")

                    let delay = Double((4 - retriesLeft) * 2)
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.request(video: media, retriesLeft: retriesLeft - 1)
                    }
                } else {
                    if let avasset = avasset {
                        DDLogWarn("MediaPickerViewController/request/video Unknown video type \(String(describing: type(of: avasset)))")
                    } else {
                        DDLogWarn("MediaPickerViewController/request/video Missing video")
                    }

                    media.error.send(PendingMediaError.loadingError)
                }
            }
        }
    }

    @objc private func cancelAction() {
        didFinish(self, config.destination, [], true)
    }

    @objc private func openAlbumsAction() {
        let controller = MediaAlbumsViewController(highlightedAssetCollection: highlightedAssetCollection) {[weak self] controller, album, cancel in
            guard let self = self else { return }
            DDLogInfo("openAlbumsAction \(album?.description ?? "missing-album")")
            
            controller.dismiss(animated: true)
            
            if !cancel {
                self.fetchAssets(album: album)
            }
        }

        present(controller, animated: true)
    }

    @objc private func closeLimitedAccessBuble() {
        limitedAccessBubble.isHidden = true
    }

    @objc private func askForLimitedAccessUpdate() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: Localizations.limitedAccessUpdateSelection, style: .default, handler: { _ in
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self)
        }))
        sheet.addAction(UIAlertAction(title: Localizations.limitedAccessChangeSettings, style: .default, handler: { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }))
        sheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))

        self.present(sheet, animated: true)
    }

    private func scrollToBottom(_ animated: Bool = false) {
        guard let count = assets?.count, count > 0 else { return }
        collectionView.scrollToItem(at: IndexPath(row: count - 1, section: 0), at: .bottom, animated: animated)
    }

    private func scrollToFirstSelectedItem(animated: Bool = false) {
        guard let assets, !selected.isEmpty else {
            return
        }

        let selectedAssetIdentifiers = Set(selected.compactMap(\.asset?.localIdentifier))
        var initialAssetIndex: Int?
        for idx in 0..<assets.count {
            if selectedAssetIdentifiers.contains(assets[idx].localIdentifier) {
                initialAssetIndex = idx
                break
            }
        }

        if let initialAssetIndex {
            collectionView.scrollToItem(at: IndexPath(item: initialAssetIndex, section: 0), at: .top, animated: false)
        }
    }
}

// MARK: UICollectionViewDelegate
extension MediaPickerViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let cell = collectionView.cellForItem(at: indexPath) as? AssetViewCell else { return false }
        guard let asset = cell.asset else { return false }

        if selected.contains(where: { $0.asset == asset }) {
            deselect(collectionView, cell: cell, asset: asset)
        } else if selected.count >= config.maxNumberOfItems {
            let alert = UIAlertController(title: Localizations.mediaLimitTitle,
                                          message: Localizations.mediaLimitMessage(config.maxNumberOfItems),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default))
            self.present(alert, animated: true)
        } else {
            select(collectionView, cell: cell, asset: asset)
        }

        return false
    }

    private func select(_ collectionView: UICollectionView, cell: AssetViewCell, asset: PHAsset) {
        guard let media = PendingMedia(asset: asset) else { return }

        if !config.allowsMultipleSelection {
            selected.append(media)
            nextAction()
            return
        }

        selected.append(media)
        updateNavigation()

        UIView.animateKeyframes(withDuration: 0.3, delay: 0, options: [], animations: {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.7, animations: {
                cell.image.layer.cornerRadius = 20
                cell.image.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
                cell.prepareIndicator(config: self.config, selection: self.selected)
            })

            UIView.addKeyframe(withRelativeStartTime: 0.7, relativeDuration: 0.3, animations: {
                cell.image.transform = CGAffineTransform.identity
            })
        }, completion: { _ in
            self.prepareCell(cell)
        })
    }

    private func deselect(_ collectionView: UICollectionView, cell: AssetViewCell, asset: PHAsset) {
        guard let idx = self.selected.firstIndex(where: { $0.asset == asset }) else { return }
        selected.remove(at: idx)
        updateNavigation()

        UIView.animateKeyframes(withDuration: 0.3, delay: 0, options: [], animations: {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.7, animations: {
                cell.image.layer.cornerRadius = 0
                cell.image.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                cell.prepareIndicator(config: self.config, selection: self.selected)
            })

            UIView.addKeyframe(withRelativeStartTime: 0.7, relativeDuration: 0.3, animations: {
                cell.image.transform = CGAffineTransform.identity
            })
        }, completion: { _ in
            for cell in collectionView.visibleCells {
                guard let cell = cell as? AssetViewCell else { continue }
                self.prepareCell(cell)
            }
        })
    }
}

// MARK: UICollectionViewDelegateFlowLayout
extension MediaPickerViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        switch mode {
        case .month:
            let size = (UIScreen.main.bounds.width - 0.1) * 0.2
            return CGSize(width: size, height: size)
        case .day:
            let size = UIScreen.main.bounds.width * 0.3333
            return CGSize(width: size, height: size)
        case .dayLarge where (indexPath.row % 5) < 2:
            let size = UIScreen.main.bounds.width * 0.5
            return CGSize(width: size, height: size * 1.27)
        case .dayLarge:
            let size = UIScreen.main.bounds.width * 0.3333
            return CGSize(width: size, height: size * 1.42)
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 0
    }
}

// MARK: UICollectionViewDataSource
extension MediaPickerViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return assets?.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AssetViewCell.reuseIdentifier, for: indexPath)

        if let cell = cell as? AssetViewCell, let asset = assets?[indexPath.row] {
            cell.asset = asset
            cell.indexPath = indexPath

            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 256, height: 256), contentMode: .aspectFill, options: options) { [weak self] image, _ in
                guard let self = self else { return }
                guard cell.asset?.localIdentifier == asset.localIdentifier else { return }
                cell.image.image = image
                self.prepareCell(cell)
            }
        }

        return cell
    }
}

// MARK: PHPhotoLibraryChangeObserver
extension MediaPickerViewController: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let assets = self.assets else { return }
        guard let details = changeInstance.changeDetails(for: assets) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.assets = details.fetchResultAfterChanges
            self.collectionView.reloadData()
        }
    }
}

// MARK: UIAdaptivePresentationControllerDelegate
extension MediaPickerViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        cancelAction()
    }
}

extension MediaPickerViewController {

    private class MediaPickerFlowLayout: UICollectionViewFlowLayout {

        override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
            guard let collectionView else {
                return proposedContentOffset
            }

            var contentOffset = proposedContentOffset
            // keep it in bounds
            // fixes issue with transition scrolling to invalid contentOffset
            contentOffset.y = min(contentOffset.y, collectionViewContentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom)
            contentOffset.y = max(contentOffset.y, -collectionView.adjustedContentInset.top)
            return contentOffset
        }
    }
}

fileprivate class AssetViewCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: AssetViewCell.self)
    }

    var asset: PHAsset?
    var indexPath: IndexPath?

    private var activeConstraints = [NSLayoutConstraint]()

    lazy var indicatorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = UIFont.gothamFont(ofFixedSize: 19, weight: .medium)
        label.textColor = .white

        return label
    }()

    lazy var indicator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 15
        view.layer.borderWidth = 3
        view.layer.masksToBounds = true

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 30),
            view.heightAnchor.constraint(equalToConstant: 30),
        ])

        view.addSubview(indicatorLabel)

        NSLayoutConstraint.activate([
            indicatorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            indicatorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 1),
        ])

        return view
    }()
    
    lazy var image: UIImageView = {
        let image = UIImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        
        return image
    }()

    lazy var debugLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .right
        label.backgroundColor = .black.withAlphaComponent(0.3)
        label.textColor = .white
        label.font = .systemFont(ofSize: 12)
        label.numberOfLines = 0
        return label
    }()

    lazy var duration: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .right
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white

        return label
    }()

    lazy var favorite: UIImageView = {
        let image = UIImage(systemName: "heart.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold))!.withTintColor(.init(white: 1.0, alpha: 0.95), renderingMode: .alwaysOriginal)
        let favorite = UIImageView(image: image)
        favorite.translatesAutoresizingMaskIntoConstraints = false
        favorite.contentMode = .scaleAspectFit
        favorite.layer.shadowColor = UIColor.black.cgColor
        favorite.layer.shadowRadius = 4
        favorite.layer.shadowOpacity = 0.25
        favorite.layer.shadowPath = UIBezierPath(ovalIn: favorite.bounds).cgPath

        return favorite
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.addSubview(image)
        contentView.addSubview(indicator)
        contentView.addSubview(debugLabel)
        contentView.addSubview(duration)
        contentView.addSubview(favorite)
        contentView.clipsToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func calculateSpacing(mode: MediaPickerMode) -> (CGFloat, CGFloat, CGFloat) {
        guard let indexPath = indexPath else { return (0, 0, 0) }
        
        let spacing = CGFloat(1)
        
        var column: CGFloat
        var columnCount: CGFloat
        
        switch mode {
        case .month:
            column = CGFloat(indexPath.row % 5)
            columnCount = 5
        case .day:
            column = CGFloat(indexPath.row % 3)
            columnCount = 3
        case .dayLarge:
            let indexInBlock = indexPath.row % 5
            
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
    
    func prepare(config: MediaPickerConfig, mode: MediaPickerMode, selection: [PendingMedia], highlightedAssetCollection: PHAssetCollection?, assetInfo: AssetInfoMap? = nil) {
        let (spacingBottom, spacingLead, spacingTrail) = calculateSpacing(mode: mode)
        
        NSLayoutConstraint.deactivate(activeConstraints)
        
        activeConstraints = [
            image.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacingLead),
            image.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacingTrail),
            image.topAnchor.constraint(equalTo: contentView.topAnchor),
            image.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -spacingBottom),
            indicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            indicator.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            debugLabel.rightAnchor.constraint(equalTo: duration.rightAnchor),
            debugLabel.bottomAnchor.constraint(equalTo: duration.topAnchor, constant: -6),
            duration.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            duration.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -6),
            favorite.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            favorite.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 6),
            favorite.widthAnchor.constraint(equalToConstant: 20),
            favorite.heightAnchor.constraint(equalToConstant: 20),
        ]
        
        NSLayoutConstraint.activate(activeConstraints)

        let selected: Bool

        if let asset = asset, selection.contains(where: { $0.asset == asset }) {
            selected = true
            image.layer.cornerRadius = 20
        } else {
            selected = false
            image.layer.cornerRadius = 0
        }

        duration.isHidden = true
        if asset?.mediaType == .video, let interval = asset?.duration {
            duration.isHidden = false
            duration.text = interval.formatted
        }

        debugLabel.text = (asset?.localIdentifier).flatMap { assetInfo?[$0]?.debugInfo }

        favorite.isHidden = asset?.isFavorite != true

        prepareIndicator(config: config, selection: selection)

        setNeedsLayout()

        if let highlightedAssetCollection {
            let highlighted: Bool
            if let asset, PHAsset.fetchAssets(in: highlightedAssetCollection, options: nil).contains(asset) {
                highlighted = true
            } else {
                highlighted = false
            }
            contentView.alpha = selected || highlighted ? 1.0 : 0.5
        }
    }

    func prepareIndicator(config: MediaPickerConfig, selection: [PendingMedia]) {
        if let asset = asset, let idx = selection.filter({ $0.asset != nil }).firstIndex(where: { $0.asset == asset }) {
            indicator.layer.borderColor = UIColor.lavaOrange.cgColor
            indicator.backgroundColor = .lavaOrange

            let text = "\(1 + idx)"
            if !indicatorLabel.isHidden && indicatorLabel.text != text {
                UIView.transition(with: indicatorLabel,
                                  duration: 0.25,
                                  options: .transitionCrossDissolve,
                                  animations: { [weak self] in
                    self?.indicatorLabel.text = text
                }, completion: nil)
            } else {
                indicatorLabel.text = text
                indicatorLabel.isHidden = false
            }
        } else {
            indicator.layer.borderColor = CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.9)
            indicator.backgroundColor = .clear
            indicatorLabel.isHidden = true
        }

        indicator.isHidden = !config.allowsMultipleSelection
    }
}
