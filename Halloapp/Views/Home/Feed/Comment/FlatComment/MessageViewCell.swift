//
//  MessageViewCell.swift
//  HalloApp
//
//  Created by Nandini Shetty on 12/2/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//
import UIKit
import Core

class MessageViewCell: UICollectionViewCell {

    private func setupView() {
        backgroundColor = UIColor.feedBackground
        contentView.preservesSuperviewLayoutMargins = false
        contentView.addSubview(messageRow)
        messageRow.constrain([.top, .leading, .trailing], to: contentView)
        messageRow.constrainMargin(anchor: .bottom, to: contentView, constant: 5, priority: UILayoutPriority(rawValue: 999))
    }

    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ messageRow ])
        view.axis = .vertical
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var leftSpacer: UIView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        return spacer
    }()
    
    
    private lazy var rightSpacer: UIView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        return spacer
    }()

    private lazy var messageRow: UIStackView = {
        let hStack = UIStackView(arrangedSubviews: [ leftSpacer, nameTextTimeRow, rightSpacer ])
        hStack.axis = .horizontal
        hStack.translatesAutoresizingMaskIntoConstraints = false
        nameTextTimeRow.setContentHuggingPriority(.defaultHigh, for: .vertical)
        nameTextTimeRow.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(UIScreen.main.bounds.width * 0.8).rounded()).isActive = true
        textView.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(UIScreen.main.bounds.width * 0.2).rounded()).isActive = true
        return hStack
    }()

    private lazy var nameTextTimeRow: UIStackView = {
        let vStack = UIStackView(arrangedSubviews: [ nameRow, textView, timeRow ])
        vStack.axis = .vertical
        vStack.alignment = .fill
        vStack.spacing = 0
        vStack.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        vStack.isLayoutMarginsRelativeArrangement = true
        vStack.translatesAutoresizingMaskIntoConstraints = false
        // Set bubble background
        bubbleView.frame = vStack.bounds
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
        bubbleView.layer.masksToBounds = true
        bubbleView.clipsToBounds = true
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

    // MARK: Text
    private lazy var textView1: TextLabel = {
        let textLabel = TextLabel()
        textLabel.numberOfLines = 0
        textLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.isUserInteractionEnabled = true
        textLabel.backgroundColor = .clear
        textLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        textLabel.textColor = UIColor.primaryBlackWhite
        return textLabel
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
        return textView
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

    func configureWithComment(comment: FeedPostComment) {
        textView.text = comment.text
        timeLabel.text = comment.timestamp.chatTimestamp()
        setNameLabel(for: comment.userId)
        configureCell(isOwnMessage: comment.userId == MainAppContext.shared.userData.userId)
    }

    private func setNameLabel(for userID: String) {
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: userID, showPushNumber: true)
    }
    
    private func configureCell(isOwnMessage: Bool) {
        if isOwnMessage {
            rightSpacer.isHidden = true
            leftSpacer.isHidden = false
            bubbleView.backgroundColor = UIColor.chatOwnBubbleBg
            textView.textColor = UIColor.chatOwnMsg
            nameRow.isHidden = true
        } else {
            rightSpacer.isHidden = false
            leftSpacer.isHidden = true
            bubbleView.backgroundColor = .secondarySystemGroupedBackground
            textView.textColor = UIColor.primaryBlackWhite
            nameRow.isHidden = false
        }
    }
}
