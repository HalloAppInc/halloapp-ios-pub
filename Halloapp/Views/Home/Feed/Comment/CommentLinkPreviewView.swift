//
//  CommentLinkPreviewView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 10/7/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Combine
import LinkPresentation
import UIKit

class CommentLinkPreviewView: UIView {

    private var imageLoadingCancellable: AnyCancellable?
    private var media: FeedMedia?
    private var feedLinkPreview: FeedLinkPreview?

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    init(feedLinkPreview: FeedLinkPreview) {
        super.init(frame: .zero)
        if feedLinkPreview.media != nil {
            let media = MainAppContext.shared.feedData.media(feedLinkPreviewID: feedLinkPreview.id)
            self.media = media?.first
        }
        self.feedLinkPreview  = feedLinkPreview
        commonInit()
    }

    private lazy var placeholderImageView: UIImageView = {
        let placeholderImageView = UIImageView()
        placeholderImageView.contentMode = .scaleToFill
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
        mediaView.contentMode = .scaleToFill
        mediaView.widthAnchor.constraint(equalToConstant: 90).isActive = true
        mediaView.heightAnchor.constraint(equalToConstant: 100).isActive = true
        mediaView.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
        return mediaView
    }()

    private lazy var titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        return titleLabel
    }()

    private lazy var urlLabel: UILabel = {
        let urlLabel = UILabel()
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        urlLabel.textColor = .secondaryLabel
        urlLabel.textAlignment = .natural
        return urlLabel
    }()

    private lazy var textStack: UIStackView = {
        let textStack = UIStackView(arrangedSubviews: [ titleLabel, urlLabel ])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        textStack.isLayoutMarginsRelativeArrangement = true
        return textStack
    }()


    private lazy var hStack: UIStackView = {
        let hStack = UIStackView(arrangedSubviews: [placeholderImageView, mediaView, textStack])
        hStack.translatesAutoresizingMaskIntoConstraints = false

        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.backgroundColor = .commentVoiceNoteBackground
        hStack.layer.borderWidth = 0.5
        hStack.layer.borderColor = UIColor.black.withAlphaComponent(0.1).cgColor
        hStack.layer.cornerRadius = 15
        hStack.layer.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        hStack.layer.shadowOffset = CGSize(width: 0, height: 2)
        hStack.layer.shadowRadius = 4
        hStack.layer.shadowOpacity = 0.5
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.clipsToBounds = true
        return hStack
    }()

    private func commonInit() {
        preservesSuperviewLayoutMargins = true
        guard let feedLinkPreview = feedLinkPreview else { return }

        titleLabel.text = feedLinkPreview.title
        urlLabel.text = feedLinkPreview.url?.host
        configureMedia()
        self.addSubview(hStack)

        hStack.widthAnchor.constraint(equalToConstant: 300).isActive = true
        hStack.heightAnchor.constraint(equalToConstant: 100).isActive = true
        hStack.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(previewTapped(sender:)))
        self.addGestureRecognizer(tapGestureRecognizer)
        self.isUserInteractionEnabled = true
    }

    @objc private func previewTapped(sender: UITapGestureRecognizer) {
        if let url = feedLinkPreview?.url {
            UIApplication.shared.open(url)
        }
    }

    private func configureMedia() {
        guard let media = media else {
            placeholderImageView.isHidden = true
            mediaView.isHidden = true
            return
        }
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
