//
//  PostLinkPreviewNoImageView.swift
//  Core
//
//  Created by Nandini Shetty on 4/29/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import Combine
import UIKit

class PostLinkPreviewNoImageView: UIView {

    public var imageLoadingCancellable: AnyCancellable?

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
        let titleUrlStack = UIStackView(arrangedSubviews: [ titleLabel, linkPreviewLinkStack ])
        titleUrlStack.translatesAutoresizingMaskIntoConstraints = false
        titleUrlStack.alignment = .leading
        titleUrlStack.axis = .vertical
        titleUrlStack.spacing = 2
        titleUrlStack.layoutMargins = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        titleUrlStack.isLayoutMarginsRelativeArrangement = true
        return titleUrlStack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let contentView = UIStackView()
        contentView.axis = .vertical
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        contentView.addSubview(titleUrlStack)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: self.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            titleUrlStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleUrlStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleUrlStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentView.heightAnchor.constraint(equalToConstant: 80),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    public func configure(url: URL, title: String) {
        urlLabel.text = url.host
        titleLabel.text = title
    }
}
