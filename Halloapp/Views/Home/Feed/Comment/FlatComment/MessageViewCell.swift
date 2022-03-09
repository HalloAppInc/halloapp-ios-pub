//
//  MessageViewCell.swift
//  HalloApp
//
//  Created by Nandini Shetty on 12/2/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//
import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import UIKit

protocol MessageViewDelegate: AnyObject {
    func messageView(_ view: MediaCarouselView, forComment feedPostCommentID: FeedPostCommentID, didTapMediaAtIndex index: Int)
    func messageView(_ messageViewCell: MessageCellViewBase, replyTo feedPostCommentID: FeedPostCommentID)
    func messageView(_ messageViewCell: MessageCellViewBase, didTapUserId userId: UserID)
    func messageView(_ messageViewCell: MessageCellViewBase, jumpTo feedPostCommentID: FeedPostCommentID)
}

class MessageViewCell: MessageCellViewBase {
    private var audioMediaStatusCancellable: AnyCancellable?

    var MaxWidthOfMessageBubble: CGFloat { return contentView.bounds.width * 0.8 }
    var MinWidthOfMessageBubble: CGFloat { return contentView.bounds.width * 0.2 }
    var MinWidthOfQuotedMessageBubble: CGFloat { return contentView.bounds.width * 0.6 }
    var MediaViewDimention: CGFloat { return 170.0 }

