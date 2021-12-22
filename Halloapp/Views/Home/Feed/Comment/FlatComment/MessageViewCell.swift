//
//  MessageViewCell.swift
//  HalloApp
//
//  Created by Nandini Shetty on 12/2/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//
import UIKit
import Core

protocol MessageViewDelegate: AnyObject {
    func messageView(_ view: MediaCarouselView, forComment feedPostCommentID: FeedPostCommentID, didTapMediaAtIndex index: Int)
}

class MessageViewCell: UICollectionViewCell {
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
        let vStack = UIStackView(arrangedSubviews: [ nameRow, mediaCarouselView, textView, timeRow ])
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
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let view = UIStackView(arrangedSubviews: [ spacer, timeLabel ])
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
        // this left inset is to align the name with the text inset.
        view.layoutMargins = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 0)
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
        feedPostCommentID = comment.id
        timeLabel.text = comment.timestamp.chatTimestamp()
        setNameLabel(for: comment.userId)
        configureText(comment: comment)
        configureMedia(comment: comment)
        configureCell(isOwnMessage: comment.userId == MainAppContext.shared.userData.userId)
    }
    
    // Adjusting constraint priorities here in a single place to be able to easily see relative priorities.
    private func configureCell(isOwnMessage: Bool) {
        if !mediaCarouselView.isHidden {
            mediaWidthConstraint.priority = UILayoutPriority.defaultHigh
            mediaHeightConstraint.priority = UILayoutPriority.defaultHigh
        } else {
            mediaWidthConstraint.priority = UILayoutPriority.defaultLow
            mediaHeightConstraint.priority = UILayoutPriority.defaultLow
        }
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
            return
        }
        guard let media = MainAppContext.shared.feedData.media(commentID: comment.id) else {
            hasMedia = false
            return
        }
        hasMedia = true
        // Download any pending media, comes in handy for media coming in while user is viewing comments
        MainAppContext.shared.feedData.downloadMedia(in: [comment])
        MainAppContext.shared.feedData.loadImages(commentID: comment.id)
        mediaCarouselView.configureMediaCarousel(media: media)
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
