//
//  MessageViewCell.swift
//  HalloApp
//
//  Created by Nandini Shetty on 12/2/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//
import Combine
import Core
import UIKit

private extension Localizations {

    static var commentDeleted: String {
        NSLocalizedString("comment.deleted", value: "This comment has been deleted", comment: "Text displayed in place of deleted comment.")
    }
}

protocol MessageViewDelegate: AnyObject {
    func messageView(_ view: MediaCarouselView, forComment feedPostCommentID: FeedPostCommentID, didTapMediaAtIndex index: Int)
}

class MessageViewCell: UICollectionViewCell {
    private var audioMediaStatusCancellable: AnyCancellable?

    var MaxWidthOfMessageBubble: CGFloat { return contentView.bounds.width * 0.8 }
    var MinWidthOfMessageBubble: CGFloat { return contentView.bounds.width * 0.5 }
    var MediaViewDimention: CGFloat { return contentView.bounds.width * 0.7 }

    var feedPostCommentID: FeedPostCommentID?
    weak var delegate: MessageViewDelegate?

    lazy var rightAlignedConstraint = messageRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
    lazy var leftAlignedConstraint = messageRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
    lazy var mediaWidthConstraint = mediaCarouselView.widthAnchor.constraint(equalToConstant: MediaViewDimention)
    lazy var mediaHeightConstraint = mediaCarouselView.heightAnchor.constraint(equalToConstant: MediaViewDimention)

    var hasMedia: Bool = false  {
        didSet {
            mediaCarouselView.isHidden = !hasMedia
        }
    }

    var hasText: Bool = false  {
        didSet {
            textView.isHidden = !hasText
        }
    }

    var hasAudio: Bool = false {
        didSet {
            audioView.isHidden = !hasAudio
            audioTimeLabel.isHidden = !hasAudio
        }
    }

    var hasLinkPreview: Bool = false {
        didSet {
            linkPreviewView.isHidden = !hasLinkPreview
        }
    }

