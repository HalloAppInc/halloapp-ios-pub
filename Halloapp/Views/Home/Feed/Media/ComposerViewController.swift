//
//  ComposerViewController.swift
//  HalloApp
//
//  Created by Stefan Fidanov on 22.06.22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import Foundation
import PhotosUI
import UIKit

struct ComposerResult {
    var destinations: [ShareDestination]

    var input: MentionInput
    var voiceNote: PendingMedia?

    var text: MentionText?
    var media: [PendingMedia]
    var linkPreviewData: LinkPreviewData?
    var linkPreviewMedia: PendingMedia?
}

struct ComposerConfig {
    var destination: ShareDestination
    var mediaEditMaxAspectRatio: CGFloat?
    var maxVideoLength: TimeInterval = ServerProperties.maxFeedVideoDuration

    fileprivate var isOnboarding = false

    static func config(with destination: ShareDestination) -> ComposerConfig {
        switch destination {
        case .feed:
            return .userPost(destination: destination)
        case .group:
            return .groupPost(destination: destination)
        case .contact:
            return .message(destination: destination)
        }
    }

    private static func userPost(destination: ShareDestination) -> ComposerConfig {
        ComposerConfig(destination: destination)
    }

    private static func groupPost(destination: ShareDestination) -> ComposerConfig {
        ComposerConfig(destination: destination)
    }

    private static func message(destination: ShareDestination) -> ComposerConfig {
        ComposerConfig(
            destination: destination,
            maxVideoLength: ServerProperties.maxChatVideoDuration
        )
    }

    static var onboardingPost: ComposerConfig {
        ComposerConfig(destination: .feed(.all), isOnboarding: true)
    }
}

typealias ComposerViewControllerCallback = (ComposerViewController, ComposerResult, Bool) -> Void

struct ComposerConstants {
    static let horizontalPadding = MediaCarouselViewConfiguration.default.cellSpacing * 0.5
    static let verticalPadding = MediaCarouselViewConfiguration.default.cellSpacing * 0.5
    static let controlSpacing: CGFloat = 9
    static let controlRadius: CGFloat = 17
    static let controlSize: CGFloat = 34
    static let backgroundRadius: CGFloat = 20

    static let postTextHorizontalPadding: CGFloat = 18
    static let postTextVerticalPadding: CGFloat = 12

    static let sendButtonHeight: CGFloat = 52
    static let postTextNoMediaMinHeight: CGFloat = 265 - 2 * postTextVerticalPadding
    static let postTextWithMeidaHeight: CGFloat = sendButtonHeight - 2 * postTextVerticalPadding
    static let postTextMaxHeight: CGFloat = 118 - 2 * postTextVerticalPadding
    static let postTextRadius: CGFloat = 26
    static let postLinkPreviewHeight: CGFloat = 187

    static let fontSize: CGFloat = 16
    static let fontSizeLarge: CGFloat = 20

    static let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
    static let smallFont = UIFont(descriptor: fontDescriptor, size: fontSize)
    static let largeFont = UIFont(descriptor: fontDescriptor, size: fontSizeLarge)

    static func getFontSize(textSize: Int, isPostWithMedia: Bool) -> UIFont {
        return isPostWithMedia || textSize > 180 ? smallFont : largeFont
    }

    static let textViewTextColor = UIColor.label.withAlphaComponent(0.9)
}

class ComposerViewController: UIViewController {
    private var config: ComposerConfig
    private var media: [PendingMedia]
    private var input: MentionInput
    private var initialType: NewPostMediaSource
    private var completion: ComposerViewControllerCallback
    private var isSharing = false
    private var link: String = ""
    private var linkPreviewData: LinkPreviewData?
    private var linkPreviewImage: UIImage?
    private var index = 0
    private var mediaErrorsCount = 0
    private var videoTooLong = false

    private lazy var groups: [Group] = {
        AppContext.shared.mainDataStore.groups(in: AppContext.shared.mainDataStore.viewContext)
    }()

    private lazy var contacts: [ABContact] = {
        AppContext.shared.contactStore.allRegisteredContacts(sorted: false, in: AppContext.shared.contactStore.viewContext)
    }()

    public var isCompactShareFlow: Bool {
        if case .contact(_, _, _) = config.destination {
            return false
        } else if case .group(_, _) = config.destination {
            return false
        } else if initialType == .unified {
            return false
        } else if AppContext.shared.userDefaults.bool(forKey: "forcePickerShare") {
            return false
        } else {
            return AppContext.shared.userDefaults.bool(forKey: "forceCompactShare") || (groups.count + contacts.count <= 6)
        }
    }

    /// - note: Only used during onboarding to cancel out of the compose flow (different from going back).
    var onCancel: (() -> Void)?

    private var cancellables: Set<AnyCancellable> = []
    private var mediaReadyCancellable: AnyCancellable?

    private var voiceNote: PendingMedia?
    private var audioRecorderControlsLocked = false
    private lazy var audioRecorder: AudioRecorder = {
        let audioRecorder = AudioRecorder()
        audioRecorder.delegate = self

        return audioRecorder
    }()

    private lazy var backButtonItem: UIBarButtonItem = {
        let imageConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        let image = UIImage(systemName: "chevron.left", withConfiguration: imageConfig)

        let button = UIButton(type: .custom)
        button.setImage(image, for: .normal)
        if case .library = initialType {
            button.setTitle(Localizations.addMore, for: .normal)
        }

        button.setTitleColor(.primaryBlue, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16)
        button.addTarget(self, action: #selector(backAction), for: .touchUpInside)

        return UIBarButtonItem(customView: button)
    }()

    private lazy var closeButtonItem: UIBarButtonItem = {
        let imageConfig = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(systemName: "chevron.down", withConfiguration: imageConfig)

        return UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(backAction))
    }()

