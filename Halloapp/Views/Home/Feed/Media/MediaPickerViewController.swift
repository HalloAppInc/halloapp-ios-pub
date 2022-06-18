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
    var destination: PostComposerDestination?
    var privacyListType: PrivacyListType?
    var filter: MediaPickerFilter = .all
    var allowsMultipleSelection = true
    var isCameraEnabled = false
    var maxNumberOfItems = ServerProperties.maxPostMediaItems

    static var feed: MediaPickerConfig {
        MediaPickerConfig(destination: .userFeed, privacyListType: .all, filter: .all, allowsMultipleSelection: true, isCameraEnabled: false)
    }

    static func group(id: GroupID) -> MediaPickerConfig {
        MediaPickerConfig(destination: .groupFeed(id), privacyListType: nil, filter: .all, allowsMultipleSelection: true, isCameraEnabled: false)
    }

    static func chat(id: UserID?) -> MediaPickerConfig {
        MediaPickerConfig(destination: .chat(id), privacyListType: nil, filter: .all, allowsMultipleSelection: true, isCameraEnabled: true, maxNumberOfItems: ServerProperties.maxChatMediaItems)
    }

    static var comments: MediaPickerConfig {
        MediaPickerConfig(destination: nil, privacyListType: nil, filter: .all, allowsMultipleSelection: false, isCameraEnabled: true)
    }

    static var moment: MediaPickerConfig {
        MediaPickerConfig(destination: nil, privacyListType: nil, filter: .all, allowsMultipleSelection: false, isCameraEnabled: false)
    }

    static var image: MediaPickerConfig {
        MediaPickerConfig(destination: nil, privacyListType: nil, filter: .image, allowsMultipleSelection: false, isCameraEnabled: true)
    }

    static var more: MediaPickerConfig {
        MediaPickerConfig(destination: nil, privacyListType: nil,filter: .all, allowsMultipleSelection: true, isCameraEnabled: false)
    }
}

typealias MediaPickerViewControllerCallback = (MediaPickerViewController, PostComposerDestination?, PrivacyListType?, [PendingMedia], Bool) -> Void

class MediaPickerViewController: UIViewController {

    private struct UserDefaultsKey {
        static let MediaPickerMode = "MediaPickerMode"
    }

