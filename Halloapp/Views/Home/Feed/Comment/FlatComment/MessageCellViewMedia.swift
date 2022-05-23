//
//  MessageCellViewMedia.swift
//  HalloApp
//
//  Created by Nandini Shetty on 3/7/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import Foundation
import UIKit

class MessageCellViewMedia: MessageCellViewBase {
    private static let mediaLoadingQueue = DispatchQueue(label: "com.halloapp.media-loading", qos: .userInitiated)

    var MediaViewDimention: CGFloat { return 238.0 }
    var MediaViewCorner: CGFloat { return 10 }
    var MediaViewSpacing: CGFloat { return 6 }
    
    // MARK: Media

    private lazy var mediaCarouselView: MediaCarouselView = {
        var configuration = MediaCarouselViewConfiguration.default
        configuration.cornerRadius = 8
        configuration.alwaysScaleToFitContent = false
        let mediaCarouselView = MediaCarouselView(media: [], configuration: configuration)
        mediaCarouselView.delegate = self

        NSLayoutConstraint.activate([
            mediaCarouselView.widthAnchor.constraint(equalToConstant: MediaViewDimention),
            mediaCarouselView.heightAnchor.constraint(equalToConstant: MediaViewDimention),
        ])

        return mediaCarouselView
    }()

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

    private lazy var imagesContainerView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        for _ in 1...4 {
            let imageView = makeImageView()
            let videoIndicatorView = makeVideoIndicatorView()

            imageViews.append(imageView)
            videoIndicatorViews.append(videoIndicatorView)

            imageView.addSubview(videoIndicatorView)
            container.addSubview(imageView)

            videoIndicatorView.constrain(to: imageView)
        }

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: MediaViewDimention),
            container.heightAnchor.constraint(equalToConstant: MediaViewDimention),
            imageViews[0].topAnchor.constraint(equalTo: container.topAnchor),
            imageViews[0].leftAnchor.constraint(equalTo: container.leftAnchor),
            imageViews[1].topAnchor.constraint(equalTo: container.topAnchor),
            imageViews[1].rightAnchor.constraint(equalTo: container.rightAnchor),
            imageViews[2].bottomAnchor.constraint(equalTo: container.bottomAnchor),
            imageViews[2].leftAnchor.constraint(equalTo: container.leftAnchor),
            imageViews[3].bottomAnchor.constraint(equalTo: container.bottomAnchor),
            imageViews[3].rightAnchor.constraint(equalTo: container.rightAnchor),
        ])

        imageViews[3].addSubview(moreImagesView)
        moreImagesView.constrain(to: imageViews[3])

        return container
    }()

    private var imageViews: [UIImageView] = []
    private var imageViewsConstraints: [NSLayoutConstraint] = []
    private var videoIndicatorViews: [UIView] = []
    
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

    private func makeImageView() -> UIImageView {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = MediaViewCorner
        imageView.layer.masksToBounds = true
        imageView.isUserInteractionEnabled = true

        return imageView
    }

    private func makeVideoIndicatorView() -> UIView {
        let imageConfig = UIImage.SymbolConfiguration(pointSize: 32)
        let image = UIImage(systemName: "play.fill", withConfiguration: imageConfig)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        let indicatorView = UIImageView(image: image)
        indicatorView.translatesAutoresizingMaskIntoConstraints = false
        indicatorView.contentMode = .center
        indicatorView.isUserInteractionEnabled = false

        indicatorView.layer.shadowColor = UIColor.black.cgColor
        indicatorView.layer.shadowOffset = CGSize(width: 0, height: 1)
        indicatorView.layer.shadowOpacity = 0.3
        indicatorView.layer.shadowRadius = 4

        return indicatorView
    }

    private func setupView() {
        backgroundColor = UIColor.feedBackground
        contentView.preservesSuperviewLayoutMargins = false
        nameContentTimeRow.addArrangedSubview(nameRow)
        nameContentTimeRow.addArrangedSubview(mediaCarouselView)
        nameContentTimeRow.addArrangedSubview(imagesContainerView)
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

    override func configureWith(comment: FeedPostComment, userColorAssignment: UIColor, parentUserColorAssignment: UIColor, isPreviousMessageFromSameSender: Bool) {
        super.configureWith(comment: comment, userColorAssignment: userColorAssignment, parentUserColorAssignment: parentUserColorAssignment, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
        configureText(comment: comment)
        configureMedia(comment: comment)
        super.configureCell()
    }
 
    private func configureMedia(comment: FeedPostComment) {
        imagesContainerView.isHidden = true

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

    override func configureWith(message: ChatMessage) {
        super.configureWith(message: message)
        configureText(chatMessage: message)

        if let media = message.media?.sorted(by: { $0.order < $1.order }), media.count > 0 {
            configure(media: media)
        } else {
            DDLogError("MessageCellViewMedia/configure/error missing media for message " + message.id)
        }

        super.configureCell()
        nameRow.isHidden = true
    }

    private func configure(media: [CommonMedia]) {
        mediaCarouselView.isHidden = true

        configureMediaLayout(for: media)
        load(media: media)

        for (i, item) in media[0..<min(imageViews.count, media.count)].enumerated() {
            videoIndicatorViews[i].isHidden = item.type != .video
        }

        if media.count > imageViews.count {
            moreImagesView.isHidden = false
            moreImagesLabel.text = "+\(media.count - imageViews.count)"
        } else {
            moreImagesView.isHidden = false
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
                imageViews[0].widthAnchor.constraint(equalTo: imagesContainerView.widthAnchor),
                imageViews[0].heightAnchor.constraint(equalTo: imagesContainerView.heightAnchor),
            ]
        case 2:
            imageViewsConstraints = [
                imageViews[0].widthAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[0].heightAnchor.constraint(equalTo: imagesContainerView.heightAnchor),
                imageViews[1].widthAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[1].heightAnchor.constraint(equalTo: imagesContainerView.heightAnchor),
            ]
        case 3:
            imageViewsConstraints = [
                imageViews[0].widthAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[0].heightAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[1].widthAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[1].heightAnchor.constraint(equalToConstant: MediaViewDimention / 2 - MediaViewSpacing / 2),
                imageViews[2].widthAnchor.constraint(equalTo: imagesContainerView.widthAnchor),
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
        let id = chatMessage?.id
        let items = media[0..<min(imageViews.count, media.count)]

        MessageCellViewMedia.mediaLoadingQueue.async { [weak self] in
            guard let self = self else { return }
            guard id == self.chatMessage?.id else { return }

            for (i, item) in items.enumerated() {
                guard let url = item.mediaURL else { continue }

                let image: UIImage?
                switch item.type {
                case .image:
                    image = UIImage(contentsOfFile: url.path)
                case .video:
                    image = VideoUtils.videoPreviewImage(url: url)
                case .audio:
                    continue // this type is handled by another cell
                }

                DispatchQueue.main.async {
                    self.imageViews[i].image = image
                }
            }
        }
    }
}

extension MessageCellViewMedia: MediaCarouselViewDelegate {

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
