//
//  CommentLinkPreviewView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 10/7/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import LinkPresentation
import UIKit

class CommentLinkPreviewView: UIView {

    private var imageLoadingCancellable: AnyCancellable?
    private var media: FeedMedia?
    private var linkPreview: CommonLinkPreview?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    func configure(linkPreview: CommonLinkPreview) {
        self.linkPreview  = linkPreview
        titleLabel.text = linkPreview.title
        urlLabel.text = linkPreview.url?.host
        configureMedia()
    }

    private lazy var placeholderImageView: UIImageView = {
        let placeholderImageView = UIImageView()
        placeholderImageView.contentMode = .scaleAspectFill
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
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.contentMode = .scaleAspectFill
        mediaView.clipsToBounds = true
        mediaView.widthAnchor.constraint(equalToConstant: 75).isActive = true
        mediaView.heightAnchor.constraint(equalToConstant: 75).isActive = true
        mediaView.isHidden = true
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

    private lazy var linkIconView: UIView = {
        let image = UIImage(named: "LinkIcon")?.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.tintColor = UIColor.label.withAlphaComponent(0.5)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private var linkPreviewLinkStack: UIStackView {
        let linkStack = UIStackView(arrangedSubviews: [ linkIconView, urlLabel, UIView() ])
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
        self.addSubview(hStack)

        hStack.heightAnchor.constraint(equalToConstant: 75).isActive = true
        hStack.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
        hStack.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(previewTapped(sender:)))
        self.addGestureRecognizer(tapGestureRecognizer)
        self.isUserInteractionEnabled = true
    }

    @objc private func previewTapped(sender: UITapGestureRecognizer) {
        if let url = linkPreview?.url {
            URLRouter.shared.handleOrOpen(url: url)
        }
    }

    private func configureMedia() {
        // no media
        guard let media = linkPreview?.media?.first else {
            placeholderImageView.isHidden = true
            mediaView.isHidden = true
            return
        }

        if let mediaURL = media.mediaURL {
            loadMedia(mediaURL: mediaURL)
        } else {
            showPlaceholderImage()
            imageLoadingCancellable = media.publisher(for: \.relativeFilePath).sink { [weak self] path in
                guard let self = self else { return }
                guard path != nil else { return }
                if let mediaURL = media.mediaURL {
                    self.loadMedia(mediaURL: mediaURL)
                }
            }
        }
    }

    private func loadMedia(mediaURL: URL) {
        if let image = UIImage(contentsOfFile: mediaURL.path) {
            show(image: image)
        } else {
            showPlaceholderImage()
            DDLogError("CommentLinkPreviewView/loadMedia/missing image")
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