    private lazy var cropButtonItem: UIBarButtonItem = {
        let imageConfig = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(systemName: "crop.rotate", withConfiguration: imageConfig)

        return UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(cropAction))
    }()

    private lazy var annotateButtonItem: UIBarButtonItem = {
        let image = UIImage(named: "Annotate")
        return UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(annotateAction))
    }()

    private lazy var drawButtonItem: UIBarButtonItem = {
        let image = UIImage(named: "Draw")
        return UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(drawAction))
    }()

    private lazy var cancelButtonItem: UIBarButtonItem = {
        let configuration = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(systemName: "xmark", withConfiguration: configuration)
        return UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(cancelAction))
    }()

    private lazy var contentView: UIStackView = {
        let contentView = UIStackView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.axis = .vertical
        contentView.spacing = ComposerConstants.verticalPadding

        return contentView
    }()

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true

        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            scrollView.contentLayoutGuide.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),
            scrollView.contentLayoutGuide.heightAnchor.constraint(greaterThanOrEqualTo: contentView.heightAnchor, constant: 16),

            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.centerYAnchor.constraint(equalTo: scrollView.contentLayoutGuide.centerYAnchor),
        ])

        return scrollView
    }()

    private lazy var bottomView: UIView = {
        let bottomView = UIView()
        bottomView.translatesAutoresizingMaskIntoConstraints = false

        return bottomView
    }()

    private lazy var mainView: UIStackView = {
        let mainView = UIStackView(arrangedSubviews: [scrollView, bottomView])
        mainView.spacing = 0
        mainView.translatesAutoresizingMaskIntoConstraints = false
        mainView.axis = .vertical

        return mainView
    }()

    private var constraints: [NSLayoutConstraint] = []

    private lazy var mainViewBottomConstraint: NSLayoutConstraint = {
        let mainViewBottomConstraint = view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: mainView.bottomAnchor)
        mainViewBottomConstraint.priority = UILayoutPriority(999)
        return mainViewBottomConstraint
    }()

    private lazy var mediaCarouselHeightConstraint: NSLayoutConstraint = {
        mediaCarouselView.heightAnchor.constraint(equalToConstant: 128)
    }()

    private lazy var mediaCarouselView: MediaCarouselView = {
        var configuration = MediaCarouselViewConfiguration.composer
        configuration.gutterWidth = ComposerConstants.horizontalPadding
        configuration.supplementaryViewsProvider = { [weak self] index in
            guard let self = self else { return [] }

            let deleteBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            deleteBackground.translatesAutoresizingMaskIntoConstraints = false
            deleteBackground.isUserInteractionEnabled = false

            let deleteImageConfiguration = UIImage.SymbolConfiguration(weight: .heavy)
            let deleteImage = UIImage(systemName: "xmark", withConfiguration: deleteImageConfiguration)?.withTintColor(.white, renderingMode: .alwaysOriginal)

            let deleteButton = UIButton(type: .custom)
            deleteButton.translatesAutoresizingMaskIntoConstraints = false
            deleteButton.setImage(deleteImage, for: .normal)
            deleteButton.layer.cornerRadius = ComposerConstants.controlRadius
            deleteButton.clipsToBounds = true
            deleteButton.addTarget(self, action: #selector(self.deleteMediaAction), for: .touchUpInside)
            deleteButton.insertSubview(deleteBackground, at: 0)
            if let imageView = deleteButton.imageView {
                deleteButton.bringSubviewToFront(imageView)
            }

            deleteBackground.constrain(to: deleteButton)
            NSLayoutConstraint.activate([
                deleteButton.widthAnchor.constraint(equalToConstant: ComposerConstants.controlSize),
                deleteButton.heightAnchor.constraint(equalToConstant: ComposerConstants.controlSize)
            ])


            let topTrailingActions = UIStackView(arrangedSubviews: [deleteButton])
            topTrailingActions.translatesAutoresizingMaskIntoConstraints = false
            topTrailingActions.axis = .horizontal
            topTrailingActions.isLayoutMarginsRelativeArrangement = true
            topTrailingActions.layoutMargins = UIEdgeInsets(top: ComposerConstants.controlSpacing, left: 0, bottom: 0, right: ComposerConstants.controlSpacing)

            return [
                MediaCarouselSupplementaryItem(anchors: [.top, .trailing], view: topTrailingActions),
            ]
        }

        let carouselView = MediaCarouselView(media: media.map { FeedMedia($0, feedPostId: "") }, configuration: configuration)
        carouselView.translatesAutoresizingMaskIntoConstraints = false
        carouselView.delegate = self

        let reorderGesture = UILongPressGestureRecognizer(target: self, action: #selector(reorderAction(gesture:)))
        carouselView.addGestureRecognizer(reorderGesture)

        return carouselView
    }()

    private var mediaReorderViewContoller: MediaReorderViewContoller?

    private lazy var mediaErrorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.textColor = .red
        label.numberOfLines = 0

        return label
    }()

    private lazy var mediaComposerTextView: MediaComposerTextView = {
        let mediaComposerTextView = MediaComposerTextView()
        mediaComposerTextView.translatesAutoresizingMaskIntoConstraints = false
        mediaComposerTextView.delegate = self

        return mediaComposerTextView
    }()

    private lazy var audioComposerView: AudioComposerView = {
        let audioComposerView = AudioComposerView()
        audioComposerView.translatesAutoresizingMaskIntoConstraints = false
        audioComposerView.delegate = self

        return audioComposerView
    }()

    private lazy var textComposerView: TextComposerView = {
        let textComposerView = TextComposerView()
        textComposerView.translatesAutoresizingMaskIntoConstraints = false
        textComposerView.delegate = self

        return textComposerView
    }()

    private lazy var unifiedComposerView: UnifiedComposerView = {
        let unifiedComposerView = UnifiedComposerView()
        unifiedComposerView.translatesAutoresizingMaskIntoConstraints = false
        unifiedComposerView.delegate = self
        return unifiedComposerView
    }()

    private lazy var destinationsView: ComposerDestinationRowView = {
        let destinationsView = ComposerDestinationRowView(destination: config.destination, groups: groups, contacts: contacts)
        destinationsView.translatesAutoresizingMaskIntoConstraints = false
        destinationsView.destinationDelegate = self

        return destinationsView
    }()

    private lazy var compactShareRow: UIView = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        label.textColor = .primaryBlackWhite.withAlphaComponent(0.4)
        label.text = Localizations.shareWith.uppercased()

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .primaryBlackWhite.withAlphaComponent(0.25)
        separator.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let buttonWrapper = UIView()
        buttonWrapper.translatesAutoresizingMaskIntoConstraints = false
        buttonWrapper.addSubview(compactSendButton)

        let stack = UIStackView(arrangedSubviews: [destinationsView, separator, buttonWrapper])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 0

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            stack.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
            stack.heightAnchor.constraint(equalToConstant: 80),
            compactSendButton.centerXAnchor.constraint(equalTo: buttonWrapper.centerXAnchor),
            compactSendButton.centerYAnchor.constraint(equalTo: buttonWrapper.centerYAnchor),
            buttonWrapper.widthAnchor.constraint(equalTo: compactSendButton.widthAnchor, constant: 20),
        ])

        return container
    }()

    private lazy var mediaPickerButton: UIButton = {
        let imageConfig = UIImage.SymbolConfiguration(pointSize: 40, weight: .bold)

        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "photo.circle.fill", withConfiguration: imageConfig), for: .normal)
        button.tintColor = .primaryBlue
        button.addTarget(self, action: #selector(openPickerAction), for: .touchUpInside)

        return button
    }()

    private var sendButton: UIButton {
        isCompactShareFlow ? compactSendButton : largeSendButton
    }

    private lazy var compactSendButton: UIButton = {
        let icon = UIImage(named: "icon_share")?.withTintColor(.white, renderingMode: .alwaysOriginal)

        let button = RoundedRectButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(icon, for: .normal)
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 52),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])

        button.addTarget(self, action: #selector(shareAction), for: .touchUpInside)

        return button
    }()

    private lazy var largeSendButton: UIButton = {
        let icon: UIImage?
        let title: String
        let leftContentInset: CGFloat
        let rightContentInset: CGFloat
        let horizontalImageInset: CGFloat

        if initialType == .unified {
            icon = UIImage(named: "icon_share")
            title = Localizations.buttonShare
            leftContentInset = 20
            rightContentInset = 16
            horizontalImageInset = 8
        } else if case .contact(_, _, _) = config.destination {
            icon = nil
            title = Localizations.buttonSend
            leftContentInset = 16
            rightContentInset = 16
            horizontalImageInset = 0
        } else if case .group(_, _) = config.destination {
            icon = nil
            title = Localizations.buttonSend
            leftContentInset = 16
            rightContentInset = 16
            horizontalImageInset = 0
        } else {
            // chevron left as the button's semantic content attribute is reversed
            icon = UIImage(systemName: "chevron.left")?.imageFlippedForRightToLeftLayoutDirection()
            title = Localizations.sendTo
            leftContentInset = 30
            rightContentInset = 36
            horizontalImageInset = 12
        }

        let button = RoundedRectButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        // Attributed strings do not respect button title colors
        let attributedTitle = NSAttributedString(string: title, attributes: [.kern: 0.5, .foregroundColor: UIColor.white])
        button.setAttributedTitle(attributedTitle, for: .normal)
        button.setAttributedTitle(attributedTitle, for: .disabled)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        let configuredIcon = icon?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .bold))
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        button.setImage(configuredIcon, for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: -1.5, left: leftContentInset, bottom: 0, right: rightContentInset)

        // keep image on the right & tappable
        if case .rightToLeft = view.effectiveUserInterfaceLayoutDirection {
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -horizontalImageInset, bottom: 0, right: horizontalImageInset)
            button.semanticContentAttribute = .forceLeftToRight
        } else {
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: horizontalImageInset, bottom: 0, right: -horizontalImageInset)
            button.semanticContentAttribute = .forceRightToLeft
        }

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 44),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
        ])

        button.addTarget(self, action: #selector(shareAction), for: .touchUpInside)

        return button
    }()

    private lazy var titleView = ComposerTitleView()

    init(
        config: ComposerConfig,
        type: NewPostMediaSource,
        input: MentionInput,
        media: [PendingMedia],
        voiceNote: PendingMedia?,
        completion: @escaping ComposerViewControllerCallback)
    {
        self.config = config
        self.initialType = type
        self.input = input
        self.media = media
        self.voiceNote = voiceNote
        self.completion = completion

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .feedBackground
        view.addSubview(mainView)

        navigationItem.titleView = titleView

        NSLayoutConstraint.activate([
            mainView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mainView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // leave at least 8pt in case of no safeAreaInsets
            mainView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8),
            mainViewBottomConstraint,
        ])

        configureUI()

        // show the favorites education modal only once to the user
        if !AppContext.shared.userDefaults.bool(forKey: "hasFavoritesModalBeenShown") {
            AppContext.shared.userDefaults.set(true, forKey: "hasFavoritesModalBeenShown")

            let vc = FavoritesInformationViewController() { privacyListType in
                self.config.destination = .feed(privacyListType)
            }

            present(vc, animated: true)
        }

        handleKeyboardUpdates()
    }

    private func configureUI() {
        NSLayoutConstraint.deactivate(constraints)
        constraints.removeAll()

        for view in contentView.subviews {
            view.removeFromSuperview()
        }

        for view in bottomView.subviews {
            view.removeFromSuperview()
        }

        contentView.isLayoutMarginsRelativeArrangement = true
        contentView.layoutMargins = UIEdgeInsets(top: ComposerConstants.verticalPadding, left: ComposerConstants.horizontalPadding, bottom: ComposerConstants.verticalPadding, right: ComposerConstants.horizontalPadding)

        if media.count > 0 {
            titleView.alignment = .leading
            if case .group(_, _) = config.destination {
                titleView.title = Localizations.newPostTitle
            } else if initialType == .unified, !config.isOnboarding {
                titleView.title = Localizations.newPostTitle
            } else {
                titleView.title = nil
            }

            contentView.addArrangedSubview(mediaCarouselView)
            contentView.addArrangedSubview(mediaErrorLabel)

            bottomView.addSubview(mediaComposerTextView)

            constraints.append(mediaCarouselHeightConstraint)
            constraints.append(mediaComposerTextView.leadingAnchor.constraint(equalTo: bottomView.leadingAnchor))
            constraints.append(mediaComposerTextView.trailingAnchor.constraint(equalTo: bottomView.trailingAnchor))
            constraints.append(mediaComposerTextView.topAnchor.constraint(equalTo: bottomView.topAnchor, constant: 8))

            if isCompactShareFlow {
                bottomView.addSubview(compactShareRow)

                constraints.append(compactShareRow.leadingAnchor.constraint(equalTo: bottomView.leadingAnchor))
                constraints.append(compactShareRow.trailingAnchor.constraint(equalTo: bottomView.trailingAnchor))
                constraints.append(compactShareRow.bottomAnchor.constraint(equalTo: bottomView.bottomAnchor))
                constraints.append(compactShareRow.topAnchor.constraint(equalTo: mediaComposerTextView.bottomAnchor, constant: 11))
            } else {
                bottomView.addSubview(sendButton)

                constraints.append(sendButton.centerXAnchor.constraint(equalTo: bottomView.centerXAnchor))
                constraints.append(sendButton.topAnchor.constraint(equalTo: mediaComposerTextView.bottomAnchor, constant: 11))
                constraints.append(sendButton.bottomAnchor.constraint(equalTo: bottomView.bottomAnchor))
            }

            listenForMediaErrors()
        } else if initialType == .voiceNote || (initialType != .unified && voiceNote != nil) {
            titleView.alignment = .center
            titleView.title = Localizations.fabAccessibilityVoiceNote

            contentView.addArrangedSubview(audioComposerView)

            if isCompactShareFlow {
                bottomView.addSubview(compactShareRow)

                constraints.append(compactShareRow.leadingAnchor.constraint(equalTo: bottomView.leadingAnchor))
                constraints.append(compactShareRow.trailingAnchor.constraint(equalTo: bottomView.trailingAnchor))
                constraints.append(compactShareRow.topAnchor.constraint(equalTo: bottomView.topAnchor))
                constraints.append(compactShareRow.bottomAnchor.constraint(equalTo: bottomView.bottomAnchor))
            } else {
                bottomView.addSubview(mediaPickerButton)
                bottomView.addSubview(sendButton)

                constraints.append(sendButton.centerXAnchor.constraint(equalTo: bottomView.centerXAnchor))
                constraints.append(sendButton.topAnchor.constraint(equalTo: bottomView.topAnchor, constant: 8))
                constraints.append(sendButton.bottomAnchor.constraint(equalTo: bottomView.bottomAnchor))
                constraints.append(mediaPickerButton.trailingAnchor.constraint(equalTo: bottomView.trailingAnchor, constant: -14))
                constraints.append(mediaPickerButton.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor))
            }
        } else if initialType == .unified {
            titleView.alignment = .center
            titleView.title = config.isOnboarding ? Localizations.onboardingFirstPostTitle : Localizations.newPostTitle

            contentView.layoutMargins = .zero
            contentView.addArrangedSubview(unifiedComposerView)

            let contentHeightContraint = contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor, constant: -36)
            contentHeightContraint.priority = UILayoutPriority(251)
            constraints.append(contentHeightContraint)

            bottomView.addSubview(sendButton)
            constraints += [
                sendButton.centerXAnchor.constraint(equalTo: bottomView.centerXAnchor),
                sendButton.topAnchor.constraint(equalTo: bottomView.topAnchor, constant: 8),
                sendButton.bottomAnchor.constraint(equalTo: bottomView.bottomAnchor),
            ]

            unifiedComposerView.becomeFirstResponder()
        } else {
            titleView.alignment = .center
            titleView.title = Localizations.fabAccessibilityTextPost

            contentView.layoutMargins = .zero
            contentView.addArrangedSubview(textComposerView)

            constraints.append(contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor, constant: -36))

            if isCompactShareFlow {
                bottomView.addSubview(compactShareRow)

                constraints.append(compactShareRow.leadingAnchor.constraint(equalTo: bottomView.leadingAnchor))
                constraints.append(compactShareRow.trailingAnchor.constraint(equalTo: bottomView.trailingAnchor))
                constraints.append(compactShareRow.topAnchor.constraint(equalTo: bottomView.topAnchor))
                constraints.append(compactShareRow.bottomAnchor.constraint(equalTo: bottomView.bottomAnchor))
            } else {
                bottomView.addSubview(sendButton)
                bottomView.addSubview(mediaPickerButton)

                constraints.append(sendButton.centerXAnchor.constraint(equalTo: bottomView.centerXAnchor))
                constraints.append(sendButton.topAnchor.constraint(equalTo: bottomView.topAnchor, constant: 8))
                constraints.append(sendButton.bottomAnchor.constraint(equalTo: bottomView.bottomAnchor))
                constraints.append(mediaPickerButton.trailingAnchor.constraint(equalTo: bottomView.trailingAnchor, constant: -14))
                constraints.append(mediaPickerButton.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor))
            }

            textComposerView.becomeFirstResponder()
        }

        titleView.subtitle = config.destination.name

        NSLayoutConstraint.activate(constraints)

        updateUI()
    }

    private func updateUI() {
        if media.count > 0 {
            // update complex media, text and audio ui
            updateMediaCarouselHeight()

            mediaComposerTextView.update(
                with: input,
                mentionables: mentionableUsers(),
                recorder: audioRecorder,
                voiceNote: voiceNote,
                locked: audioRecorderControlsLocked)

            if isCompactShareFlow {
                sendButton.isEnabled = media.allSatisfy({ $0.ready.value }) && destinationsView.destinations.count > 0
            } else {
                sendButton.isEnabled = media.allSatisfy({ $0.ready.value })
            }

            mediaReadyCancellable = Publishers.MergeMany(media.map { $0.ready }).sink { [weak self] _ in
                guard let self = self else { return }
                guard self.media.allSatisfy({ $0.ready.value }) else { return }

                self.updateMediaCarouselHeight()

                if self.isCompactShareFlow {
                    self.sendButton.isEnabled = self.destinationsView.destinations.count > 0
                } else {
                    self.sendButton.isEnabled = true
                }
            }
        } else if initialType == .voiceNote || (initialType != .unified && voiceNote != nil) {
            audioComposerView.update(with: audioRecorder, voiceNote: voiceNote)

            mediaPickerButton.isHidden = audioRecorder.isRecording || voiceNote == nil

            if isCompactShareFlow {
                sendButton.isEnabled = !audioRecorder.isRecording && voiceNote != nil && destinationsView.destinations.count > 0
            } else {
                sendButton.isEnabled = !audioRecorder.isRecording && voiceNote != nil
            }
        } else if initialType == .unified {
            unifiedComposerView.update(with: input, mentionables: mentionableUsers(), recorder: audioRecorder, voiceNote: voiceNote, locked: audioRecorderControlsLocked)
            sendButton.isEnabled = !input.text.isEmpty || (!audioRecorder.isRecording && voiceNote != nil)
        } else {
            textComposerView.update(with: input, mentionables: mentionableUsers())

            mediaPickerButton.isHidden = input.text.isEmpty

            if isCompactShareFlow {
                sendButton.isEnabled = !input.text.isEmpty && destinationsView.destinations.count > 0
            } else {
                sendButton.isEnabled = !input.text.isEmpty
            }
        }

        updateBarButtons()
    }

    private func updateBarButtons() {
        var leftItems = [UIBarButtonItem]()
        var rightItems = [UIBarButtonItem]()

        defer {
            navigationItem.leftBarButtonItems = leftItems
            navigationItem.rightBarButtonItems = rightItems
        }

        switch initialType {
        case .library where !media.isEmpty:
            fallthrough
        case .camera where !media.isEmpty:
            leftItems = [backButtonItem]
        default:
            leftItems = [closeButtonItem]
        }

        if config.isOnboarding {
            leftItems = [backButtonItem]
            rightItems = [cancelButtonItem]
        }

        guard index >= 0, index < media.count else {
            DDLogDebug("ComposerViewController/updateUI index out of bounds")
            return
        }

        switch media[index].type {
        case .image:
            rightItems = [drawButtonItem, annotateButtonItem, cropButtonItem]
        case .video:
            rightItems = [cropButtonItem]
        case .audio, .document:
            break
        }
    }

    private func updateMediaCarouselHeight() {
        guard self.media.allSatisfy({ $0.ready.value }) else { return }

        let width = UIScreen.main.bounds.width - 4 * ComposerConstants.horizontalPadding
        let items = media.map { FeedMedia($0, feedPostId: "") }

        mediaCarouselHeightConstraint.constant = MediaCarouselView.preferredHeight(for: items, width: width)
    }

    private func listenForMediaErrors() {
        guard media.count > 0 else { return }

        mediaErrorsCount = 0

        Publishers.MergeMany(media.map { $0.error }).compactMap { $0 }.sink { [weak self] _ in
            guard let self = self else { return }
            self.mediaErrorsCount += 1
            self.updateMediaError()
        }.store(in: &cancellables)

        updateMediaError()
    }

    private func updateMediaError() {
        guard media.count > 0 else { return }

        if mediaErrorsCount > 0 {
            mediaErrorLabel.isHidden = true
            mediaErrorLabel.text = Localizations.mediaPrepareFailed(mediaErrorsCount)
        } else if videoTooLong {
            mediaErrorLabel.isHidden = false
            mediaErrorLabel.text = Localizations.maxVideoLengthTitle(config.maxVideoLength) + "\n" + Localizations.maxVideoLengthMessage
        } else {
            mediaErrorLabel.isHidden = true
            mediaErrorLabel.text = ""
        }
    }

    @objc private func backAction() {
        ImageServer.shared.clearUnattachedTasks(keepFiles: false)

        let result = ComposerResult(destinations: [config.destination], input: input, voiceNote: voiceNote, media: media)
        completion(self, result, false)
    }

    @objc private func shareAction() {
        guard !isSharing else { return }
        isSharing = true

        isVideoLengthWithinLimit { [weak self] isWithinLimit in
            guard let self = self else { return }

            if isWithinLimit {
                self.share()
            } else {
                self.isSharing = false
                self.alertVideoLengthOverLimit()
            }
        }
    }

    private func share() {
        var destinations: [ShareDestination]
        if isCompactShareFlow {
            destinations = destinationsView.destinations
        } else {
            destinations  = [config.destination]
        }

        let mentionText = MentionText(expandedText: input.text, mentionRanges: input.mentions).trimmed()

        if let voiceNote = voiceNote {
            media.append(voiceNote)
        }

        // if no link preview or link preview not yet loaded, send without link preview.
        // if the link preview does not have an image... send immediately
        if link == "" || linkPreviewData == nil ||  linkPreviewImage == nil {
            let result = ComposerResult(destinations: destinations, input: input, text: mentionText, media: media, linkPreviewData: linkPreviewData)
            completion(self, result, true)
            isSharing = false
        } else {
            // if link preview has an image, load the image before sending.
            loadLinkPreviewImageAndShare(destinations: destinations, mentionText: mentionText, mediaItems: media)
        }
    }

    @objc private func reorderAction(gesture: UILongPressGestureRecognizer) {
        guard media.count > 1 else { return }
        guard media.allSatisfy({ $0.ready.value }) else { return }

        switch(gesture.state) {
        case .began:
            let controller = MediaReorderViewContoller(media: media, index: index)
            controller.animatorDelegate = mediaCarouselView
            present(controller.withNavigationController(), animated: true)

            mediaReorderViewContoller = controller
        case .changed:
            mediaReorderViewContoller?.move(using: gesture)
        case .ended:
            mediaReorderViewContoller?.end()

            if let controller = mediaReorderViewContoller {
                media = controller.media
                index = controller.index

                updateMediaState(animated: false)
            }

            dismiss(animated: true)
            mediaReorderViewContoller = nil
        default:
            dismiss(animated: true)
            mediaReorderViewContoller = nil
        }
    }

    private func loadLinkPreviewImageAndShare(destinations: [ShareDestination], mentionText: MentionText, mediaItems: [PendingMedia]) {
        // Send link preview with image in it
        let linkPreviewMedia = PendingMedia(type: .image)
        linkPreviewMedia.image = linkPreviewImage

        if linkPreviewMedia.ready.value {
            let result = ComposerResult(
                destinations: destinations,
                input: input,
                text: mentionText,
                media: media,
                linkPreviewData: linkPreviewData,
                linkPreviewMedia: linkPreviewMedia)

            completion(self, result, true)
            isSharing = false
        } else {
            linkPreviewMedia.ready.sink { [weak self] ready in
                guard let self = self else { return }
                guard ready else { return }

                let result = ComposerResult(
                    destinations: destinations,
                    input: self.input,
                    text: mentionText,
                    media: self.media,
                    linkPreviewData: self.linkPreviewData,
                    linkPreviewMedia: linkPreviewMedia)

                self.completion(self, result, true)
                self.isSharing = false
            }.store(in: &cancellables)
        }
    }

    private func alertVideoLengthOverLimit() {
        let alert = UIAlertController(title: Localizations.maxVideoLengthTitle(config.maxVideoLength),
                                      message: Localizations.maxVideoLengthMessage,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default))

        present(alert, animated: true)
    }

    private func isVideoLengthWithinLimit(action: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            for item in self.media {
                guard item.type == .video else { continue }
                guard let url = item.fileURL else { continue }

                if AVURLAsset(url: url).duration.seconds > self.config.maxVideoLength {
                    DispatchQueue.main.async {
                        action(false)
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                action(true)
            }
        }
    }

    private func shouldDismissWhenNoMedia() -> Bool {
        // don't dimiss when
        // - has a voice note
        // - started as text post and still has text
        // - is not the unified composer
        return voiceNote == nil && !(initialType == .noMedia && !input.text.isEmpty) && initialType != .unified
    }
}