    private var mode: MediaPickerMode
    private var selected = [PHAsset]()
    private var config: MediaPickerConfig
    private let didFinish: MediaPickerViewControllerCallback
    private var assets: PHFetchResult<PHAsset>?
    private var transitionLayout: UICollectionViewTransitionLayout?
    private var initialTransitionVelocity: CGFloat = 0
    private var transitionState: TransitionState = .ready
    private var preview: MediaPickerPreview?
    private var updatingSnapshot = false
    private var nextInProgress = false
    private var originalMedia: [PendingMedia] = []

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: view.frame, collectionViewLayout: makeLayout())
        collectionView.delegate = self
        collectionView.backgroundColor = .feedBackground
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.allowsMultipleSelection = true
        collectionView.register(AssetViewCell.self, forCellWithReuseIdentifier: AssetViewCell.reuseIdentifier)
        collectionView.contentInset = UIEdgeInsets(top: 80, left: 0, bottom: 80, right: 0)
        collectionView.dataSource = self

        return collectionView
    }()

    private lazy var nextButton: UIButton = {
        let attributedTitle = NSAttributedString(string: Localizations.buttonNext,
                                                 attributes: [.kern: 0.5, .foregroundColor: UIColor.white])
        let disabledAttributedTitle = NSAttributedString(string: Localizations.buttonNext,
                                                         attributes: [.kern: 0.5, .foregroundColor: UIColor.gray])

        class MediaPickerButton: UIButton {

            override init(frame: CGRect) {
                super.init(frame: frame)
                updateBackgrounds()
            }

            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            private func updateBackgrounds() {
                setBackgroundColor(.primaryBlue, for: .normal)
                setBackgroundColor(.label.withAlphaComponent(0.19), for: .disabled)
            }

            override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
                super.traitCollectionDidChange(previousTraitCollection)
                if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                    updateBackgrounds()
                }
            }
        }

        let button = MediaPickerButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        // Attributed strings do not respect button title colors
        button.setAttributedTitle(attributedTitle, for: .normal)
        button.setAttributedTitle(disabledAttributedTitle, for: .disabled)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        button.layer.cornerRadius = 22
        button.layer.masksToBounds = true
        button.contentEdgeInsets = UIEdgeInsets(top: -1.5, left: 8, bottom: 0, right: 8)

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 44),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
        ])

        button.addTarget(self, action: #selector(nextAction), for: .touchUpInside)

        return button
    }()

    private lazy var albumsButton: UIButton = {
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        let icon = UIImage(systemName: "chevron.down", withConfiguration: iconConfig)

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .gothamFont(ofFixedSize: 16, weight: .medium)
        button.setTitleColor(.label.withAlphaComponent(0.9), for: .normal)
        button.setImage(icon, for: .normal)
        
        let insets: UIEdgeInsets
        if case .rightToLeft = view.effectiveUserInterfaceLayoutDirection {
            // keep image on the right & tappable
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 0)
            button.semanticContentAttribute = .forceLeftToRight
        } else {
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
            button.semanticContentAttribute = .forceRightToLeft
        }
        
        button.addTarget(self, action: #selector(openAlbumsAction), for: .touchUpInside)
        return button
    }()

    private lazy var actionsContainerView: UIView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [albumsButton, spacer, nextButton])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .feedBackground
        container.addSubview(row)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 80),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
        ])

        return container
    }()

    private lazy var limitedAccessBubble: UIView = {
        let bubble = UIView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = .nux
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

    private var changeDestinationIconConstraint: NSLayoutConstraint?
    private lazy var changeDestinationIcon: UIImageView = {
        let iconImage = UIImage(named: "PrivacySettingMyContacts")?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        let icon = UIImageView(image: iconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit

        let iconConstraint = icon.widthAnchor.constraint(equalToConstant: 13)
        NSLayoutConstraint.activate([
            iconConstraint,
            icon.heightAnchor.constraint(equalTo: icon.widthAnchor),
        ])
        changeDestinationIconConstraint = iconConstraint

        return icon
    }()

    private lazy var changeDestinationLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)

        return label
    }()

    private lazy var changeDestinationButton: UIButton = {
        let arrowImage = UIImage(named: "ArrowDownSmall")?.withTintColor(.white, renderingMode: .alwaysOriginal)
        let arrow = UIImageView(image: arrowImage)
        arrow.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [changeDestinationIcon, changeDestinationLabel, arrow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.isUserInteractionEnabled = false

        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setBackgroundColor(.primaryBlue, for: .normal)
        button.layer.cornerRadius = 14
        button.layer.masksToBounds = true
        button.addTarget(self, action: #selector(changeDestinationAction), for: .touchUpInside)

        button.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.heightAnchor.constraint(equalToConstant: 28),
            stack.topAnchor.constraint(equalTo: button.topAnchor),
            stack.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -10),
        ])

        return button
    }()

    private lazy var changeDestinationRow: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(changeDestinationButton)

        NSLayoutConstraint.activate([
            changeDestinationButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            changeDestinationButton.heightAnchor.constraint(equalTo: view.heightAnchor),
        ])

        return view
    }()

    private lazy var backButton: UIButton = {
        let imageColor = UIColor.label.withAlphaComponent(0.9)
        let imageConfig = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(systemName: "xmark", withConfiguration: imageConfig)?.withTintColor(imageColor)

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(image, for: .normal)
        button.addTarget(self, action: #selector(cancelAction), for: .touchUpInside)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])

        return button
    }()

    private lazy var cameraButton: UIButton = {
        let imageColor = UIColor.label.withAlphaComponent(0.9)
        let imageConfig = UIImage.SymbolConfiguration(scale: .large)
        let image = UIImage(systemName: "camera.fill", withConfiguration: imageConfig)?.withTintColor(imageColor)

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

    private lazy var titleLabel: UILabel = {
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.textAlignment = .center
        title.font = .gothamFont(ofFixedSize: 15, weight: .medium)
        title.textColor = .label.withAlphaComponent(0.9)

        return title
    }()


    private var customNavigationContentTopConstraint: NSLayoutConstraint?
    private lazy var customNavigationBar: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .feedBackground

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let navigationRow = UIStackView(arrangedSubviews: [backButton, spacer, cameraButton])
        navigationRow.translatesAutoresizingMaskIntoConstraints = false
        navigationRow.axis = .horizontal
        navigationRow.alignment = .center
        navigationRow.distribution = .equalSpacing
        navigationRow.addSubview(titleLabel)

        let rowsView = UIStackView(arrangedSubviews: [navigationRow, changeDestinationRow])
        rowsView.translatesAutoresizingMaskIntoConstraints = false
        rowsView.axis = .vertical
        rowsView.alignment = .fill
        rowsView.spacing = -4

        container.addSubview(rowsView)

        NSLayoutConstraint.activate([
            navigationRow.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: navigationRow.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: navigationRow.centerYAnchor),
            rowsView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            rowsView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            rowsView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -9),
        ])

        customNavigationContentTopConstraint = rowsView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)

        return container
    }()

    private var isAnyCallOngoingCancellable: AnyCancellable?
    private var privacyCancellable: AnyCancellable?
    private var changeDestinationAvatarCancellable: AnyCancellable?
    
    init(config: MediaPickerConfig, selected: [PendingMedia] = [] , didFinish: @escaping MediaPickerViewControllerCallback) {
        self.config = config
        self.originalMedia.append(contentsOf: selected)
        self.selected.append(contentsOf: selected.filter { $0.asset != nil }.map { $0.asset! })
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
        view.addSubview(actionsContainerView)
        view.addSubview(limitedAccessBubble)
        view.addSubview(customNavigationBar)

        collectionView.constrain(to: view)

        NSLayoutConstraint.activate([
            actionsContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -80),
            actionsContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            actionsContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionsContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            limitedAccessBubble.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 20),
            limitedAccessBubble.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -20),
            limitedAccessBubble.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            customNavigationBar.topAnchor.constraint(equalTo: view.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        customNavigationContentTopConstraint?.isActive = true

        updateNavigation()
        albumsButton.setTitle("", for: .normal)

        if config.destination != nil {
            updateChangeDestinationBtn()

            privacyCancellable = MainAppContext.shared.privacySettings.objectWillChange.sink { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.updateChangeDestinationBtn()
                }
            }
        }

        setupZoom()
        setupPreviews()

        PHPhotoLibrary.shared().register(self)
        fetchAssets()

        isAnyCallOngoingCancellable = MainAppContext.shared.callManager.isAnyCallOngoing.sink { [weak self] activeCall in
            let isVideoCallOngoing = activeCall?.isVideoCall ?? false
            self?.cameraButton.isEnabled = !isVideoCallOngoing
        }

        //Show the favorites education modal only once to the user
        if !AppContext.shared.userDefaults.bool(forKey: "hasFavoritesModalBeenShown") {
            AppContext.shared.userDefaults.set(true, forKey: "hasFavoritesModalBeenShown")
            let favoritesVC = FavoritesInformationViewController() { privacyListType in
                self.config.privacyListType = privacyListType
                self.config.destination = .userFeed
            }
            self.present(favoritesVC, animated: true)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
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
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    private func fetchAssets(album: PHAssetCollection? = nil) {
        let status: PHAuthorizationStatus
        if #available(iOS 14, *) {
            status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        } else {
            status = PHPhotoLibrary.authorizationStatus()
        }

        switch(status) {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { status in
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

            let assets: PHFetchResult<PHAsset>
            if let album = album ?? recent {
                let options: PHFetchOptions?
                switch self.config.filter {
                case .all:
                    options = nil
                case .image:
                    options = PHFetchOptions()
                    options?.predicate = NSPredicate(format: "mediaType == %i", PHAssetMediaType.image.rawValue)
                case .video:
                    options = PHFetchOptions()
                    options?.predicate = NSPredicate(format: "mediaType == %i", PHAssetMediaType.video.rawValue)
                }

                assets = PHAsset.fetchAssets(in: album, options: options)
            } else {
                switch self.config.filter {
                case .all:
                    assets = PHAsset.fetchAssets(with: nil)
                case .image:
                    assets = PHAsset.fetchAssets(with: .image, options: nil)
                case .video:
                    assets = PHAsset.fetchAssets(with: .video, options: nil)
                }
            }
            
            DispatchQueue.main.async {
                self.assets = assets
                self.collectionView.reloadData()
                self.scrollToBottom()
                self.updateNavigation()
                self.albumsButton.setTitle((album ?? recent)?.localizedTitle ?? "", for: .normal)
                self.showLimitedAccessBubbleIfNecessary()
            }
        }
    }

    func showLimitedAccessBubbleIfNecessary() {
        if #available(iOS 14, *), PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited {
            limitedAccessBubble.isHidden = false
        } else {
            limitedAccessBubble.isHidden = true
        }
    }
    
    public func reset(destination: PostComposerDestination?, privacyListType: PrivacyListType?, selected: [PendingMedia]) {
        originalMedia.removeAll()
        originalMedia.append(contentsOf: selected)

        self.selected.removeAll()
        self.selected.append(contentsOf: selected.filter { $0.asset != nil }.map { $0.asset! })
        
        for cell in collectionView.visibleCells {
            guard let cell = cell as? AssetViewCell else { continue }
            cell.prepare(config: self.config, mode: self.mode, selection: self.selected)
        }

        config.privacyListType = privacyListType
        config.destination = destination

        updateNavigation()
        updateChangeDestinationBtn()
    }
    
    private func updateNavigation() {
        let backImageColor = UIColor.label.withAlphaComponent(0.9)
        let backImageConfig = UIImage.SymbolConfiguration(weight: .bold)
        let backImage = UIImage(systemName: selected.count > 0 ? "xmark" : "chevron.down", withConfiguration: backImageConfig)?.withTintColor(backImageColor)
        backButton.setImage(backImage, for: .normal)

        titleLabel.text = title

        nextButton.isHidden = !config.allowsMultipleSelection
        nextButton.isEnabled = selected.count > 0

        cameraButton.isHidden = !config.isCameraEnabled
        if config.isCameraEnabled {
            let isVideoCallOngoing = MainAppContext.shared.callManager.activeCall?.isVideoCall ?? false
            cameraButton.isEnabled = !isVideoCallOngoing
        }

        changeDestinationRow.isHidden = config.destination == nil
        if case .chat = config.destination {
            changeDestinationRow.isHidden = true
        }
    }

    private func updateChangeDestinationBtn() {
        guard let destination = config.destination else { return }

        changeDestinationIcon.isHidden = false
        changeDestinationIcon.layer.cornerRadius = 0
        changeDestinationIcon.layer.masksToBounds = false
        changeDestinationAvatarCancellable?.cancel()

        switch destination {
        case .userFeed:
            guard let privacy = config.privacyListType else { return }

            switch privacy {
            case .all:
                changeDestinationIcon.image = UIImage(named: "PrivacySettingMyContacts")?.withTintColor(.white, renderingMode: .alwaysOriginal)
                changeDestinationButton.setBackgroundColor(.primaryBlue, for: .normal)
            case .whitelist:
                changeDestinationIcon.image = UIImage(named: "PrivacySettingFavoritesInversed")
                changeDestinationButton.setBackgroundColor(.favoritesBg, for: .normal)
            default:
                changeDestinationIcon.image = UIImage(named: "settingsSettings")?.withTintColor(.white, renderingMode: .alwaysOriginal)
                changeDestinationButton.setBackgroundColor(.primaryBlue, for: .normal)
            }

            changeDestinationIconConstraint?.constant = 13

            changeDestinationLabel.text = PrivacyList.name(forPrivacyListType: privacy)
        case .groupFeed(let groupId):
            changeDestinationButton.setBackgroundColor(.primaryBlue, for: .normal)
            
            let avatarData = MainAppContext.shared.avatarStore.groupAvatarData(for: groupId)

            if let image = avatarData.image {
                changeDestinationIcon.image = image
                changeDestinationIcon.layer.cornerRadius = 6
                changeDestinationIcon.layer.masksToBounds = true
            } else {
                changeDestinationIcon.image = AvatarView.defaultGroupImage

                if !avatarData.isEmpty {
                    changeDestinationAvatarCancellable = avatarData.imageDidChange.sink { [weak self] image in
                        guard let self = self else { return }
                        guard let image = image else { return }
                        self.changeDestinationIcon.image = image
                    }

                    avatarData.loadImage(using: MainAppContext.shared.avatarStore)
                }
            }

            changeDestinationIconConstraint?.constant = 19

            if let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: MainAppContext.shared.chatData.viewContext) {
                changeDestinationLabel.text = group.name
            }
        case .chat:
            break
        }
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
                    cell.prepare(config: self.config, mode: self.mode, selection: self.selected)
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
        let layout = UICollectionViewFlowLayout()
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
                media.order = 1
                media.image = image.correctlyOrientedImage()

                self.didFinish(self, self.config.destination, self.config.privacyListType, [media], false)
            },
            didPickVideo: { [weak self] url in
                guard let self = self else { return }
                self.dismiss(animated: true)

                let media = PendingMedia(type: .video)
                media.order = 1
                media.originalVideoURL = url
                media.fileURL = url

                self.didFinish(self, self.config.destination, self.config.privacyListType, [media], false)
            }
        )

        self.present(controller, animated: true)
    }
    
    @objc private func nextAction() {
        guard selected.count > 0 else { return }
        guard !nextInProgress else { return }
        nextInProgress = true
        
        var result = [PendingMedia]()
        let manager = PHImageManager.default()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // keep in-app camera media
            result.append(contentsOf: self.originalMedia.filter { $0.asset == nil })
            
            for i in 0..<self.selected.count {
                let asset = self.selected[i]

                if let media = self.originalMedia.first(where: { $0.asset == asset }) {
                    media.order = i
                    result.append(media)
                    continue
                }
                
                switch asset.mediaType {
                case .image:
                    let media = PendingMedia(type: .image)
                    media.asset = asset
                    media.order = i
                    
                    let options = PHImageRequestOptions()
                    options.isSynchronous = false
                    options.isNetworkAccessAllowed = true
                    options.deliveryMode = .highQualityFormat
                    options.progressHandler = { progress, error, stop, _ in
                        DDLogInfo("MediaPickerViewController/next/image/progress [\(progress)] asset=[\(asset)]")
                        media.progress.send(Float(progress))

                        if let error = error {
                            DDLogError("MediaPickerViewController/next/image error=[\(error)] asset=[\(asset)]")
                            media.error.send(PendingMediaError.loadingError)
                        }
                    }

                    manager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .default, options: options) { image, _ in
                        guard let image = image else {
                            DDLogWarn("MediaPickerViewController/next/image Unable to fetch image")
                            return media.error.send(PendingMediaError.loadingError)
                        }

                        media.image = image
                    }
                    
                    result.append(media)
                case .video:
                    let media = PendingMedia(type: .video)
                    media.asset = asset
                    media.order = i

                    let options = PHVideoRequestOptions()
                    options.isNetworkAccessAllowed = true
                    options.deliveryMode = .highQualityFormat
                    options.progressHandler = { progress, error, stop, _ in
                        DDLogInfo("MediaPickerViewController/next/video/progress [\(progress)] asset=[\(asset)]")
                        if progress < 1.0 {
                            media.progress.send(Float(progress))
                        }

                        if let error = error {
                            DDLogError("MediaPickerViewController/next/video error=[\(error)] asset=[\(asset)]")
                            media.error.send(PendingMediaError.loadingError)
                        }
                    }

                    manager.requestAVAsset(forVideo: asset, options: options) { avasset, _, _ in
                        // Sometimes NextLevelSessionExporterError/AVAssetReader is unable to process videos if they are not copied first
                        let url = URL(fileURLWithPath: NSTemporaryDirectory())
                            .appendingPathComponent(UUID().uuidString, isDirectory: false)
                            .appendingPathExtension("mp4")

                        if let video = avasset as? AVURLAsset {
                            do {
                                try FileManager.default.copyItem(at: video.url, to: url)
                            } catch {
                                DDLogError("MediaPickerViewController/next/video/copy/error Failed to copy [\(error)] url=[\(video.url.description)] tmp=[\(url.description)]")
                                return media.error.send(PendingMediaError.loadingError)
                            }
                            DDLogInfo("MediaPickerViewController/next/video/copy/ready  Temporary url: [\(url.description)] url=[\(video.url.description)] original order=[\(media.order)]")

                            media.originalVideoURL = url
                            media.fileURL = url
                        } else if let composition = avasset as? AVComposition {
                            let slowMotion = (asset.mediaSubtypes.rawValue & PHAssetMediaSubtype.videoHighFrameRate.rawValue) != 0

                            VideoUtils.save(composition: composition, to: url, slowMotion: slowMotion) { result in
                                DispatchQueue.main.async {
                                    switch(result) {
                                    case .success(let url):
                                        DDLogInfo("MediaPickerViewController/next/video/copy/ready  Temporary url: [\(url.description)] order=[\(media.order)]")
                                        media.originalVideoURL = url
                                        media.fileURL = url
                                    case .failure(let error):
                                        DDLogError("MediaPickerViewController/next/video/copy/error Failed to save [\(error)] tmp=[\(url.description)]")
                                        media.error.send(PendingMediaError.loadingError)
                                    }
                                }
                            }
                        } else {
                            if let avasset = avasset {
                                DDLogWarn("MediaPickerViewController/next/video Unknown video type \(String(describing: type(of: avasset)))")
                            } else {
                                DDLogWarn("MediaPickerViewController/next/video Missing video")
                            }

                            media.error.send(PendingMediaError.loadingError)
                        }
                    }
                    
                    result.append(media)
                default:
                    continue
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                if !self.config.allowsMultipleSelection {
                    self.selected.removeAll()
                }

                self.nextInProgress = false
                self.didFinish(self, self.config.destination, self.config.privacyListType, result, false)
            }
        }
    }

    @objc private func cancelAction() {
        privacyCancellable?.cancel() // prevent blue pill changing during closing animation
        didFinish(self, config.destination, self.config.privacyListType, [], true)
    }

    @objc private func openAlbumsAction() {
        let controller = MediaAlbumsViewController() {[weak self] controller, album, cancel in
            guard let self = self else { return }
            DDLogInfo("openAlbumsAction \(album?.description ?? "missing-album")")
            
            controller.dismiss(animated: true)
            
            if !cancel {
                self.fetchAssets(album: album)
            }
        }

        present(controller, animated: true)
    }

    @objc private func changeDestinationAction() {
        guard let destination = config.destination, let privacyListType = config.privacyListType else { return }

        let controller = ChangeDestinationViewController(destination: destination, privacyListType: privacyListType) { controller, destination, privacyListType in
            controller.dismiss(animated: true)
            self.config.privacyListType = privacyListType
            self.config.destination = destination
            self.updateChangeDestinationBtn()
        }

        present(UINavigationController(rootViewController: controller), animated: true)
    }

    @objc private func closeLimitedAccessBuble() {
        limitedAccessBubble.isHidden = true
    }

    @objc private func askForLimitedAccessUpdate() {
        if #available(iOS 14, *) {
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
    }

    private func scrollToBottom(_ animated: Bool = false) {
        guard let count = assets?.count, count > 0 else { return }
        collectionView.scrollToItem(at: IndexPath(row: count - 1, section: 0), at: .bottom, animated: animated)
    }
}

