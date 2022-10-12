//
//  QuotedMessageCellView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 12/23/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import Combine
import UIKit

fileprivate struct Constants {
    static let QuotedMediaSize: CGFloat = 45
}

/// For displaying reply context for flat comments.
class QuotedCommentPanel: UIView, InputContextPanel {

    static var expiredIndicator: UIImage? {
        UIImage(systemName: "hourglass.tophalf.filled")
    }

    private(set) lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(named: "NavbarClose")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = .placeholderText
        return button
    }()

    private lazy var quotedView: QuotedMessageCellView = {
        let view = QuotedMessageCellView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    init(comment: FeedPostComment, color: UIColor) {
        super.init(frame: .zero)
        preservesSuperviewLayoutMargins = true

        addSubview(quotedView)
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            quotedView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            quotedView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            quotedView.topAnchor.constraint(equalTo: topAnchor),
            quotedView.bottomAnchor.constraint(equalTo: bottomAnchor),
            closeButton.trailingAnchor.constraint(equalTo: quotedView.trailingAnchor, constant: -8),
            closeButton.topAnchor.constraint(equalTo: quotedView.topAnchor, constant: 8),
        ])

        quotedView.configureWith(comment: comment, userColorAssignment: color)
    }

    required init?(coder: NSCoder) {
        fatalError("QuotedCommentPanel coder init not implemented...")
    }
}

class QuotedMessageCellView: UIView {

