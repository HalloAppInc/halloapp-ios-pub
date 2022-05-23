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
    private static let mediaLoadingQueue = DispatchQueue(label: "com.halloapp.media-loading", qos: .userInitiated)

    var MediaViewDimention: CGFloat { return 238.0 }
    var MediaViewCorner: CGFloat { return 10 }
    var MediaViewSpacing: CGFloat { return 6 }
    
    // MARK: Media

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

        for idx in 0..<4 {
            let imageView = PreviewImageView()
            imageView.layer.cornerRadius = MediaViewCorner

            imageViews.append(imageView)
            container.addSubview(imageView)

            imageView.onTap = { [weak self] in
                guard let self = self else { return }

                if let commentID = self.feedPostComment?.id {
                    self.commentDelegate?.messageView(imageView, forComment: commentID, didTapMediaAtIndex: idx)
                }
            }
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

    private var imageViews: [PreviewImageView] = []
    private var imageViewsConstraints: [NSLayoutConstraint] = []
    private var cancellables: Set<AnyCancellable> = []
    
    override func prepareForReuse() {
        super.prepareForReuse()
        textLabel.attributedText = nil
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
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

        if let media = comment.media?.sorted(by: { $0.order < $1.order }), media.count > 0 {
            MainAppContext.shared.feedData.downloadMedia(in: [comment])
            // required so that fullscreen open works
            // TODO(stefan): remove it once fullscreen works only with CommonMedia
            MainAppContext.shared.feedData.loadImages(commentID: comment.id)
            configure(media: media)
        } else {
            DDLogError("MessageCellViewMedia/configure/error missing media for comment " + comment.id)
        }

        configureCell()
    }

    override func configureWith(message: ChatMessage) {
        super.configureWith(message: message)
        configureText(chatMessage: message)

        if let media = message.media?.sorted(by: { $0.order < $1.order }), media.count > 0 {
            MainAppContext.shared.chatData.downloadMedia(in: message)
            configure(media: media)
        } else {
            DDLogError("MessageCellViewMedia/configure/error missing media for message " + message.id)
        }

        configureCell()

        // hide empty space above media on incomming messages
        nameRow.isHidden = true
    }

    private func configure(media: [CommonMedia]) {
        configureMediaLayout(for: media)
        load(media: media)

        if media.count > imageViews.count {
            moreImagesView.isHidden = false
            moreImagesLabel.text = "+\(media.count - imageViews.count)"
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
        let items = media[0..<min(imageViews.count, media.count)].map { (item: CommonMedia) -> (CommonMediaType, URL?) in
            return (item.type, item.mediaURL)
        }

        for (idx, item) in items.enumerated() {
            let imageView = imageViews[idx]

            if let url = item.1 {
                display(url: url, type: item.0, in: imageView)
            } else {
                imageView.image = nil
                imageView.isProgressHidden = false
            }
        }

        listenForDownloadProgress(media: media)
    }

    private func listenForDownloadProgress(media: [CommonMedia]) {
        var items: [String: (idx: Int, type: CommonMediaType)] = [:]
        for (i, item) in media.enumerated() {
            items[item.id] = (idx: i, type: item.type)
        }

        FeedDownloadManager.downloadProgress.receive(on: DispatchQueue.main).sink { [weak self] (id, progress) in
            guard let self = self else { return }
            guard let item = items[id] else { return }
            guard self.imageViews.count > item.idx else { return }

            self.imageViews[item.idx].progress = progress
        }.store(in: &cancellables)

        FeedDownloadManager.mediaDidBecomeAvailable.receive(on: DispatchQueue.main).sink { [weak self] (id, url) in
            guard let self = self else { return }
            guard let item = items[id] else { return }
            guard self.imageViews.count > item.idx else { return }

            self.display(url: url, type: item.type, in: self.imageViews[item.idx])
        }.store(in: &cancellables)
    }

    private func display(url: URL, type: CommonMediaType, in imageView: PreviewImageView) {
        let id: String? = chatMessage?.id ?? feedPostComment?.id

        MessageCellViewMedia.mediaLoadingQueue.async {
            let image: UIImage?
            switch type {
            case .image:
                image = UIImage(contentsOfFile: url.path)
            case .video:
                image = VideoUtils.videoPreviewImage(url: url)
            case .audio:
                return // this type is handled by another cell
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard self.chatMessage?.id == id || self.feedPostComment?.id == id else { return }

                imageView.isVideo = type == .video
                imageView.isProgressHidden = true
                imageView.image = image
            }
        }
    }
}

fileprivate class PreviewImageView: UIImageView {

    var isVideo = false {
        didSet {
            videoIndicatorView.isHidden = !isVideo
        }
    }

    var progress: Float {
        set {
            progressView.setProgress(newValue, animated: true)
        }
        get {
            progressView.progress
        }
    }

    var isProgressHidden = true {
        didSet {
            placeholderView.isHidden = isProgressHidden
            progressView.isHidden = isProgressHidden
        }
    }

    var onTap: (() -> Void)?

    private lazy var videoIndicatorView: UIView = {
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
        indicatorView.layer.shadowPath = UIBezierPath(ovalIn: indicatorView.bounds).cgPath

        indicatorView.isHidden = true

        return indicatorView
    }()

    private lazy var placeholderView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "photo")
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .largeTitle)
        imageView.contentMode = .center
        imageView.tintColor = .systemGray3

        imageView.isHidden = true

        return imageView
    }()

    private lazy var progressView: CircularProgressView = {
        let progressView = CircularProgressView()
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.barWidth = 2
        progressView.trackTintColor = .systemGray3

        progressView.isHidden = true

        return progressView
    }()

    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        self.translatesAutoresizingMaskIntoConstraints = false
        self.contentMode = .scaleAspectFill
        self.layer.masksToBounds = true
        self.isUserInteractionEnabled = true

        addSubview(videoIndicatorView)
        addSubview(placeholderView)
        addSubview(progressView)

        NSLayoutConstraint.activate([
            videoIndicatorView.centerXAnchor.constraint(equalTo: centerXAnchor),
            videoIndicatorView.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholderView.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderView.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressView.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressView.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressView.widthAnchor.constraint(equalToConstant: 72),
            progressView.heightAnchor.constraint(equalToConstant: 72),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onTapAction)))
    }

    @objc private func onTapAction() {
        if let onTap = onTap {
            onTap()
        }
    }
}
