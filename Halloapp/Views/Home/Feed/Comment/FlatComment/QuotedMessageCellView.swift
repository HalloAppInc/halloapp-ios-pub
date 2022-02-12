//
//  QuotedMessageCellView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 12/23/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import Combine
import UIKit

fileprivate struct Constants {
    static let QuotedMediaSize: CGFloat = 40
}

class QuotedMessageCellView: UIView {

    private var imageLoadingCancellable: AnyCancellable?
    lazy var mediaWidthConstraint = mediaView.widthAnchor.constraint(equalToConstant: Constants.QuotedMediaSize)
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
        mediaView.layer.cornerRadius = 8
        return mediaView
    }()
    
    // For quoted messages, we truncate the message at 3 lines.
    lazy var textLabel: UILabel = {
        let textLabel = UILabel()
        textLabel.isUserInteractionEnabled = true
        textLabel.backgroundColor = .clear
        textLabel.font = UIFont.systemFont(ofSize: 12)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.isHidden = true
        textLabel.numberOfLines = 2
        textLabel.textColor = UIColor.chatTime
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
        label.font = UIFont.boldSystemFont(ofSize: 12)
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
        // Set bubble background
        vStack.insertSubview(bubbleView, at: 0)
        return vStack
    }()

    private lazy var quotedView: UIStackView = {
        let quotedView = UIStackView(arrangedSubviews: [mediaView, nameTextRow])
        quotedView.axis = .horizontal
        quotedView.alignment = .fill
        quotedView.layoutMargins = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        quotedView.isLayoutMarginsRelativeArrangement = true
        quotedView.translatesAutoresizingMaskIntoConstraints = false
        quotedView.spacing = 5
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
            mediaWidthConstraint,
            mediaHeightConstraint
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
    }

    func configureWithComment(comment: FeedPostComment, userColorAssignment: UIColor) {
        hasText = false
        hasMedia = false
        setNameLabel(for: comment.userId, userColorAssignment: userColorAssignment)
        configureText(comment: comment)
        configureMedia(comment: comment)
        configureCell()

        textLabel.textColor = UIColor.quotedMessageText
    }

    // Adjusting constraint priorities here in a single place to be able to easily see relative priorities.
    private func configureCell() {
        if hasMedia {
            mediaHeightConstraint.priority = UILayoutPriority.defaultHigh
        } else {
            mediaHeightConstraint.priority = UILayoutPriority.defaultLow
        }
    }

    private func setNameLabel(for userID: String, userColorAssignment: UIColor) {
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: userID, showPushNumber: true)
        nameLabel.textColor = userColorAssignment.withAlphaComponent(0.8)
    }

    private func configureText(comment: FeedPostComment) {
        if !comment.text.isEmpty  {
            let textWithMentions = MainAppContext.shared.contactStore.textWithMentions(
                comment.text,
                mentions: Array(comment.mentions ?? Set()))

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

    private func configureMedia(comment: FeedPostComment) {
        guard let commentMedia = comment.media, commentMedia.count > 0 else {
            return
        }
        guard let media = MainAppContext.shared.feedData.media(commentID: comment.id) else {
            return
        }
        // Check for voice note
        if let audioMedia = getCommentAudioMedia(media: media) {
            configureAudio(media: audioMedia)
            return
        }
        // Download any pending media, comes in handy for media coming in while user is viewing comments
        MainAppContext.shared.feedData.downloadMedia(in: [comment])
        MainAppContext.shared.feedData.loadImages(commentID: comment.id)
        hasMedia = true
        if let media = media.first {
            showMedia(media: media)
            // if quoted comment does not contain text, we need placeholder text
            if comment.text.isEmpty {
                textLabel.attributedText = getPlaceholderMediaText(media: media)
                hasText = true
            }
        }
    }

    private func getCommentAudioMedia(media: [FeedMedia]) ->  FeedMedia? {
        var audioMedia: FeedMedia?
        if media.count == 1 && media[0].type == .audio {
            audioMedia = media[0]
        }
        return audioMedia
    }

    private func configureAudio(media: FeedMedia) {
        textLabel.attributedText = getPlaceholderMediaText(media: media)
        hasText = true
    }

    private func showMedia(media: FeedMedia) {
        if media.isMediaAvailable {
            displayMediaView(media: media)
        } else {
            imageLoadingCancellable = media.imageDidBecomeAvailable.sink { [weak self] (image) in
                guard let self = self else { return }
                self.displayMediaView(media: media)
            }
        }
    }

    private func displayMediaView(media: FeedMedia) {
        if media.type == .image {
            self.mediaView.image = media.image
        } else if media.type == .video {
            guard let url = media.fileURL else { return }
            self.mediaView.image = VideoUtils.videoPreviewImage(url: url)
        }
    }

    private func getPlaceholderMediaText(media: FeedMedia) -> NSMutableAttributedString {
        var mediaIcon: UIImage?
        var messageText = ""
        switch media.type {
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
