//
//  MessageCellViewLinkPreview.swift
//  HalloApp
//
//  Created by Nandini Shetty on 3/8/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit

class MessageCellViewLinkPreview: MessageCellViewBase {

    var LinkPreviewViewWidth: CGFloat { return contentView.bounds.width * 0.7 }
    lazy var rightAlignedConstraint = messageRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
    lazy var leftAlignedConstraint = messageRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)

    private lazy var linkPreviewView: CommentLinkPreviewView = {
        let linkPreviewView = CommentLinkPreviewView(frame: .zero)
        linkPreviewView.translatesAutoresizingMaskIntoConstraints = false
        return linkPreviewView
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
        nameContentTimeRow.addArrangedSubview(linkPreviewView)
        nameContentTimeRow.addArrangedSubview(textRow)
        nameContentTimeRow.addArrangedSubview(timeRow)
        contentView.addSubview(messageRow)
        messageRow.constrain([.top], to: contentView)
        messageRow.constrain(anchor: .bottom, to: contentView, priority: UILayoutPriority(rawValue: 999))
        
        NSLayoutConstraint.activate([
            linkPreviewView.widthAnchor.constraint(equalToConstant: LinkPreviewViewWidth),
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
        configureLinkPreviewView(comment: comment)
        configureCell()
    }

    func configureLinkPreviewView(comment: FeedPostComment) {
        guard let feedLinkPreviews = comment.linkPreviews, let feedLinkPreview = feedLinkPreviews.first else {
            return
        }
        MainAppContext.shared.feedData.loadImages(feedLinkPreviewID: feedLinkPreview.id)
        linkPreviewView.configure(feedLinkPreview: feedLinkPreview)
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
            if isPreviousMessageOwnMessage {
                messageRow.layoutMargins = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
            } else {
                messageRow.layoutMargins = UIEdgeInsets(top: 3, left: 10, bottom: 3, right: 10)
            }
        }
    }
}