// MARK: Keybord
extension ComposerViewController {
    private func handleKeyboardUpdates() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification).sink { [weak self] notification in
            guard let self = self else { return }
            guard let info = KeyboardNotificationInfo(userInfo: notification.userInfo) else { return }

            let height = self.view.convert(info.endFrame, from: nil).intersection(self.view.bounds.inset(by: self.view.safeAreaInsets)).height
            UIView.animate(withKeyboardNotificationInfo: info) {
                self.mainViewBottomConstraint.constant = height + 16
                self.view?.layoutIfNeeded()
            }
        }.store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification).sink { [weak self] notification in
            guard let self = self else { return }
            guard let info = KeyboardNotificationInfo(userInfo: notification.userInfo) else { return }

            UIView.animate(withKeyboardNotificationInfo: info) {
                self.mainViewBottomConstraint.constant = 0
                self.view?.layoutIfNeeded()
            }
        }.store(in: &cancellables)
    }
}

// MARK: MediaCarouselViewDelegate
extension ComposerViewController: MediaCarouselViewDelegate {
    func mediaCarouselView(_ view: MediaCarouselView, indexChanged newIndex: Int) {
        index = max(0, min(newIndex, media.count - 1))
        updateUI()
    }

    func mediaCarouselView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func mediaCarouselView(_ view: MediaCarouselView, didDoubleTapMediaAtIndex index: Int) {
    }