    private lazy var messageRow: UIStackView = {
        let hStack = UIStackView(arrangedSubviews: [ nameTextTimeRow ])
        hStack.axis = .horizontal
        hStack.translatesAutoresizingMaskIntoConstraints = false
        nameTextTimeRow.setContentHuggingPriority(.defaultHigh, for: .vertical)
        NSLayoutConstraint.activate([
            nameTextTimeRow.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(MaxWidthOfMessageBubble).rounded()),
            nameTextTimeRow.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(MinWidthOfMessageBubble).rounded())
        ])
        return hStack
    }()

    private lazy var nameTextTimeRow: UIStackView = {
        let vStack = UIStackView(arrangedSubviews: [ nameRow, linkPreviewView, audioView, mediaCarouselView, textView, timeRow ])
        vStack.axis = .vertical
        vStack.alignment = .fill
        vStack.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        vStack.isLayoutMarginsRelativeArrangement = true
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.spacing = 5
        // Set bubble background
        vStack.insertSubview(bubbleView, at: 0)
        return vStack
    }()

    private lazy var bubbleView: UIView = {
        let bubbleView = UIView()
        bubbleView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        bubbleView.layer.borderWidth = 0.5
        bubbleView.layer.borderColor = UIColor.black.withAlphaComponent(0.1).cgColor
        bubbleView.layer.cornerRadius = 15
        bubbleView.layer.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        bubbleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        bubbleView.layer.shadowRadius = 4
        bubbleView.layer.shadowOpacity = 0.5
        return bubbleView
    }()

    private lazy var timeRow: UIStackView = {
        let leadingSpacer = UIView()
        leadingSpacer.translatesAutoresizingMaskIntoConstraints = false
        leadingSpacer.widthAnchor.constraint(equalToConstant: 30).isActive = true
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let view = UIStackView(arrangedSubviews: [ leadingSpacer, audioTimeLabel, spacer, timeLabel ])
        view.axis = .horizontal
        view.spacing = 0
        view.isLayoutMarginsRelativeArrangement = true
        return view
    }()

    // MARK: Name Row

    private lazy var nameRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ nameLabel ])
        view.axis = .vertical
        view.spacing = 0
        view.isLayoutMarginsRelativeArrangement = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1

        label.font = UIFont.boldSystemFont(ofSize: 14)
        label.textColor = .secondaryLabel

        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()

    private lazy var textView: UnselectableUITextView = {
        let textView = UnselectableUITextView()
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.dataDetectorTypes = .link
        textView.textContainerInset = UIEdgeInsets.zero
        // TODO: Issue 1672 - Remove this negative inset
        textView.textContainerInset = UIEdgeInsets(top: 0, left: -5, bottom: 0, right: 0)
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textView.linkTextAttributes = [.foregroundColor: UIColor.chatOwnMsg, .underlineStyle: 1]
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isHidden = true
        return textView
    }()

    // MARK: Media

    private lazy var mediaCarouselView: MediaCarouselView = {
        var configuration = MediaCarouselViewConfiguration.default
        configuration.alwaysScaleToFitContent = false
        let mediaCarouselView = MediaCarouselView(media: [], configuration: configuration)
        mediaCarouselView.isHidden = true
        mediaCarouselView.delegate = self
        return mediaCarouselView
    }()

    // MARK: Audio Media

    private lazy var audioView: AudioView = {
        let audioView = AudioView()
        audioView.isHidden = true
        audioView.translatesAutoresizingMaskIntoConstraints = false
        audioView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        audioView.delegate = self
        return audioView
    }()

    // MARK: Link Preview

    private lazy var linkPreviewView: CommentLinkPreviewView = {
        let linkPreviewView = CommentLinkPreviewView(frame: .zero)
        linkPreviewView.translatesAutoresizingMaskIntoConstraints = false
        linkPreviewView.isHidden = true
        return linkPreviewView
    }()

    private lazy var audioTimeLabel: UILabel = {
        let label = UILabel()
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        label.textColor = UIColor.chatTime

        return label
    }()

    // MARK: Time

    private lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        label.textColor = UIColor.chatTime
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bubbleView.layer.shadowPath = UIBezierPath(roundedRect: bubbleView.bounds, cornerRadius: 15).cgPath
    }

    private func setupView() {
        backgroundColor = UIColor.feedBackground
        contentView.preservesSuperviewLayoutMargins = false
        contentView.addSubview(messageRow)
        messageRow.constrain([.top], to: contentView)
        messageRow.constrainMargin(anchor: .bottom, to: contentView, constant: 5, priority: UILayoutPriority(rawValue: 999))
        setupConditionalConstraints()
    }
    
    private func setupConditionalConstraints() {
        NSLayoutConstraint.activate([
            rightAlignedConstraint,
            leftAlignedConstraint,
            mediaWidthConstraint,
            mediaHeightConstraint
        ])
    }

    func configureWithComment(comment: FeedPostComment) {
        audioMediaStatusCancellable?.cancel()
        feedPostCommentID = comment.id
        timeLabel.text = comment.timestamp.chatTimestamp()
        setNameLabel(for: comment.userId)
        // Set up retracted comment
        if comment.status == .retracted || comment.status == .retracting {
            configureCell(isOwnMessage: comment.userId == MainAppContext.shared.userData.userId)
            configureRetractedComment()
            return
        }
        configureText(comment: comment)
        configureMedia(comment: comment)
        configureLinkPreviewView(comment: comment)
        configureCell(isOwnMessage: comment.userId == MainAppContext.shared.userData.userId)
    }

    private func configureRetractedComment() {
        hasText = true
        hasMedia = false
        hasAudio = false
        textView.text = Localizations.commentDeleted
        textView.textColor = UIColor.chatTime
    }
    
    // Adjusting constraint priorities here in a single place to be able to easily see relative priorities.
    private func configureCell(isOwnMessage: Bool) {
        updateMediaConstraints()
        if isOwnMessage {
            bubbleView.backgroundColor = UIColor.chatOwnBubbleBg
            textView.textColor = UIColor.chatOwnMsg
            nameRow.isHidden = true
            rightAlignedConstraint.priority = UILayoutPriority(800)
            leftAlignedConstraint.priority = UILayoutPriority(1)
        } else {
            bubbleView.backgroundColor = .secondarySystemGroupedBackground
            textView.textColor = UIColor.primaryBlackWhite
            nameRow.isHidden = false
            rightAlignedConstraint.priority = UILayoutPriority(1)
            leftAlignedConstraint.priority = UILayoutPriority(800)
        }
    }

    private func updateMediaConstraints() {
        mediaWidthConstraint.priority = UILayoutPriority.defaultLow
        mediaHeightConstraint.priority = UILayoutPriority.defaultLow
        if hasMedia || hasAudio {
            mediaWidthConstraint.priority = UILayoutPriority.defaultHigh
        }
        if hasMedia {
            mediaHeightConstraint.priority = UILayoutPriority.defaultHigh
        }
    }

    private func setNameLabel(for userID: String) {
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: userID, showPushNumber: true)
    }

    private func configureText(comment: FeedPostComment) {
        if !comment.text.isEmpty  {
            textView.text = comment.text
            hasText = true
            return
        }
        hasText = false
    }

    private func configureMedia(comment: FeedPostComment) {
        guard let commentMedia = comment.media, commentMedia.count > 0 else {
            hasMedia = false
            hasAudio = false
            return
        }
        guard let media = MainAppContext.shared.feedData.media(commentID: comment.id) else {
            hasMedia = false
            hasAudio = false
            return
        }
        // Download any pending media, comes in handy for media coming in while user is viewing comments
        MainAppContext.shared.feedData.downloadMedia(in: [comment])
        MainAppContext.shared.feedData.loadImages(commentID: comment.id)
        // Check for voice note
        if commentHasAudio(media: media) {
            configureAudio(comment: comment, audioMedia: media[0])
            return
        }
        hasMedia = true
        mediaCarouselView.configureMediaCarousel(media: media)
    }

    private func commentHasAudio(media: [FeedMedia]) -> Bool {
        if media.count == 1 && media[0].type == .audio {
            hasAudio = true
        } else {
            hasAudio = false
        }
        return hasAudio
    }

    func configureAudio(comment: FeedPostComment, audioMedia: FeedMedia) {
        if audioView.url != audioMedia.fileURL {
            audioTimeLabel.text = "0:00"
            audioView.url = audioMedia.fileURL
        }

        if !audioView.isPlaying {
            let isOwn = comment.userId == MainAppContext.shared.userData.userId
            audioView.state = comment.status == .played || isOwn ? .played : .normal
        }

        if audioMedia.fileURL == nil {
            audioView.state = .loading

            audioMediaStatusCancellable = audioMedia.mediaStatusDidChange.sink { [weak self] mediaItem in
                guard let self = self else { return }
                guard let url = mediaItem.fileURL else { return }
                self.audioView.url = url

                let isOwn = comment.userId == MainAppContext.shared.userData.userId
                self.audioView.state = comment.status == .played || isOwn ? .played : .normal
            }
        }
    }

    func configureLinkPreviewView(comment: FeedPostComment) {
        guard let feedLinkPreviews = comment.linkPreviews, let feedLinkPreview = feedLinkPreviews.first else {
            hasLinkPreview = false
            return
        }
        hasLinkPreview = true
        MainAppContext.shared.feedData.loadImages(feedLinkPreviewID: feedLinkPreview.id)
        linkPreviewView.configure(feedLinkPreview: feedLinkPreview)
    }
}

extension MessageViewCell: MediaCarouselViewDelegate {

    func mediaCarouselView(_ view: MediaCarouselView, indexChanged newIndex: Int) {
    }

    func mediaCarouselView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int) {
        if let commentID = feedPostCommentID {
            delegate?.messageView(view, forComment: commentID, didTapMediaAtIndex: index)
        }
    }

    func mediaCarouselView(_ view: MediaCarouselView, didDoubleTapMediaAtIndex index: Int) {
    }

    func mediaCarouselView(_ view: MediaCarouselView, didZoomMediaAtIndex index: Int, withScale scale: CGFloat) {
    }
}

// MARK: AudioViewDelegate
extension MessageViewCell: AudioViewDelegate {
    func audioView(_ view: AudioView, at time: String) {
        audioTimeLabel.text = time
    }
    func audioViewDidStartPlaying(_ view: AudioView) {
        guard let commentId = feedPostCommentID else { return }
        audioView.state = .played
        MainAppContext.shared.feedData.markCommentAsPlayed(commentId: commentId)
    }
    func audioViewDidEndPlaying(_ view: AudioView, completed: Bool) {
    }
}
