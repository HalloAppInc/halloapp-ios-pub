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
    var config: ComposerConfig
    var audience: FeedAudience?

    var input: MentionInput
    var voiceNote: PendingMedia?

    var text: MentionText?
    var media: [PendingMedia]
    var linkPreviewData: LinkPreviewData?
    var linkPreviewMedia: PendingMedia?
}

struct ComposerConfig {
    var destination: PostComposerDestination
    var mediaEditMaxAspectRatio: CGFloat?
    var maxVideoLength: TimeInterval = ServerProperties.maxFeedVideoDuration
    var privacyListType: PrivacyListType = .all

    static var userPost: ComposerConfig {
        ComposerConfig(destination: .userFeed)
    }

    static func groupPost(id groupID: GroupID) -> ComposerConfig {
        ComposerConfig(destination: .groupFeed(groupID))
    }

    static func message(id userId: UserID?) -> ComposerConfig {
        ComposerConfig(
            destination: .chat(userId),
            maxVideoLength: ServerProperties.maxChatVideoDuration
        )
    }
}

typealias ComposerViewControllerCallback = (ComposerViewController, ComposerResult, Bool) -> Void

fileprivate struct Constants {
    static let horizontalPadding = MediaCarouselViewConfiguration.default.cellSpacing * 0.5
    static let verticalPadding = MediaCarouselViewConfiguration.default.cellSpacing * 0.5
    static let controlSpacing: CGFloat = 9
    static let controlRadius: CGFloat = 17
    static let controlSize: CGFloat = 34
    static let backgroundRadius: CGFloat = 20

    static let postTextHorizontalPadding: CGFloat = 16
    static let postTextVerticalPadding: CGFloat = 10

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

    static let mainScrollCoordinateSpace = "MainScrollView"

    static func getFontSize(textSize: Int, isPostWithMedia: Bool) -> UIFont {
        return isPostWithMedia || textSize > 180 ? smallFont : largeFont
    }
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

    private var cancellables: Set<AnyCancellable> = []
    private var mediaCarouselHeightCancellable: AnyCancellable?
    private var changeDestinationAvatarCancellable: AnyCancellable?

    private let audioComposerRecorder = AudioComposerRecorder()

    private lazy var backButton: UIButton = {
        let imageColor = UIColor.label.withAlphaComponent(0.9)
        let imageConfig = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(systemName: "chevron.left", withConfiguration: imageConfig)?.withTintColor(imageColor)

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(image, for: .normal)
        button.addTarget(self, action: #selector(backAction), for: .touchUpInside)

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

    private lazy var customNavigationView: UIView = {
        let navigationRow = UIView()
        navigationRow.translatesAutoresizingMaskIntoConstraints = false
        navigationRow.addSubview(backButton)
        navigationRow.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            navigationRow.heightAnchor.constraint(equalToConstant: 44),
            backButton.leadingAnchor.constraint(equalTo: navigationRow.leadingAnchor),
            backButton.centerYAnchor.constraint(equalTo: navigationRow.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: navigationRow.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: navigationRow.centerYAnchor),
        ])

        let rowsView = UIStackView(arrangedSubviews: [navigationRow, changeDestinationRow])
        rowsView.translatesAutoresizingMaskIntoConstraints = false
        rowsView.axis = .vertical
        rowsView.alignment = .fill
        rowsView.spacing = -4
        rowsView.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        return rowsView
    }()

    private lazy var contentView: UIStackView = {
        let contentView = UIStackView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.axis = .vertical
        contentView.spacing = Constants.verticalPadding

        return contentView
    }()

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive

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
        let mainView = UIStackView(arrangedSubviews: [customNavigationView, scrollView, bottomView])
        mainView.spacing = 0
        mainView.translatesAutoresizingMaskIntoConstraints = false
        mainView.axis = .vertical

        return mainView
    }()

    private var constraints: [NSLayoutConstraint] = []

    private lazy var mainViewBottomConstraint: NSLayoutConstraint = {
        mainView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    }()

    private lazy var mediaCarouselHeightConstraint: NSLayoutConstraint = {
        mediaCarouselView.heightAnchor.constraint(equalToConstant: 128)
    }()

    private lazy var mediaCarouselView: MediaCarouselView = {
        var configuration = MediaCarouselViewConfiguration.composer
        configuration.gutterWidth = Constants.horizontalPadding
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
            deleteButton.layer.cornerRadius = Constants.controlRadius
            deleteButton.clipsToBounds = true
            deleteButton.addTarget(self, action: #selector(self.deleteMediaAction), for: .touchUpInside)
            deleteButton.insertSubview(deleteBackground, at: 0)
            if let imageView = deleteButton.imageView {
                deleteButton.bringSubviewToFront(imageView)
            }

            deleteBackground.constrain(to: deleteButton)
            NSLayoutConstraint.activate([
                deleteButton.widthAnchor.constraint(equalToConstant: Constants.controlSize),
                deleteButton.heightAnchor.constraint(equalToConstant: Constants.controlSize)
            ])

            let editBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            editBackground.translatesAutoresizingMaskIntoConstraints = false
            editBackground.isUserInteractionEnabled = false

            let editImageConfiguration = UIImage.SymbolConfiguration(pointSize: 22)
            let editImage = UIImage(systemName: "pencil.circle.fill", withConfiguration: editImageConfiguration)?.withTintColor(.white, renderingMode: .alwaysOriginal)

            let editButton = UIButton(type: .custom)
            editButton.translatesAutoresizingMaskIntoConstraints = false
            editButton.setImage(editImage, for: .normal)
            editButton.setTitle(Localizations.edit, for: .normal)
            editButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
            editButton.layer.cornerRadius = Constants.controlRadius
            editButton.clipsToBounds = true
            editButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 12)
            editButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 1, right: 6)
            editButton.addTarget(self, action: #selector(self.editMediaAction), for: .touchUpInside)
            editButton.insertSubview(editBackground, at: 0)
            if let imageView = editButton.imageView {
                editButton.bringSubviewToFront(imageView)
            }
            if let titleLabel = editButton.titleLabel {
                editButton.bringSubviewToFront(titleLabel)
            }

            editBackground.constrain(to: editButton)
            NSLayoutConstraint.activate([
                editButton.heightAnchor.constraint(equalToConstant: Constants.controlSize)
            ])

            let topTrailingActions = UIStackView(arrangedSubviews: [deleteButton])
            topTrailingActions.translatesAutoresizingMaskIntoConstraints = false
            topTrailingActions.axis = .horizontal
            topTrailingActions.isLayoutMarginsRelativeArrangement = true
            topTrailingActions.layoutMargins = UIEdgeInsets(top: Constants.controlSpacing, left: 0, bottom: 0, right: Constants.controlSpacing)

            let bottomTrailingActions = UIStackView(arrangedSubviews: [editButton])
            bottomTrailingActions.translatesAutoresizingMaskIntoConstraints = false
            bottomTrailingActions.axis = .horizontal
            bottomTrailingActions.isLayoutMarginsRelativeArrangement = true
            bottomTrailingActions.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: Constants.controlSpacing, right: Constants.controlSpacing)

            return [
                MediaCarouselSupplementaryItem(anchors: [.top, .trailing], view: topTrailingActions),
                MediaCarouselSupplementaryItem(anchors: [.bottom, .trailing], view: bottomTrailingActions),
            ]
        }
        configuration.pageControlViewsProvider = { [weak self] numberOfPages in
            guard let self = self else { return [] }

            var items: [MediaCarouselSupplementaryItem] = []

            if numberOfPages == 1 {
                let button = UIButton(type: .system)
                button.translatesAutoresizingMaskIntoConstraints = false
                button.setTitle(Localizations.addMore, for: .normal)
                button.setTitleColor(.label.withAlphaComponent(0.4), for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 14)
                button.addTarget(self, action: #selector(self.openPickerAction), for: .touchUpInside)

                items.append(MediaCarouselSupplementaryItem(anchors: [.trailing], view: button))
            }

            if numberOfPages < 10 {
                let imageConf = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
                let image = UIImage(systemName: "plus", withConfiguration: imageConf)
                let moreButton = UIButton(type: .custom)
                moreButton.translatesAutoresizingMaskIntoConstraints = false
                moreButton.setImage(image?.withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
                moreButton.setBackgroundColor(.composerMore, for: .normal)
                moreButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
                moreButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
                moreButton.layer.cornerRadius = 14
                moreButton.layer.masksToBounds = true
                moreButton.addTarget(self, action: #selector(self.openPickerAction), for: .touchUpInside)

                items.append(MediaCarouselSupplementaryItem(anchors: [.trailing], view: moreButton))
            }

            return items
        }

        let carouselView = MediaCarouselView(media: media.map { FeedMedia($0, feedPostId: "") }, configuration: configuration)
        carouselView.translatesAutoresizingMaskIntoConstraints = false
        carouselView.delegate = self

        return carouselView
    }()

    private lazy var mediaErrorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.textColor = .red
        label.numberOfLines = 0

        return label
    }()

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
        self.completion = completion

        audioComposerRecorder.voiceNote = voiceNote

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .feedBackground
        view.addSubview(mainView)

        NSLayoutConstraint.activate([
            mainView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mainView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainViewBottomConstraint,
        ])

        configureUI()

        switch config.destination {
        case .chat(_):
            titleLabel.text = Localizations.newMessageTitle
        default:
            titleLabel.text = Localizations.newPostTitle
        }

        MainAppContext.shared.privacySettings.feedPrivacySettingDidChange.sink { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.updateChangeDestinationBtn()
            }
        }.store(in: &cancellables)

        updateChangeDestinationBtn()

        // show the favorites education modal only once to the user
        if !AppContext.shared.userDefaults.bool(forKey: "hasFavoritesModalBeenShown") {
            AppContext.shared.userDefaults.set(true, forKey: "hasFavoritesModalBeenShown")

            let vc = FavoritesInformationViewController() { privacyListType in
                self.config.privacyListType = privacyListType
                self.config.destination = .userFeed
                self.updateChangeDestinationBtn()
            }

            present(vc, animated: true)
        }

        handleKeyboardUpdates()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    private func configureUI() {
        NSLayoutConstraint.deactivate(constraints)
        constraints.removeAll()

        if media.count > 0 {
            contentView.isLayoutMarginsRelativeArrangement = true
            contentView.layoutMargins = UIEdgeInsets(top: Constants.verticalPadding, left: Constants.horizontalPadding, bottom: Constants.verticalPadding, right: Constants.horizontalPadding)

            contentView.addArrangedSubview(mediaCarouselView)
            constraints.append(mediaCarouselHeightConstraint)

            updateMediaCarouselHeight()

            contentView.addArrangedSubview(mediaErrorLabel)

            listenForMediaErrors()

            // media > 0
            //   contentView
            //     carouselView
            //     failed items warning
            //   bottomView
            //     textView
        } else if initialType == .voiceNote || audioComposerRecorder.voiceNote != nil {
            // audio only
            //   contentView
            //     card with audio buttons only
            //   bottomView height = 0
        } else {
            // text only
            //   contentView
            //     card with text only
            //   bottomView height = 0
        }

        NSLayoutConstraint.activate(constraints)
    }

    private func updateMediaCarouselHeight() {
        mediaCarouselHeightCancellable = nil

        let setHeight: () -> Void = { [weak self] in
            guard let self = self else { return }

            let width = UIScreen.main.bounds.width - 4 * Constants.horizontalPadding
            let items = self.media.map { FeedMedia($0, feedPostId: "") }

            self.mediaCarouselHeightConstraint.constant = MediaCarouselView.preferredHeight(for: items, width: width)
        }

        if media.allSatisfy({ $0.ready.value }) {
            setHeight()
        } else {
            mediaCarouselHeightCancellable = Publishers.MergeMany(media.map { $0.ready }).sink { [weak self] _ in
                guard let self = self else { return }

                if self.media.allSatisfy({ $0.ready.value }) {
                    setHeight()
                }
            }
        }
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

        let result = ComposerResult(config: config, input: input, voiceNote: audioComposerRecorder.voiceNote, media: media)
        completion(self, result, false)
    }

    @objc private func previewTapped() {
        if let url = linkPreviewData?.url {
            URLRouter.shared.handleOrOpen(url: url)
        }
    }

    @objc private func changeDestinationAction() {
        if case .chat = config.destination {
            return
        }

        let controller = ChangeDestinationViewController(destination: config.destination, privacyListType: config.privacyListType) { controller, destination, privacyListType in
            controller.dismiss(animated: true)

            // ALWAYS change privacyListType before destination
            self.config.privacyListType = privacyListType
            self.config.destination = destination
            self.updateChangeDestinationBtn()
        }

        present(UINavigationController(rootViewController: controller), animated: true)
    }

    private func updateChangeDestinationBtn() {
        changeDestinationIcon.isHidden = false
        changeDestinationIcon.layer.cornerRadius = 0
        changeDestinationIcon.layer.masksToBounds = false
        changeDestinationAvatarCancellable?.cancel()

        switch config.destination {
        case .userFeed:
            let privacy = config.privacyListType

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
        case .chat(let userId):
            changeDestinationIcon.isHidden = true

            if let userId = userId {
                let name = MainAppContext.shared.contactStore.fullName(for: userId, in: MainAppContext.shared.contactStore.viewContext)
                changeDestinationLabel.text = Localizations.newMessageSubtitle(recipient: name)
            }
        }
    }

    private func share() {
        guard !isSharing else { return }
        isSharing = true

        let mentionText = MentionText(expandedText: input.text, mentionRanges: input.mentions).trimmed()

        if let voiceNote = audioComposerRecorder.voiceNote {
            media.append(voiceNote)
        }

        let feedAudience = try! MainAppContext.shared.privacySettings.feedAudience(for: config.privacyListType)

        // if no link preview or link preview not yet loaded, send without link preview.
        // if the link preview does not have an image... send immediately
        if link == "" || linkPreviewData == nil ||  linkPreviewImage == nil {
            let result = ComposerResult(config: config, audience: feedAudience, input: input, text: mentionText, media: media, linkPreviewData: linkPreviewData)
            completion(self, result, true)
        } else {
            // if link preview has an image, load the image before sending.
            loadLinkPreviewImageAndShare(mentionText: mentionText, mediaItems: media, feedAudience: feedAudience)
        }
    }

    private func loadLinkPreviewImageAndShare(mentionText: MentionText, mediaItems: [PendingMedia], feedAudience: FeedAudience) {
        // Send link preview with image in it
        let linkPreviewMedia = PendingMedia(type: .image)
        linkPreviewMedia.image = linkPreviewImage

        if linkPreviewMedia.ready.value {
            let result = ComposerResult(
                config: config,
                audience: feedAudience,
                input: input,
                text: mentionText,
                media: media,
                linkPreviewData: linkPreviewData,
                linkPreviewMedia: linkPreviewMedia)

            completion(self, result, true)
        } else {
            linkPreviewMedia.ready.sink { [weak self] ready in
                guard let self = self else { return }
                guard ready else { return }

                let result = ComposerResult(
                    config: self.config,
                    audience: feedAudience,
                    input: self.input,
                    text: mentionText,
                    media: self.media,
                    linkPreviewData: self.linkPreviewData,
                    linkPreviewMedia: linkPreviewMedia)

                self.completion(self, result, true)
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
        return audioComposerRecorder.voiceNote == nil && !(initialType == .noMedia && !input.text.isEmpty)
    }
}

// MARK: Keybord
extension ComposerViewController {
    private func handleKeyboardUpdates() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification).sink { [weak self] notification in
            guard let self = self else { return }
            guard let info = KeyboardNotificationInfo(userInfo: notification.userInfo) else { return }

            UIView.animate(withKeyboardNotificationInfo: info) {
                self.mainViewBottomConstraint.constant = -info.endFrame.height
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
        self.index = newIndex
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

        let controller = MediaPickerViewController(config: .more, selected: media) { controller, _, _, media, cancel in
            guard !cancel else { return }

            let assets = Set(self.media.map(\.asset))
            if let idx = media.firstIndex(where: { assets.contains($0.asset) }) {
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

            self.updateMediaState(animated: beforeCount != media.count)
        }

        present(UINavigationController(rootViewController: controller), animated: true)
    }

    @objc func deleteMediaAction() {
        media.remove(at: index)

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

    @objc func editMediaAction() {
        MediaCarouselView.stopAllPlayback()

        let controller = MediaEditViewController(mediaToEdit: media, selected: index) { controller, media, selected, cancel in
            controller.dismiss(animated: true)

            guard !cancel else { return }

            let beforeCount = self.media.count

            self.media = media
            self.index = selected

            if media.count == 0 {
                if self.shouldDismissWhenNoMedia() {
                    self.backAction()
                } else {
                    self.configureUI()
                }
            } else {
                self.updateMediaState(animated: beforeCount != media.count)
            }
        }

        present(controller.withNavigationController(), animated: true)
    }

    private func updateMediaState(animated: Bool) {
        let items = media.map { FeedMedia($0, feedPostId: "") }
        mediaCarouselView.refreshData(media: items, index: index, animated: animated)
        updateMediaCarouselHeight()
        listenForMediaErrors()
    }
}

private extension Localizations {

    static var writeDescription: String {
        NSLocalizedString("composer.placeholder.media.description", value: "Write a description", comment: "Placeholder text for media caption field in post composer.")
    }

    static var writePost: String {
        NSLocalizedString("composer.placeholder.text.post", value: "Write a post", comment: "Placeholder text in text post composer screen.")
    }

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
        NSLocalizedString("composer.delete.recording.title", value: "Delete voice recording?", comment: "Title warning that a voice recording will be deleted")
    }
}
