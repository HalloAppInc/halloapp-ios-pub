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
        static let commentIndicatorSize: CGFloat = 5
        static let audioAvatarSize: CGFloat = 60
        static let audioAvatarMicSize: CGFloat = 32
    }

    // MARK: Body Views

    private let textView: UITextView = {
        let textView = UITextView()
        textView.adjustsFontForContentSizeCategory = true
        textView.dataDetectorTypes = .link
        textView.font = .scaledSystemFont(ofSize: 19, weight: .regular)
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.isUserInteractionEnabled = false
        textView.linkTextAttributes = [.foregroundColor: UIColor.link]
        textView.textColor = UIColor(dynamicProvider: {
            switch $0.userInterfaceStyle {
            case .dark:
                return .white.withAlphaComponent(0.8)
            default:
                return .white
            } 
        })
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        return textView
    }()

    private let imageView: MediaImageView = {
        return MediaImageView(configuration: .groupGrid)
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
        commentIndicator.backgroundColor = .systemBlue
        commentIndicator.layer.cornerRadius = Constants.commentIndicatorSize / 2
        return commentIndicator
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

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = .feedPostBackground
        contentView.layer.cornerRadius = 9

        contentView.layer.shadowOffset = .zero
        contentView.layer.shadowOpacity = 1
        contentView.layer.shadowRadius = 10

        // Body
        // Add first to position below other content
        textView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        audioBlurView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(audioBlurView)

        [textView, imageView, audioBlurView].forEach {
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

        // Header
        let headerStackView = UIStackView(arrangedSubviews: [nameLabel])
        headerStackView.alignment = .center
        headerStackView.axis = .horizontal
        headerStackView.isLayoutMarginsRelativeArrangement = true
        headerStackView.layoutMargins = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        headerStackView.spacing = 6
        headerStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerStackView)

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
        footerStackView.spacing = 6
        footerStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(footerStackView)

        NSLayoutConstraint.activate([
            // Header
            headerStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerStackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerStackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),

            // Body
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            textView.topAnchor.constraint(equalTo: headerStackView.bottomAnchor),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: footerStackView.topAnchor),

            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.topAnchor.constraint(equalTo: headerStackView.bottomAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: footerStackView.topAnchor),

            audioBlurView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            audioBlurView.topAnchor.constraint(equalTo: headerStackView.bottomAnchor),
            audioBlurView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            audioBlurView.bottomAnchor.constraint(equalTo: footerStackView.topAnchor),

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

            // Footer
            commentIndicator.widthAnchor.constraint(equalToConstant: Constants.commentIndicatorSize),
            commentIndicator.heightAnchor.constraint(equalToConstant: Constants.commentIndicatorSize),

            footerStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            footerStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            footerStackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
        ])

        updateBorderAndShadowColors()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(with post: FeedPost) {
        audioAvatarChangedCancellable?.cancel()

        nameLabel.text = MainAppContext.shared.contactStore.fullNameIfAvailable(for: post.userID,
                                                                                ownName: Localizations.meCapitalized) ?? Localizations.unknownContact
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
            // load image, if available
            visibleMedia.loadImage()

            switch visibleMedia.type {
            case .audio:
                let userAvatar = MainAppContext.shared.avatarStore.userAvatar(forUserId: post.userID)

                audioAvatarView.configure(with: userAvatar, using: MainAppContext.shared.avatarStore)
                audioDurationLabel.text = Self.durationFormatter.string(from: visibleMedia.fileURL.flatMap { AVAsset(url: $0).duration.seconds } ?? 0)

                imageView.clipsToBounds = true
                imageView.contentMode = .scaleAspectFill
                imageView.image = userAvatar.image ?? AvatarView.defaultImage
                audioAvatarChangedCancellable = userAvatar.imageDidChange.sink { [weak self] image in
                    self?.imageView.image = image ?? AvatarView.defaultImage
                }
                showAudioView = true
                showImageView = true
            case .image, .video:
                visibleMedia.loadImage()
                imageView.configure(with: visibleMedia)
                showImageView = true
            }
        } else {
            // Text post
            let mentionText = MainAppContext.shared.contactStore.textWithMentions(post.rawText, mentions: post.orderedMentions)
            let bodyFont = textView.font ?? UIFont()
            let mentionFont = UIFont(descriptor: bodyFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)

            textView.attributedText = mentionText.flatMap {
                HAMarkdown(font: bodyFont, color: textView.textColor ?? .white)
                    .parse($0)
                    .applyingFontForMentions(mentionFont)
            }
            textView.backgroundColor = Self.backgroundColor(for: post.id)

            showTextView = true
        }

        textView.isHidden = !showTextView
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

        commentIndicator.alpha = (post.unreadCount > 0) ? 1 : 0

        // Initiate download for images that were not yet downloaded.
        MainAppContext.shared.feedData.downloadMedia(in: [post])
    }
    
    func startAnimations() {
        imageView.startAnimating()
    }
    
    func stopAnimations() {
        imageView.stopAnimating()
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

    private static let postBackgroundColors = [
        UIColor(named: "GroupFeedCellBackground1"),
        UIColor(named: "GroupFeedCellBackground2"),
        UIColor(named: "GroupFeedCellBackground3"),
        UIColor(named: "GroupFeedCellBackground4"),
        UIColor(named: "GroupFeedCellBackground5"),
        UIColor(named: "GroupFeedCellBackground6"),
        UIColor(named: "GroupFeedCellBackground7"),
        UIColor(named: "GroupFeedCellBackground8"),
        UIColor(named: "GroupFeedCellBackground9"),
        UIColor(named: "GroupFeedCellBackground10"),
        UIColor(named: "GroupFeedCellBackground11"),
        UIColor(named: "GroupFeedCellBackground12"),
    ].compactMap { $0 }

    private static func backgroundColor(for postID: FeedPostID) -> UIColor {
        return postBackgroundColors[abs(postID.hashValue) % postBackgroundColors.count]
    }
}