    private var imageLoadingCancellable: AnyCancellable?
    lazy var mediaWidthConstraint = mediaView.widthAnchor.constraint(equalToConstant: Constants.QuotedMediaSize)
    lazy var mediaWidthConstraintHidden = mediaView.widthAnchor.constraint(equalToConstant: 0)
    lazy var mediaHeightConstraint = mediaView.heightAnchor.constraint(equalToConstant: Constants.QuotedMediaSize)
    lazy var quotedPanelMinHeightConstraint = mediaTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: Constants.QuotedMediaSize)

    var hasMedia: Bool = false  {
        didSet {
            mediaView.isHidden = !hasMedia
        }
    }

    var hasText: Bool = false  {
        didSet {
            textLabel.isHidden = !hasText
        }
    }

    private lazy var mediaView: UIImageView = {
        let mediaView = UIImageView()
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.isHidden = true
        mediaView.contentMode = .scaleAspectFill
        mediaView.clipsToBounds = true
        mediaView.layer.cornerRadius = 3
        return mediaView
    }()
    
    // For quoted messages, we truncate the message at 3 lines.
    lazy var textLabel: UILabel = {
        let textLabel = UILabel()
        textLabel.isUserInteractionEnabled = true
        textLabel.backgroundColor = .clear
        textLabel.font = .scaledSystemFont(ofSize: 13)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.isHidden = true
        textLabel.numberOfLines = 2
        textLabel.textColor = UIColor.timeHeaderText
        textLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return textLabel
    }()
    
    lazy var bubbleView: UIView = {
        let bubbleView = UIView()
        bubbleView.backgroundColor = UIColor.quotedMessageOwnBackground
        bubbleView.layer.cornerRadius = 8
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        return bubbleView
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .scaledSystemFont(ofSize: 13, weight: .bold)
        label.textColor = .secondaryLabel.withAlphaComponent(0.2)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return label
    }()

    private lazy var nameTextRow: UIStackView = {
        let vStack = UIStackView(arrangedSubviews: [ nameLabel, textLabel, UIView()])
        vStack.axis = .vertical
        vStack.alignment = .fill
        vStack.isLayoutMarginsRelativeArrangement = true
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.spacing = 2
        vStack.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
        vStack.isLayoutMarginsRelativeArrangement = true
        // Set bubble background
        vStack.insertSubview(bubbleView, at: 0)
        return vStack
    }()

    private lazy var mediaTextView: UIView = {
        let mediaTextView = UIView()
        mediaTextView.translatesAutoresizingMaskIntoConstraints = false
        mediaTextView.addSubview(mediaView)
        mediaTextView.addSubview(nameTextRow)
        return mediaTextView
    }()

    private lazy var quotedView: UIStackView = {
        let quotedView = UIStackView(arrangedSubviews: [mediaTextView])
        quotedView.axis = .horizontal
        quotedView.alignment = .fill
        quotedView.layoutMargins = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        quotedView.isLayoutMarginsRelativeArrangement = true
        quotedView.translatesAutoresizingMaskIntoConstraints = false
        quotedView.spacing = 10
        // Set bubble background
        quotedView.insertSubview(bubbleView, at: 0)
        return quotedView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        self.preservesSuperviewLayoutMargins = false
        self.addSubview(quotedView)
        quotedView.constrain([.top, .leading, .bottom, .trailing], to: self)
        bubbleView.constrain([.top, .leading, .bottom, .trailing], to: quotedView)
        NSLayoutConstraint.activate([
            mediaHeightConstraint,
            mediaView.leadingAnchor.constraint(equalTo: mediaTextView.leadingAnchor),
            mediaView.trailingAnchor.constraint(equalTo: nameTextRow.leadingAnchor, constant: -8),
            mediaView.centerYAnchor.constraint(equalTo: mediaTextView.centerYAnchor),
            nameTextRow.trailingAnchor.constraint(equalTo: mediaTextView.trailingAnchor),
            nameTextRow.topAnchor.constraint(equalTo: mediaTextView.topAnchor),
            nameTextRow.bottomAnchor.constraint(equalTo: mediaTextView.bottomAnchor),
            nameTextRow.trailingAnchor.constraint(equalTo: mediaTextView.trailingAnchor),
            quotedPanelMinHeightConstraint,
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
    }

    private func prepareForReuse() {
        hasText = false
        hasMedia = false
        mediaView.contentMode = .scaleAspectFill
        mediaView.layer.borderWidth = 0
        mediaView.image = nil
    }

    func configureWith(comment: FeedPostComment, userColorAssignment: UIColor) {
        // Download any pending media, comes in handy for media coming in while user is viewing comments
        MainAppContext.shared.feedData.downloadMedia(in: [comment])
        MainAppContext.shared.feedData.loadImages(commentID: comment.id)
        prepareForReuse()
        setNameLabel(for: comment.userId, userColorAssignment: userColorAssignment)
        configureText(text: comment.rawText, mentions: comment.mentions)
        configureMedia(media: comment.media)
        configureCell()
        textLabel.textColor = UIColor.quotedMessageText
    }

    func configureWith(message: ChatMessage, userColorAssignment: UIColor) {
        prepareForReuse()
        setNameLabel(for: message.fromUserId, userColorAssignment: userColorAssignment)
        configureText(text: message.rawText ?? "", mentions: message.mentions)
        configureMedia(media: message.media)
        configureCell()
        textLabel.textColor = UIColor.quotedMessageText
    }

    func configureWith(quoted: ChatQuoted) {
        prepareForReuse()
        if let userID = quoted.userID {
            setNameLabel(for: userID)
        }
        switch quoted.type {
        case .feedpost:
            configureQuotedFeedPost(quoted: quoted)
            textLabel.textColor = UIColor.quotedMessageText
        case .moment:
            configureQuotedMoment(quoted: quoted)
        default:
            break
        }
        configureCell()
    }

    private func configureQuotedFeedPost(quoted: ChatQuoted) {
        if let feedPostID = quoted.message?.feedPostID, let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostID, in: MainAppContext.shared.feedData.viewContext) {
            // For posts that are retracted and current user is not author, show "post deleted" view
            if (feedPost.status == .retracted || feedPost.status == .retracting) && feedPost.userID != MainAppContext.shared.userData.userId {
                configureText(text: Localizations.postDeletedLabel, mentions: quoted.orderedMentions)
            } else {
                configureText(text: quoted.rawText ?? "", mentions: quoted.orderedMentions)
                configureMedia(media: quoted.media)
            }
        } else {
            // handle post expired
            configureText(text: Localizations.postExpiredLabel, mentions: quoted.orderedMentions)
        }
    }

    private func configureQuotedMoment(quoted: ChatQuoted) {
        if quoted.userID == MainAppContext.shared.userData.userId {
            guard let media = quoted.media?.first else {
                return
            }
            hasText = true
            hasMedia = true
            textLabel.attributedText = NSAttributedString(string: Localizations.momentLabel)
            if let thumbnailData = media.previewData, media.type != .audio {
                mediaView.image = UIImage(data: thumbnailData)
            } else {
                if .image == media.type, let mediaURL = media.mediaURL {
                    if let image = UIImage(contentsOfFile: mediaURL.path) {
                        mediaView.image = image
                    } else {
                        // This should ideally never happen : issue #3031
                        configureExpiredPost(isMoment: true)
                        DDLogError("QuotedMessageCellView/configureQuotedMoment/Incoming/configureQuotedMoment/no-image/fileURL \(mediaURL)")
                    }
                }
            }
        } else {
            hasText = true
            hasMedia = true
            textLabel.attributedText = NSAttributedString(string: Localizations.momentExpiredLabel)
            mediaView.image = QuotedCommentPanel.expiredIndicator
            mediaView.layer.borderWidth = 1 / UIScreen.main.scale
            mediaView.layer.borderColor = UIColor.primaryBlackWhite.withAlphaComponent(0.25).cgColor
            mediaView.contentMode = .center
            mediaView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .regular)
            mediaView.tintColor = UIColor.primaryBlackWhite.withAlphaComponent(0.3)
            mediaView.layer.masksToBounds = true
        }
    }

    private func configureExpiredPost(isMoment: Bool) {
        hasText = true
        hasMedia = false
        if isMoment {
            textLabel.attributedText = NSAttributedString(string: Localizations.momentExpiredLabel)
        } else {
            textLabel.attributedText = NSAttributedString(string: Localizations.postExpiredLabel)
        }
    }

    // Adjusting constraint priorities here in a single place to be able to easily see relative priorities.
    private func configureCell() {
        if hasMedia {
            mediaWidthConstraint.isActive = true
            mediaWidthConstraintHidden.isActive = false
        } else {
            mediaWidthConstraintHidden.isActive = true
            mediaWidthConstraint.isActive = false
        }
    }

    private func setNameLabel(for userID: String, userColorAssignment: UIColor? = nil) {
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: userID, in: MainAppContext.shared.contactStore.viewContext)
        if let userColorAssignment = userColorAssignment {
            nameLabel.textColor = userColorAssignment.withAlphaComponent(0.8)
        }
    }

    private func configureText(text: String, mentions: [MentionData]) {
        if !text.isEmpty  {
            let textWithMentions = MainAppContext.shared.contactStore.textWithMentions(
                text,
                mentions: mentions,
                in: MainAppContext.shared.contactStore.viewContext)

            let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
            let font = UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize - 3)
            let boldFont = UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold)!, size: font.pointSize)
            if let attrText = textWithMentions?.with(font: font, color: .label) {
                let ham = HAMarkdown(font: font, color: UIColor.chatTime)
                textLabel.attributedText = ham.parse(attrText).applyingFontForMentions(boldFont)
            }
            hasText = true
            return
        }
    }

    private func configureMedia(media: Set<CommonMedia>?) {
        guard let media = media, media.count > 0 else {
            return
        }
        // Check for voice note
        if isAudioNote(media: media) {
            textLabel.attributedText = getPlaceholderMediaText(mediaType: .audio, name: media.first?.name)
            hasText = true
            return
        }
        hasMedia = media.contains { [.image, .video].contains($0.type) }
        if let media = media.first {
            showMedia(media: media)
            // if quoted comment does not contain text, we need placeholder text
            if !hasText {
                textLabel.attributedText = getPlaceholderMediaText(mediaType: media.type, name: media.name)
                hasText = true
            }
        }
    }

    private func isAudioNote(media: Set<CommonMedia>) -> Bool {
        return media.count == 1 && media.first?.type == .audio
    }

    private func showMedia(media: CommonMedia) {
        if let thumbnailData = media.previewData, media.type != .audio {
            self.mediaView.image = UIImage(data: thumbnailData)
            return
        }
        if media.mediaURL != nil {
            displayMediaView(media: media)
        } else {
            imageLoadingCancellable = media.publisher(for: \.relativeFilePath).sink { [weak self] path in
                guard let self = self else { return }
                guard path != nil else { return }
                if media.mediaURL != nil {
                    self.displayMediaView(media: media)
                }
            }
        }
    }

    private func displayMediaView(media: CommonMedia) {
        guard let mediaURL = media.mediaURL else { return }
        if media.type == .image {
            guard let image = UIImage(contentsOfFile: mediaURL.path) else { return }
            self.mediaView.image = image
        } else if media.type == .video {
            self.mediaView.image = VideoUtils.videoPreviewImage(url: mediaURL)
        }
    }

    private func getPlaceholderMediaText(mediaType: CommonMediaType, name: String?) -> NSMutableAttributedString {
        var mediaIcon: UIImage?
        var messageText = ""
        switch mediaType {
        case .image:
            mediaIcon = UIImage(named: "messagesPhoto")?.withTintColor(UIColor.quotedMessageText)
            messageText = Localizations.chatMessagePhoto
        case .video:
            mediaIcon = UIImage(named: "messagesVideo")?.withTintColor(.systemGray, renderingMode: .alwaysOriginal)
            messageText = Localizations.chatMessageVideo
        case .audio:
            mediaIcon = UIImage(systemName: "mic.fill")?.withTintColor(.systemGray, renderingMode: .alwaysOriginal)
            messageText = Localizations.chatMessageAudio
        case .document:
            mediaIcon = UIImage(systemName: "doc.fill")?.withTintColor(.systemGray, renderingMode: .alwaysOriginal)
            messageText = name ?? Localizations.chatMessageDocument
        }
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
        let font = UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize - 3)
        let result = NSMutableAttributedString(string: "")
        if let mediaIcon = mediaIcon {
            let imageSize = mediaIcon.size
            let scale = font.capHeight / imageSize.height
            let iconAttachment = NSTextAttachment(image: mediaIcon)
            iconAttachment.bounds.size = CGSize(width: ceil(imageSize.width * scale), height: ceil(imageSize.height * scale))
            result.append(NSAttributedString(attachment: iconAttachment))
            result.append(NSAttributedString(string: " "))
        }
        let ham = HAMarkdown(font: font, color: UIColor.systemGray)
        result.append(ham.parse(messageText))
        return result
    }
}
