//
//  PhotoSuggestionCell.swift
//  Notification Content Extension
//
//  Created by Chris Leonavicius on 12/12/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import Photos
import UIKit

class PhotoSuggestionCell: UICollectionViewCell {

    private var displayedAssetLocalIdentifier: String?

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = .black

        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with asset: PHAsset) {
        guard displayedAssetLocalIdentifier != asset.localIdentifier else {
            return
        }
        displayedAssetLocalIdentifier = asset.localIdentifier

        PHImageManager.default().requestImage(for: asset, targetSize: bounds.size, contentMode: .aspectFill, options: nil) { [weak self] image, _ in
            guard let self, displayedAssetLocalIdentifier == asset.localIdentifier else {
                return
            }

            self.imageView.image = image
        }
    }
}
