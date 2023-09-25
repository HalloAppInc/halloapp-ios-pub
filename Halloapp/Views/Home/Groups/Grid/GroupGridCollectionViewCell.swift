//
//  GroupGridCollectionViewCell.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 5/6/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Combine
import Core
import CoreCommon
import UIKit
import AVFoundation

class GroupGridCollectionViewCell: UICollectionViewCell {

    static let reuseIdentifier = String(describing: GroupGridCollectionViewCell.self)

    var openPost: (() -> Void)?

    private struct Constants {
        static let commentIndicatorSize: CGFloat = 7
        static let audioAvatarSize: CGFloat = 60
        static let audioAvatarMicSize: CGFloat = 32
    }

    // MARK: Body Views

    private let textBackground = UIView()

    private let textLabel: UILabel = {
        let textLabel = UILabel()
        textLabel.adjustsFontForContentSizeCategory = true
        textLabel.adjustsFontSizeToFitWidth = true
        textLabel.numberOfLines = 0
        return textLabel
    }()

    private let imageView: MediaImageView = {
        let imageView = MediaImageView(configuration: .groupGrid)
        imageView.canPlayVideoPreviews = false
        return imageView
    }()

    private let audioBlurView: UIVisualEffectView = {
        let audioBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        audioBlurView.backgroundColor = .white.withAlphaComponent(0.4)
        return audioBlurView
    }()

    private let audioAvatarView: AvatarView = {
        let audioAvatarView = AvatarView()

        let audioImageView = UIImageView(image: UIImage(systemName: "mic.fill"))
        audioImageView.backgroundColor = .systemBlue
        audioImageView.contentMode = .center
        audioImageView.tintColor = .white
        audioImageView.layer.cornerRadius = Constants.audioAvatarMicSize / 2
        audioImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: Constants.audioAvatarMicSize * 0.6)
        audioImageView.translatesAutoresizingMaskIntoConstraints = false
        audioAvatarView.addSubview(audioImageView)

        NSLayoutConstraint.activate([
            audioImageView.centerXAnchor.constraint(equalTo: audioAvatarView.trailingAnchor),
            audioImageView.bottomAnchor.constraint(equalTo: audioAvatarView.bottomAnchor),
            audioImageView.widthAnchor.constraint(equalToConstant: Constants.audioAvatarMicSize),
            audioImageView.heightAnchor.constraint(equalToConstant: Constants.audioAvatarMicSize),
        ])