    func mediaCarouselView(_ view: MediaCarouselView, didZoomMediaAtIndex index: Int, withScale scale: CGFloat) {
    }

    @objc func openPickerAction() {
        MediaCarouselView.stopAllPlayback()

        let controller = MediaPickerViewController(config: .more, selected: media) { controller, _, media, cancel in
            controller.dismiss(animated: true)

            guard !cancel else { return }

            let assets = Set(self.media.map(\.asset))
            if let idx = media.firstIndex(where: { !assets.contains($0.asset) }) {
                // focus on the first newly added item if possible
                self.index = idx
            } else if let idx = media.firstIndex(where: { $0.asset == self.media[self.index].asset }) {
                // try to restore focus to the same item
                self.index = idx
            } else {
                self.index = 0
            }

            let beforeCount = self.media.count
            self.media = media

            if beforeCount == 0 && media.count > 0 {
                self.configureUI()
            }

            self.updateMediaState(animated: beforeCount != media.count)
        }

        present(UINavigationController(rootViewController: controller), animated: true)
    }

    @objc func deleteMediaAction() {
        media.remove(at: index)

        index = max(0, min(index, media.count - 1))

        if media.count == 0 {
            if shouldDismissWhenNoMedia() {
                backAction()
            } else {
                configureUI()
            }
        } else {
            updateMediaState(animated: true)
        }
    }

