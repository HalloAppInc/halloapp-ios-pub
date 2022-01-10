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
            textView.isHidden = !hasText
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
    
    private lazy var textView: UnselectableUITextView = {
        let textView = UnselectableUITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isHidden = true
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.dataDetectorTypes = .link
        textView.textContainerInset = UIEdgeInsets.zero
        textView.textColor = UIColor.systemGray
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .footnote)
        textView.linkTextAttributes = [.foregroundColor: UIColor.chatOwnMsg, .underlineStyle: 1]
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return textView
    }()
    
    private lazy var bubbleView: UIView = {
        let bubbleView = UIView()
        bubbleView.backgroundColor = .commentVoiceNoteBackground
        bubbleView.layer.borderWidth = 0.5
        bubbleView.layer.borderColor = UIColor.black.withAlphaComponent(0.1).cgColor
        bubbleView.layer.cornerRadius = 15
        bubbleView.layer.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        bubbleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        bubbleView.layer.shadowRadius = 4
        bubbleView.layer.shadowOpacity = 0.5
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        return bubbleView
    }()
    
    private lazy var quotedView: UIStackView = {
        let quotedView = UIStackView(arrangedSubviews: [textView, mediaView])
        quotedView.axis = .horizontal
        quotedView.alignment = .fill
        quotedView.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
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
        bubbleView.layer.shadowPath = UIBezierPath(roundedRect: bubbleView.bounds, cornerRadius: 15).cgPath
    }

    func configureWithComment(comment: FeedPostComment) {
        hasText = false
        hasMedia = false
        configureText(comment: comment)
        configureMedia(comment: comment)
        updateMediaConstraints()
    }

    private func updateMediaConstraints() {
        if hasMedia {
            mediaWidthConstraint.priority = UILayoutPriority.defaultHigh
            mediaHeightConstraint.priority = UILayoutPriority.defaultHigh
        } else {
            mediaWidthConstraint.priority = UILayoutPriority.defaultLow
            mediaHeightConstraint.priority = UILayoutPriority.defaultLow
        }
    }

    private func configureText(comment: FeedPostComment) {
        if !comment.text.isEmpty  {
            textView.text = comment.text
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
                textView.attributedText = getPlaceholderMediaText(media: media)
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
        textView.attributedText = getPlaceholderMediaText(media: media)
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
            mediaIcon = UIImage(systemName: "photo")?.withTintColor(.systemGray, renderingMode: .alwaysOriginal)
            messageText = Localizations.chatMessagePhoto
        case .video:
            mediaIcon = UIImage(systemName: "video.fill")?.withTintColor(.systemGray, renderingMode: .alwaysOriginal)
            messageText = Localizations.chatMessageVideo
        case .audio:
            mediaIcon = UIImage(systemName: "mic.fill")?.withTintColor(.systemGray, renderingMode: .alwaysOriginal)
            messageText = Localizations.chatMessageAudio
            break
        }
        let result = NSMutableAttributedString(string: "")
        if let mediaIcon = mediaIcon {
            result.append(NSAttributedString(attachment: NSTextAttachment(image: mediaIcon)))
            result.append(NSAttributedString(string: " "))
        }
        let ham = HAMarkdown(font: UIFont.preferredFont(forTextStyle: .footnote), color: UIColor.systemGray)
        result.append(ham.parse(messageText))
        return result
    }
}