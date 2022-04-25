//
//  PostLinkPreviewView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 10/7/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Combine
import UIKit
import SwiftUI


extension UIColor {
    class var linkPreviewPostBackground: UIColor {
        UIColor(named: "LinkPreviewPostBackground")!
    }
}

public class PostLinkPreviewView: UIView {

    public var imageLoadingCancellable: AnyCancellable?
    public var linkPreviewURL: URL?
    public var linkPreviewData: LinkPreviewData?
    private var textStackHeightConstraint: NSLayoutConstraint?
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

    public var url: String? { get { urlLabel.text } set { urlLabel.text = newValue } }
    public var title: String? { get { titleLabel.text } set { titleLabel.text = newValue }}

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

        let topC = contentView.topAnchor.constraint(equalTo: self.topAnchor)
        topC.isActive = true
        topC.priority = .required
        
        let bottomC = contentView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        bottomC.isActive = true
        bottomC.priority = .required
        
        let leadingC = contentView.leadingAnchor.constraint(equalTo: self.leadingAnchor)
        leadingC.isActive = true
        leadingC.priority = .required
        
        let trailingC = contentView.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        trailingC.isActive = true
        trailingC.priority = .required

        contentHeightConstraint = contentView.heightAnchor.constraint(equalToConstant: 250)
        textStackHeightConstraint = contentView.heightAnchor.constraint(equalToConstant: 72)
        textStackHeightConstraint?.priority = UILayoutPriority(rawValue: 999)
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

    func configure(linkPreviewData: LinkPreviewData, previewImage: UIImage?) {
        self.linkPreviewData = linkPreviewData
        urlLabel.text = linkPreviewData.url.host
        titleLabel.text = linkPreviewData.title
        if let previewImage = previewImage {
            let linkPreviewMedia = PendingMedia(type: .image)
            linkPreviewMedia.image = previewImage
            if linkPreviewMedia.ready.value {
                activateViewConstraints(isImagePresent: true)
                previewImageView.image = linkPreviewMedia.image
            } else {
              self.imageLoadingCancellable =
                  linkPreviewMedia.ready.sink { [weak self] ready in
                      guard let self = self else { return }
                      guard ready else { return }
                      self.previewImageView.image = linkPreviewMedia.image
                      self.activateViewConstraints(isImagePresent: true)
                  }
            }
            activateViewConstraints(isImagePresent: true)
        } else {
            activateViewConstraints(isImagePresent: false)
        }
    }

    public func activateViewConstraints(isImagePresent: Bool) {
        if isImagePresent {
            previewImageView.isHidden = false
            previewImageHeightConstraint?.isActive = false
            textStackHeightConstraint?.isActive = false
            contentHeightConstraint?.isActive = true
        } else {
            previewImageView.isHidden = true
            previewImageHeightConstraint?.isActive = true
            textStackHeightConstraint?.isActive = true
            contentHeightConstraint?.isActive = false
        }
    }

    @objc private func previewTapped(sender: UITapGestureRecognizer) {
        // if let url = linkPreviewURL {
            // TODO: make preview clickble
            // URLRouter.shared.handleOrOpen(url: url)
        // }
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