    @objc private func cropAction() {
        MediaCarouselView.stopAllPlayback()

        guard 0 <= index, index < media.count else {
            DDLogDebug("ComposerViewController/cropAction index out of bounds")
            return
        }

        let controller = MediaEditViewController(config: .crop, mediaToEdit: [media[index]], selected: 0) { controller, media, selected, cancel in
            controller.dismiss(animated: true)

            guard !cancel else { return }

            self.media[self.index] = media[0]
            self.updateMediaState(animated: false)
        }

        present(controller.withNavigationController(), animated: true)
    }

    @objc private func annotateAction() {
        MediaCarouselView.stopAllPlayback()

        guard 0 <= index, index < media.count else {
            DDLogDebug("ComposerViewController/annotateAction index out of bounds")
            return
        }

        let controller = MediaEditViewController(config: .annotate, mediaToEdit: [media[index]], selected: 0) { controller, media, selected, cancel in
            controller.dismiss(animated: true)

            guard !cancel else { return }

            self.media[self.index] = media[0]
            self.updateMediaState(animated: false)
        }

        present(controller.withNavigationController(), animated: true)
    }

    @objc private func drawAction() {
        MediaCarouselView.stopAllPlayback()

        guard 0 <= index, index < media.count else {
            DDLogDebug("ComposerViewController/drawAction index out of bounds")
            return
        }

        let controller = MediaEditViewController(config: .draw, mediaToEdit: [media[index]], selected: 0) { controller, media, selected, cancel in
            controller.dismiss(animated: true)

            guard !cancel else { return }

            self.media[self.index] = media[0]
            self.updateMediaState(animated: false)
        }

        present(controller.withNavigationController(), animated: true)
    }

