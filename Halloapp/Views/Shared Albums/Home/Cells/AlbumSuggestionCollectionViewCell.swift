//
//  AlbumSuggestionCollectionViewCell.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 7/13/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CoreCommon
import UIKit

class AlbumSuggestionCollectionViewCell: UICollectionViewCell {

    static let reuseIdentifier = "AlbumSuggestionCollectionViewCell"

    private let imageView: AssetImageView = {
        let imageView = AssetImageView()
        imageView.assetMode = .thumbnail
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 10
        return imageView
    }()

    private let countLabel: UILabel = {
        let countLabel = UILabel()
        countLabel.allowsDefaultTighteningForTruncation = true
        countLabel.adjustsFontSizeToFitWidth = true
        countLabel.font = .gothamFont(ofFixedSize: 17, weight: .bold)
        countLabel.textColor = .white
        return countLabel
    }()

    private let titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = .scaledSystemFont(ofSize: 16, weight: .regular)
        titleLabel.numberOfLines = 0
        titleLabel.textColor = .white
        return titleLabel
    }()

    private let timestampLabel: UILabel = {
        let timestampLabel = UILabel()
        timestampLabel.font = .scaledSystemFont(ofSize: 13, weight: .medium)
        timestampLabel.textColor = .white.withAlphaComponent(0.4)
        return timestampLabel
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let backgroundView = UIView()
        backgroundView.backgroundColor = .black.withAlphaComponent(0.5)
        backgroundView.layer.cornerRadius = 22
        self.backgroundView = backgroundView

        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        imageView.addSubview(countLabel)

        titleLabel.setContentCompressionResistancePriority(UILayoutPriority(1), for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        timestampLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(timestampLabel)

        let heightMinimizationConstraint = contentView.heightAnchor.constraint(equalToConstant: 0)
        heightMinimizationConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            imageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
            imageView.widthAnchor.constraint(equalToConstant: 64),
            imageView.heightAnchor.constraint(equalToConstant: 64),

            countLabel.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            countLabel.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: imageView.leadingAnchor, constant: 2),

            titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 12),

            timestampLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 2),
            timestampLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            timestampLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),

            heightMinimizationConstraint,
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(photoCluster: PhotoSuggestions.PhotoCluster) {
        imageView.asset = photoCluster.assets.first
        countLabel.text = Localizations.albumSuggestionFormattedCount(photoCluster.assets.count - 1)
        titleLabel.text = Localizations.albumSuggestionsFormattedTitle(count: photoCluster.assets.count, location: photoCluster.locationName)
        timestampLabel.text = photoCluster.start.feedTimestamp()
    }
}

extension Localizations {

    static func albumSuggestionFormattedCount(_ count: Int) -> String {
        let format = NSLocalizedString("sharedalbums.albumsuggestioncell.countformat",
                                       value: "+%d",
                                       comment: "Count of photos in album")
        return String(format: format, count)
    }

    static func albumSuggestionsFormattedTitle(count: Int, location: String?) -> String {
        if let location {
            let format = NSLocalizedString("sharedalbums.albumsuggestioncell.titleformat.location",
                                           value: "%d photos taken @%@",
                                           comment: "title of album suggestion with location")
            return String(format: format, count, location)
        } else {
            let format = NSLocalizedString("sharedalbums.albumsuggestioncell.titleformat.nolocation",
                                           value: "%d photos taken",
                                           comment: "title of album suggestion without location")
            return String(format: format, count)
        }


    }
}