        return audioAvatarView
    }()

    private let audioDurationLabel: UILabel = {
        let audioDurationLabel = UILabel()
        audioDurationLabel.font = .scaledSystemFont(ofSize: 12, weight: .semibold)
        audioDurationLabel.textColor = .label.withAlphaComponent(0.8)

        return audioDurationLabel
    }()

    private let newPostIndicator: UIView = {
        let newPostLabel = UILabel()
        newPostLabel.font = .scaledSystemFont(ofSize: 13, weight: .bold)
        newPostLabel.text = Localizations.newPostIndicator
        newPostLabel.textColor = .white
        newPostLabel.translatesAutoresizingMaskIntoConstraints = false

        let newPostView = PillView()
        newPostView.fillColor = .lavaOrange
        newPostView.addSubview(newPostLabel)

        NSLayoutConstraint.activate([
            newPostLabel.leadingAnchor.constraint(equalTo: newPostView.leadingAnchor, constant: 6),
            newPostLabel.topAnchor.constraint(equalTo: newPostView.topAnchor),
            newPostLabel.bottomAnchor.constraint(equalTo: newPostView.bottomAnchor, constant: -2),
            newPostLabel.trailingAnchor.constraint(equalTo: newPostView.trailingAnchor, constant: -6),
        ])

        return newPostView
    }()

    // MARK: Header Views

    private let nameLabel: UILabel = {
        let nameLabel = UILabel()
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.font = .scaledSystemFont(ofSize: 14, weight: .semibold)
        nameLabel.textColor = .label.withAlphaComponent(0.6)
        return nameLabel
    }()

    // MARK: Footer Views

    private let commentIndicator: UIView = {
        let commentIndicator = UIView()
        commentIndicator.layer.cornerRadius = Constants.commentIndicatorSize / 2
        return commentIndicator
    }()

    // MARK: Progress Overlay

    private let progressView: GroupGridProgressView = {
        let progressControl = GroupGridProgressView()
        return progressControl
    }()

    private class ContentIndicatorImageView: UIImageView {

        init() {
            super.init(frame: .zero)

            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOffset = .zero
            layer.shadowOpacity = 0.1
            layer.shadowRadius = 4
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            layer.shadowPath = UIBezierPath(roundedRect: bounds.insetBy(dx: bounds.width > 8 ? 4 : 0, dy: bounds.height > 8 ? 4 : 0), cornerRadius: 4).cgPath
        }

        override var intrinsicContentSize: CGSize {
            return image?.size ?? .zero
        }
    }

    private let leadingContentTypeImageView = ContentIndicatorImageView()

    private let trailingContentTypeImageView = ContentIndicatorImageView()

    // MARK: Util

    private var audioAvatarChangedCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var uploadProgressCancellables = Set<AnyCancellable>()
    private var linkDetectionWorkItem: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = .feedPostBackground
        contentView.clipsToBounds = true
        contentView.layer.cornerRadius = 9

        layer.shadowRadius = 10.0
        layer.shadowOffset = .zero
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08

        // Body
        // Add first to position below other content
        textBackground.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textBackground)

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textBackground.addSubview(textLabel)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        audioBlurView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(audioBlurView)

        [textLabel, imageView, audioBlurView].forEach {
            $0.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
            $0.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        }

        audioAvatarView.translatesAutoresizingMaskIntoConstraints = false
        audioBlurView.contentView.addSubview(audioAvatarView)

        audioDurationLabel.translatesAutoresizingMaskIntoConstraints = false
        audioBlurView.contentView.addSubview(audioDurationLabel)

        leadingContentTypeImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(leadingContentTypeImageView)

        trailingContentTypeImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(trailingContentTypeImageView)

        newPostIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(newPostIndicator)

        // Header
        let headerStackView = UIStackView(arrangedSubviews: [nameLabel])
        headerStackView.alignment = .center
        headerStackView.axis = .horizontal
        headerStackView.isLayoutMarginsRelativeArrangement = true
        headerStackView.layoutMargins = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        headerStackView.spacing = 6
        headerStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerStackView)

        let headerStackViewBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        headerStackViewBackground.translatesAutoresizingMaskIntoConstraints = false
        headerStackView.insertSubview(headerStackViewBackground, at: 0)

        // Footer
        let commentImageView = UIImageView(image: UIImage(named: "FeedPostComment")?.withRenderingMode(.alwaysTemplate))
        commentImageView.tintColor = .label.withAlphaComponent(0.675)

        let commentLabel = UILabel()
        commentLabel.adjustsFontForContentSizeCategory = true
        commentLabel.font = .scaledGothamFont(ofSize: 13, weight: .medium)
        commentLabel.text = Localizations.feedComment
        commentLabel.textColor = .label.withAlphaComponent(0.675)
        commentLabel.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)

        let footerStackView = UIStackView(arrangedSubviews: [commentImageView, commentLabel, commentIndicator])
        footerStackView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openPostTapped)))
        footerStackView.alignment = .center
        footerStackView.axis = .horizontal
        footerStackView.isLayoutMarginsRelativeArrangement = true
        footerStackView.isUserInteractionEnabled = true
        footerStackView.layoutMargins = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        footerStackView.setCustomSpacing(4, after: commentImageView)
        footerStackView.setCustomSpacing(6, after: commentLabel)
        footerStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(footerStackView)

        let footerStackViewBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        footerStackViewBackground.translatesAutoresizingMaskIntoConstraints = false
        footerStackView.insertSubview(footerStackViewBackground, at: 0)

        // Progress View
        progressView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressView)

        NSLayoutConstraint.activate([
            // Header
            headerStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerStackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            headerStackViewBackground.leadingAnchor.constraint(equalTo: headerStackView.leadingAnchor),
            headerStackViewBackground.topAnchor.constraint(equalTo: headerStackView.topAnchor),
            headerStackViewBackground.bottomAnchor.constraint(equalTo: headerStackView.bottomAnchor),
            headerStackViewBackground.trailingAnchor.constraint(equalTo: headerStackView.trailingAnchor),

            // Body
            textBackground.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            textBackground.topAnchor.constraint(equalTo: contentView.topAnchor),
            textBackground.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            textBackground.bottomAnchor.constraint(equalTo: footerStackView.bottomAnchor),

            textLabel.leadingAnchor.constraint(equalTo: textBackground.leadingAnchor, constant: 12),
            textLabel.trailingAnchor.constraint(equalTo: textBackground.trailingAnchor, constant: -12),
            textLabel.topAnchor.constraint(greaterThanOrEqualTo: headerStackView.bottomAnchor, constant: 4),
            textLabel.centerYAnchor.constraint(equalTo: textBackground.centerYAnchor),

            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: footerStackView.bottomAnchor),

            audioBlurView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            audioBlurView.topAnchor.constraint(equalTo: contentView.topAnchor),
            audioBlurView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            audioBlurView.bottomAnchor.constraint(equalTo: footerStackView.bottomAnchor),

            audioAvatarView.widthAnchor.constraint(equalToConstant: Constants.audioAvatarSize),
            audioAvatarView.heightAnchor.constraint(equalToConstant: Constants.audioAvatarSize),
            audioAvatarView.centerXAnchor.constraint(equalTo: audioBlurView.centerXAnchor),
            audioAvatarView.centerYAnchor.constraint(equalTo: audioBlurView.centerYAnchor),

            audioDurationLabel.centerXAnchor.constraint(equalTo: audioAvatarView.centerXAnchor),
            audioDurationLabel.topAnchor.constraint(equalTo: audioAvatarView.bottomAnchor, constant: 4),

            leadingContentTypeImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            leadingContentTypeImageView.bottomAnchor.constraint(equalTo: footerStackView.topAnchor),

            trailingContentTypeImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            trailingContentTypeImageView.bottomAnchor.constraint(equalTo: footerStackView.topAnchor),

            newPostIndicator.topAnchor.constraint(equalTo: headerStackView.bottomAnchor, constant: 5),
            newPostIndicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),

            // Footer
            commentIndicator.widthAnchor.constraint(equalToConstant: Constants.commentIndicatorSize),
            commentIndicator.heightAnchor.constraint(equalToConstant: Constants.commentIndicatorSize),

            footerStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            footerStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            footerStackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),

            // footerStackView is leading aligned, while the background is full-width
            footerStackViewBackground.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            footerStackViewBackground.topAnchor.constraint(equalTo: footerStackView.topAnchor),
            footerStackViewBackground.bottomAnchor.constraint(equalTo: footerStackView.bottomAnchor),
            footerStackViewBackground.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            // Progress View
            progressView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            progressView.topAnchor.constraint(equalTo: contentView.topAnchor),
            progressView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        updateBorderAndShadowColors()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private var configuredPostID: FeedPostID?

    func configure(with post: FeedPost) {
        guard post.id != configuredPostID else {
            return
        }

        let postID = post.id
        configuredPostID = postID

        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        uploadProgressCancellables.forEach { $0.cancel() }
        uploadProgressCancellables.removeAll()

        nameLabel.text = post.user.displayName

        progressView.cancelAction = { MainAppContext.shared.feedData.cancelMediaUpload(postId: postID) }
        progressView.deleteAction = { MainAppContext.shared.feedData.deleteUnsentPost(postID: postID) }
        progressView.retryAction = { MainAppContext.shared.feedData.retryPosting(postId: postID) }

        let mediaCount = post.feedMedia.count
        let statusPublisher = post.publisher(for: \.statusValue).compactMap { FeedPost.Status(rawValue: $0) }

        // Content
        statusPublisher
            .sink { [weak self, post] _ in self?.configureContent(with: post) }
            .store(in: &cancellables)

        // Comment Indicator
        Publishers.CombineLatest(post.publisher(for: \.comments), post.publisher(for: \.unreadCount))
            .sink { [commentIndicator] (comments, unreadCount) in
                if unreadCount > 0 {
                    commentIndicator.backgroundColor = .groupFeedCommentIndicatorUnread
                } else if let comments = comments, !comments.isEmpty {
                    commentIndicator.backgroundColor = .groupFeedCommentIndicatorRead
                } else {
                    commentIndicator.backgroundColor = .clear
                }
            }
            .store(in: &cancellables)

        // New Post Indicator
        statusPublisher
            .sink { [newPostIndicator] status in newPostIndicator.isHidden = status != .incoming }
            .store(in: &cancellables)

        // Uploading overlay
        var animateStatusChange = false // Don't animate changes on initial bind
        statusPublisher
            .sink { [weak self, progressView] status in
                guard let self = self else {
                    return
                }
                switch status {
                case .sending, .retracting:
                    progressView.setState(.uploading, animated: animateStatusChange)
                    if mediaCount > 0 {
                        var animateProgressChange = false
                        MainAppContext.shared.feedData.uploadProgressPublisher(for: post)
                            .receive(on: DispatchQueue.main)
                            .sink { progress in
                                progressView.setProgress(progress, animated: animateProgressChange)
                                animateProgressChange = true
                            }
                            .store(in: &self.uploadProgressCancellables)
                    } else {
                        // For non media posts, show a tiny bit of progress
                        progressView.setProgress(0.1)
                    }
                case .sendError:
                    self.uploadProgressCancellables.removeAll()
                    progressView.setState(.failed, animated: animateStatusChange)
                default:
                    self.uploadProgressCancellables.removeAll()
                    progressView.setState(.hidden, animated: animateStatusChange)
                }
                animateStatusChange = true
            }
            .store(in: &cancellables)

        // Initiate download for images that were not yet downloaded.
        MainAppContext.shared.feedData.downloadMedia(in: [post])
    }

    private func configureContent(with post: FeedPost) {
        linkDetectionWorkItem?.cancel()

        var isLinkPreview = false
        var isAlbum = false
        var hasAudio = false

        let visibleMedia: FeedMedia? = {
            let feedMedia = post.feedMedia
            switch feedMedia.count {
            case 0:
                if let linkPreviewMedia = post.linkPreview?.feedMedia {
                    isLinkPreview = true
                    return linkPreviewMedia
                }
                return nil
            case 1:
                // Show audio if it is the only item
                return feedMedia.first
            default:
                isAlbum = true
                hasAudio = feedMedia.contains { [.audio].contains($0.type) }
                return feedMedia.first { [.image, .video].contains($0.type) }
            }
        }()

        var showImageView = false
        var showTextView = false
        var showAudioView = false

        if let visibleMedia = visibleMedia {
            switch visibleMedia.type {
            case .audio:
                let userAvatar = MainAppContext.shared.avatarStore.userAvatar(forUserId: post.userID)

                audioAvatarView.configure(with: userAvatar, using: MainAppContext.shared.avatarStore)
                audioDurationLabel.text = Self.durationFormatter.string(from: visibleMedia.fileURL.flatMap { AVAsset(url: $0).duration.seconds } ?? 0)

                imageView.clipsToBounds = true
                imageView.contentMode = .scaleAspectFill
                imageView.transform = CGAffineTransform(scaleX: sqrt(2.0), y: sqrt(2.0)) // scale up to fill entire background
                imageView.image = userAvatar.image ?? AvatarView.defaultImage
                userAvatar.imageDidChange
                    .sink { [imageView] in imageView.image = $0 ?? AvatarView.defaultImage }
                    .store(in: &cancellables)
                showAudioView = true
                showImageView = true
            case .image, .video:
                imageView.transform = .identity
                visibleMedia.loadImage()
                imageView.configure(with: visibleMedia)
                showImageView = true
            case .document:
                break
            }
        } else {
            // Text post
            let baseFont = UIFont.scaledSystemFont(ofSize: 19, weight: .regular)
            let textColor = UIColor {
                switch $0.userInterfaceStyle {
                case .dark:
                    return .white.withAlphaComponent(0.6)
                default:
                    return .white.withAlphaComponent(0.8)
                }
            }

            let textLabelMinimumScaleFactor: CGFloat
            if post.isUnsupported {
                textLabel.attributedText = NSAttributedString(string: "⚠️ \(Localizations.feedPostUnsupported)",
                                                              attributes: [.font: baseFont.withItalicsIfAvailable, .foregroundColor: textColor])
                textLabelMinimumScaleFactor = 0
            } else if post.isWaiting {
                textLabel.attributedText = NSAttributedString(string: "🕓 \(Localizations.feedPostWaiting)",
                                                              attributes: [.font: baseFont.withItalicsIfAvailable, .foregroundColor: textColor])
                textLabelMinimumScaleFactor = 0
            } else {
                let mentionText = UserProfile.text(with: post.orderedMentions,
                                                   collapsedText: post.rawText,
                                                   in: MainAppContext.shared.mainDataStore.viewContext)
                let mentionFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
                let attributedText = mentionText.flatMap {
                    HAMarkdown(font: baseFont, color: textColor)
                        .parse($0)
                        .applyingFontForMentions(mentionFont)
                }
                textLabel.attributedText = attributedText
                textLabelMinimumScaleFactor = 0.7

                if let attributedText = attributedText {
                    // manually detect links as we are using a uilabel to handle text scaling
                    let workItem = DispatchWorkItem { [weak self] in
                        guard let dataDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
                              let mutableAttributedText = attributedText.mutableCopy() as? NSMutableAttributedString else {
                            return
                        }
                        dataDetector.enumerateMatches(in: mutableAttributedText.string,
                                                      options: [],
                                                      range: NSRange(location: 0, length: mutableAttributedText.length)) { result, _, _ in
                            result.flatMap { mutableAttributedText.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: $0.range) }
                        }
                        DispatchQueue.main.async { [weak self] in
                            self?.textLabel.attributedText = mutableAttributedText
                        }
                    }
                    linkDetectionWorkItem = workItem
                    DispatchQueue.global(qos: .userInteractive).async(execute: workItem)
                }

            }
            textLabel.minimumScaleFactor = textLabelMinimumScaleFactor
            textBackground.backgroundColor = Self.backgroundColor(for: post.id)

            showTextView = true
        }

        textBackground.isHidden = !showTextView
        imageView.isHidden = !showImageView
        audioBlurView.isHidden = !showAudioView

        let leadingContentTypeImage: UIImage?
        if isLinkPreview {
            leadingContentTypeImage = UIImage(named: "GroupPostLinkIndicator")
        } else if hasAudio {
            leadingContentTypeImage = UIImage(named: "GroupPostAudioIndicator")
        } else {
            leadingContentTypeImage = nil
        }
        leadingContentTypeImageView.image = leadingContentTypeImage
        leadingContentTypeImageView.isHidden = (leadingContentTypeImage == nil)

        let trailingContentTypeImage: UIImage?
        if isAlbum {
            trailingContentTypeImage = UIImage(named: "GroupPostAlbumIndicator")
        } else {
            trailingContentTypeImage = nil
        }
        trailingContentTypeImageView.image = trailingContentTypeImage
        trailingContentTypeImageView.isHidden = (trailingContentTypeImage == nil)
    }

    func startAnimations() {
        imageView.canPlayVideoPreviews = true
    }

    func stopAnimations() {
        imageView.canPlayVideoPreviews = false
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateBorderAndShadowColors()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        contentView.layer.shadowPath = UIBezierPath(roundedRect: contentView.bounds,
                                                    cornerRadius: contentView.layer.cornerRadius).cgPath
    }

    @objc private func openPostTapped() {
        openPost?()
    }

    private func updateBorderAndShadowColors() {
        contentView.layer.shadowColor = UIColor.label
            .withAlphaComponent(0.12)
            .resolvedColor(with: traitCollection)
            .cgColor
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = [.second, .minute]
        return formatter
    }()

    private static let postBackgroundColors: [UIColor] = [
        .groupFeedCellBackground1,
        .groupFeedCellBackground2,
        .groupFeedCellBackground3,
        .groupFeedCellBackground4,
        .groupFeedCellBackground5,
        .groupFeedCellBackground6,
        .groupFeedCellBackground7,
        .groupFeedCellBackground8,
        .groupFeedCellBackground9,
        .groupFeedCellBackground10,
    ]

    private static func backgroundColor(for postID: FeedPostID) -> UIColor {
        return postBackgroundColors[abs(postID.hashValue % postBackgroundColors.count)]
    }
}

extension Localizations {

    static var newPostIndicator: String {
        NSLocalizedString("groupGrid.newPostIndicator", value: "new", comment: "Tag for new posts in groups grid")
    }
}
