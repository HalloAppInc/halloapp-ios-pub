//
//  MessageCellViewMedia.swift
//  HalloApp
//
//  Created by Nandini Shetty on 3/7/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit

class MessageCellViewMedia: MessageCellViewBase {

    var MediaViewDimention: CGFloat { return 238.0 }

    lazy var rightAlignedConstraint = messageRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
    lazy var leftAlignedConstraint = messageRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
    
    // MARK: Media

    private lazy var mediaCarouselView: MediaCarouselView = {
        var configuration = MediaCarouselViewConfiguration.default
        configuration.alwaysScaleToFitContent = false
        let mediaCarouselView = MediaCarouselView(media: [], configuration: configuration)
        mediaCarouselView.delegate = self
        return mediaCarouselView
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

    private func setupView() {
        backgroundColor = UIColor.feedBackground
        contentView.preservesSuperviewLayoutMargins = false
        nameContentTimeRow.addArrangedSubview(nameRow)
        nameContentTimeRow.addArrangedSubview(mediaCarouselView)
        nameContentTimeRow.addArrangedSubview(textRow)
        nameContentTimeRow.addArrangedSubview(timeRow)
        contentView.addSubview(messageRow)
        messageRow.constrain([.top], to: contentView)
        messageRow.constrain(anchor: .bottom, to: contentView, priority: UILayoutPriority(rawValue: 999))

        NSLayoutConstraint.activate([
            mediaCarouselView.widthAnchor.constraint(equalToConstant: MediaViewDimention),
            mediaCarouselView.heightAnchor.constraint(equalToConstant: MediaViewDimention),
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
        configureMedia(comment: comment)
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
            nameRow.isHidden = false
            if let userId = feedPostComment?.userId {
                nameLabel.text =  MainAppContext.shared.contactStore.fullName(for: userId)
            }
            rightAlignedConstraint.priority = UILayoutPriority(1)
            leftAlignedConstraint.priority = UILayoutPriority(800)
        }
    }
 
    private func configureMedia(comment: FeedPostComment) {
        guard let commentMedia = comment.media, commentMedia.count > 0 else {
            return
        }
        guard let media = MainAppContext.shared.feedData.media(commentID: comment.id) else {
            return
        }
        // Download any pending media, comes in handy for media coming in while user is viewing comments
        MainAppContext.shared.feedData.downloadMedia(in: [comment])
        MainAppContext.shared.feedData.loadImages(commentID: comment.id)
        mediaCarouselView.configureMediaCarousel(media: media)
    }
}

extension MessageCellViewMedia: MediaCarouselViewDelegate {

    func mediaCarouselView(_ view: MediaCarouselView, indexChanged newIndex: Int) {
    }

    func mediaCarouselView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int) {
        if let commentID = feedPostComment?.id {
            delegate?.messageView(view, forComment: commentID, didTapMediaAtIndex: index)
        }
    }

    func mediaCarouselView(_ view: MediaCarouselView, didDoubleTapMediaAtIndex index: Int) {
    }

    func mediaCarouselView(_ view: MediaCarouselView, didZoomMediaAtIndex index: Int, withScale scale: CGFloat) {
    }
}
