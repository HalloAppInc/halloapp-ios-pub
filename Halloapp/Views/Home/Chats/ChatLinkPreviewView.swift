//
//  ChatLinkPreviewView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 11/8/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Combine
import LinkPresentation
import UIKit

class ChatLinkPreviewView: UIView {

    private var imageLoadingCancellable: AnyCancellable?
    private var media: ChatMedia?
    private var chatLinkPreview: ChatLinkPreview?

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func configure(chatLinkPreview: ChatLinkPreview) {
        if let media = chatLinkPreview.media {
            self.media = media.first
        }
        self.chatLinkPreview  = chatLinkPreview
        commonInit()
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
        mediaView.widthAnchor.constraint(equalToConstant: 100).isActive = true
        mediaView.heightAnchor.constraint(equalToConstant: 100).isActive = true
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
        hStack.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.clipsToBounds = true
        return hStack
    }()

    private func commonInit() {
        preservesSuperviewLayoutMargins = true
        guard let chatLinkPreview = chatLinkPreview else { return }

        titleLabel.text = chatLinkPreview.title
        urlLabel.text = chatLinkPreview.url?.host
        configureMedia()
        self.addSubview(hStack)

        hStack.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        hStack.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(previewTapped(sender:)))
        self.addGestureRecognizer(tapGestureRecognizer)
        self.isUserInteractionEnabled = true
    }

    @objc private func previewTapped(sender: UITapGestureRecognizer) {
        if let url = chatLinkPreview?.url {
            UIApplication.shared.open(url)
        }
    }

    private func configureMedia() {
        guard let media = media else {
            placeholderImageView.isHidden = true
            mediaView.isHidden = true
            return
        }
        let fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(media.relativeFilePath ?? "", isDirectory: false)
        
        if media.type == .image {
            if let image = UIImage(contentsOfFile: fileURL.path) {
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

