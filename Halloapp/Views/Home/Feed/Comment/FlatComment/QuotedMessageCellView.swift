//
//  QuotedMessageCellView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 12/23/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import Combine
import UIKit

fileprivate struct Constants {
    static let QuotedMediaSize: CGFloat = 45
}

/// For displaying reply context for flat comments.
class QuotedCommentPanel: UIView, InputContextPanel {
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
        mediaView.layer.cornerRadius = 4
        return mediaView
    }()
    
    // For quoted messages, we truncate the message at 3 lines.
    lazy var textLabel: UILabel = {
        let textLabel = UILabel()
        textLabel.isUserInteractionEnabled = true
        textLabel.backgroundColor = .clear
        textLabel.font = UIFont.systemFont(ofSize: 13)
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
        bubbleView.layer.cornerRadius = 10
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        return bubbleView
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.boldSystemFont(ofSize: 13)
        label.textColor = .secondaryLabel.withAlphaComponent(0.2)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return label
    }()

    private lazy var nameTextRow: UIStackView = {
        let vStack = UIStackView(arrangedSubviews: [ nameLabel, textLabel])
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
        quotedView.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
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
            mediaView.topAnchor.constraint(equalTo: mediaTextView.topAnchor),
            mediaView.bottomAnchor.constraint(equalTo: mediaTextView.bottomAnchor),
            nameTextRow.centerYAnchor.constraint(equalTo: mediaTextView.centerYAnchor),
            nameTextRow.trailingAnchor.constraint(equalTo: mediaTextView.trailingAnchor),
            nameTextRow.trailingAnchor.constraint(equalTo: mediaTextView.trailingAnchor)
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
    }

    func configureWith(comment: FeedPostComment, userColorAssignment: UIColor) {
        // Download any pending media, comes in handy for media coming in while user is viewing comments
        MainAppContext.shared.feedData.downloadMedia(in: [comment])
        MainAppContext.shared.feedData.loadImages(commentID: comment.id)
        hasText = false
        hasMedia = false
        setNameLabel(for: comment.userId, userColorAssignment: userColorAssignment)
        configureText(text: comment.rawText, mentions: comment.mentions)
        configureMedia(media: comment.media)
        configureCell()
        textLabel.textColor = UIColor.quotedMessageText
    }

    func configureWith(message: ChatMessage) {
        hasText = false
        hasMedia = false
        setNameLabel(for: message.fromUserId)
        configureText(text: message.rawText ?? "", mentions: message.mentions)
        configureMedia(media: message.media)
        configureCell()
        textLabel.textColor = UIColor.quotedMessageText
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
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: userID, showPushNumber: true)
        if let userColorAssignment = userColorAssignment {
            nameLabel.textColor = userColorAssignment.withAlphaComponent(0.8)
        }
    }

    private func configureText(text: String, mentions: [MentionData]) {
        if !text.isEmpty  {
            let textWithMentions = MainAppContext.shared.contactStore.textWithMentions(
                text,
                mentions: mentions)

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
            textLabel.attributedText = getPlaceholderMediaText(mediaType: .audio)
            hasText = true
            return
        }
        hasMedia = true
        if let media = media.first {
            showMedia(media: media)
            // if quoted comment does not contain text, we need placeholder text
            if !hasText {
                textLabel.attributedText = getPlaceholderMediaText(mediaType: media.type)
                hasText = true
            }
        }
    }

    private func isAudioNote(media: Set<CommonMedia>) -> Bool {
        return media.count == 1 && media.first?.type == .audio
    }

    private func showMedia(media: CommonMedia) {
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

    private func getPlaceholderMediaText(mediaType: CommonMediaType) -> NSMutableAttributedString {
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
            break
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
