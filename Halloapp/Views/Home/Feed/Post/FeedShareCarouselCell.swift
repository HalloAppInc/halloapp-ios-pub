//
//  FeedShareCarouselCell.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/19/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

class FeedShareCarouselCell: UICollectionViewCell {

    var shareAction: ((ShareProvider.Type) -> Void)? {
        get {
            return shareCarousel.share
        }
        set {
            shareCarousel.share = newValue
        }
    }

    class var reuseIdentifier: String {
        return String(describing: self)
    }

    private let titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = .scaledSystemFont(ofSize: 13, weight: .medium)
        titleLabel.text = Localizations.shareDestinationTitle.uppercased()
        titleLabel.textColor = .primaryBlackWhite.withAlphaComponent(0.75)
        return titleLabel
    }()

    private let shareCarousel = ShareCarousel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        preservesSuperviewLayoutMargins = true
        contentView.preservesSuperviewLayoutMargins = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        shareCarousel.share = shareAction
        shareCarousel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(shareCarousel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),

            shareCarousel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            shareCarousel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            shareCarousel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            shareCarousel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }
}

extension Localizations {

    static var shareDestinationTitle: String {
        NSLocalizedString("share.carousel.title", value: "Share with more friends:", comment: "Title for inline external share prompt")
    }
}