    @objc
    private func cancelAction(_ sender: UIBarButtonItem) {
        onCancel?()
    }

    private func updateMediaState(animated: Bool) {
        let items = media.map { FeedMedia($0, feedPostId: "") }
        mediaCarouselView.refreshData(media: items, index: index, animated: animated)
        listenForMediaErrors()
        updateUI()
    }
}

// MARK: UITextViewDelegate
extension ComposerViewController: ContentTextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if let contentTextView = textView as? ContentTextView {

            if (contentTextView.shouldChangeMentionText(in: range, text: text)) {
                return true
            } else {
                updateUI()
                return false
            }
        } else {
            return true
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        input.text = textView.text ?? ""

        if let contentTextView = textView as? ContentTextView {
            input.mentions = contentTextView.mentions
        }

        updateUI()
        updateLinkIfNecessary()
        updateWithMarkdown(textView)
        updateWithMention(textView)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        input.selectedRange = textView.selectedRange
    }

    // MARK: ContentTextViewDelegate
    func textViewShouldDetectLink(_ textView: ContentTextView) -> Bool {
        return false
    }

    func textView(_ textView: ContentTextView, didPaste image: UIImage) {
    }

    private func updateWithMarkdown(_ textView: UITextView) {
        guard textView.markedTextRange == nil else { return } // account for IME
        let font = textView.font ?? UIFont.preferredFont(forTextStyle: .body)
        let color = ComposerConstants.textViewTextColor

        let ham = HAMarkdown(font: font, color: color)
        if let text = textView.text {
            if let selectedRange = textView.selectedTextRange {
                textView.attributedText = ham.parseInPlace(text)
                textView.selectedTextRange = selectedRange
            }
        }
    }

    private func updateLinkIfNecessary() {
        if let url = detectLink() {
            link = url.absoluteString
        } else {
            link = ""
        }
    }

    private func detectLink() -> URL? {
        let text = input.text
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

        return matches.first?.url
    }
}

