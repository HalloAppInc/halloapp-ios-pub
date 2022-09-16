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

protocol MessageViewCommentDelegate: AnyObject {
    func messageView(_ view: MediaListAnimatorDelegate, forComment feedPostCommentID: FeedPostCommentID, didTapMediaAtIndex index: Int)
    func messageView(_ messageViewCell: MessageCellViewBase, replyTo feedPostCommentID: FeedPostCommentID)
    func messageView(_ messageViewCell: MessageCellViewBase, didTapUserId userId: UserID)
    func messageView(_ messageViewCell: MessageCellViewBase, jumpTo feedPostCommentID: FeedPostCommentID)
    func messageView(_ messageViewCell: MessageCellViewBase, didLongPressOn feedPostComment: FeedPostComment)
    func messageView(_ messageViewCell: MessageCellViewBase, showReactionsFor feedPostComment: FeedPostComment)
}

protocol MessageViewChatDelegate: AnyObject {
    func messageView(_ messageViewCell: MessageCellViewBase, replyToChat chatMessage: ChatMessage)
    func messageView(_ messageViewCell: MessageCellViewBase, didTapUserId userId: UserID)
    func messageView(_ messageViewCell: MessageCellViewBase, didLongPressOn chatMessage: ChatMessage)
    func messageView(_ messageViewCell: MessageCellViewBase, jumpTo chatMessageID: ChatMessageID)
    func messageView(_ messageViewCell: MessageCellViewBase, for chatMessageID: ChatMessageID, didTapMediaAtIndex index: Int)
    func messageView(_ messageViewCell: MessageCellViewBase, openPost feedPostId: String)
    func messageView(_ messageViewCell: MessageCellViewBase, openDocument documentURL: URL)
    func messageView(_ messageViewCell: MessageCellViewBase, didCompleteVoiceNote chatMessageID: ChatMessageID)
    func messageView(_ messageViewCell: MessageCellViewBase, showReactionsFor chatMessage: ChatMessage)
    func messageView(_ messageViewCell: MessageCellViewBase, forwardingMessage chatMessage: ChatMessage)
}

class MessageViewCell: MessageCellViewBase {
    private var audioMediaStatusCancellable: AnyCancellable?

    var MaxWidthOfMessageBubble: CGFloat { return contentView.bounds.width * 0.8 }
    var MinWidthOfMessageBubble: CGFloat { return contentView.bounds.width * 0.2 }
    var MinWidthOfQuotedMediaMessageBubble: CGFloat { return contentView.bounds.width * 0.6 }
    var MinWidthOfQuotedMessageBubble: CGFloat { return contentView.bounds.width * 0.4 }
    var MediaViewDimention: CGFloat { return 238.0 }

    var hasText: Bool = false  {
        didSet {
            textLabel.isHidden = !hasText
        }
    }

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
        nameContentTimeRow.addArrangedSubview(textRow)
        nameContentTimeRow.addArrangedSubview(timeRow)
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
        
    }
    
    private func setupConditionalConstraints() {
        NSLayoutConstraint.activate([
            nameContentTimeRow.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(MaxWidthOfMessageBubble).rounded()),
            nameContentTimeRow.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(MinWidthOfMessageBubble).rounded()),
            rightAlignedConstraint,
            leftAlignedConstraint,
        ])
    }

    override func configureWith(comment: FeedPostComment, userColorAssignment: UIColor, parentUserColorAssignment: UIColor, isPreviousMessageFromSameSender: Bool) {
        audioMediaStatusCancellable?.cancel()
        setNameLabel(for: comment.userId)
        super.configureWith(comment: comment, userColorAssignment: userColorAssignment, parentUserColorAssignment: parentUserColorAssignment, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
        configureCell()
        // Set up retracted comment
        if comment.status == .retracted || comment.status == .retracting {
            configureRetracted(text: Localizations.commentDeleted)
        } else if comment.status == .rerequesting {
            configureWaiting(text: Localizations.feedCommentWaiting)
        } else if comment.status == .unsupported {
            let cryptoResultString: String = FeedItemContentView.obtainCryptoResultString(for: comment.id)
            configureUnsupportedComment(text: Localizations.commentIsNotSupported + cryptoResultString)
        }
    }

    override func configureWith(message: ChatMessage, isPreviousMessageFromSameSender: Bool) {
        timeLabel.text = message.timestamp?.chatDisplayTimestamp()
        super.configureWith(message: message, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
        configureCell()
        if [.retracted, .retracting].contains(message.outgoingStatus) || [.retracted].contains(message.incomingStatus) {
            configureRetracted(text: Localizations.chatMessageDeleted)
        } else if message.incomingStatus == .rerequesting {
            configureWaiting(text: Localizations.chatMessageWaiting)
        } else if message.incomingStatus == .unsupported {
            configureUnsupportedComment(text: Localizations.chatMessageUnsupported)
        }
    }

    private func configureRetracted(text: String) {
        hasText = true
        textLabel.text = text
        textLabel.textColor = UIColor.chatTime
    }

    private func configureWaiting(text: String) {
        let waitingString = "🕓 " + text
        let attributedString = Localizations.appendLearnMoreLabel(to: waitingString)
        hasText = true
        textLabel.attributedText = attributedString.with(font: UIFont.preferredFont(forTextStyle: .subheadline).withItalicsIfAvailable, color: .secondaryLabel)
        textLabel.textColor = UIColor.chatTime
    }

    private func configureUnsupportedComment(text: String) {
        let attributedString = NSMutableAttributedString(string: "⚠️ " +  text)
        hasText = true
        textLabel.attributedText = attributedString.with(font: UIFont.preferredFont(forTextStyle: .subheadline).withItalicsIfAvailable, color: .secondaryLabel)
        textLabel.textColor = UIColor.chatTime
    }

    // Adjusting constraint priorities here in a single place to be able to easily see relative priorities.
    override func configureCell() {
        super.configureCell()
    }

    private func setNameLabel(for userID: String) {
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: userID, in: MainAppContext.shared.contactStore.viewContext)
    }
}
