//
//  MessageCellViewMedia.swift
//  HalloApp
//
//  Created by Nandini Shetty on 3/7/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import Foundation
import UIKit

class MessageCellViewMedia: MessageCellViewBase {

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

    private func setupView() {
        backgroundColor = UIColor.feedBackground
        contentView.preservesSuperviewLayoutMargins = false
        nameContentTimeRow.addArrangedSubview(nameRow)
        nameContentTimeRow.addArrangedSubview(mediaView)
        nameContentTimeRow.addArrangedSubview(textRow)
        nameContentTimeRow.addArrangedSubview(timeRow)
        nameContentTimeRow.setCustomSpacing(0, after: textRow)
        contentView.addSubview(messageRow)
        messageRow.constrain([.top], to: contentView)
        messageRow.constrain(anchor: .bottom, to: contentView, priority: UILayoutPriority(rawValue: 999))

        NSLayoutConstraint.activate([
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

    // MARK: Media
    private(set) lazy var mediaView: MessageMediaView = {
        let mediaView = MessageMediaView()
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.delegate = self
        return mediaView
    }()

    override func configureWith(comment: FeedPostComment, userColorAssignment: UIColor, parentUserColorAssignment: UIColor, isPreviousMessageFromSameSender: Bool) {
        super.configureWith(comment: comment, userColorAssignment: userColorAssignment, parentUserColorAssignment: parentUserColorAssignment, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
        configureText(comment: comment)

        if let media = comment.media?.sorted(by: { $0.order < $1.order }), !media.isEmpty {
            MainAppContext.shared.feedData.downloadMedia(in: [comment])
            // required so that fullscreen open works
            // TODO(stefan): remove it once fullscreen works only with CommonMedia
            MainAppContext.shared.feedData.loadImages(commentID: comment.id)
            mediaView.configure(feedPostComment: comment, media: media)
        } else {
            DDLogError("MessageCellViewMedia/configure/error missing media for comment " + comment.id)
        }

        configureCell()
    }

    override func configureWith(message: ChatMessage, isPreviousMessageFromSameSender: Bool) {
        super.configureWith(message: message, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
        configureText(chatMessage: message)

        if let media = message.media?.sorted(by: { $0.order < $1.order }), !media.isEmpty {
            MainAppContext.shared.chatData.downloadMedia(in: message)
            mediaView.configure(chatMessage: message, media: media)
        } else {
            DDLogError("MessageCellViewMedia/configure/error missing media for message " + message.id)
        }

        configureCell()

        // hide empty space above media on incomming messages
        nameRow.isHidden = true
    }
}

extension MessageCellViewMedia: MessageMediaViewDelegate {

    func messageMediaView(_ view: MediaImageView, forComment: FeedPostCommentID, didTapMediaAtIndex index: Int) {
        self.commentDelegate?.messageView(view, forComment: forComment, didTapMediaAtIndex: index)
    }

    func messageMediaView(_ view: MediaImageView, forMessage: ChatMessageID, didTapMediaAtIndex index: Int) {
        self.chatDelegate?.messageView(self, for: forMessage, didTapMediaAtIndex: index)
    }
}
