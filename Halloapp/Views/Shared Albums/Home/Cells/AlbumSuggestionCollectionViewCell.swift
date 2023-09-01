//
//  AlbumSuggestionCollectionViewCell.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 7/13/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CoreCommon
import Photos
import UIKit

class AlbumSuggestionCollectionViewCell: UICollectionViewCell {

    static let reuseIdentifier = "AlbumSuggestionCollectionViewCell"

    private let photoGridView: PhotoGridView = {
        let imageView = PhotoGridView()
        return imageView
    }()

    private let headerLabel: UILabel = {
        let headerLabel = UILabel()
        headerLabel.adjustsFontSizeToFitWidth = true
        headerLabel.font = .scaledSystemFont(ofSize: 19, weight: .medium)
        headerLabel.numberOfLines = 2
        headerLabel.textColor = .primaryBlackWhite
        return headerLabel
    }()

    private let titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = .scaledSystemFont(ofSize: 16, weight: .regular)
        titleLabel.numberOfLines = 0
        titleLabel.textColor = .primaryBlackWhite
        return titleLabel
    }()

    private let timestampLabel: UILabel = {
        let timestampLabel = UILabel()
        timestampLabel.font = .scaledSystemFont(ofSize: 13, weight: .medium)
        timestampLabel.textColor = .primaryBlackWhite.withAlphaComponent(0.4)
        return timestampLabel
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let backgroundView = UIView()
        backgroundView.layer.cornerRadius = 22
        backgroundView.layer.shadowColor = UIColor.black.cgColor
        backgroundView.layer.shadowOffset = CGSize(width: 0, height: 3)
        backgroundView.layer.shadowOpacity = 0.05
        backgroundView.layer.shadowRadius = 6
        self.backgroundView = backgroundView

        contentView.backgroundColor = .feedPostBackground
        contentView.clipsToBounds = true
        contentView.layer.cornerRadius = 22

        photoGridView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(photoGridView)

        timestampLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(timestampLabel)

        let headerTitleStack = UIStackView(arrangedSubviews: [headerLabel, titleLabel])
        headerTitleStack.axis = .vertical
        headerTitleStack.alignment = .leading
        headerTitleStack.spacing = 2
        headerTitleStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerTitleStack)

        let heightConstraint = contentView.heightAnchor.constraint(equalToConstant: 130)
        heightConstraint.priority = .defaultHigh

        let stackCenterYConstraint = headerTitleStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        stackCenterYConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            photoGridView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            photoGridView.topAnchor.constraint(equalTo: contentView.topAnchor),
            photoGridView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            photoGridView.widthAnchor.constraint(equalToConstant: 130),

            timestampLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            timestampLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),

            headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: timestampLabel.leadingAnchor, constant: -5),

            headerTitleStack.leadingAnchor.constraint(equalTo: photoGridView.trailingAnchor, constant: 18),
            headerTitleStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            headerTitleStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
            headerTitleStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 12),
            stackCenterYConstraint,

            heightConstraint,
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let backgroundView else {
            return
        }

        backgroundView.layer.shadowPath = UIBezierPath(roundedRect: backgroundView.bounds, cornerRadius: backgroundView.layer.cornerRadius).cgPath
    }

    func configure(photoCluster: PhotoSuggestions.PhotoCluster) {
        let assets = photoCluster.assets.sorted { $0.creationDate ?? .distantFuture < $1.creationDate ?? .distantFuture}
        if assets.count < 4 {
            photoGridView.configure(assets: assets)
        } else {
            let selectedAssets = [assets[0], assets[assets.count / 4], assets[assets.count * 3 / 4], assets[assets.count - 1]]
            photoGridView.configure(assets: selectedAssets)
        }

        timestampLabel.text = photoCluster.start.chatListTimestamp()
        headerLabel.text = photoCluster.location?.name
        headerLabel.isHidden = headerLabel.text?.isEmpty ?? true
        titleLabel.text = Localizations.albumSuggestionsFormattedTitle(count: photoCluster.assets.count, address: photoCluster.location?.address)
    }
}

extension AlbumSuggestionCollectionViewCell {

    private class PhotoGridView: UIView {

        private let imageViews = (0..<4).map { _ in
            let imageView = AssetImageView()
            imageView.assetMode = .thumbnail
            imageView.clipsToBounds = true
            imageView.contentMode = .scaleAspectFill
            imageView.isHidden = true
            return imageView
        }

        override init(frame: CGRect) {
            super.init(frame: frame)

            imageViews.forEach { addSubview($0) }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func configure(assets: [PHAsset]) {
            for imageView in imageViews {
                imageView.isHidden = true
            }
            for (imageView, asset) in zip(imageViews, assets) {
                imageView.asset = asset
                imageView.isHidden = false
            }

            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            let visibleImageViews = imageViews.filter { !$0.isHidden }

            var frames = Array(repeating: CGRect.zero, count: imageViews.count)

            switch visibleImageViews.count {
            case 0:
                break
            case 1:
                frames[0] = bounds
            case 2:
                (frames[0], _) = bounds.divided(atDistance: (bounds.width - 1) * 0.5, from: .minXEdge)
                (frames[1], _) = bounds.divided(atDistance: (bounds.width - 1) * 0.5, from: .maxXEdge)
            case 3:
                let (topRect, _) = bounds.divided(atDistance: (bounds.height - 1) * 0.5, from: .minYEdge)

                (frames[0], _) = topRect.divided(atDistance: (bounds.width - 1) * 0.4, from: .minXEdge)
                (frames[1], _) = topRect.divided(atDistance: (bounds.width - 1) * 0.6, from: .maxXEdge)
                (frames[2], _) = bounds.divided(atDistance: (bounds.height - 1) * 0.5, from: .maxYEdge)
            default: // 4+
                let (topRect, _) = bounds.divided(atDistance: (bounds.height - 1) * 0.5, from: .minYEdge)
                let (bottomRect, _) = bounds.divided(atDistance: (bounds.height - 1) * 0.5, from: .maxYEdge)

                (frames[0], _) = topRect.divided(atDistance: (bounds.width - 1) * 0.4, from: .minXEdge)
                (frames[1], _) = topRect.divided(atDistance: (bounds.width - 1) * 0.6, from: .maxXEdge)
                (frames[2], _) = bottomRect.divided(atDistance: (bounds.width - 1) * 0.7, from: .minXEdge)
                (frames[3], _) = bottomRect.divided(atDistance: (bounds.width - 1) * 0.3, from: .maxXEdge)
            }

            for (imageView, frame) in zip(imageViews, frames) {
                imageView.frame = frame
            }
        }
    }
}

extension Localizations {

    static func albumSuggestionsFormattedTitle(count: Int, address: String?) -> String {
        if let address, !address.isEmpty {
            let format = NSLocalizedString("sharedalbums.albumsuggestioncell.titleformat.location",
                                           value: "%d photos taken at %@",
                                           comment: "title of album suggestion with location")
            return String(format: format, count, address)
        } else {
            let format = NSLocalizedString("sharedalbums.albumsuggestioncell.titleformat.nolocation",
                                           value: "%d photos taken",
                                           comment: "title of album suggestion without location")
            return String(format: format, count)
        }
    }
}
