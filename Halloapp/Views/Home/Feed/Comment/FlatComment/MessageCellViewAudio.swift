//
//  MessageCellViewAudio.swift
//  HalloApp
//
//  Created by Nandini Shetty on 3/8/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import Combine
import Foundation
import UIKit

class MessageCellViewAudio: MessageCellViewBase {
    
    private var audioMediaStatusCancellable: AnyCancellable?

    var AudioViewWidth: CGFloat { return contentView.bounds.width * 0.5 }
    var AudioViewHeight: CGFloat { return contentView.bounds.width * 0.1 }

    // MARK: Audio Media
    
    private lazy var audioRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ audioView ])
        view.axis = .vertical
        view.spacing = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isLayoutMarginsRelativeArrangement = true
        view.layoutMargins = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 3)
        return view
    }()

    private lazy var audioView: AudioView = {
        let audioView = AudioView()
        audioView.translatesAutoresizingMaskIntoConstraints = false
        audioView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        audioView.delegate = self
        return audioView
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
        let view = UIStackView(arrangedSubviews: [ leadingSpacer, audioTimeLabel, spacer, timeRow ])
        view.axis = .horizontal
        view.spacing = 0
        view.isLayoutMarginsRelativeArrangement = true
        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 3)
        return view
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
        nameContentTimeRow.addArrangedSubview(audioRow)
        nameContentTimeRow.addArrangedSubview(audioTimeRow)
        nameContentTimeRow.setCustomSpacing(0, after: audioRow)
        contentView.addSubview(messageRow)
        messageRow.constrain([.top], to: contentView)
        messageRow.constrain(anchor: .bottom, to: contentView, priority: UILayoutPriority(rawValue: 999))
        
        NSLayoutConstraint.activate([
            audioView.widthAnchor.constraint(equalToConstant: AudioViewWidth),
            audioView.heightAnchor.constraint(equalToConstant: AudioViewHeight),
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
        super.configureWith(comment: comment, userColorAssignment: userColorAssignment, parentUserColorAssignment: parentUserColorAssignment, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
        audioMediaStatusCancellable?.cancel()

        // Download any pending media, comes in handy for media coming in while user is viewing comments
        MainAppContext.shared.feedData.downloadMedia(in: [comment])
        MainAppContext.shared.feedData.loadImages(commentID: comment.id)
        if comment.media?.count == 1, let media = comment.media?.first, media.type == .audio {
            configureAudio(audioMedia: media,
                                isOwn: comment.userId == MainAppContext.shared.userData.userId,
                                isPlayed: comment.status == .played)
        }
        configureCell()
    }

    override func configureWith(message: ChatMessage) {
        if audioMediaStatusCancellable != nil {
            audioMediaStatusCancellable?.cancel()
            audioMediaStatusCancellable = nil
        }
        super.configureWith(message: message)
        if message.media?.count == 1, let media = message.media?.first, media.type == .audio {
            configureAudio(audioMedia: media,
                           isOwn: message.fromUserId == MainAppContext.shared.userData.userId,
                           isPlayed: [.played, .sentPlayedReceipt].contains(message.incomingStatus))
        }
        super.configureCell()
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

    // Adjusting constraint priorities here in a single place to be able to easily see relative priorities.
    override func configureCell() {
        super.configureCell()
        if isOwnMessage {
            nameContentTimeRow.layoutMargins =  UIEdgeInsets(top: 16, left: 6, bottom: 6, right: 6)
        } else {
            nameContentTimeRow.layoutMargins =  UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        }
    }

    func playVoiceNote() {
        audioView.play()
    }

    func pauseVoiceNote() {
        audioView.pause()
    }
}

// MARK: AudioViewDelegate
extension MessageCellViewAudio: AudioViewDelegate {
    func audioView(_ view: AudioView, at time: String) {
        audioTimeLabel.text = time
    }

    func audioViewDidStartPlaying(_ view: AudioView) {
        if let commentId = feedPostComment?.id {
            MainAppContext.shared.feedData.markCommentAsPlayed(commentId: commentId)
        } else if let messageID = chatMessage?.id {
            audioView.state = .played
            MainAppContext.shared.chatData.markPlayedMessage(for: messageID)
        }
    }

    func audioViewDidEndPlaying(_ view: AudioView, completed: Bool) {
        guard completed else { return }
        guard let messageID = chatMessage?.id else { return }
        chatDelegate?.messageView(self, didCompleteVoiceNote: messageID)
    }
}