    lazy var rightAlignedConstraint = messageRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
    lazy var leftAlignedConstraint = messageRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
    lazy var mediaWidthConstraint = mediaCarouselView.widthAnchor.constraint(equalToConstant: MediaViewDimention)
    lazy var mediaHeightConstraint = mediaCarouselView.heightAnchor.constraint(equalToConstant: MediaViewDimention)
    lazy var quotedMessageMinWidthConstraint = quotedMessageView.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(MinWidthOfQuotedMessageBubble).rounded())

    var hasMedia: Bool = false  {
        didSet {
            mediaCarouselView.isHidden = !hasMedia
        }
    }

    var hasText: Bool = false  {
        didSet {
            textLabel.isHidden = !hasText
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

    var hasQuotedComment: Bool = false {
        didSet {
            quotedMessageView.isHidden = !hasQuotedComment
        }
    }

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
    
    private lazy var audioTimeRow: UIStackView = {
        let leadingSpacer = UIView()
        leadingSpacer.translatesAutoresizingMaskIntoConstraints = false
        leadingSpacer.widthAnchor.constraint(equalToConstant: 40).isActive = true
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let view = UIStackView(arrangedSubviews: [ leadingSpacer, audioTimeLabel, spacer, timeLabel ])
        view.axis = .horizontal
        view.spacing = 0
        view.isLayoutMarginsRelativeArrangement = true
        return view
    }()

    // MARK: Quoted Message
    
    private lazy var quotedMessageView: QuotedMessageCellView = {
        let quotedMessageView = QuotedMessageCellView()
        quotedMessageView.translatesAutoresizingMaskIntoConstraints = false
        quotedMessageView.isHidden = true
        return quotedMessageView
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
        backgroundColor = UIColor.feedBackground
        contentView.preservesSuperviewLayoutMargins = false
        nameContentTimeRow.addArrangedSubview(nameRow)
        nameContentTimeRow.addArrangedSubview(quotedMessageView)
        nameContentTimeRow.addArrangedSubview(linkPreviewView)
        nameContentTimeRow.addArrangedSubview(audioView)
        nameContentTimeRow.addArrangedSubview(mediaCarouselView)
        nameContentTimeRow.addArrangedSubview(textRow)
        nameContentTimeRow.addArrangedSubview(audioTimeRow)
        contentView.addSubview(messageRow)
        messageRow.constrain([.top], to: contentView)
        messageRow.constrain(anchor: .bottom, to: contentView, priority: UILayoutPriority(rawValue: 999))
        setupConditionalConstraints()

        // Tapping on user name should take you to the user's feed
        nameLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showUserFeedForPostAuthor)))
        // Reply gesture
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(panGestureCellAction))
        panGestureRecognizer.delegate = self
        self.addGestureRecognizer(panGestureRecognizer)
        // Tapping on quoted comment should take you to the original comment
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(jumpToQuotedMsg(_:)))
        quotedMessageView.isUserInteractionEnabled = true
        quotedMessageView.addGestureRecognizer(tapGesture)
        
    }
    
    private func setupConditionalConstraints() {
        NSLayoutConstraint.activate([
            nameContentTimeRow.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(MaxWidthOfMessageBubble).rounded()),
            nameContentTimeRow.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(MinWidthOfMessageBubble).rounded()),
            rightAlignedConstraint,
            leftAlignedConstraint,
            mediaWidthConstraint,
            mediaHeightConstraint,
            quotedMessageMinWidthConstraint
        ])
    }

    override func configureWithComment(comment: FeedPostComment, userColorAssignment: UIColor, parentUserColorAssignment: UIColor, isPreviousMessageFromSameSender: Bool) {
        audioMediaStatusCancellable?.cancel()
        feedPostComment = comment
        isOwnMessage = comment.userId == MainAppContext.shared.userData.userId
        isPreviousMessageOwnMessage = isPreviousMessageFromSameSender
        userNameColorAssignment = userColorAssignment
        nameLabel.textColor = userNameColorAssignment
        timeLabel.text = comment.timestamp.chatTimestamp()
        setNameLabel(for: comment.userId)
        // Set up retracted comment
        if comment.status == .retracted || comment.status == .retracting {
            configureCell()
            configureRetractedComment()
        } else if comment.status == .rerequesting {
            configureCell()
            configureWaitingComment()
        } else if comment.status == .unsupported {
            configureCell()
            configureUnsupportedComment(comment: comment)
        } else {
            configureQuotedComment(comment: comment, parentUserColorAssignment: parentUserColorAssignment)
            configureText(comment: comment)
            configureMedia(comment: comment)
            configureLinkPreviewView(comment: comment)
            configureCell()
        }
    }

    private func configureRetractedComment() {
        hasText = true
        hasMedia = false
        hasAudio = false
        hasQuotedComment = false
        hasLinkPreview = false
        textLabel.text = Localizations.commentDeleted
        textLabel.textColor = UIColor.chatTime
    }

    private func configureWaitingComment() {
        let waitingString = "🕓 " + Localizations.feedCommentWaiting
        let attributedString = Localizations.appendLearnMoreLabel(to: waitingString)
        hasText = true
        hasMedia = false
        hasAudio = false
        hasQuotedComment = false
        hasLinkPreview = false
        textLabel.attributedText = attributedString.with(font: UIFont.preferredFont(forTextStyle: .subheadline).withItalicsIfAvailable, color: .secondaryLabel)
        textLabel.textColor = UIColor.chatTime
    }

    private func configureUnsupportedComment(comment: FeedPostComment) {
        let cryptoResultString: String = FeedItemContentView.obtainCryptoResultString(for: comment.id)
        let attributedString = NSMutableAttributedString(string: "⚠️ " + Localizations.commentIsNotSupported + cryptoResultString)
        hasText = true
        hasMedia = false
        hasAudio = false
        hasQuotedComment = false
        hasLinkPreview = false
        textLabel.attributedText = attributedString.with(font: UIFont.preferredFont(forTextStyle: .subheadline).withItalicsIfAvailable, color: .secondaryLabel)
        textLabel.textColor = UIColor.chatTime
    }
    
    // Adjusting constraint priorities here in a single place to be able to easily see relative priorities.
    private func configureCell() {
        updateMediaConstraints()
        if isOwnMessage {
            bubbleView.backgroundColor = UIColor.messageOwnBackground
            textLabel.textColor = UIColor.messageOwnText
            nameRow.isHidden = true
            rightAlignedConstraint.priority = UILayoutPriority(800)
            leftAlignedConstraint.priority = UILayoutPriority(1)
            quotedMessageView.bubbleView.backgroundColor = UIColor.quotedMessageOwnBackground
        } else {
            bubbleView.backgroundColor = UIColor.messageNotOwnBackground
            textLabel.textColor = UIColor.messageNotOwnText
            rightAlignedConstraint.priority = UILayoutPriority(1)
            leftAlignedConstraint.priority = UILayoutPriority(800)
            quotedMessageView.bubbleView.backgroundColor = UIColor.quotedMessageNotOwnBackground
            // If the message contains media, always show name
            // If the previous message was from the same user, hide name
            if hasMedia || !isPreviousMessageOwnMessage {
                nameRow.isHidden = false
            } else {
                nameRow.isHidden = true
            }
        }
    }

    private func updateMediaConstraints() {
        mediaWidthConstraint.isActive = false
        mediaHeightConstraint.isActive = false
        quotedMessageMinWidthConstraint.isActive = false
        if hasMedia || hasAudio {
            mediaWidthConstraint.isActive = true
        } else if (hasQuotedComment && quotedMessageView.hasMedia) ||  hasLinkPreview {
            // If quoted comments have media, set the min width of the comment.
            quotedMessageMinWidthConstraint .isActive = true
        }
        if hasMedia {
            mediaHeightConstraint.isActive = true
        }
    }

    private func setNameLabel(for userID: String) {
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: userID)
    }

    private func configureQuotedComment(comment: FeedPostComment, parentUserColorAssignment: UIColor) {
        if let parentComment = comment.parent {
            quotedMessageView.configureWithComment(comment: parentComment, userColorAssignment: parentUserColorAssignment)
            hasQuotedComment = true
        } else {
            hasQuotedComment = false
        }
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
        if let commentID = feedPostComment?.id {
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
        guard let commentId = feedPostComment?.id else { return }
        audioView.state = .played
        MainAppContext.shared.feedData.markCommentAsPlayed(commentId: commentId)
    }
    func audioViewDidEndPlaying(_ view: AudioView, completed: Bool) {
    }
}
