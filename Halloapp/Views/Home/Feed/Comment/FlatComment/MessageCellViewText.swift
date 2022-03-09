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

class MessageCellViewText: MessageCellViewBase {

    var MaxWidthOfMessageBubble: CGFloat { return contentView.bounds.width * 0.8 }
    var MinWidthOfMessageBubble: CGFloat { return contentView.bounds.width * 0.3 }

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
        let vStack = UIStackView(arrangedSubviews: [ nameRow, textRow, timeRow ])
        vStack.axis = .vertical
        vStack.alignment = .fill
        vStack.layoutMargins = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        vStack.isLayoutMarginsRelativeArrangement = true
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.spacing = 3
        // Set bubble background
        vStack.insertSubview(bubbleView, at: 0)
        return vStack
    }()
    
    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
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
            nameTextTimeRow.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(MaxWidthOfMessageBubble).rounded()),
            nameTextTimeRow.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(MinWidthOfMessageBubble).rounded()),
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

    override func configureWithComment(comment: FeedPostComment, userColorAssignment: UIColor, parentUserColorAssignment: UIColor, isPreviousMessageFromSameSender: Bool) {
        super.configureWithComment(comment: comment, userColorAssignment: userColorAssignment, parentUserColorAssignment: parentUserColorAssignment, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
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
            if let userId = feedPostComment?.userId {
                nameLabel.text =  MainAppContext.shared.contactStore.fullName(for: userId)
            }
            
            // If the message contains media, always show name
            // If the previous message was from the same user, hide name
            if !isPreviousMessageOwnMessage {
                nameRow.isHidden = false
            } else {
                nameRow.isHidden = true
            }
        }
    }
}
