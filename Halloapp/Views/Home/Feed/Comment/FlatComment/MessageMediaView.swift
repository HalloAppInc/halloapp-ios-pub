//
//  MessageMediaView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 6/6/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import Combine
import UIKit

protocol MessageMediaViewDelegate: AnyObject {
    func messageMediaView(_ view: MediaImageView, forComment: FeedPostCommentID, didTapMediaAtIndex index: Int)
    func messageMediaView(_ view: MediaImageView, forMessage: ChatMessageID, didTapMediaAtIndex index: Int)
}

class MessageMediaView: UIView {

    var chatMessage: ChatMessage?
    var feedPostComment: FeedPostComment?

    weak var delegate: MessageMediaViewDelegate?

    var MediaViewDimention: CGFloat { return 238.0 }
    var MediaViewCorner: CGFloat { return 10 }
    var MediaViewSpacing: CGFloat { return 6 }

    private lazy var moreImagesLabel: UILabel = {
        var label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = .systemFont(ofSize: 30)
        label.textAlignment = .center

        return label
    }()

    private lazy var moreImagesView: UIView = {
        let blurredEffectView = BlurView(effect: UIBlurEffect(style: .systemUltraThinMaterial), intensity: 0.5)
        blurredEffectView.isUserInteractionEnabled = false
        blurredEffectView.translatesAutoresizingMaskIntoConstraints = false

        blurredEffectView.contentView.addSubview(moreImagesLabel)
        moreImagesLabel.constrain(to: blurredEffectView.contentView)

        return blurredEffectView
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
        translatesAutoresizingMaskIntoConstraints = false

        for _ in 0..<4 {
            let imageView = MediaImageView(configuration: .message)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.isUserInteractionEnabled = true
            imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onTapAction(sender:))))
            imageView.layer.cornerRadius = MediaViewCorner

            imageViews.append(imageView)
            addSubview(imageView)
        }

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: MediaViewDimention),
            heightAnchor.constraint(equalToConstant: MediaViewDimention),
            imageViews[0].topAnchor.constraint(equalTo: topAnchor),
            imageViews[0].leftAnchor.constraint(equalTo: leftAnchor),
            imageViews[1].topAnchor.constraint(equalTo: topAnchor),
            imageViews[1].rightAnchor.constraint(equalTo: rightAnchor),
            imageViews[2].bottomAnchor.constraint(equalTo: bottomAnchor),
            imageViews[2].leftAnchor.constraint(equalTo: leftAnchor),
            imageViews[3].bottomAnchor.constraint(equalTo: bottomAnchor),
            imageViews[3].rightAnchor.constraint(equalTo: rightAnchor),
        ])

        imageViews[3].addSubview(moreImagesView)
        moreImagesView.constrain(to: imageViews[3])
    }

    private var imageViews: [MediaImageView] = []
    private var imageViewsConstraints: [NSLayoutConstraint] = []
    private var cancellables: Set<AnyCancellable> = []
    
    public func configure(chatMessage: ChatMessage, media: [CommonMedia]) {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()

        self.chatMessage = chatMessage
        configureMediaLayout(for: media)
        load(media: media)

        if media.count > imageViews.count {
            moreImagesView.isHidden = false
            moreImagesLabel.text = "+\(media.count - imageViews.count + 1)"
        } else {
            moreImagesView.isHidden = true
        }
    }

    public func configure(feedPostComment: FeedPostComment, media: [CommonMedia]) {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()

        self.feedPostComment = feedPostComment
        configureMediaLayout(for: media)
        load(media: media)

        if media.count > imageViews.count {
            moreImagesView.isHidden = false
            moreImagesLabel.text = "+\(media.count - imageViews.count + 1)"
        } else {
            moreImagesView.isHidden = true
        }
    }

    private func configureMediaLayout(for media: [CommonMedia]) {
        NSLayoutConstraint.deactivate(imageViewsConstraints)
        imageViewsConstraints.removeAll()
        imageViews.forEach { $0.isHidden = true }

        guard media.count > 0 else { return }

        let mediaCount = min(imageViews.count, media.count)
        imageViews[0..<mediaCount].forEach { $0.isHidden = false }

        switch media.count {
        case 1:
            imageViewsConstraints = [
                imageViews[0].widthAnchor.constraint(equalTo: widthAnchor),
                imageViews[0].heightAnchor.constraint(equalTo: heightAnchor),
            ]
        case 2:
            imageViewsConstraints = [
                imageViews[0].widthAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[0].heightAnchor.constraint(equalTo: heightAnchor),
                imageViews[1].widthAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[1].heightAnchor.constraint(equalTo: heightAnchor),
            ]
        case 3:
            imageViewsConstraints = [
                imageViews[0].widthAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[0].heightAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[1].widthAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[1].heightAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[2].widthAnchor.constraint(equalTo: widthAnchor),
                imageViews[2].heightAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
            ]
        default:
            imageViewsConstraints = [
                imageViews[0].widthAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[0].heightAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[1].widthAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[1].heightAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[2].widthAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[2].heightAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[3].widthAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[3].heightAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
            ]
        }

        NSLayoutConstraint.activate(imageViewsConstraints)
    }

    private func load(media: [CommonMedia]) {
        let items = media[0..<min(imageViews.count, media.count)]

        for (idx, item) in items.enumerated() {
            let imageView = imageViews[idx]
            imageView.configure(with: item)
        }
    }

    public func imageView(at index: Int) -> MediaImageView? {
        guard index < imageViews.count else { return nil }
        guard !imageViews[index].isHidden else { return nil }

        return imageViews[index]
    }

    @objc private func onTapAction(sender: UITapGestureRecognizer) {
        guard let imageView = sender.view as? MediaImageView else { return }
        guard let idx = imageViews.firstIndex(of: imageView) else { return }

        if let commentID = self.feedPostComment?.id {
            self.delegate?.messageMediaView(imageView, forComment: commentID, didTapMediaAtIndex: idx)
        } else if let messageID = self.chatMessage?.id {
            self.delegate?.messageMediaView(imageView, forMessage: messageID, didTapMediaAtIndex: idx)
        }
    }
}
