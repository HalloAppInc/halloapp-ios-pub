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

class GroupGridCollectionViewCell: UICollectionViewCell {

    static let reuseIdentifier = String(describing: GroupGridCollectionViewCell.self)

    private struct Constants {
        static let commentIndicatorSize: CGFloat = 5
    }

    // MARK: Body Views

    private let textView: UITextView = {
        let textView = UITextView()
        textView.dataDetectorTypes = .link
        textView.font = .scaledSystemFont(ofSize: 13, weight: .regular)
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.isUserInteractionEnabled = false
        textView.linkTextAttributes = [.foregroundColor: UIColor.systemBlue]
        textView.textContainerInset = .zero
        return textView
    }()

    private lazy var imageView: UIImageView = {
        let contentImageView = UIImageView()
        contentImageView.clipsToBounds = true
        return contentImageView
    }()

    private lazy var audioPlayer: PostAudioView = {
        let audioPlayer = PostAudioView(configuration: .feed)
        audioPlayer.isUserInteractionEnabled = false
        return audioPlayer
    }()

    // MARK: Header Views

    private lazy var nameLabel: UILabel = {
        let nameLabel = UILabel()
        nameLabel.font = UIFont.scaledSystemFont(ofSize: 14, weight: .semibold)
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

    private let contentTypeImageView: UIImageView = {
        let contentTypeImageView = UIImageView()

        return contentTypeImageView
    }()

    private let pageControl: UIPageControl = {
        let pageControl = UIPageControl()
        pageControl.currentPageIndicatorTintColor = .lavaOrange
        return pageControl
    }()

    // MARK: Util

    private var imageLoadingCancellable: AnyCancellable?

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = .systemBackground
        contentView.layer.cornerRadius = 9
        contentView.layer.borderWidth = 1

        // Body
        // Add first to position below other content
        textView.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        textView.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        textView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textView)

        imageView.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        imageView.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        audioPlayer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(audioPlayer)

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
        let commentImageView = UIImageView(image: UIImage(named: "FeedPostComment"))
        imageView.tintColor = .label

        let commentLabel = UILabel()
        commentLabel.font = UIFont.scaledSystemFont(ofSize: 13, weight: .medium)
        commentLabel.text = Localizations.feedComment
        commentLabel.textColor = .label.withAlphaComponent(0.8)
        commentLabel.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)

        let footerStackView = UIStackView(arrangedSubviews: [commentImageView, commentLabel, commentIndicator])
        footerStackView.alignment = .center
        footerStackView.axis = .horizontal
        footerStackView.isLayoutMarginsRelativeArrangement = true
        footerStackView.layoutMargins = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        footerStackView.spacing = 6
        footerStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(footerStackView)

        contentTypeImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentTypeImageView)

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

            audioPlayer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            audioPlayer.centerXAnchor.constraint(equalTo: centerXAnchor),
            audioPlayer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            // Footer
            commentIndicator.widthAnchor.constraint(equalToConstant: Constants.commentIndicatorSize),
            commentIndicator.heightAnchor.constraint(equalToConstant: Constants.commentIndicatorSize),

            footerStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            footerStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            footerStackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
        ])

        updateBorderColor()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(with post: FeedPost) {
        imageLoadingCancellable?.cancel()

        nameLabel.text = MainAppContext.shared.contactStore.fullNameIfAvailable(for: post.userID,
                                                                                ownName: Localizations.meCapitalized) ?? Localizations.unknownContact

        var showImageView = false
        var showTextView = false
        var showAudioPlayer = false

        let visibleMedia: FeedMedia? = {
            let feedMedia = post.feedMedia
            if feedMedia.count == 1 {
                return feedMedia.first
            } else {
                return feedMedia.first { [.image, .video].contains($0.type) }
            }
        }()

        if let visibleMedia = visibleMedia {
            switch visibleMedia.type {
            case .audio:
                audioPlayer.feedMedia = visibleMedia
                showAudioPlayer = true
            case .image:
                var image: UIImage?
                if visibleMedia.isMediaAvailable {
                    image = visibleMedia.image
                } else {
                    imageLoadingCancellable = visibleMedia.imageDidBecomeAvailable.sink { [weak self] image in
                        self?.imageView.contentMode = .scaleAspectFill
                        self?.imageView.image = image
                    }
                }
                if let image = image {
                    imageView.image = image
                    imageView.contentMode = .scaleAspectFill
                } else {
                    imageView.image = UIImage(systemName: "photo")
                    imageView.contentMode = .center
                }
                showImageView = true
            case .video:
                var image: UIImage?
                if visibleMedia.isMediaAvailable {
                    if let fileURL = visibleMedia.fileURL {
                        image = VideoUtils.videoPreviewImage(url: fileURL)
                    }
                } else {
                    imageLoadingCancellable = visibleMedia.videoDidBecomeAvailable
                        .receive(on: DispatchQueue.main)
                        .sink(receiveValue: { [weak self] fileURL in
                            if let image = VideoUtils.videoPreviewImage(url: fileURL) {
                                self?.imageView.contentMode = .scaleAspectFill
                                self?.imageView.image = image
                            }
                        })
                }
                if let image = image {
                    imageView.image = image
                    imageView.contentMode = .scaleAspectFill
                } else {
                    imageView.image = UIImage(systemName: "video")
                    imageView.contentMode = .center
                }
                showImageView = true
            }
        } else {
            // Text post
            let mentionText = MainAppContext.shared.contactStore.textWithMentions(post.rawText, mentions: post.orderedMentions)
            let bodyFont = UIFont(descriptor: .preferredFontDescriptor(withTextStyle: .body), size: 13)
            let mentionFont = UIFont(descriptor: bodyFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)

            textView.attributedText = mentionText.flatMap {
                HAMarkdown(font: bodyFont, color: .label)
                    .parse($0/*.with(font: bodyFont, color: .label)*/)
                    .applyingFontForMentions(mentionFont)
            }

            showTextView = true
        }


        textView.isHidden = !showTextView
        imageView.isHidden = !showImageView
        audioPlayer.isHidden = !showAudioPlayer

        commentIndicator.alpha = (post.unreadCount > 0) ? 1 : 0
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateBorderColor()
        }
    }

    private func updateBorderColor() {
        contentView.layer.borderColor = UIColor.label
            .withAlphaComponent(0.12)
            .resolvedColor(with: contentView.traitCollection)
            .cgColor
    }
}
