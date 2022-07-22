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
        let imageConfig = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(systemName: "chevron.left", withConfiguration: imageConfig)?
                    .withTintColor(.primaryBlue, renderingMode: .alwaysOriginal)

        let button = UIButton(type: .custom)
        button.setImage(image, for: .normal)
        button.setTitle(Localizations.addMore, for: .normal)
        button.setTitleColor(.primaryBlue, for: .normal)
        button.addTarget(self, action: #selector(backAction), for: .touchUpInside)

        return UIBarButtonItem(customView: button)
    }()

    private lazy var closeButtonItem: UIBarButtonItem = {
        let imageConfig = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(systemName: "chevron.down", withConfiguration: imageConfig)?
                    .withTintColor(.primaryBlue, renderingMode: .alwaysOriginal)

        return UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(backAction))
    }()

    private lazy var cropButtonItem: UIBarButtonItem = {
        let imageConfig = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(systemName: "crop.rotate", withConfiguration: imageConfig)?
                    .withTintColor(.primaryBlue, renderingMode: .alwaysOriginal)

        return UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(cropAction))
    }()

    private lazy var annotateButtonItem: UIBarButtonItem = {
        let imageConfig = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(named: "Annotate")?.withTintColor(.primaryBlue, renderingMode: .alwaysOriginal)

        return UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(annotateAction))
    }()

    private lazy var drawButtonItem: UIBarButtonItem = {
        let imageConfig = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(named: "Draw")?.withTintColor(.primaryBlue, renderingMode: .alwaysOriginal)

        return UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(drawAction))
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
        mainView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
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


            let topTrailingActions = UIStackView(arrangedSubviews: [deleteButton])
            topTrailingActions.translatesAutoresizingMaskIntoConstraints = false
            topTrailingActions.axis = .horizontal
            topTrailingActions.isLayoutMarginsRelativeArrangement = true
            topTrailingActions.layoutMargins = UIEdgeInsets(top: Constants.controlSpacing, left: 0, bottom: 0, right: Constants.controlSpacing)

            return [
                MediaCarouselSupplementaryItem(anchors: [.top, .trailing], view: topTrailingActions),
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

    private lazy var textViewPlaceholder: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16)
        label.textColor = .label.withAlphaComponent(0.4)

        return label
    }()

    private lazy var textViewHeightConstraint: NSLayoutConstraint = {
        textView.heightAnchor.constraint(equalToConstant: 0)
    }()

    private lazy var textView: ContentTextView = {
        let textView = ContentTextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = self
        textView.isEditable = true
        textView.isUserInteractionEnabled = true
        textView.backgroundColor = .clear
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.font = Constants.getFontSize(textSize: input.text.count, isPostWithMedia: media.count > 0)
        textView.tintColor = .systemBlue
        textView.textColor = Constants.textViewTextColor
        textView.text = input.text
        textView.mentions = input.mentions

        textView.addSubview(textViewPlaceholder)

        NSLayoutConstraint.activate([
            textViewPlaceholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 5),
            textViewPlaceholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 9)
        ])

        return textView
    }()

    private lazy var textComposerPlaceholder: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 20)
        label.textColor = .label.withAlphaComponent(0.4)

        return label
    }()

    private lazy var textComposerView: ContentTextView = {
        let textView = ContentTextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = self
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.isUserInteractionEnabled = true
        textView.backgroundColor = .clear
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.font = Constants.getFontSize(textSize: input.text.count, isPostWithMedia: media.count > 0)
        textView.tintColor = .systemBlue
        textView.textColor = Constants.textViewTextColor
        textView.text = input.text
        textView.mentions = input.mentions

        textView.addSubview(textComposerPlaceholder)

        NSLayoutConstraint.activate([
            textComposerPlaceholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 5),
            textComposerPlaceholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 9),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 86),
        ])

        return textView
    }()

    private lazy var mentionPickerView: HorizontalMentionPickerView = {
        let picker = HorizontalMentionPickerView(config: .composer, avatarStore: MainAppContext.shared.avatarStore)
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.setContentHuggingPriority(.defaultHigh, for: .vertical)
        picker.clipsToBounds = true
        picker.isHidden = true
        picker.didSelectItem = { [weak self] item in
            guard let self = self else { return }

            if self.media.count > 0 {
                self.textView.accept(mention: item)
            } else {
                self.textComposerView.accept(mention: item)
            }

            self.updateMentionPicker()
        }

        return picker
    }()

    private lazy var audioRecorderControlView: AudioRecorderControlView = {
        let controlView = AudioRecorderControlView(configuration: .post)
        controlView.translatesAutoresizingMaskIntoConstraints = false
        controlView.delegate = self

        NSLayoutConstraint.activate([
            controlView.widthAnchor.constraint(equalToConstant: 24),
            controlView.heightAnchor.constraint(equalToConstant: 24),
        ])

        return controlView
    }()

    private lazy var audioPlayerView: PostAudioView = {
        let view = PostAudioView(configuration: .composerWithMedia)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.delegate = self
        view.isSeen = true
        view.isHidden = true

        return view
    }()

    private lazy var textFieldView: UIView = {
        let backgroundView = ShadowView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = .secondarySystemGroupedBackground
        backgroundView.layer.cornerRadius = 20
        backgroundView.layer.masksToBounds = true
        backgroundView.layer.borderWidth = 0.5
        backgroundView.layer.borderColor = UIColor.black.withAlphaComponent(0.12).cgColor
        backgroundView.layer.shadowOpacity = 1
        backgroundView.layer.shadowRadius = 1
        backgroundView.layer.shadowOffset = CGSize(width: 0, height: 1)
        backgroundView.layer.shadowPath = UIBezierPath(roundedRect: backgroundView.bounds, cornerRadius: 20).cgPath
        backgroundView.layer.shadowColor = UIColor.black.withAlphaComponent(0.04).cgColor

        let field = UIStackView(arrangedSubviews: [])
        field.translatesAutoresizingMaskIntoConstraints = false
        field.spacing = 0
        field.axis = .horizontal
        field.alignment = .center
        field.isLayoutMarginsRelativeArrangement = true
        field.layoutMargins = UIEdgeInsets(top: 7, left: 18, bottom: 7, right: 18)
        field.addSubview(backgroundView)
        field.addArrangedSubview(textView)
        field.addArrangedSubview(audioRecorderControlView)
        field.addSubview(voiceNoteTimeLabel)
        field.addSubview(stopVoiceRecordingButton)
        field.addSubview(audioPlayerView)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: field.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: field.bottomAnchor),
            voiceNoteTimeLabel.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: 28),
            voiceNoteTimeLabel.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            stopVoiceRecordingButton.centerXAnchor.constraint(equalTo: field.centerXAnchor),
            stopVoiceRecordingButton.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            audioPlayerView.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            audioPlayerView.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            audioPlayerView.centerYAnchor.constraint(equalTo: field.centerYAnchor),
        ])

        return field
    }()

    private lazy var voiceNoteTimeLabel: AudioRecorderTimeView = {
        let label = AudioRecorderTimeView()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.isHidden = true

        return label
    }()

    // note: Displays when the audio recorder is in the locked state.
    private lazy var stopVoiceRecordingButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .primaryBlue
        button.setTitle(Localizations.buttonStop, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 19)
        button.addTarget(self, action: #selector(stopVoiceRecordingAction), for: .touchUpInside)
        button.isHidden = true

        return button
    }()

    private lazy var cardView: UIView = {
        let cardView = UIView()
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .secondarySystemGroupedBackground
        cardView.layer.cornerRadius = Constants.backgroundRadius
        cardView.layer.shadowOpacity = 1
        cardView.layer.shadowColor = UIColor.black.withAlphaComponent(0.08).cgColor
        cardView.layer.shadowRadius = 8
        cardView.layer.shadowOffset = CGSize(width: 0, height: 5)

        return cardView
    }()

    private lazy var audioComposerTitle: UILabel = {
        let audioComposerTitle = UILabel()
        audioComposerTitle.translatesAutoresizingMaskIntoConstraints = false
        audioComposerTitle.font = .systemFont(ofSize: 16)
        audioComposerTitle.textColor = .audioComposerTitleText
        audioComposerTitle.text = Localizations.newAudioPost

        return audioComposerTitle
    }()

    private lazy var audioComposerHelper: UILabel = {
        let audioComposerHelper = UILabel()
        audioComposerHelper.translatesAutoresizingMaskIntoConstraints = false
        audioComposerHelper.font = .preferredFont(forTextStyle: .footnote)
        audioComposerHelper.textColor = .audioComposerHelperText
        audioComposerHelper.text = Localizations.tapToRecord

        return audioComposerHelper
    }()

    private lazy var audioComposerRecordImage: UIImage? = {
        UIImage(named: "icon_mic")?.withTintColor(.audioComposerRecordButtonBackground, renderingMode: .alwaysOriginal)
    }()

    private lazy var audioComposerStopImage: UIImage? = {
        UIImage(named: "icon_stop")?.withTintColor(.audioComposerRecordButtonForeground, renderingMode: .alwaysOriginal)
    }()

    private lazy var audioComposerRecordButton: UIButton = {
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(audioComposerRecordImage, for: .normal)
        button.backgroundColor = .audioComposerRecordButtonForeground
        button.layer.borderWidth = 2
        button.layer.borderColor = UIColor.audioComposerRecordButtonForeground.cgColor
        button.layer.cornerRadius = 38
        button.layer.shadowOpacity = 1
        button.layer.shadowColor = UIColor.black.withAlphaComponent(0.15).cgColor
        button.layer.shadowRadius = 4
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.layer.masksToBounds = false
        button.addTarget(self, action: #selector(toggleRecordingAction), for: .touchUpInside)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 76),
            button.heightAnchor.constraint(equalToConstant: 76),
        ])

        return button
    }()

    private lazy var audioComposerTimeLabel: UILabel = {
        let label = AudioRecorderTimeView()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.isHidden = true

        return label
    }()

    private lazy var audioComposerPlayerView: PostAudioView = {
        let view = PostAudioView(configuration: .composer)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.delegate = self
        view.isSeen = true
        view.isHidden = true

        return view
    }()

    private lazy var audioComposerMeterLarge: UIImageView = {
        let view = UIImageView(image: UIImage(named: "AudioRecorderLevelsLarge"))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit

        return view
    }()

    private lazy var audioComposerMeterSmall: UIImageView = {
        let view = UIImageView(image: UIImage(named: "AudioRecorderLevelsSmall"))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit

        return view
    }()

    private lazy var audioComposerMeterView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(audioComposerMeterLarge)
        view.addSubview(audioComposerMeterSmall)

        audioComposerMeterLarge.constrain(to: view)
        audioComposerMeterSmall.constrain(to: view)

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 76),
            view.heightAnchor.constraint(equalToConstant: 76),
        ])

        return view
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

    private lazy var linkPreviewView: PostComposerLinkPreviewView = {
        let linkPreviewView = PostComposerLinkPreviewView() { [weak self] resetLink, linkPreviewData, linkPreviewImage in
            guard let self = self else { return }

            self.linkPreviewView.isHidden = resetLink
            self.linkPreviewData = linkPreviewData
            self.linkPreviewImage = linkPreviewImage
        }

        linkPreviewView.translatesAutoresizingMaskIntoConstraints = false
        linkPreviewView.isHidden = true
        linkPreviewView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        return linkPreviewView
    }()

    private lazy var sendButton: UIButton = {
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        let icon = UIImage(systemName: "chevron.right", withConfiguration: iconConfig)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal)

        let attributedTitle = NSAttributedString(string: Localizations.sendTo,
                                                 attributes: [.kern: 0.5, .foregroundColor: UIColor.white])
        let disabledAttributedTitle = NSAttributedString(string: Localizations.sendTo,
                                                         attributes: [.kern: 0.5, .foregroundColor: UIColor.white])

        class LavaButton: UIButton {

            override init(frame: CGRect) {
                super.init(frame: frame)
                updateBackgrounds()
            }

            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            private func updateBackgrounds() {
                setBackgroundColor(.lavaOrange, for: .normal)
                setBackgroundColor(.label.withAlphaComponent(0.19), for: .disabled)
            }

            override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
                super.traitCollectionDidChange(previousTraitCollection)
                if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                    updateBackgrounds()
                }
            }
        }

        let button = LavaButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        // Attributed strings do not respect button title colors
        button.setAttributedTitle(attributedTitle, for: .normal)
        button.setAttributedTitle(disabledAttributedTitle, for: .disabled)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        button.setImage(icon, for: .normal)
        button.layer.cornerRadius = 22
        button.layer.masksToBounds = true
        button.contentEdgeInsets = UIEdgeInsets(top: -1.5, left: 32, bottom: 0, right: 38)

        // keep image on the right & tappable
        if case .rightToLeft = view.effectiveUserInterfaceLayoutDirection {
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -12, bottom: 0, right: 12)
            button.semanticContentAttribute = .forceLeftToRight
        } else {
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: -12)
            button.semanticContentAttribute = .forceRightToLeft
        }

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 44),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
        ])

        button.addTarget(self, action: #selector(share), for: .touchUpInside)

        return button
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

        NSLayoutConstraint.activate([
            mainView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mainView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainViewBottomConstraint,
        ])

        configureUI()

        // show the favorites education modal only once to the user
        if !AppContext.shared.userDefaults.bool(forKey: "hasFavoritesModalBeenShown") {
            AppContext.shared.userDefaults.set(true, forKey: "hasFavoritesModalBeenShown")

            let vc = FavoritesInformationViewController() { privacyListType in
                self.config.privacyListType = privacyListType
                self.config.destination = .userFeed
            }

            present(vc, animated: true)
        }

        handleKeyboardUpdates()

        audioRecorder.meter.receive(on: RunLoop.main) .sink { [weak self] (averagePower: Float, _) in
            guard let self = self else { return }
            let scale = self.convertMeterToScale(dbm: CGFloat(averagePower))
            self.audioComposerMeterLarge.transform = CGAffineTransform(scaleX: scale, y: scale)
        }.store(in: &cancellables)

        audioRecorder.meter.delay(for: .seconds(0.2), scheduler: RunLoop.main).sink { [weak self] (averagePower: Float, _) in
            guard let self = self else { return }
            let scale = self.convertMeterToScale(dbm: CGFloat(averagePower))
            self.audioComposerMeterSmall.transform = CGAffineTransform(scaleX: scale, y: scale)
        }.store(in: &cancellables)
    }

    private func convertMeterToScale(dbm: CGFloat) -> CGFloat {
        return 1.0 + 0.4 * min(1.0, max(0.0, 8 * CGFloat(pow(10.0, (0.05 * dbm)))))
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
        contentView.layoutMargins = UIEdgeInsets(top: Constants.verticalPadding, left: Constants.horizontalPadding, bottom: Constants.verticalPadding, right: Constants.horizontalPadding)

        if media.count > 0 {
            title = ""
            navigationItem.leftBarButtonItem = backButtonItem

            contentView.addArrangedSubview(mediaCarouselView)
            contentView.addArrangedSubview(mediaErrorLabel)

            bottomView.addSubview(mentionPickerView)
            bottomView.addSubview(textFieldView)
            bottomView.addSubview(sendButton)

            constraints.append(mediaCarouselHeightConstraint)
            constraints.append(mentionPickerView.leadingAnchor.constraint(equalTo: bottomView.leadingAnchor))
            constraints.append(mentionPickerView.trailingAnchor.constraint(equalTo: bottomView.trailingAnchor))
            constraints.append(mentionPickerView.topAnchor.constraint(equalTo: bottomView.topAnchor))
            constraints.append(textFieldView.leadingAnchor.constraint(equalTo: bottomView.leadingAnchor, constant: 12))
            constraints.append(textFieldView.trailingAnchor.constraint(equalTo: bottomView.trailingAnchor, constant: -12))
            constraints.append(textFieldView.topAnchor.constraint(equalTo: mentionPickerView.bottomAnchor, constant: 8))
            constraints.append(textViewHeightConstraint)
            constraints.append(sendButton.centerXAnchor.constraint(equalTo: bottomView.centerXAnchor))
            constraints.append(sendButton.topAnchor.constraint(equalTo: textFieldView.bottomAnchor, constant: 11))
            constraints.append(sendButton.bottomAnchor.constraint(equalTo: bottomView.bottomAnchor))

            textViewPlaceholder.text = Localizations.writeDescription

            listenForMediaErrors()
        } else if initialType == .voiceNote || voiceNote != nil {
            title = Localizations.fabAccessibilityVoiceNote
            navigationItem.leftBarButtonItem = closeButtonItem
            navigationItem.rightBarButtonItems = []

            cardView.addSubview(audioComposerTitle)
            cardView.addSubview(audioComposerMeterView)
            cardView.addSubview(audioComposerRecordButton)
            cardView.addSubview(audioComposerHelper)
            cardView.addSubview(audioComposerTimeLabel)
            cardView.addSubview(audioComposerPlayerView)

            contentView.addArrangedSubview(cardView)

            bottomView.addSubview(sendButton)
            bottomView.addSubview(mediaPickerButton)

            constraints.append(audioComposerTitle.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 26))
            constraints.append(audioComposerTitle.centerXAnchor.constraint(equalTo: cardView.centerXAnchor))
            constraints.append(audioComposerRecordButton.topAnchor.constraint(equalTo: audioComposerTitle.bottomAnchor, constant: 75))
            constraints.append(audioComposerRecordButton.centerXAnchor.constraint(equalTo: cardView.centerXAnchor))
            constraints.append(audioComposerHelper.topAnchor.constraint(equalTo: audioComposerRecordButton.bottomAnchor, constant: 11))
            constraints.append(audioComposerHelper.centerXAnchor.constraint(equalTo: cardView.centerXAnchor))
            constraints.append(audioComposerHelper.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -67))
            constraints.append(audioComposerTimeLabel.centerXAnchor.constraint(equalTo: audioComposerTitle.centerXAnchor))
            constraints.append(audioComposerTimeLabel.centerYAnchor.constraint(equalTo: audioComposerTitle.centerYAnchor))
            constraints.append(audioComposerPlayerView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16))
            constraints.append(audioComposerPlayerView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16))
            constraints.append(audioComposerPlayerView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor))
            constraints.append(audioComposerMeterView.centerXAnchor.constraint(equalTo: audioComposerRecordButton.centerXAnchor))
            constraints.append(audioComposerMeterView.centerYAnchor.constraint(equalTo: audioComposerRecordButton.centerYAnchor))
            constraints.append(sendButton.centerXAnchor.constraint(equalTo: bottomView.centerXAnchor))
            constraints.append(sendButton.topAnchor.constraint(equalTo: bottomView.topAnchor, constant: 8))
            constraints.append(sendButton.bottomAnchor.constraint(equalTo: bottomView.bottomAnchor))
            constraints.append(mediaPickerButton.trailingAnchor.constraint(equalTo: bottomView.trailingAnchor, constant: -14))
            constraints.append(mediaPickerButton.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor))
        } else {
            title = Localizations.fabAccessibilityTextPost
            navigationItem.leftBarButtonItem = closeButtonItem
            navigationItem.rightBarButtonItems = []

            let stack = UIStackView(arrangedSubviews: [textComposerView, linkPreviewView])
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.axis = .vertical
            stack.spacing = 8

            cardView.addSubview(stack)

            let cardWrapperView = UIView()
            cardWrapperView.translatesAutoresizingMaskIntoConstraints = false
            cardWrapperView.addSubview(cardView)

            contentView.layoutMargins = .zero
            contentView.addArrangedSubview(mentionPickerView)
            contentView.addArrangedSubview(cardWrapperView)

            bottomView.addSubview(sendButton)
            bottomView.addSubview(mediaPickerButton)

            constraints.append(contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor, constant: -16))
            constraints.append(cardWrapperView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: -12))
            constraints.append(cardWrapperView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: 12))
            constraints.append(cardWrapperView.topAnchor.constraint(equalTo: cardView.topAnchor))
            constraints.append(cardWrapperView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor))
            constraints.append(stack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12))
            constraints.append(stack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12))
            constraints.append(stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12))
            constraints.append(stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12))
            constraints.append(sendButton.centerXAnchor.constraint(equalTo: bottomView.centerXAnchor))
            constraints.append(sendButton.topAnchor.constraint(equalTo: bottomView.topAnchor, constant: 8))
            constraints.append(sendButton.bottomAnchor.constraint(equalTo: bottomView.bottomAnchor))
            constraints.append(mediaPickerButton.trailingAnchor.constraint(equalTo: bottomView.trailingAnchor, constant: -14))
            constraints.append(mediaPickerButton.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor))

            textComposerPlaceholder.text = Localizations.writePost
        }

        NSLayoutConstraint.activate(constraints)

        updateUI()
    }

    private func updateUI() {
        if media.count > 0 {
            // update complex media, text and audio ui
            updateMediaCarouselHeight()
            updateTextViewFontAndHeight()

            textView.alpha = audioRecorder.isRecording || voiceNote != nil ? 0 : 1

            audioRecorderControlView.isHidden = !input.text.isEmpty || voiceNote != nil
            textViewPlaceholder.isHidden = !input.text.isEmpty

            voiceNoteTimeLabel.isHidden = !audioRecorder.isRecording
            stopVoiceRecordingButton.isHidden = !audioRecorder.isRecording || !audioRecorderControlsLocked

            audioPlayerView.isHidden = voiceNote == nil

            if let voiceNote = voiceNote, audioPlayerView.url != voiceNote.fileURL {
                audioPlayerView.url = voiceNote.fileURL
            }

            sendButton.isEnabled = media.allSatisfy({ $0.ready.value })

            mediaReadyCancellable = Publishers.MergeMany(media.map { $0.ready }).sink { [weak self] _ in
                guard let self = self else { return }
                guard self.media.allSatisfy({ $0.ready.value }) else { return }

                self.updateMediaCarouselHeight()
                self.sendButton.isEnabled = true
            }

            guard 0 <= index, index < media.count else {
                DDLogDebug("ComposerViewController/updateUI index out of bounds")
                return
            }

            switch media[index].type {
            case .image:
                navigationItem.rightBarButtonItems = [drawButtonItem, annotateButtonItem, cropButtonItem]
            case .video:
                navigationItem.rightBarButtonItems = [cropButtonItem]
            case .audio:
                navigationItem.rightBarButtonItems = []
            }
        } else if initialType == .voiceNote || voiceNote != nil {
            // update audio only ui
            if audioRecorder.isRecording {
                audioComposerTimeLabel.isHidden = false
                audioComposerTitle.alpha = 0
                audioComposerRecordButton.backgroundColor = .audioComposerRecordButtonBackground
                audioComposerRecordButton.setImage(audioComposerStopImage, for: .normal)
                audioComposerHelper.text = Localizations.buttonStop
                audioComposerHelper.textColor = .audioComposerRecordButtonForeground
                audioComposerPlayerView.isHidden = true
                mediaPickerButton.isHidden = true
                audioComposerMeterView.isHidden = false
            } else {
                audioComposerTimeLabel.isHidden = true
                audioComposerTitle.alpha = 1
                audioComposerRecordButton.backgroundColor = .audioComposerRecordButtonForeground
                audioComposerRecordButton.setImage(audioComposerRecordImage, for: .normal)
                audioComposerRecordButton.isHidden = voiceNote != nil
                audioComposerHelper.text = Localizations.tapToRecord
                audioComposerHelper.textColor = .audioComposerHelperText
                audioComposerHelper.isHidden = voiceNote != nil
                mediaPickerButton.isHidden = voiceNote == nil
                audioComposerMeterView.isHidden = true

                audioComposerPlayerView.isHidden = voiceNote == nil

                if let voiceNote = voiceNote, audioComposerPlayerView.url != voiceNote.fileURL {
                    audioComposerPlayerView.url = voiceNote.fileURL
                }
            }

            sendButton.isEnabled = !audioRecorder.isRecording && voiceNote != nil
        } else {
            // update text only ui
            updateTextViewFontAndHeight()
            updateLinkPreviewViewIfNecessary()
            textComposerPlaceholder.isHidden = !input.text.isEmpty
            mediaPickerButton.isHidden = input.text.isEmpty
            sendButton.isEnabled = !input.text.isEmpty
        }
    }

    private func updateMediaCarouselHeight() {
        guard self.media.allSatisfy({ $0.ready.value }) else { return }

        let width = UIScreen.main.bounds.width - 4 * Constants.horizontalPadding
        let items = media.map { FeedMedia($0, feedPostId: "") }

        mediaCarouselHeightConstraint.constant = MediaCarouselView.preferredHeight(for: items, width: width)
    }

    private func updateTextViewFontAndHeight() {
        let font = Constants.getFontSize(textSize: input.text.count, isPostWithMedia: media.count > 0)

        if media.count > 0 {
            textView.font = font

            let size = textView.sizeThatFits(CGSize(width: textView.frame.size.width, height: CGFloat.greatestFiniteMagnitude))
            textViewHeightConstraint.constant = min(size.height, 86)
        } else {
            textComposerView.font = font
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

        let result = ComposerResult(config: config, input: input, voiceNote: voiceNote, media: media)
        completion(self, result, false)
    }

    @objc private func previewTapped() {
        if let url = linkPreviewData?.url {
            URLRouter.shared.handleOrOpen(url: url)
        }
    }

    @objc private func share() {
        guard !isSharing else { return }
        isSharing = true

        let mentionText = MentionText(expandedText: input.text, mentionRanges: input.mentions).trimmed()

        if let voiceNote = voiceNote {
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
        return voiceNote == nil && !(initialType == .noMedia && !input.text.isEmpty)
    }
}

// MARK: Keybord
extension ComposerViewController {
    private func handleKeyboardUpdates() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification).sink { [weak self] notification in
            guard let self = self else { return }
            guard let info = KeyboardNotificationInfo(userInfo: notification.userInfo) else { return }

            UIView.animate(withKeyboardNotificationInfo: info) {
                self.mainViewBottomConstraint.constant = -info.endFrame.height + 16
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

        let controller = MediaPickerViewController(config: .more, selected: media) { controller, _, _, media, cancel in
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

        updateMentionPicker()
        updateLinkPreviewViewIfNecessary()
        updateWithMarkdown(textView)
        updateWithMention(textView)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        input.selectedRange = textView.selectedRange
        updateMentionPicker()
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
        let color = Constants.textViewTextColor

        let ham = HAMarkdown(font: font, color: color)
        if let text = textView.text {
            if let selectedRange = textView.selectedTextRange {
                textView.attributedText = ham.parseInPlace(text)
                textView.selectedTextRange = selectedRange
            }
        }
    }

    // MARK: Link Preview

    private func updateLinkPreviewViewIfNecessary() {
        if let url = detectLink(text: textComposerView.text) {
            linkPreviewView.updateLink(url: url)
            linkPreviewView.isHidden = false
        } else {
            linkPreviewView.isHidden = true
        }
    }

    private func detectLink(text: String) -> URL? {
        let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = linkDetector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let url = text[range]
            if let url = URL(string: String(url)) {
                // We only care about the first link
                return url
            }
        }

        return nil
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

    private func updateMentionPicker() {
        let mentionables = mentionableUsers()

        // don't animate the initial load
        let shouldShow = !mentionables.isEmpty
        let shouldAnimate = mentionPickerView.isHidden != shouldShow
        mentionPickerView.updateItems(mentionables, animated: shouldAnimate)

        mentionPickerView.isHidden = !shouldShow
    }

    private func mentionableUsers() -> [MentionableUser] {
        guard let candidateRange = input.rangeOfMentionCandidateAtCurrentPosition() else {
            return []
        }

        let mentionCandidate = input.text[candidateRange]
        let trimmedInput = String(mentionCandidate.dropFirst())


        let mentionableUsers: [MentionableUser]
        switch config.destination {
        case .userFeed:
            mentionableUsers = Mentions.mentionableUsersForNewPost(privacyListType: config.privacyListType)
        case .groupFeed(let id):
            mentionableUsers = Mentions.mentionableUsers(forGroupID: id, in: MainAppContext.shared.feedData.viewContext)
        case .chat(_):
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
    @objc func toggleRecordingAction() {
        if audioRecorder.isRecording {
            audioRecorder.stop(cancel: false)
        } else {
            audioRecorder.start()
        }
    }

    func audioRecorderMicrophoneAccessDenied(_ recorder: AudioRecorder) {
        DispatchQueue.main.async { [weak self] in
            self?.alertMicrophoneAccessDenied()
        }
    }

    func audioRecorderStarted(_ recorder: AudioRecorder) {
        DispatchQueue.main.async { [weak self] in
            self?.voiceNoteTimeLabel.text = 0.formatted
            self?.audioComposerTimeLabel.text = 0.formatted
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
            self?.voiceNoteTimeLabel.text = time
            self?.audioComposerTimeLabel.text = time
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

    @objc private func stopVoiceRecordingAction() {
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

private extension Localizations {

    static var sendTo: String {
        NSLocalizedString("composer.button.send.to", value: "Send To", comment: "Send button title")
    }

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

    static let newAudioPost = NSLocalizedString("composer.audio.title",
                                                value: "New Audio",
                                                comment: "Title for audio post composer")

    static let tapToRecord = NSLocalizedString("composer.audio.instructions",
                                               value: "Tap to record",
                                               comment: "Instructions for audio post composer")
}