// MARK: TextComposerDelegate
extension ComposerViewController: TextComposerDelegate {
    func textComposer(_ textComposerView: TextComposerView, didUpdate data: LinkPreviewData?, andImage image: UIImage?) {
        linkPreviewData = data
        linkPreviewImage = image
    }

    func textComposer(_ textComposerView: TextComposerView, didSelect mention: MentionableUser) {
        updateUI()
    }

    func textComposerDidTapPreviewLink(_ textComposerView: TextComposerView) {
        if let url = linkPreviewData?.url {
            URLRouter.shared.handleOrOpen(url: url)
        }
    }
}

// MARK: UnifiedComposerViewDelegate

extension ComposerViewController: UnifiedComposerViewDelegate {

    func unifiedComposer(_ unifiedComposerView: UnifiedComposerView, didUpdate data: LinkPreviewData?, andImage image: UIImage?) {
        linkPreviewData = data
        linkPreviewImage = image
    }

    func unifiedComposer(_ unifiedComposerView: UnifiedComposerView, didSelect mention: MentionableUser) {
        updateUI()
    }

    func unifiedComposerDidTapPreviewLink(_ unifiedComposerView: UnifiedComposerView) {
        if let url = linkPreviewData?.url {
            URLRouter.shared.handleOrOpen(url: url)
        }
    }

    func unifiedComposerOpenMediaPicker(_ unifiedComposerView: UnifiedComposerView) {
        openPickerAction()
    }

    func unifiedComposerStopRecording(_ unifiedComposerView: UnifiedComposerView) {
        if audioRecorder.isRecording {
            audioRecorder.stop(cancel: false)
        }
    }
}

// MARK: Mentions

extension ComposerViewController {
    private func updateWithMention(_ textView: UITextView) {
        guard input.mentions.isEmpty == false,
        let selected = textView.selectedTextRange
        else {
            return
        }
        let defaultFont = textView.font ?? UIFont.preferredFont(forTextStyle: .body)
        let defaultColor = textView.textColor ?? .label
        let attributedString = NSMutableAttributedString(attributedString: textView.attributedText)
        for range in input.mentions.keys {
            attributedString.setAttributes([
                .font: defaultFont,
                .strokeWidth: -3,
                .foregroundColor: defaultColor,
            ], range: range)
        }
        textView.attributedText = attributedString
        textView.selectedTextRange = selected
    }

    private func mentionableUsers() -> [MentionableUser] {
        guard let candidateRange = input.rangeOfMentionCandidateAtCurrentPosition() else {
            return []
        }

        let mentionCandidate = input.text[candidateRange]
        let trimmedInput = String(mentionCandidate.dropFirst())


        let mentionableUsers: [MentionableUser]
        switch config.destination {
        case .feed(let privacyListType):
            mentionableUsers = Mentions.mentionableUsersForNewPost(privacyListType: privacyListType)
        case .group(let id, _):
            mentionableUsers = Mentions.mentionableUsers(forGroupID: id, in: MainAppContext.shared.feedData.viewContext)
        case .contact:
            mentionableUsers = []
        }

        return mentionableUsers.filter {
            Mentions.isPotentialMatch(fullName: $0.fullName, input: trimmedInput)
        }
    }
}

// MARK: AudioRecorderControlViewDelegate
extension ComposerViewController: AudioRecorderControlViewDelegate {
    func audioRecorderControlViewShouldStart(_ view: AudioRecorderControlView) -> Bool {
        guard !MainAppContext.shared.callManager.isAnyCallActive else {
            alertMicrophoneAccessDeniedDuringCall()
            return false
        }

        return true
    }

    func audioRecorderControlViewStarted(_ view: AudioRecorderControlView) {
        audioRecorder.start()
    }

    func audioRecorderControlViewFinished(_ view: AudioRecorderControlView, cancel: Bool) {
        audioRecorder.stop(cancel: cancel)
    }

    func audioRecorderControlViewLocked(_ view: AudioRecorderControlView) {
        audioRecorderControlsLocked = true
        updateUI()
    }

    private func alertMicrophoneAccessDeniedDuringCall() {
        let alert = UIAlertController(title: Localizations.failedActionDuringCallTitle,
                                    message: Localizations.failedActionDuringCallNoticeText,
                             preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: { _ in }))
        present(alert, animated: true)
    }
}

