//
//  MessageCellViewLinkPreview.swift
//  HalloApp
//
//  Created by Nandini Shetty on 3/8/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import Foundation
import UIKit

class MessageCellViewLinkPreview: MessageCellViewBase {

    var LinkPreviewViewWidth: CGFloat { return contentView.bounds.width * 0.7 }

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
        nameContentTimeRow.addArrangedSubview(forwardCountLabel)
        nameContentTimeRow.addArrangedSubview(linkPreviewView)
        nameContentTimeRow.addArrangedSubview(textRow)
        nameContentTimeRow.addArrangedSubview(timeRow)
        nameContentTimeRow.setCustomSpacing(0, after: textRow)
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

    override func configureWith(comment: FeedPostComment, userColorAssignment: UIColor, parentUserColorAssignment: UIColor, isPreviousMessageFromSameSender: Bool) {
        MainAppContext.shared.feedData.downloadMedia(in: [comment])
        super.configureWith(comment: comment, userColorAssignment: userColorAssignment, parentUserColorAssignment: parentUserColorAssignment, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
        configureText(comment: comment)
        if let feedLinkPreviews = comment.linkPreviews, let feedLinkPreview = feedLinkPreviews.first {
            MainAppContext.shared.feedData.loadImages(feedLinkPreviewID: feedLinkPreview.id)
            linkPreviewView.configure(linkPreview: feedLinkPreview)
        }
        super.configureCell()
    }

    override func configureWith(message: ChatMessage, userColorAssignment: UIColor, parentUserColorAssignment: UIColor, isPreviousMessageFromSameSender: Bool) {
        super.configureWith(message: message, userColorAssignment: userColorAssignment, parentUserColorAssignment: parentUserColorAssignment, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
        configureText(chatMessage: message)
        if let feedLinkPreviews = message.linkPreviews, let feedLinkPreview = feedLinkPreviews.first {
            linkPreviewView.configure(linkPreview: feedLinkPreview)
        }
        super.configureCell()
    }
}
