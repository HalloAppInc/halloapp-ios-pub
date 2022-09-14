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
        titleLabel.textColor = .black
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        return titleLabel
    }()

    private lazy var linkImageView: UIView = {
        let image = UIImage(named: "LinkIcon")?.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.tintColor = UIColor.black.withAlphaComponent(0.5)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var urlLabel: UILabel = {
        let urlLabel = UILabel()
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        urlLabel.textColor = .black.withAlphaComponent(0.5)
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

    private lazy var progressView: CircularProgressView = {
        let progressView = CircularProgressView()
        progressView.barWidth = 2
        progressView.trackTintColor = .systemGray3 // Same color as the placeholder
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.heightAnchor.constraint(equalTo: progressView.widthAnchor, multiplier: 1).isActive = true
        progressView.isHidden = true
        return progressView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let contentView = UIStackView()
        contentView.axis = .vertical
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .linkPreviewPostSquareBackground
        contentView.isLayoutMarginsRelativeArrangement = false

        contentView.addArrangedSubview(previewImageView)
        contentView.addArrangedSubview(titleUrlStack)
        contentView.addSubview(progressView)

        addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.heightAnchor.constraint(equalToConstant: 230),
            progressView.centerXAnchor.constraint(equalTo: previewImageView.centerXAnchor),
            progressView.centerYAnchor.constraint(equalTo: previewImageView.centerYAnchor),
            progressView.widthAnchor.constraint(equalToConstant: 80),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    public func configure(url: URL, title: String, previewImage: UIImage?) {
        urlLabel.text = url.host
        titleLabel.text = title

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
    }

    public func showPlaceholderImage() {
        previewImageView.contentMode = .center
        previewImageView.image = UIImage(systemName: "photo")?.withConfiguration(UIImage.SymbolConfiguration(textStyle: .largeTitle))
    }

    public func show(image: UIImage) {
        previewImageView.contentMode = .scaleAspectFill
        previewImageView.image = image
    }

    public func hideProgressView() {
        progressView.isHidden = true
    }

    public func showProgressView() {
        progressView.isHidden = false
    }

    public func setProgress(_ progress: Float, animated: Bool) {
        progressView.setProgress(progress, animated: animated)
    }
}