// MARK: AudioRecorderDelegate
extension ComposerViewController: AudioRecorderDelegate {
    func audioRecorderMicrophoneAccessDenied(_ recorder: AudioRecorder) {
        DispatchQueue.main.async { [weak self] in
            self?.alertMicrophoneAccessDenied()
        }
    }

    func audioRecorderStarted(_ recorder: AudioRecorder) {
        DispatchQueue.main.async { [weak self] in
            self?.updateUI()
        }
    }

    func audioRecorderStopped(_ recorder: AudioRecorder) {
        DispatchQueue.main.async { [weak self] in
            self?.audioRecorderControlsLocked = false
            self?.saveRecording()
            self?.updateUI()
        }
    }

    func audioRecorderInterrupted(_ recorder: AudioRecorder) {
        DispatchQueue.main.async { [weak self] in
            self?.audioRecorderControlsLocked = false
            self?.saveRecording()
            self?.updateUI()
        }
    }

    func audioRecorder(_ recorder: AudioRecorder, at time: String) {
        DispatchQueue.main.async { [weak self] in
            self?.updateUI()
        }
    }

    private func alertMicrophoneAccessDenied() {
        let alert = UIAlertController(title: Localizations.micAccessDeniedTitle,
                                    message: Localizations.micAccessDeniedMessage,
                             preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        alert.addAction(UIAlertAction(title: Localizations.settingsAppName, style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })

        present(alert, animated: true)
    }

    private func saveRecording() {
        guard audioRecorder.url != nil, let url = audioRecorder.saveVoicePost() else {
            return
        }

        let pendingMedia = PendingMedia(type: .audio)
        pendingMedia.fileURL = url
        pendingMedia.size = .zero
        pendingMedia.order = 0
        voiceNote = pendingMedia
    }
}

// MARK: MediaComposerTextDelegate
extension ComposerViewController: MediaComposerTextDelegate {
    func mediaComposerText(_ textView: MediaComposerTextView, didSelect mention: MentionableUser) {
        updateUI()
    }

    func mediaComposerTextStopRecording(_ textView: MediaComposerTextView) {
        if audioRecorder.isRecording {
            audioRecorder.stop(cancel: false)
        }
    }
}

// MARK: PostAudioViewDelegate
extension ComposerViewController: PostAudioViewDelegate {
    func postAudioViewDidRequestDeletion(_ postAudioView: PostAudioView) {
        let alert = UIAlertController(title: Localizations.deleteVoiceRecordingTitle, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonDelete, style: .destructive, handler: { [weak self] _ in
            self?.voiceNote = nil
            self?.updateUI()
        }))
        alert.addAction(.init(title: Localizations.buttonCancel, style: .cancel))

        present(alert, animated: true)
    }
}

// MARK: AudioComposerDelegate
extension ComposerViewController: AudioComposerDelegate {
    func audioComposerDidToggleRecording(_ audioComposerView: AudioComposerView) {
        if audioRecorder.isRecording {
            audioRecorder.stop(cancel: false)
        } else {
            audioRecorder.start()
        }
    }
}

// MARK: ComposerDestinationRowDelegate
extension ComposerViewController: ComposerDestinationRowDelegate {
    func destinationRowOpenContacts(_ destinationRowView: ComposerDestinationRowView) {
    }

    func destinationRowOpenInvites(_ destinationRowView: ComposerDestinationRowView) {
        guard ContactStore.contactsAccessAuthorized else {
            let controller = InvitePermissionDeniedViewController()
            present(UINavigationController(rootViewController: controller), animated: true)

            return
        }

        InviteManager.shared.requestInvitesIfNecessary()

        let controller = InviteViewController(manager: InviteManager.shared, dismissAction: { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        })
        present(UINavigationController(rootViewController: controller), animated: true)
    }

    func destinationRow(_ destinationRowView: ComposerDestinationRowView, selected destination: ShareDestination) {
        updateUI()
    }

    func destinationRow(_ destinationRowView: ComposerDestinationRowView, deselected destination: ShareDestination) {
        updateUI()
    }
}

private extension Localizations {

    static func mediaPrepareFailed(_ mediaCount: Int) -> String {
        let format = NSLocalizedString("media.prepare.failed.n.count", comment: "Error text displayed in post composer when some of the media selected couldn't be sent.")
        return String.localizedStringWithFormat(format, mediaCount)
    }

    static func maxVideoLengthTitle(_ maxVideoLength: TimeInterval) -> String {
        let format = NSLocalizedString("composer.max.video.length.title", value: "This video is over %.0f seconds long", comment: "Alert title in composer when a video is too long")
        return String.localizedStringWithFormat(format, maxVideoLength)
    }

    static var maxVideoLengthMessage: String {
        NSLocalizedString("composer.max.video.length.message", value: "Please select another video or tap the edit button.", comment: "Alert message in composer when a video is too long")
    }

    static var newMessageTitle: String {
        NSLocalizedString("composer.message.title", value: "New Message", comment: "Composer New Message title.")
    }

    static func newMessageSubtitle(recipient: String) -> String {
        let format = NSLocalizedString("composer.message.subtitle", value: "Sending to %@", comment: "Composer subtitle for messages.")
        return String.localizedStringWithFormat(format, recipient)
    }

    static var tapToChange: String {
        NSLocalizedString("composer.subtitle.cta", value: "Tap to change", comment: "Show the user that the title is tappable")
    }

    static var addMore: String {
        NSLocalizedString("composer.label.more", value: "Add more", comment: "Label shown when only single media item selected")
    }

    static var edit: String {
        NSLocalizedString("composer.button.edit", value: "Edit", comment: "Title on edit button")
    }

    static var deleteVoiceRecordingTitle: String {
        NSLocalizedString("composer.delete.recording.title", value: "Delete audio recording?", comment: "Title warning that a audio recording will be deleted")
    }

    static var shareWith: String {
        NSLocalizedString("composer.destinations.label", value: "Share with", comment: "Label above the list with whom you share")
    }

    static var onboardingFirstPostTitle: String {
        NSLocalizedString("composer.onboarding.post.title",
                   value: "My First Post",
                 comment: "Title of the composer during a user's very first post.")
    }
}
