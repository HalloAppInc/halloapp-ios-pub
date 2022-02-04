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
import UIKit

private extension Localizations {

    static var commentDeleted: String {
        NSLocalizedString("comment.deleted", value: "This comment has been deleted", comment: "Text displayed in place of deleted comment.")
    }
}

protocol MessageViewDelegate: AnyObject {
    func messageView(_ view: MediaCarouselView, forComment feedPostCommentID: FeedPostCommentID, didTapMediaAtIndex index: Int)
    func messageView(_ messageViewCell: MessageViewCell, replyTo feedPostCommentID: FeedPostCommentID)
    func messageView(_ messageViewCell: MessageViewCell, didTapUserId userId: UserID)
    func messageView(_ messageViewCell: MessageViewCell, jumpTo feedPostCommentID: FeedPostCommentID)
}

class MessageViewCell: UICollectionViewCell {
    private var audioMediaStatusCancellable: AnyCancellable?

    var MaxWidthOfMessageBubble: CGFloat { return contentView.bounds.width * 0.8 }
    var MinWidthOfMessageBubble: CGFloat { return contentView.bounds.width * 0.5 }
    var MediaViewDimention: CGFloat { return contentView.bounds.width * 0.7 }

    var feedPostComment: FeedPostComment?
    weak var delegate: MessageViewDelegate?
    private var isReplyTriggered = false // track if swiping gesture on cell is enough to trigger reply

    private var isOwnMessage: Bool = false
    private var isPreviousMessageOwnMessage: Bool = false
    private var userNameColorAssignment: UIColor = UIColor.primaryBlue

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

    var isCellHighlighted: Bool = false {
        didSet {
            self.backgroundColor = isCellHighlighted ? UIColor.systemBlue.withAlphaComponent(0.1) : .clear
        }
    }

    private lazy var messageRow: UIStackView = {
        let hStack = UIStackView(arrangedSubviews: [ nameTextTimeRow ])
        hStack.axis = .horizontal
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.isUserInteractionEnabled = true
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.layoutMargins = UIEdgeInsets(top: 3, left: 10, bottom: 3, right: 10)
        NSLayoutConstraint.activate([
            nameTextTimeRow.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(MaxWidthOfMessageBubble).rounded()),
            nameTextTimeRow.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(MinWidthOfMessageBubble).rounded())
        ])
        return hStack
    }()

    func markViewSelected() {
        UIView.animate(withDuration: 0.5, animations: {
            self.bubbleView.backgroundColor = .systemGray4
        })
    }

    func markViewUnselected() {
        UIView.animate(withDuration: 0.5, animations: {
            self.configureCell()
        })
    }

    private lazy var nameTextTimeRow: UIStackView = {
        let vStack = UIStackView(arrangedSubviews: [ nameRow, quotedMessageView, linkPreviewView, audioView, mediaCarouselView, textLabel, timeRow ])
        vStack.axis = .vertical
        vStack.alignment = .fill
        vStack.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        vStack.isLayoutMarginsRelativeArrangement = true
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.spacing = 3
        // Set bubble background
        vStack.insertSubview(bubbleView, at: 0)
        return vStack
    }()

    private lazy var bubbleView: UIView = {
        let bubbleView = UIView()
        bubbleView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        bubbleView.layer.borderWidth = 0.5
        bubbleView.layer.borderColor = UIColor.black.withAlphaComponent(0.1).cgColor
        bubbleView.layer.cornerRadius = 16
        bubbleView.layer.shadowColor = UIColor.black.withAlphaComponent(0.08).cgColor
        bubbleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        bubbleView.layer.shadowRadius = 1.5
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

        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabel
        label.isUserInteractionEnabled = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()

    lazy var textLabel: TextLabel = {
        let textLabel = TextLabel()
        textLabel.isUserInteractionEnabled = true
        textLabel.backgroundColor = .clear
        textLabel.font = UIFont.systemFont(ofSize: 15)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.isHidden = true
        textLabel.numberOfLines = 0
        textLabel.textColor = UIColor.primaryBlackWhite.withAlphaComponent(0.8)
        return textLabel
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
    
    // MARK: Quoted Message
    
    private lazy var quotedMessageView: QuotedMessageCellView = {
        let quotedMessageView = QuotedMessageCellView()
        quotedMessageView.translatesAutoresizingMaskIntoConstraints = false
        return quotedMessageView
    }()

    // MARK: Reply Arrow

    private lazy var replyArrow: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "arrowshape.turn.up.left.fill"))
        view.tintColor = UIColor.systemGray4
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 25),
            view.heightAnchor.constraint(equalToConstant: 25)
        ])
        view.isHidden = true
        return view
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
            rightAlignedConstraint,
            leftAlignedConstraint,
            mediaWidthConstraint,
            mediaHeightConstraint
        ])
    }

    func configureWithComment(comment: FeedPostComment, userColorAssignment: UIColor, parentUserColorAssignment: UIColor, isPreviousMessageFromSameSender: Bool) {
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
            return
        }
        configureQuotedComment(comment: comment, parentUserColorAssignment: parentUserColorAssignment)
        configureText(comment: comment)
        configureMedia(comment: comment)
        configureLinkPreviewView(comment: comment)
        configureCell()
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
    
    // Adjusting constraint priorities here in a single place to be able to easily see relative priorities.
    private func configureCell() {
        updateMediaConstraints()
        if isOwnMessage {
            bubbleView.backgroundColor = UIColor.chatOwnBubbleBg
            textLabel.textColor = UIColor.chatOwnMsg
            nameRow.isHidden = true
            rightAlignedConstraint.priority = UILayoutPriority(800)
            leftAlignedConstraint.priority = UILayoutPriority(1)
        } else {
            bubbleView.backgroundColor = .secondarySystemGroupedBackground
            textLabel.textColor = UIColor.primaryBlackWhite
            rightAlignedConstraint.priority = UILayoutPriority(1)
            leftAlignedConstraint.priority = UILayoutPriority(800)
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
            let textWithMentions = MainAppContext.shared.contactStore.textWithMentions(
                comment.text,
                mentions: Array(comment.mentions ?? Set()))

            let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
            let font = UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize - 1)
            let boldFont = UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold)!, size: font.pointSize)
            if let attrText = textWithMentions?.with(font: font, color: .label) {
                let ham = HAMarkdown(font: font, color: .label)
                textLabel.attributedText = ham.parse(attrText).applyingFontForMentions(boldFont)
            }
            hasText = true
            return
        }
        hasText = false
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

