//
//  ExternalSharePostView.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/12/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

class ExternalSharePostView: UIView {

    private let header = FeedItemHeaderView()
    private let contentView = FeedItemContentView(mediaCarouselViewConfiguration: .init(loadMediaSynchronously: true), maxMediaHeight: 300)
    private let separator: UIView = {
        let separator = UIView()
        separator.backgroundColor = .separator
        return separator
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        // By default the background view is transparent - render it over a feed colored background
        let opaqueBackgroundView = UIView()
        opaqueBackgroundView.backgroundColor = .feedBackground
        opaqueBackgroundView.layer.cornerRadius = FeedPostCollectionViewCell.LayoutConstants.backgroundCornerRadius
        opaqueBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(opaqueBackgroundView)

        let backgroundView = FeedItemBackgroundPanelView()
        backgroundView.cornerRadius = FeedPostCollectionViewCell.LayoutConstants.backgroundCornerRadius
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)

        header.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(header)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(contentView)

        separator.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(separator)

        let footer = ExternalSharePostFooter()
        footer.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(footer)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            opaqueBackgroundView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            opaqueBackgroundView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            opaqueBackgroundView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            opaqueBackgroundView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

            header.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 8),
            header.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 8),
            header.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -8),

            contentView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 8),
            contentView.topAnchor.constraint(equalTo: header.bottomAnchor),
            contentView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -8),

            separator.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            separator.topAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            footer.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 8),
            footer.topAnchor.constraint(equalTo: separator.bottomAnchor),
            footer.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -8),
            footer.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -8),
        ])
    }

    func configure(with feedPost: FeedPost) {
        let contentWidth = bounds.width - layoutMargins.left - layoutMargins.right
        let gutterWidth = (1 - FeedPostCollectionViewCell.LayoutConstants.backgroundPanelHMarginRatio) * layoutMargins.left
        header.configure(with: feedPost, contentWidth: contentWidth, showGroupName: false, useFullUserName: true)
        header.refreshTimestamp(with: feedPost, dateFormatter: .dateTimeFormatterTime)
        contentView.configure(with: feedPost, contentWidth: contentWidth, gutterWidth: gutterWidth, displayData: nil)
        separator.isHidden = feedPost.hideFooterSeparator
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    static func snapshot(with feedPost: FeedPost, includeBackground: Bool = false) -> UIImage {
        let imageSizeWithBackgound = CGSize(width: 720, height: 1280)
        // Draw view at 2x scale so fonts don't look abnormally small
        let backgroundSize = CGSize(width: imageSizeWithBackgound.width / 2, height: imageSizeWithBackgound.height / 2)
        let postInset: CGFloat = 16
        let postWidth = backgroundSize.width - 2 * postInset

        let externalSharePostView = ExternalSharePostView(frame: CGRect(origin: .zero, size: CGSize(width: postWidth, height: 0)))
        externalSharePostView.configure(with: feedPost)

        let viewToRender: UIView
        let viewToRenderSize: CGSize

        if includeBackground {
            let backgroundView = UIView()
            backgroundView.backgroundColor = .externalShareBackgound

            externalSharePostView.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.addSubview(externalSharePostView)

            let downloadLabel = UILabel()
            downloadLabel.font = .gothamFont(ofFixedSize: 13, weight: .medium)
            downloadLabel.text = Localizations.downloadHalloApp
            downloadLabel.textColor = .white

            let urlLabel = UILabel()
            urlLabel.font = .gothamFont(ofFixedSize: 15, weight: .bold)
            urlLabel.text = "halloapp.com/dl"
            urlLabel.textColor = .white

            let labelStack = UIStackView(arrangedSubviews: [downloadLabel, urlLabel])
            labelStack.axis = .vertical
            labelStack.alignment = .center
            labelStack.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.addSubview(labelStack)

            let labelStackBottomPreferredConstraint = labelStack.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -50)
            labelStackBottomPreferredConstraint.priority = UILayoutPriority(2)

            let externalSharePostCenterYPreferredConstraint = externalSharePostView.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor)
            externalSharePostCenterYPreferredConstraint.priority = UILayoutPriority(1)

            NSLayoutConstraint.activate([
                externalSharePostView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: postInset),
                externalSharePostView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -postInset),
                externalSharePostView.topAnchor.constraint(greaterThanOrEqualTo: backgroundView.topAnchor, constant: 50),
                externalSharePostCenterYPreferredConstraint,

                labelStack.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
                labelStackBottomPreferredConstraint,
                labelStack.topAnchor.constraint(greaterThanOrEqualTo: externalSharePostView.bottomAnchor, constant: 24),
                labelStack.bottomAnchor.constraint(lessThanOrEqualTo: backgroundView.bottomAnchor, constant: -8),
            ])

            viewToRender = backgroundView
            viewToRenderSize = backgroundSize
        } else {
            viewToRender = externalSharePostView
            viewToRenderSize = viewToRender.systemLayoutSizeFitting(CGSize(width: postWidth, height: 0),
                                                                    withHorizontalFittingPriority: .required,
                                                                    verticalFittingPriority: .fittingSizeLevel)
        }

        // always render in light mode
        let viewController = UIViewController()
        viewController.overrideUserInterfaceStyle = .light
        viewController.view = viewToRender

        viewToRender.frame = CGRect(origin: .zero, size: viewToRenderSize)

        let format = UIGraphicsImageRendererFormat()
        format.opaque = includeBackground

        let imageSize = CGSize(width: viewToRenderSize.width * 2, height: viewToRenderSize.height * 2)
        return UIGraphicsImageRenderer(size: imageSize, format: format).image { context in
            viewToRender.drawHierarchy(in: CGRect(origin: .zero, size: imageSize), afterScreenUpdates: true)
        }
    }
}

// MARK: -- ExternalSharePostFooter

extension ExternalSharePostView {

    private class ExternalSharePostFooter: UIView {

        override init(frame: CGRect) {
            super.init(frame: frame)

            let label = UILabel()
            label.font = .gothamFont(ofFixedSize: 13, weight: .medium)
            label.text = Localizations.postedFrom
            label.textColor = .primaryBlackWhite.withAlphaComponent(0.75)

            let imageView = UIImageView()
            imageView.image = UIImage(named: "logo")

            let stackView = UIStackView(arrangedSubviews: [label, imageView])
            stackView.spacing = 4
            stackView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stackView)

            NSLayoutConstraint.activate([
                stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                stackView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
                stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

private extension Localizations {

    static var downloadHalloApp: String {
        return NSLocalizedString("externalshare.download", value: "Download HalloApp for free:", comment: "Text on external share preview background, followed by URL")
    }

    static var postedFrom: String {
        return NSLocalizedString("externalshare.postedFrom", value: "Posted from", comment: "Attached to our logo as an image, 'Posted from HalloApp'")
    }
}
