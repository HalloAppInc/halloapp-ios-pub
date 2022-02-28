//
//  PostLinkPreviewView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 10/7/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Combine
import LinkPresentation
import UIKit
import SwiftUI

class PostLinkPreviewView: UIView {

    private var imageLoadingCancellable: AnyCancellable?
    private var feedLinkPreview: FeedLinkPreview?
    private var contentHeightConstraint: NSLayoutConstraint?
    private var previewImageHeightConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private lazy var previewImageView: UIImageView = {
        let previewImageView = UIImageView()
        previewImageView.clipsToBounds = true
        previewImageView.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        previewImageView.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        previewImageView.tintColor = .systemGray3
        return previewImageView
    }()

    private lazy var titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.numberOfLines = 2
        titleLabel.font = .systemFont(forTextStyle: .callout, weight: .semibold)
        titleLabel.textAlignment = .natural
        return titleLabel
    }()

    private lazy var linkImageView: UIView = {
        let image = UIImage(named: "LinkIcon")?.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.tintColor = UIColor.label.withAlphaComponent(0.5)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var urlLabel: UILabel = {
        let urlLabel = UILabel()
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        urlLabel.textColor = .secondaryLabel
        urlLabel.textAlignment = .natural
        urlLabel.numberOfLines = 1
        return urlLabel
    }()

    private var linkPreviewLinkStack: UIStackView {
        let linkStack = UIStackView(arrangedSubviews: [ linkImageView, urlLabel ])
        linkStack.translatesAutoresizingMaskIntoConstraints = false
        linkStack.spacing = 2
        linkStack.alignment = .center
        linkStack.axis = .horizontal
        return linkStack
    }

    private lazy var textStack: UIStackView = {
        let textStack = UIStackView(arrangedSubviews: [ titleLabel, linkPreviewLinkStack ])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.alignment = .leading
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.layoutMargins = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        textStack.isLayoutMarginsRelativeArrangement = true
        return textStack
    }()

    private func commonInit() {
        preservesSuperviewLayoutMargins = true

        let contentView = UIView()
        contentView.backgroundColor = .linkPreviewPostBackground
        contentView.clipsToBounds = true
        contentView.layer.borderWidth = 0.5
        contentView.layer.borderColor = UIColor.black.withAlphaComponent(0.1).cgColor
        contentView.layer.cornerRadius = 15
        contentView.layer.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        contentView.layer.shadowOffset = CGSize(width: 0, height: 2)
        contentView.layer.shadowRadius = 4
        contentView.layer.shadowOpacity = 0.5
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(previewImageView)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textStack)

        contentView.constrainMargins(to: self)

        contentHeightConstraint = contentView.heightAnchor.constraint(equalToConstant: 250)
        previewImageHeightConstraint = previewImageView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            previewImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            previewImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: textStack.topAnchor),

            textStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(previewTapped(sender:)))
        addGestureRecognizer(tapGestureRecognizer)
        isUserInteractionEnabled = true
    }

    func configure(feedLinkPreview: FeedLinkPreview) {
        if feedLinkPreview.id != self.feedLinkPreview?.id {
            imageLoadingCancellable?.cancel()
            imageLoadingCancellable = nil
        }
        self.feedLinkPreview = feedLinkPreview

        urlLabel.text = feedLinkPreview.url?.host
        titleLabel.text = feedLinkPreview.title

        if feedLinkPreview.media != nil, let media = MainAppContext.shared.feedData.media(feedLinkPreviewID: feedLinkPreview.id)?.first {
            configureMedia(media: media)
            previewImageView.isHidden = false
            previewImageHeightConstraint?.isActive = false
            contentHeightConstraint?.isActive = true
        } else {
            previewImageView.isHidden = true
            previewImageHeightConstraint?.isActive = true
            contentHeightConstraint?.isActive = false
        }
    }

    private func configureMedia(media: FeedMedia) {
        showPlaceholderImage()
        if media.isMediaAvailable {
            if let image = media.image {
                show(image: image)
            } else {
                showPlaceholderImage()
                MainAppContext.shared.errorLogger?.logError(FeedMediaError.missingImage)
            }
        } else if imageLoadingCancellable == nil {
            showPlaceholderImage()
            imageLoadingCancellable = media.imageDidBecomeAvailable.sink { [weak self] (image) in
                guard let self = self else { return }
                self.imageLoadingCancellable = nil
                self.show(image: image)
            }
        }
    }

    private func showPlaceholderImage() {
        previewImageView.contentMode = .center
        previewImageView.image = UIImage(systemName: "photo")?.withConfiguration(UIImage.SymbolConfiguration(textStyle: .largeTitle))
    }

    private func show(image: UIImage) {
        previewImageView.contentMode = .scaleAspectFill
        previewImageView.image = image
    }

    @objc private func previewTapped(sender: UITapGestureRecognizer) {
        if let url = feedLinkPreview?.url {
            guard MainAppContext.shared.chatData.proceedIfNotGroupInviteLink(url) else { return }
            UIApplication.shared.open(url)
        }
    }
}
