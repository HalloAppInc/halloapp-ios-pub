//
//  MessageViewCellBase.swift
//  HalloApp
//
//  Created by Nandini Shetty on 3/7/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import Combine
import Foundation
import UIKit

class MessageCellViewBase: UICollectionViewCell {

    private var outgoingMessageStatusCancellable: AnyCancellable?
    private var reactionCancellable: AnyCancellable?

    lazy var rightAlignedConstraint = messageRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
    lazy var leftAlignedConstraint = messageRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)

    var feedPostComment: FeedPostComment?
    var chatMessage: ChatMessage?
    public var isOwnMessage: Bool = false
    public var isPreviousMessageFromSameSender: Bool = false
    public var userNameColorAssignment: UIColor = UIColor.primaryBlue
    weak var commentDelegate: MessageViewCommentDelegate?
    weak var chatDelegate: MessageViewChatDelegate?
    public var isReplyTriggered = false // track if swiping gesture on cell is enough to trigger reply
    private var highlightAnimator: UIViewPropertyAnimator?
    private var pendingMessageIconTimer: Timer? = nil

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

        label.font = .scaledSystemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        label.isUserInteractionEnabled = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh + 50, for: .horizontal)
        return label
    }()

    public lazy var forwardCountLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1

        label.font = UIFont.preferredFont(forTextStyle: .footnote).withItalicsIfAvailable
        label.textColor = .lightGray
        let result = NSMutableAttributedString(string: " ")
        if let icon = UIImage(systemName: "arrowshape.turn.up.right.fill")?.withTintColor(.lightGray) {
            let imageSize = icon.size
            let font = UIFont.scaledSystemFont(ofSize: label.font.pointSize - 1)

            let scale = font.capHeight / imageSize.height
            let iconAttachment = NSTextAttachment(image: icon)
            iconAttachment.bounds.size = CGSize(width: ceil(imageSize.width * scale), height: ceil(imageSize.height * scale))
            result.append(NSAttributedString(attachment: iconAttachment))
            result.append(NSAttributedString(string: " "))
        }
        result.append(NSAttributedString(string:Localizations.messageForwarded))

        label.attributedText = result
        label.isUserInteractionEnabled = false
        label.isHidden = true

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
            textLabel.font = UIFont.scaledSystemFont(ofSize: 15)
            textLabel.translatesAutoresizingMaskIntoConstraints = false
            textLabel.numberOfLines = 0
            textLabel.textColor = UIColor.primaryBlackWhite.withAlphaComponent(0.8)
            textLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            return textLabel
    }()

    public class ReactionViewBase: UIStackView {
        override public func layoutSubviews() {
            super.layoutSubviews()
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
        }
    }

    public lazy var bubbleBorder: ShadowView = {
        let bubbleBorder = ShadowView()
        bubbleBorder.translatesAutoresizingMaskIntoConstraints = false
        bubbleBorder.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        bubbleBorder.layer.cornerRadius = 14
        bubbleBorder.layer.shadowColor = UIColor.black.cgColor
        bubbleBorder.layer.shadowOpacity = 0.08
        bubbleBorder.layer.shadowOffset = CGSize(width: 0, height: 2)
        bubbleBorder.layer.shadowRadius = 1.5
        return bubbleBorder
    }()
    
    public lazy var bubbleView: ShadowView = {
        let bubbleView = ShadowView()
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.layer.cornerRadius = 14
        bubbleBorder.addSubview(bubbleView)
        let width = 1.0 / UIScreen.main.scale
        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: bubbleBorder.topAnchor, constant: width),
            bubbleView.bottomAnchor.constraint(equalTo: bubbleBorder.bottomAnchor, constant: -width),
            bubbleView.leadingAnchor.constraint(equalTo: bubbleBorder.leadingAnchor, constant: width),
            bubbleView.trailingAnchor.constraint(equalTo: bubbleBorder.trailingAnchor, constant: -width),
        ])
        return bubbleView
    }()
    
    public lazy var reactionBubble: UIStackView = {
        let reactionBubble = ReactionViewBase()
        reactionBubble.axis = .horizontal
        reactionBubble.spacing = -7
        reactionBubble.translatesAutoresizingMaskIntoConstraints = false
        reactionBubble.layer.borderWidth = 0.5
        reactionBubble.layer.borderColor = UIColor.black.withAlphaComponent(0.18).cgColor
        reactionBubble.layer.cornerRadius = 15
        reactionBubble.layer.shadowColor = UIColor.black.cgColor
        reactionBubble.layer.shadowOpacity = 0.08
        reactionBubble.layer.shadowOffset = CGSize(width: 0, height: 2)
        reactionBubble.layer.shadowRadius = 1.5
        reactionBubble.layoutMargins = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        reactionBubble.isLayoutMarginsRelativeArrangement = true
        reactionBubble.isHidden = true
        reactionBubble.isUserInteractionEnabled = true
        return reactionBubble
    }()

    lazy var forwardButton: UIButton = {
        let forwardButton = UIButton()
        forwardButton.addTarget(self, action: #selector(forwardAction), for: .touchUpInside)
        let image = UIImage(named: "ForwardArrow")
        forwardButton.setBackgroundImage(image, for: .normal)
        forwardButton.isHidden = true
        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        return forwardButton
    }()

    public lazy var timeRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let view = UIStackView(arrangedSubviews: [ spacer, timeLabel ])
        view.axis = .horizontal
        view.spacing = 0
        view.isLayoutMarginsRelativeArrangement = true
        view.layoutMargins = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 1)
        return view
    }()

    public lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .scaledSystemFont(ofSize: 12)
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

    public func runHighlightAnimation() {
        highlightAnimator = UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.5, delay: 0.0) {
            self.bubbleView.backgroundColor = UIColor {
                switch $0.userInterfaceStyle {
                case .dark:
                    return .systemGray2.resolvedColor(with: $0)
                default:
                    return .systemGray4.resolvedColor(with: $0)
                }
            }
        } completion: { [weak self] _ in
            guard let self = self else {
                return
            }
            self.highlightAnimator = UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.25, delay: 0.0, animations: {
                self.configureCellBackgroundColor()
            })
        }
    }

    private func cancelHighlightAnimation() {
        highlightAnimator?.stopAnimation(true)
        highlightAnimator = nil
    }
    
    public lazy var messageRow: UIStackView = {
        let hStack = UIStackView(arrangedSubviews: [ nameContentTimeRow ])
        hStack.axis = .horizontal
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.isUserInteractionEnabled = true
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.layoutMargins = UIEdgeInsets(top: 3, left: 10, bottom: 3, right: 10)
        hStack.spacing = -5
        hStack.distribution = .fill
        hStack.alignment = .bottom
        return hStack
    }()

    public lazy var nameContentTimeRow: UIStackView = {
        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.alignment = .fill
        vStack.layoutMargins = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        vStack.isLayoutMarginsRelativeArrangement = true
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.spacing = 5
        // Set bubble background
        vStack.insertSubview(bubbleBorder, at: 0)
        
        NSLayoutConstraint.activate([
            bubbleBorder.leadingAnchor.constraint(equalTo: vStack.leadingAnchor),
            bubbleBorder.topAnchor.constraint(equalTo: vStack.topAnchor),
            bubbleBorder.bottomAnchor.constraint(equalTo: vStack.bottomAnchor),
            bubbleBorder.trailingAnchor.constraint(equalTo: vStack.trailingAnchor),
        ])
        return vStack
    }()

    private lazy var pendingMessageIconView: UIImageView = {
        let view = UIImageView()
        view.image = UIImage(named: "Clock")?.withTintColor(.systemGray2)
        view.contentMode = .scaleAspectFill

        view.translatesAutoresizingMaskIntoConstraints = false

        let height = timeLabel.font.pointSize + 4
        view.widthAnchor.constraint(equalToConstant: height).isActive = true
        view.heightAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        return view
    }()

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
            reactionBubble.backgroundColor = UIColor.messageOwnBackground
        } else {
            bubbleView.backgroundColor = UIColor.messageNotOwnBackground
            reactionBubble.backgroundColor = UIColor.messageNotOwnBackground
        }
    }

    public func configureText(comment: FeedPostComment) {
        let cryptoResultString: String = FeedItemContentView.obtainCryptoResultString(for: comment.id)
        configureText(text: comment.rawText, cryptoResultString: cryptoResultString, mentions: comment.mentions)
    }

    public func configureText(chatMessage: ChatMessage) {
        configureText(text: chatMessage.rawText, cryptoResultString: "", mentions: chatMessage.mentions)
    }

    func configureText(text: String?, cryptoResultString: String, mentions: [MentionData]) {
        if let messageText = text, !messageText.isEmpty  {
            textLabel.isHidden = false
            let textWithMentions = UserProfile.text(with: mentions,
                                                    collapsedText: messageText + cryptoResultString,
                                                    in: MainAppContext.shared.mainDataStore.viewContext)
            let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
            var font = UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize + 1)
            if messageText.count <= 3, messageText.containsOnlyEmoji {
                font = UIFont.preferredFont(forTextStyle: .largeTitle)
            }
            let boldFont = UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold)!, size: font.pointSize)

            let textColor = isOwnMessage ? UIColor.messageOwnText : UIColor.messageNotOwnText
            if let attrText = textWithMentions?.with(font: font, color: UIColor.messageOwnText) {
                let ham = HAMarkdown(font: font, color: textColor)
                textLabel.attributedText = ham.parse(attrText).applyingFontForMentions(boldFont)
            }
        } else {
            textLabel.attributedText = nil
            textLabel.isHidden = true
        }
    }

    public func addReactionLabel(reaction: String) {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.scaledSystemFont(ofSize: 18)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = reaction
        reactionBubble.addArrangedSubview(label)
        reactionBubble.isHidden = false
    }

    public func updateReactionLabel() {
        if ServerProperties.chatReactions, let chatMessage = chatMessage {
            for reaction in reactionBubble.arrangedSubviews {
                reaction.removeFromSuperview()
            }
            guard !chatMessage.sortedReactionsList.isEmpty else {
                reactionBubble.isHidden = true
                return
            }
            for reaction in chatMessage.sortedReactionsList {
                addReactionLabel(reaction: reaction.emoji)
            }
            reactionBubble.isHidden = false
        } else if ServerProperties.commentReactions, let feedPostComment = feedPostComment {
            for reaction in reactionBubble.arrangedSubviews {
                reaction.removeFromSuperview()
            }
            guard !feedPostComment.sortedReactionsList.isEmpty else {
                reactionBubble.isHidden = true
                return
            }
            for reaction in feedPostComment.sortedReactionsList.prefix(3) {
                addReactionLabel(reaction: reaction.emoji)
            }
            reactionBubble.isHidden = false
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        forwardButton.isHidden = true
        chatMessage = nil
        feedPostComment = nil
        for reaction in reactionBubble.arrangedSubviews {
            reaction.removeFromSuperview()
        }
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(showMessageOptions(_:)))
        let listReactions = UITapGestureRecognizer(target: self, action: #selector(showReactionList(_:)))
        self.removeGestureRecognizer(longPressGesture)
        self.removeGestureRecognizer(listReactions)
        reactionBubble.removeFromSuperview()
        forwardButton.removeFromSuperview()
        if outgoingMessageStatusCancellable != nil {
            outgoingMessageStatusCancellable?.cancel()
            outgoingMessageStatusCancellable = nil
        }
        if reactionCancellable != nil {
            reactionCancellable?.cancel()
            reactionCancellable = nil
        }
        forwardCountLabel.isHidden = true
    }

    func configureWith(comment: FeedPostComment, userColorAssignment: UIColor, parentUserColorAssignment: UIColor, isPreviousMessageFromSameSender: Bool) {
        feedPostComment = comment
        isOwnMessage = comment.userId == MainAppContext.shared.userData.userId
        self.isPreviousMessageFromSameSender = isPreviousMessageFromSameSender
        userNameColorAssignment = userColorAssignment
        nameLabel.textColor = userNameColorAssignment
        timeLabel.text = comment.timestamp.chatDisplayTimestamp()
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(showCommentOptions(_:)))
        contentView.isUserInteractionEnabled = true
        contentView.addGestureRecognizer(longPressGesture)
        let listReactions = UITapGestureRecognizer(target: self, action: #selector(showReactionList(_:)))
        reactionBubble.addGestureRecognizer(listReactions)
        if !isOwnMessage {
            nameLabel.text = comment.user.displayName
        }
        if let feedPostComment = feedPostComment {
            // track changes to reactions for feedPostComment
            reactionCancellable = feedPostComment.publisher(for: \.reactions).receive(on: DispatchQueue.main).sink { [weak self] reaction in
                guard let self = self else { return }
                self.updateReactionLabel()
            }
        }
    }

    func configureWith(message: ChatMessage, userColorAssignment: UIColor, parentUserColorAssignment: UIColor, isPreviousMessageFromSameSender: Bool) {
        contentView.addSubview(forwardButton)
        chatMessage = message
        isOwnMessage = message.fromUserId == MainAppContext.shared.userData.userId
        self.isPreviousMessageFromSameSender = isPreviousMessageFromSameSender
        timeLabel.text = message.timestamp?.chatDisplayTimestamp()
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(showMessageOptions(_:)))
        contentView.isUserInteractionEnabled = true
        contentView.addGestureRecognizer(longPressGesture)
        let listReactions = UITapGestureRecognizer(target: self, action: #selector(showReactionList(_:)))
        reactionBubble.addGestureRecognizer(listReactions)
        if message.forwardCount > 0 {
            forwardCountLabel.isHidden = false
        } else {
            forwardCountLabel.isHidden = true
        }
        if let chatMessage = chatMessage, chatMessage.fromUserId == MainAppContext.shared.userData.userId {
            // outgoing message cell, track outgoing status
            setMessageOutgoingStatus()
        }
        if let chatMessage = chatMessage, chatMessage.chatMessageRecipient.chatType == .groupChat {
            nameLabel.text =  chatMessage.user.displayName
            nameLabel.textColor = userColorAssignment
            nameRow.isHidden = false
        }
        if let chatMessage = chatMessage {
            // track changes to reactions for chatMessage
            reactionCancellable = chatMessage.publisher(for: \.reactions).receive(on: DispatchQueue.main).sink { [weak self] reaction in
                guard let self = self else { return }
                self.updateReactionLabel()
            }
        }
     }

    private func setMessageOutgoingStatus() {
        guard let chatMessage = chatMessage, let timestamp =  chatMessage.timestamp?.chatDisplayTimestamp() else {
             return
        }

        let result = NSMutableAttributedString(string: timestamp)

        if chatMessage.media?.count == 1 && chatMessage.media?.first?.type == .audio {
            let isPlayed = chatMessage.outgoingStatus == .played
            let playedIcon: UIImage? = {
                if isPlayed {
                    return UIImage(named: "Microphone")?.withTintColor(UIColor.primaryBlue)
                } else {
                    return UIImage(named: "Microphone")?.withTintColor(.systemGray)
                }
            } ()
            if let icon = playedIcon {
                let iconAttachment = NSTextAttachment(image: icon)
                iconAttachment.bounds = CGRect(x: 0, y: -2, width: 12, height: 12)

                result.append(NSAttributedString(string: "  "))
                result.append(NSAttributedString(attachment: iconAttachment))
            }
        }

         if let icon = statusIcon(chatMessage.outgoingStatus) {
             let imageSize = icon.size
             let font = UIFont.scaledSystemFont(ofSize: timeLabel.font.pointSize - 1)

             let scale = font.capHeight / imageSize.height
             let iconAttachment = NSTextAttachment(image: icon)
             iconAttachment.bounds.size = CGSize(width: ceil(imageSize.width * scale), height: ceil(imageSize.height * scale))

             result.append(NSAttributedString(string: "  "))
             result.append(NSAttributedString(attachment: iconAttachment))
         }
         timeLabel.attributedText = result
     }

     func statusIcon(_ status: ChatMessage.OutgoingStatus) -> UIImage? {
         if pendingMessageIconTimer != nil {
             pendingMessageIconTimer?.invalidate()
             pendingMessageIconView.removeFromSuperview()
         }

         switch status {
         case .pending:
             // TODO dini - this belongs in the update function instead of the icon getter.
             pendingMessageIconTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in

                 guard let self = self else { return }
                  self.timeRow.addSubview(self.pendingMessageIconView)
                  NSLayoutConstraint.activate([
                      self.pendingMessageIconView.trailingAnchor.constraint(equalTo: self.timeLabel.trailingAnchor, constant: 3),
                      self.pendingMessageIconView.bottomAnchor.constraint(equalTo: self.timeLabel.bottomAnchor)
                  ])
              }
              return UIImage(named: "CheckmarkSingle")?.withTintColor(.clear)
         case .sentOut:
              return UIImage(named: "CheckmarkSingle")?.withTintColor(.systemGray)
         case .delivered:
              return UIImage(named: "CheckmarkDouble")?.withTintColor(.systemGray)
         case .seen, .played:
              return UIImage(named: "CheckmarkDouble")?.withTintColor(UIColor.primaryBlue)
         default: return nil
         }
    }

    func configureCell() {
        cancelHighlightAnimation()
        if isOwnMessage {
            bubbleView.backgroundColor = UIColor.messageOwnBackground
            reactionBubble.backgroundColor = UIColor.messageOwnBackground
            messageRow.insertArrangedSubview(reactionBubble, at: 0)
            nameRow.isHidden = true
            rightAlignedConstraint.priority = UILayoutPriority(800)
            leftAlignedConstraint.priority = UILayoutPriority(1)
        } else {
            bubbleView.backgroundColor = UIColor.messageNotOwnBackground
            reactionBubble.backgroundColor = UIColor.messageNotOwnBackground
            messageRow.insertArrangedSubview(reactionBubble, at: 1)
            nameRow.isHidden = false
            rightAlignedConstraint.priority = UILayoutPriority(1)
            leftAlignedConstraint.priority = UILayoutPriority(800)
        }
        if isPreviousMessageFromSameSender {
            messageRow.layoutMargins = UIEdgeInsets(top: 1, left: 10, bottom: 2, right: 10)
        } else {
            messageRow.layoutMargins = UIEdgeInsets(top: 3, left: 10, bottom: 3, right: 10)
        }
    }

    func playVoiceNote() {
        // no op
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

                if self.isReplyTriggered {
                    if let chatMessage = self.chatMessage {
                        self.chatDelegate?.messageView(self, replyToChat: chatMessage)
                    } else {
                        guard let feedPostCommentID = self.feedPostComment?.id else { return }
                        self.commentDelegate?.messageView(self, replyTo: feedPostCommentID)
                    }
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
            commentDelegate?.messageView(self, didTapUserId: feedPostComment.userId)
        } else if let chatMessage = chatMessage {
            chatDelegate?.messageView(self, didTapUserId: chatMessage.fromUserID)
        }
    }

    @objc public func jumpToQuotedMsg(_ sender: UIView) {
        if let parentCommentId = feedPostComment?.parent?.id {
            commentDelegate?.messageView(self, jumpTo: parentCommentId)
        } else if let parentMessageId = chatMessage?.chatReplyMessageID {
            chatDelegate?.messageView(self, jumpTo: parentMessageId)
        } else if let parentPostId = chatMessage?.feedPostID {
            chatDelegate?.messageView(self, openPost: parentPostId)
        }
    }

    @objc public func showMessageOptions(_ recognizer: UILongPressGestureRecognizer) {
        guard let chatMessage = chatMessage else { return }
        if(recognizer.state == .began) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            chatDelegate?.messageView(self, didLongPressOn: chatMessage)
        }
    }
    
    @objc public func showCommentOptions(_ recognizer: UILongPressGestureRecognizer) {
        guard let feedPostComment = feedPostComment, !feedPostComment.isRetracted else { return }
        if(recognizer.state == .began) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            commentDelegate?.messageView(self, didLongPressOn: feedPostComment)
        }
    }

    @objc public func showReactionList(_ recognizer: UITapGestureRecognizer) {
        if let chatMessage = chatMessage, let chatDelegate = chatDelegate {
            chatDelegate.messageView(self, showReactionsFor: chatMessage)
        } else if let feedPostComment = feedPostComment, let commentDelegate = commentDelegate {
            commentDelegate.messageView(self, showReactionsFor: feedPostComment)
        }
    }

    @objc func forwardAction(_ recognizer: UITapGestureRecognizer) {
        guard let chatMessage = chatMessage else {
            return
        }
        chatDelegate?.messageView(self, forwardingMessage: chatMessage)
    }
}
