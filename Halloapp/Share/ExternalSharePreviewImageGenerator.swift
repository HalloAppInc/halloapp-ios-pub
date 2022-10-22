//
//  ExternalSharePreviewImageGenerator.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/12/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

class ExternalSharePreviewImageGenerator {

    private struct Constants {
        static let imageSizeWithBackgound = CGSize(width: 720, height: 1280)
        // Draw view at 2x scale so fonts don't look abnormally small
        static let backgroundSize = CGSize(width: imageSizeWithBackgound.width / 2, height: imageSizeWithBackgound.height / 2)
        static let postInset: CGFloat = 16
        static let postWidth = backgroundSize.width - 2 * postInset
        static let momentWidth = postWidth - 16
    }

    static func image(for post: FeedPost, includeBackground: Bool = false) -> UIImage {
        let postView: UIView
        if post.isMoment {
            postView = ExternalSharePreviewMomentView(feedPost: post)
            if !includeBackground {
                postView.backgroundColor = .externalShareBackgound
                postView.layer.cornerRadius = 12
            }
        } else {
            postView = ExternalSharePreviewPostView(feedPost: post)
        }

        let viewToRender: UIView
        let viewToRenderSize: CGSize
        if includeBackground {
            viewToRender = ExternalSharePreviewBackgroundView(postView: postView)
            viewToRenderSize = Constants.backgroundSize
        } else {
            viewToRender = postView
            viewToRenderSize = postView.systemLayoutSizeFitting(CGSize(width: Constants.postWidth, height: 0),
                                                                withHorizontalFittingPriority: .required,
                                                                verticalFittingPriority: .fittingSizeLevel)
        }

        // always render in light mode
        viewToRender.overrideUserInterfaceStyle = .light
        viewToRender.frame = CGRect(origin: .zero, size: viewToRenderSize)

        let format = UIGraphicsImageRendererFormat()
        format.opaque = includeBackground

        let imageSize = CGSize(width: viewToRenderSize.width * 2, height: viewToRenderSize.height * 2)
        let i = UIGraphicsImageRenderer(size: imageSize, format: format).image { context in
            viewToRender.drawHierarchy(in: CGRect(origin: .zero, size: imageSize), afterScreenUpdates: true)
        }

        return i
    }
}

// MARK: - ExternalSharePreviewPostView

extension ExternalSharePreviewImageGenerator {

    private class ExternalSharePreviewPostView: UIView {

        init(feedPost: FeedPost) {
            super.init(frame: .zero)

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

            let header = FeedItemHeaderView()
            header.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.addSubview(header)

            let contentView = FeedItemContentView(mediaCarouselViewConfiguration: .init(loadMediaSynchronously: true), maxMediaHeight: 300)
            contentView.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.addSubview(contentView)

            let separator = UIView()
            separator.backgroundColor = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.addSubview(separator)

            let footer = UIView()
            footer.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.addSubview(footer)

            let footerLabel = UILabel()
            footerLabel.font = .gothamFont(ofFixedSize: 13, weight: .medium)
            footerLabel.text = Localizations.postedFrom
            footerLabel.textColor = .primaryBlackWhite.withAlphaComponent(0.75)

            let logoImageView = UIImageView()
            logoImageView.image = UIImage(named: "logo")

            let footerStackView = UIStackView(arrangedSubviews: [footerLabel, logoImageView])
            footerStackView.spacing = 4
            footerStackView.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(footerStackView)

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

                footerStackView.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 8),
                footerStackView.topAnchor.constraint(equalTo: footer.topAnchor, constant: 16),
                footerStackView.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -8)
            ])

            let contentWidth = Constants.postWidth - layoutMargins.left - layoutMargins.right
            let gutterWidth = (1 - FeedPostCollectionViewCell.LayoutConstants.backgroundPanelHMarginRatio) * layoutMargins.left
            header.configure(with: feedPost, contentWidth: contentWidth, showGroupName: false, useFullUserName: true)
            header.refreshTimestamp(with: feedPost, dateFormatter: .dateTimeFormatterTime)
            contentView.configure(with: feedPost, contentWidth: contentWidth, gutterWidth: gutterWidth, displayData: nil)
            separator.isHidden = feedPost.hideFooterSeparator
        }

        required init?(coder: NSCoder) {
            fatalError()
        }
    }
}

