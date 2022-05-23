//
//  MessageCellViewQuoted.swift
//  HalloApp
//
//  Created by Nandini Shetty on 3/11/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import UIKit

class MessageCellViewQuoted: MessageCellViewBase {
    private var audioMediaStatusCancellable: AnyCancellable?

    var MaxWidthOfMessageBubble: CGFloat { return contentView.bounds.width * 0.8 }
    var MinWidthOfMessageBubble: CGFloat { return contentView.bounds.width * 0.2 }
    var MinWidthOfQuotedMediaMessageBubble: CGFloat { return contentView.bounds.width * 0.6 }
    var MinWidthOfQuotedMessageBubble: CGFloat { return contentView.bounds.width * 0.4 }
    var MediaViewDimention: CGFloat { return 238.0 }

    lazy var mediaWidthConstraint = mediaCarouselView.widthAnchor.constraint(equalToConstant: MediaViewDimention)
    lazy var mediaHeightConstraint = mediaCarouselView.heightAnchor.constraint(equalToConstant: MediaViewDimention)
    lazy var audioWidthConstraint = audioView.widthAnchor.constraint(equalToConstant: MediaViewDimention)
    lazy var quotedMediaMessageMinWidthConstraint = quotedMessageView.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(MinWidthOfQuotedMediaMessageBubble).rounded())
    lazy var quotedMessageMinWidthConstraint = quotedMessageView.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(MinWidthOfQuotedMessageBubble).rounded())

    var hasMedia: Bool = false
    var hasAudio: Bool = false
    var hasLinkPreview: Bool = false

    // MARK: Media

    private lazy var mediaCarouselView: MediaCarouselView = {
        var configuration = MediaCarouselViewConfiguration.default
        configuration.alwaysScaleToFitContent = false
        let mediaCarouselView = MediaCarouselView(media: [], configuration: configuration)
        mediaCarouselView.delegate = self
        return mediaCarouselView
    }()

    // MARK: Audio Media

    private lazy var audioView: AudioView = {
        let audioView = AudioView()
        audioView.translatesAutoresizingMaskIntoConstraints = false
        audioView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        audioView.delegate = self
        return audioView
    }()

    // MARK: Link Preview

    private lazy var linkPreviewView: CommentLinkPreviewView = {
        let linkPreviewView = CommentLinkPreviewView(frame: .zero)
        linkPreviewView.translatesAutoresizingMaskIntoConstraints = false
        return linkPreviewView
    }()

    private lazy var audioTimeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        label.textColor = UIColor.chatTime

        return label
    }()
    
    private lazy var audioTimeRow: UIStackView = {
        let leadingSpacer = UIView()
        leadingSpacer.translatesAutoresizingMaskIntoConstraints = false
        leadingSpacer.widthAnchor.constraint(equalToConstant: 40).isActive = true
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let view = UIStackView(arrangedSubviews: [ leadingSpacer, audioTimeLabel, spacer, timeLabel ])
        view.axis = .horizontal
        view.spacing = 0
        view.isLayoutMarginsRelativeArrangement = true
        return view
    }()

    // MARK: Quoted Message
    
    private lazy var quotedMessageView: QuotedMessageCellView = {
        let quotedMessageView = QuotedMessageCellView()
        quotedMessageView.translatesAutoresizingMaskIntoConstraints = false
        return quotedMessageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        nameContentTimeRow.removeArrangedSubview(nameRow)
        nameRow.removeFromSuperview()
        nameContentTimeRow.removeArrangedSubview(mediaCarouselView)
        mediaCarouselView.removeFromSuperview()
        nameContentTimeRow.removeArrangedSubview(audioView)
        audioView.removeFromSuperview()
        nameContentTimeRow.removeArrangedSubview(linkPreviewView)
        linkPreviewView.removeFromSuperview()
        nameContentTimeRow.removeArrangedSubview(quotedMessageView)
        quotedMessageView.removeFromSuperview()
        nameContentTimeRow.removeArrangedSubview(textRow)
        textRow.removeFromSuperview()
        nameContentTimeRow.removeArrangedSubview(audioTimeRow)
        audioTimeRow.removeFromSuperview()

        hasMedia = false
        hasAudio = false
        hasLinkPreview = false

        mediaWidthConstraint.isActive = false
        mediaHeightConstraint.isActive = false
        audioWidthConstraint.isActive = false
        quotedMediaMessageMinWidthConstraint.isActive = false
        quotedMessageMinWidthConstraint.isActive = false
    }

    private func setupView() {
        backgroundColor = UIColor.feedBackground
        contentView.preservesSuperviewLayoutMargins = false
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
        // Tapping on quoted comment should take you to the original comment
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(jumpToQuotedMsg(_:)))
        quotedMessageView.isUserInteractionEnabled = true
        quotedMessageView.addGestureRecognizer(tapGesture)
        
    }
    
    private func setupConditionalConstraints() {
        NSLayoutConstraint.activate([
            nameContentTimeRow.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(MaxWidthOfMessageBubble).rounded()),
            nameContentTimeRow.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(MinWidthOfMessageBubble).rounded()),
            rightAlignedConstraint,
            leftAlignedConstraint,
            mediaWidthConstraint,
            mediaHeightConstraint,
            audioWidthConstraint
        ])
    }

    override func configureWith(comment: FeedPostComment, userColorAssignment: UIColor, parentUserColorAssignment: UIColor, isPreviousMessageFromSameSender: Bool) {
        super.configureWith(comment: comment, userColorAssignment: userColorAssignment, parentUserColorAssignment: parentUserColorAssignment, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
        MainAppContext.shared.feedData.downloadMedia(in: [comment])
        MainAppContext.shared.feedData.loadImages(commentID: comment.id)
        audioMediaStatusCancellable?.cancel()

        setNameLabel(for: comment.userId)
        guard feedPostComment?.parent != nil else { return }
        nameContentTimeRow.addArrangedSubview(nameRow)
        configureText(comment: comment)

        // Configure parent comment view
        if let parentComment = comment.parent {
            quotedMessageView.configureWith(comment: parentComment, userColorAssignment: parentUserColorAssignment)
            nameContentTimeRow.addArrangedSubview(quotedMessageView)
        }
        //Configure media view
        if let media = MainAppContext.shared.feedData.media(commentID: comment.id, in: MainAppContext.shared.feedData.viewContext) {
            if let commentMedia = comment.media, commentMedia.count > 0 {
                // Audio comment
                if comment.media?.count == 1, let media = comment.media?.first, media.type == .audio {
                    configureAudio(audioMedia: media,
                                   isOwn: comment.userId == MainAppContext.shared.userData.userId,
                                   isPlayed: comment.status == .played)
                    nameContentTimeRow.addArrangedSubview(audioView)
                    hasAudio = true
                } else {
                    mediaCarouselView.configureMediaCarousel(media: media)
                    nameContentTimeRow.addArrangedSubview(mediaCarouselView)
                    hasMedia = true
                }
            }
        }
        // Configure link preview
        configureLinkPreview(linkPreviews: comment.linkPreviews)
        configureCell()
    }

    override func configureWith(message: ChatMessage) {
        super.configureWith(message: message)
        audioMediaStatusCancellable?.cancel()
        guard message.chatReplyMessageID != nil || message.feedPostId != nil else { return }
        configureText(chatMessage: message)
        // Configure parent chat view
        if let chatReplyMessageID = message.chatReplyMessageID, let replyMessage = MainAppContext.shared.chatData.chatMessage(with: chatReplyMessageID, in: MainAppContext.shared.chatData.viewContext) {
            quotedMessageView.configureWith(message: replyMessage)
            nameContentTimeRow.addArrangedSubview(quotedMessageView)
        } else if let quotedMessage = chatMessage?.quoted {
            quotedMessageView.configureWith(quoted: quotedMessage)
            nameContentTimeRow.addArrangedSubview(quotedMessageView)
        }
        // Configure media view
        if let chatMedia = chatMessage?.media, chatMedia.count > 0 {
            if chatMedia.count == 1, let media = chatMedia.first, media.type == .audio {
                configureAudio(audioMedia: media,
                               isOwn: message.fromUserId == MainAppContext.shared.userData.userId,
                               isPlayed: [.played, .sentPlayedReceipt].contains(message.incomingStatus))
                nameContentTimeRow.addArrangedSubview(audioView)
                hasAudio = true
            } else {
                // TODO handle chat media management
                hasMedia = true
            }
        }
        // Configure link preview
        configureLinkPreview(linkPreviews: message.linkPreviews)
        configureCell()
    }

    private func configureLinkPreview(linkPreviews: Set<CommonLinkPreview>?) {
        if let linkPreviews = linkPreviews, let linkPreview = linkPreviews.first {
            MainAppContext.shared.feedData.loadImages(feedLinkPreviewID: linkPreview.id)
            linkPreviewView.configure(linkPreview: linkPreview)
            hasLinkPreview = true
        }
    }

    // Adjusting constraint priorities here in a single place to be able to easily see relative priorities.
    override func configureCell() {
        configureQuotedMessage()
        super.configureCell()
        if isOwnMessage {
            quotedMessageView.bubbleView.backgroundColor = UIColor.quotedMessageOwnBackground
        } else {
            quotedMessageView.bubbleView.backgroundColor = UIColor.quotedMessageNotOwnBackground
        }
    }

    private func configureQuotedMessage() {
        nameContentTimeRow.addArrangedSubview(textRow)
        nameContentTimeRow.addArrangedSubview(audioTimeRow)
        if hasMedia {
            mediaWidthConstraint.isActive = true
        } else if hasAudio {
            audioWidthConstraint.isActive = true
        } else if quotedMessageView.hasMedia ||  hasLinkPreview {
            // If quoted comments have media, set the min width of the comment.
            quotedMediaMessageMinWidthConstraint .isActive = true
        } else if !quotedMessageView.hasMedia {
            quotedMessageMinWidthConstraint .isActive = true
        }
        if hasMedia {
            mediaHeightConstraint.isActive = true
        }
    }

    private func setNameLabel(for userID: String) {
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: userID, in: MainAppContext.shared.contactStore.viewContext)
    }

    private func configureAudio(audioMedia: CommonMedia, isOwn: Bool, isPlayed: Bool) {
        if let mediaURL = audioMedia.mediaURL {
            audioView.url = mediaURL
            if !audioView.isPlaying {
                audioView.state = isPlayed || isOwn ? .played : .normal
            }
        } else {
            audioView.state = .loading
            audioMediaStatusCancellable = audioMedia.publisher(for: \.relativeFilePath).sink { [weak self] path in
                guard let self = self else { return }
                guard path != nil else { return }
                self.audioView.url = audioMedia.mediaURL
                if !self.audioView.isPlaying {
                    self.audioView.state = isPlayed || isOwn ? .played : .normal
                }
            }
        }
    }
}

extension MessageCellViewQuoted: MediaCarouselViewDelegate {

    func mediaCarouselView(_ view: MediaCarouselView, indexChanged newIndex: Int) {
    }

    func mediaCarouselView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int) {
        if let commentID = feedPostComment?.id {
            commentDelegate?.messageView(view, forComment: commentID, didTapMediaAtIndex: index)
        }
    }

    func mediaCarouselView(_ view: MediaCarouselView, didDoubleTapMediaAtIndex index: Int) {
    }

    func mediaCarouselView(_ view: MediaCarouselView, didZoomMediaAtIndex index: Int, withScale scale: CGFloat) {
    }
}

// MARK: AudioViewDelegate
extension MessageCellViewQuoted: AudioViewDelegate {
    func audioView(_ view: AudioView, at time: String) {
        audioTimeLabel.text = time
    }
    func audioViewDidStartPlaying(_ view: AudioView) {
        guard let commentId = feedPostComment?.id else { return }
        audioView.state = .played
        MainAppContext.shared.feedData.markCommentAsPlayed(commentId: commentId)
    }
    func audioViewDidEndPlaying(_ view: AudioView, completed: Bool) {
    }
}

