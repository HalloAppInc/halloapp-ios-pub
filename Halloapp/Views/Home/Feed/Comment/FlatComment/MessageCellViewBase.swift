//
//  MessageViewCellBase.swift
//  HalloApp
//
//  Created by Nandini Shetty on 3/7/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit

class MessageCellViewBase: UICollectionViewCell {

    var feedPostComment: FeedPostComment?
    public var isOwnMessage: Bool = false
    public var isPreviousMessageOwnMessage: Bool = false
    public var userNameColorAssignment: UIColor = UIColor.primaryBlue
    weak var delegate: MessageViewDelegate?
    public var isReplyTriggered = false // track if swiping gesture on cell is enough to trigger reply

    // MARK: Name Row

    public lazy var nameRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ nameLabel ])
        view.axis = .vertical
        view.spacing = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isLayoutMarginsRelativeArrangement = true
        view.layoutMargins = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        return view
    }()

    public lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1

        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        label.isUserInteractionEnabled = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()
    
    public lazy var textRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ textLabel ])
        view.axis = .vertical
        view.spacing = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isLayoutMarginsRelativeArrangement = true
        view.layoutMargins = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        return view
    }()

    lazy var textLabel: TextLabel = {
        let textLabel = TextLabel()
        textLabel.isUserInteractionEnabled = true
        textLabel.backgroundColor = .clear
        textLabel.font = UIFont.systemFont(ofSize: 15)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.numberOfLines = 0
        textLabel.textColor = UIColor.primaryBlackWhite.withAlphaComponent(0.8)
        textLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return textLabel
    }()
    
    public lazy var bubbleView: UIView = {
        let bubbleView = UIView()
        bubbleView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        bubbleView.layer.borderWidth = 0.5
        bubbleView.layer.borderColor = UIColor.black.withAlphaComponent(0.1).cgColor
        bubbleView.layer.cornerRadius = 14
        bubbleView.layer.shadowColor = UIColor.black.withAlphaComponent(0.08).cgColor
        bubbleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        bubbleView.layer.shadowRadius = 1.5
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        return bubbleView
    }()

    public lazy var timeRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let view = UIStackView(arrangedSubviews: [ spacer, timeLabel ])
        view.axis = .horizontal
        view.spacing = 0
        view.isLayoutMarginsRelativeArrangement = true
        view.layoutMargins = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        return view
    }()

    public lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        label.textColor = UIColor.chatTime
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()

    // MARK: Reply Arrow
    public lazy var replyArrow: UIImageView = {
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
    
    var isCellHighlighted: Bool = false {
        didSet {
            self.backgroundColor = isCellHighlighted ? UIColor.systemBlue.withAlphaComponent(0.1) : .clear
        }
    }
    
    func markViewSelected() {
        UIView.animate(withDuration: 0.5, animations: {
            self.bubbleView.backgroundColor = .systemGray4
        })
    }

    func markViewUnselected() {
        UIView.animate(withDuration: 0.5, animations: {
            self.configureCellBackgroundColor()
        })
    }
    
    func configureCellBackgroundColor() {
        if isOwnMessage {
            bubbleView.backgroundColor = UIColor.messageOwnBackground
        } else {
            bubbleView.backgroundColor = UIColor.messageNotOwnBackground
        }
    }

    public func configureText(comment: FeedPostComment) {
        let cryptoResultString: String = FeedItemContentView.obtainCryptoResultString(for: comment.id)
        let feedPostCommentText = comment.text + cryptoResultString
        if !feedPostCommentText.isEmpty  {
            let textWithMentions = MainAppContext.shared.contactStore.textWithMentions(
                feedPostCommentText,
                mentions: Array(comment.mentions ?? Set()))

            let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
            var font = UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize)
            if comment.text.containsOnlyEmoji {
                font = UIFont.preferredFont(forTextStyle: .largeTitle)
            }
            let boldFont = UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold)!, size: font.pointSize)

            if let attrText = textWithMentions?.with(font: font, color: .label) {
                let ham = HAMarkdown(font: font, color: .label)
                textLabel.attributedText = ham.parse(attrText).applyingFontForMentions(boldFont)
            }
        } else {
            textLabel.isHidden = true
        }
    }
    
    func configureWithComment(comment: FeedPostComment, userColorAssignment: UIColor, parentUserColorAssignment: UIColor, isPreviousMessageFromSameSender: Bool) {
        feedPostComment = comment
        isOwnMessage = comment.userId == MainAppContext.shared.userData.userId
        isPreviousMessageOwnMessage = isPreviousMessageFromSameSender
        userNameColorAssignment = userColorAssignment
        nameLabel.textColor = userNameColorAssignment
        timeLabel.text = comment.timestamp.chatTimestamp()
    }
}

// MARK: UIGestureRecognizer Delegates
extension MessageCellViewBase: UIGestureRecognizerDelegate {

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

    @objc public func showUserFeedForPostAuthor() {
        if let feedPostComment = feedPostComment {
            delegate?.messageView(self, didTapUserId: feedPostComment.userId)
        }
    }

    @objc public func jumpToQuotedMsg(_ sender: UIView) {
        if let parentCommentId = feedPostComment?.parent?.id {
            delegate?.messageView(self, jumpTo: parentCommentId)
        }
    }
}
