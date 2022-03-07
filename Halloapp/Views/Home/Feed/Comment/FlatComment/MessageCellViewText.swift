//
//  MessageCellViewText.swift
//  HalloApp
//
//  Created by Nandini Shetty on 3/4/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import UIKit

class MessageCellViewText: MessageViewCellBase {

    var MaxWidthOfMessageBubble: CGFloat { return contentView.bounds.width * 0.8 }
    var MinWidthOfMessageBubble: CGFloat { return contentView.bounds.width * 0.2 }

    lazy var rightAlignedConstraint = messageRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
    lazy var leftAlignedConstraint = messageRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)

    private lazy var messageRow: UIStackView = {
        let hStack = UIStackView(arrangedSubviews: [ nameTextTimeRow ])
        hStack.axis = .horizontal
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.isUserInteractionEnabled = true
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.layoutMargins = UIEdgeInsets(top: 3, left: 10, bottom: 3, right: 10)
        return hStack
    }()

    private lazy var nameTextTimeRow: UIStackView = {
        let vStack = UIStackView(arrangedSubviews: [ nameRow, textLabel, timeRow ])
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
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()

    lazy var textLabel: TextLabel = {
        let textLabel = TextLabel()
        textLabel.isUserInteractionEnabled = true
        textLabel.backgroundColor = .clear
        textLabel.font = UIFont.systemFont(ofSize: 15)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.numberOfLines = 0
        textLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        textLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        textLabel.textColor = UIColor.primaryBlackWhite.withAlphaComponent(0.8)
        return textLabel
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
    
    override func prepareForReuse() {
        super.prepareForReuse()
        textLabel.attributedText = nil
    }

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
        
        NSLayoutConstraint.activate([
            nameRow.topAnchor.constraint(equalTo: nameTextTimeRow.topAnchor, constant: 8),
            nameRow.leadingAnchor.constraint(equalTo: nameTextTimeRow.leadingAnchor, constant: 8),
            nameRow.bottomAnchor.constraint(equalTo: textLabel.topAnchor),
            nameRow.trailingAnchor.constraint(equalTo: nameTextTimeRow.trailingAnchor, constant: 8),
            textLabel.leadingAnchor.constraint(equalTo: nameTextTimeRow.leadingAnchor, constant: 8),
            textLabel.bottomAnchor.constraint(equalTo: timeRow.topAnchor),
            textLabel.trailingAnchor.constraint(equalTo: nameTextTimeRow.trailingAnchor, constant: 8),
            timeRow.leadingAnchor.constraint(equalTo: nameTextTimeRow.leadingAnchor, constant: 8),
            timeRow.bottomAnchor.constraint(equalTo: nameTextTimeRow.bottomAnchor, constant: 8),
            timeRow.trailingAnchor.constraint(equalTo: nameTextTimeRow.trailingAnchor, constant: 8),
            textLabel.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(MaxWidthOfMessageBubble).rounded()),
            textLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(MinWidthOfMessageBubble).rounded()),
            rightAlignedConstraint,
            leftAlignedConstraint
        ])

        // Tapping on user name should take you to the user's feed
        nameLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showUserFeedForPostAuthor)))
        // Reply gesture
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(panGestureCellAction))
        panGestureRecognizer.delegate = self
        self.addGestureRecognizer(panGestureRecognizer)
    }

    func configureWithComment(comment: FeedPostComment, userColorAssignment: UIColor, parentUserColorAssignment: UIColor, isPreviousMessageFromSameSender: Bool) {
        feedPostComment = comment
        isOwnMessage = comment.userId == MainAppContext.shared.userData.userId
        isPreviousMessageOwnMessage = isPreviousMessageFromSameSender
        userNameColorAssignment = userColorAssignment
        nameLabel.textColor = userNameColorAssignment
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: comment.userId)
        timeLabel.text = comment.timestamp.chatTimestamp()

        configureText(comment: comment)
        configureCell()
    }
    
    // Adjusting constraint priorities here in a single place to be able to easily see relative priorities.
    private func configureCell() {
        if isOwnMessage {
            bubbleView.backgroundColor = UIColor.messageOwnBackground
            textLabel.textColor = UIColor.messageOwnText
            nameRow.isHidden = true
            rightAlignedConstraint.priority = UILayoutPriority(800)
            leftAlignedConstraint.priority = UILayoutPriority(1)
        } else {
            bubbleView.backgroundColor = UIColor.messageNotOwnBackground
            textLabel.textColor = UIColor.messageNotOwnText
            rightAlignedConstraint.priority = UILayoutPriority(1)
            leftAlignedConstraint.priority = UILayoutPriority(800)
            // If the message contains media, always show name
            // If the previous message was from the same user, hide name
            if !isPreviousMessageOwnMessage {
                nameRow.isHidden = false
            } else {
                nameRow.isHidden = true
            }
        }
    }

    private func configureText(comment: FeedPostComment) {
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
        }
    }
}