// MARK: UIGestureRecognizer Delegates
extension MessageViewCell: UIGestureRecognizerDelegate {

    // used for swiping to reply
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity: CGPoint = panGestureRecognizer.velocity(in: contentView)
        if velocity.x < 0 { return false }
        return abs(velocity.x) > abs(velocity.y)
    }

    @objc func panGestureCellAction(recognizer: UIPanGestureRecognizer)  {
        guard let view = recognizer.view else { return }
        guard let superview = view.superview else { return }
        let replyArrowStartOffset:CGFloat = -25.0
        let replyArrowOffset:CGFloat = replyArrowStartOffset
        let windowWidth = self.window?.bounds.width ?? UIScreen.main.bounds.width
        let replyTriggerThreshold = windowWidth / 4.5

        // add to mainView so arrow can appear off-screen and slide in
        if !superview.subviews.contains(replyArrow) {
            superview.addSubview(replyArrow)
            replyArrow.isHidden = false

            replyArrow.trailingAnchor.constraint(equalTo: superview.leadingAnchor, constant: replyArrowStartOffset).isActive = true

            // anchor to bubbleRow since mainView can have the timestamp row also
            replyArrow.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        }

        let translation = recognizer.translation(in: view) // movement in the gesture
        let originX = view.frame.minX
        let originY = view.frame.minY

        let newViewCenter = CGPoint(x: view.center.x + translation.x, y: view.center.y)
        let newReplyArrowCenter = CGPoint(x: replyArrow.center.x + translation.x, y: replyArrow.center.y)

        if (originX + translation.x) > 0 {
            view.center = newViewCenter // move bubbleRow view
            if originX < replyTriggerThreshold {
                replyArrow.center = newReplyArrowCenter // only move reply arrow forward if it's not past threshold
            } else {
                let replyArrowCenterMaxX = replyTriggerThreshold - replyArrow.frame.width
                replyArrow.center = CGPoint(x: replyArrowCenterMaxX, y: replyArrow.center.y)
            }
        } else {
            // move back to 0, barely noticeable but helps eliminate small stutter when dragging towards 0 to negatives
            view.frame = CGRect(x: 0, y: originY, width: view.frame.width, height: view.frame.height)
            replyArrow.frame = CGRect(x: replyArrowOffset, y: replyArrow.frame.origin.y, width: replyArrow.frame.width, height: replyArrow.frame.height)
        }

        recognizer.setTranslation(CGPoint(x: 0, y: 0), in: view)

        let isOriginXPastThreshold = originX > replyTriggerThreshold

        if !isReplyTriggered, isOriginXPastThreshold {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            isReplyTriggered = true
            replyArrow.tintColor = userNameColorAssignment
        }

        if !isOriginXPastThreshold {
            self.isReplyTriggered = false
            replyArrow.tintColor = UIColor.systemGray4
        }

        if recognizer.state == .ended {

            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) { [weak self] in
                guard let self = self else { return }
                view.frame = CGRect(x: 0, y: originY, width: view.frame.width, height: view.frame.height)

                self.replyArrow.frame = CGRect(x: replyArrowOffset, y: self.replyArrow.frame.origin.y, width: self.replyArrow.frame.width, height: self.replyArrow.frame.height)
            } completion: { (finished) in
                guard let feedPostCommentID = self.feedPostComment?.id else { return }

                if self.isReplyTriggered {
                    self.delegate?.messageView(self, replyTo: feedPostCommentID)
                    self.isReplyTriggered = false
                }

                if superview.subviews.contains(self.replyArrow) {
                    self.replyArrow.removeFromSuperview()
                }
            }
        }
    }

    @objc private func showUserFeedForPostAuthor() {
        if let feedPostComment = feedPostComment {
            delegate?.messageView(self, didTapUserId: feedPostComment.userId)
        }
    }
    
    @objc private func jumpToQuotedMsg(_ sender: UIView) {
        if let parentCommentId = feedPostComment?.parent?.id {
            delegate?.messageView(self, jumpTo: parentCommentId)
        }
        
    }
}