// MARK: UICollectionViewDelegate
extension MediaPickerViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let cell = collectionView.cellForItem(at: indexPath) as? AssetViewCell else { return false }
        guard let asset = cell.asset else { return false }

        if selected.contains(asset) {
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
        if !config.allowsMultipleSelection {
            selected.append(asset)
            nextAction()
            return
        }

        selected.append(asset)
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
            cell.prepare(config: self.config, mode: self.mode, selection: self.selected)
        })
    }

    private func deselect(_ collectionView: UICollectionView, cell: AssetViewCell, asset: PHAsset) {
        guard let idx = self.selected.firstIndex(of: asset) else { return }
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
                cell.prepare(config: self.config, mode: self.mode, selection: self.selected)
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
                cell.prepare(config: self.config, mode: self.mode, selection: self.selected)
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
    
    func prepare(config: MediaPickerConfig, mode: MediaPickerMode, selection: [PHAsset]) {
        let (spacingBottom, spacingLead, spacingTrail) = calculateSpacing(mode: mode)
        
        NSLayoutConstraint.deactivate(activeConstraints)
        
        activeConstraints = [
            image.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacingLead),
            image.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacingTrail),
            image.topAnchor.constraint(equalTo: contentView.topAnchor),
            image.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -spacingBottom),
            indicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            indicator.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            duration.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            duration.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -6),
            favorite.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            favorite.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 6),
            favorite.widthAnchor.constraint(equalToConstant: 20),
            favorite.heightAnchor.constraint(equalToConstant: 20),
        ]
        
        NSLayoutConstraint.activate(activeConstraints)

        if let asset = asset, selection.contains(asset) {
            image.layer.cornerRadius = 20
        } else {
            image.layer.cornerRadius = 0
        }

        duration.isHidden = true
        if asset?.mediaType == .video, let interval = asset?.duration {
            duration.isHidden = false
            duration.text = interval.formatted
        }

        favorite.isHidden = asset?.isFavorite != true

        prepareIndicator(config: config, selection: selection)

        setNeedsLayout()
    }

    func prepareIndicator(config: MediaPickerConfig, selection: [PHAsset]) {
        if let asset = asset, let idx = selection.firstIndex(of: asset) {
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
            indicator.layer.borderColor = CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.7)
            indicator.backgroundColor = .clear
            indicatorLabel.isHidden = true
        }

        indicator.isHidden = !config.allowsMultipleSelection
    }
}
