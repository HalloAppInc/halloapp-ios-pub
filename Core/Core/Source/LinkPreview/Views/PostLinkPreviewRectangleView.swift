//
//  PostLinkPreviewRectangleView.swift
//  Core
//
//  Created by Nandini Shetty on 4/29/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import Combine
import UIKit

class PostLinkPreviewRectangleView: UIView {

    public var imageLoadingCancellable: AnyCancellable?

    private lazy var previewImageView: UIImageView = {
        let previewImageView = UIImageView()
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.clipsToBounds = true
        previewImageView.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        previewImageView.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        previewImageView.tintColor = .systemGray3
        previewImageView.contentMode = .scaleAspectFill
        return previewImageView
    }()

    private lazy var titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.numberOfLines = 2
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
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
    
    private lazy var titleUrlStack: UIStackView = {
        let urlStack = UIStackView(arrangedSubviews: [ titleLabel, linkPreviewLinkStack ])
        urlStack.translatesAutoresizingMaskIntoConstraints = false
        urlStack.alignment = .leading
        urlStack.axis = .vertical
        urlStack.spacing = 2
        urlStack.layoutMargins = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        urlStack.isLayoutMarginsRelativeArrangement = true
        return urlStack
    }()

    public func configure(url: URL, title: String, previewImage: UIImage?) {
        showPlaceholderImage()
        let contentView = UIStackView()
        contentView.axis = .vertical
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(contentView)
        urlLabel.text = url.host
        titleLabel.text = title
        contentView.addArrangedSubview(previewImageView)
        contentView.addArrangedSubview(titleUrlStack)

        if let previewImage = previewImage {
            let linkPreviewMedia = PendingMedia(type: .image)
            linkPreviewMedia.image = previewImage
            if linkPreviewMedia.ready.value {
                previewImageView.contentMode = .scaleAspectFill
                previewImageView.image = linkPreviewMedia.image
            } else {
              self.imageLoadingCancellable =
                  linkPreviewMedia.ready.sink { [weak self] ready in
                      guard let self = self else { return }
                      guard ready else { return }
                      self.previewImageView.contentMode = .scaleAspectFill
                      self.previewImageView.image = linkPreviewMedia.image
                  }
            }
        }
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: self.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            contentView.heightAnchor.constraint(equalToConstant: 230),
        ])
    }

    public func showPlaceholderImage() {
        previewImageView.contentMode = .center
        previewImageView.image = UIImage(systemName: "photo")?.withConfiguration(UIImage.SymbolConfiguration(textStyle: .largeTitle))
    }

    public func show(image: UIImage) {
        previewImageView.contentMode = .scaleAspectFill
        previewImageView.image = image
    }
}
