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
    private var media: FeedMedia?
    private var feedLinkPreview: FeedLinkPreview?

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func configure(feedLinkPreview: FeedLinkPreview) {
        if feedLinkPreview.media != nil {
            let media = MainAppContext.shared.feedData.media(feedLinkPreviewID: feedLinkPreview.id)
            self.media = media?.first
        }
        self.feedLinkPreview  = feedLinkPreview
        commonInit()
    }

    private lazy var placeholderImageView: UIImageView = {
        let placeholderImageView = UIImageView()
        placeholderImageView.contentMode = .center
        placeholderImageView.widthAnchor.constraint(equalToConstant: 50).isActive = true
        placeholderImageView.heightAnchor.constraint(equalToConstant: 90).isActive = true
        placeholderImageView.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
        placeholderImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .largeTitle)
        placeholderImageView.image = UIImage(systemName: "photo")
        placeholderImageView.tintColor = .systemGray3
        placeholderImageView.isHidden = true
        return placeholderImageView
    }()

    private lazy var mediaView: UIImageView = {
        let mediaView = UIImageView()
        mediaView.contentMode = .scaleAspectFill
        mediaView.clipsToBounds = true
        return mediaView
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
        let linkStack = UIStackView(arrangedSubviews: [ linkImageView, urlLabel, UIView() ])
        linkStack.translatesAutoresizingMaskIntoConstraints = false
        linkStack.spacing = 2
        linkStack.alignment = .center
        linkStack.axis = .horizontal
        return linkStack
    }

    private lazy var textStack: UIStackView = {
        let textStack = UIStackView(arrangedSubviews: [ titleLabel, linkPreviewLinkStack ])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        textStack.isLayoutMarginsRelativeArrangement = true
        return textStack
    }()


    private lazy var vStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [placeholderImageView, mediaView, textStack])
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        stack.backgroundColor = .commentVoiceNoteBackground
        stack.layer.borderWidth = 0.5
        stack.layer.borderColor = UIColor.black.withAlphaComponent(0.1).cgColor
        stack.layer.cornerRadius = 15
        stack.layer.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        stack.layer.shadowOffset = CGSize(width: 0, height: 2)
        stack.layer.shadowRadius = 4
        stack.layer.shadowOpacity = 0.5
        stack.isLayoutMarginsRelativeArrangement = true
        stack.clipsToBounds = true
        stack.distribution = .fillProportionally
        stack.backgroundColor = .linkPreviewPostBackground
        textStack.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 20).isActive = true
        return stack
    }()

    private func commonInit() {
        preservesSuperviewLayoutMargins = true
        guard let feedLinkPreview = feedLinkPreview else { return }

        titleLabel.text = feedLinkPreview.title
        // We want the text to be visible and the image to fill up remaining available s pace.
        titleLabel.setContentCompressionResistancePriority(.defaultHigh + 1000, for: .vertical)
        urlLabel.setContentCompressionResistancePriority(.defaultHigh + 1000, for: .vertical)
        urlLabel.text = feedLinkPreview.url?.host
        if let media = media {
            configureMedia(media: media)
            vStack.heightAnchor.constraint(equalToConstant: 250).isActive = true
            textStack.topAnchor.constraint(equalTo: mediaView.bottomAnchor).isActive = true
        } else {
            placeholderImageView.isHidden = true
            mediaView.isHidden = true
        }
        
        self.addSubview(vStack)
        
        vStack.constrainMargins(to: self)

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(previewTapped(sender:)))
        self.addGestureRecognizer(tapGestureRecognizer)
        self.isUserInteractionEnabled = true
    }

    @objc private func previewTapped(sender: UITapGestureRecognizer) {
        if let url = feedLinkPreview?.url {
            UIApplication.shared.open(url)
        }
    }

    private func configureMedia(media: FeedMedia) {
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
                self.show(image: image)
            }
        }
    }

    private func showPlaceholderImage() {
        placeholderImageView.isHidden = false
        mediaView.isHidden = true
    }

    private func show(image: UIImage) {
        placeholderImageView.isHidden = true
        mediaView.isHidden = false
        mediaView.image = image
        // Loading cancellable is no longer needed
        imageLoadingCancellable?.cancel()
        imageLoadingCancellable = nil
    }
}