// MARK: - ExternalSharePreviewMomentView

extension ExternalSharePreviewImageGenerator {

    private class ExternalSharePreviewMomentView: UIView {

        init(feedPost: FeedPost) {
            super.init(frame: .zero)

            let header = FeedItemHeaderView()
            header.avatarViewButton.avatarView.borderColor = .white
            header.avatarViewButton.avatarView.borderWidth = 2
            header.overrideUserInterfaceStyle = .dark
            header.translatesAutoresizingMaskIntoConstraints = false
            addSubview(header)

            let momentView = MomentView()
            momentView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(momentView)

            let label = UILabel()
            label.font = .gothamFont(ofFixedSize: 13, weight: .medium)
            label.text = Localizations.postedFrom
            label.textColor = .primaryBlackWhite.withAlphaComponent(0.75 * 0.75)

            let imageView = UIImageView()
            imageView.image = UIImage(named: "logo")

            let logoStackView = UIStackView(arrangedSubviews: [label, imageView])
            logoStackView.axis = .vertical
            logoStackView.spacing = 4
            logoStackView.translatesAutoresizingMaskIntoConstraints = false
            momentView.addSubview(logoStackView)

            let momentLeadingConstraint = momentView.leadingAnchor.constraint(equalTo: leadingAnchor)
            momentLeadingConstraint.priority = UILayoutPriority(1)

            NSLayoutConstraint.activate([
                header.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                header.leadingAnchor.constraint(equalTo: momentView.leadingAnchor),
                header.trailingAnchor.constraint(equalTo: momentView.trailingAnchor),

                momentView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
                momentView.centerXAnchor.constraint(equalTo: centerXAnchor),
                momentView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
                momentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
                momentView.widthAnchor.constraint(equalToConstant: Constants.momentWidth),
                momentLeadingConstraint,

                logoStackView.leadingAnchor.constraint(equalTo: momentView.leadingAnchor, constant: 10),
                logoStackView.bottomAnchor.constraint(equalTo: momentView.bottomAnchor, constant: -16),
            ])

            let contentWidth = bounds.width - layoutMargins.left - layoutMargins.right
            header.configure(with: feedPost, contentWidth: contentWidth, showGroupName: false, useFullUserName: true)
            header.refreshTimestamp(with: feedPost, dateFormatter: .dateTimeFormatterTime)

            momentView.configure(with: feedPost)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }
    }
}

// MARK: - ExternalSharePreviewBackgroundView

extension ExternalSharePreviewImageGenerator {

    private class ExternalSharePreviewBackgroundView: UIView {

        init(postView: UIView) {
            super.init(frame: .zero)

            backgroundColor = .externalShareBackgound

            postView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(postView)

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
            addSubview(labelStack)

            let labelStackBottomPreferredConstraint = labelStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -50)
            labelStackBottomPreferredConstraint.priority = UILayoutPriority(2)

            let externalSharePostCenterYPreferredConstraint = postView.centerYAnchor.constraint(equalTo: centerYAnchor)
            externalSharePostCenterYPreferredConstraint.priority = UILayoutPriority(1)

            NSLayoutConstraint.activate([
                postView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.postInset),
                postView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.postInset),
                postView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 50),
                externalSharePostCenterYPreferredConstraint,

                labelStack.centerXAnchor.constraint(equalTo: centerXAnchor),
                labelStackBottomPreferredConstraint,
                labelStack.topAnchor.constraint(greaterThanOrEqualTo: postView.bottomAnchor, constant: 24),
                labelStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
            ])
        }

        required init?(coder: NSCoder) {
            fatalError()
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
