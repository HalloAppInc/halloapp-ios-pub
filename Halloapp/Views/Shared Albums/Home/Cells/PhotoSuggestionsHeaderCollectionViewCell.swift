//
//  PhotoSuggestionsHeader.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 8/31/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CoreCommon
import UIKit

class PhotoSuggestionsHeaderCollectionViewCell: UICollectionViewCell {

    static let reuseIdentifier = "PhotoSuggestionsHeaderCollectionViewCell"

    override init(frame: CGRect) {
        super.init(frame: frame)

        let titleLabel = UILabel()
        titleLabel.font = .scaledSystemFont(ofSize: 12, weight: .medium)
        titleLabel.text = Localizations.photoSuggestionsHeaderTitle.uppercased()
        titleLabel.textColor = .primaryBlackWhite.withAlphaComponent(0.5)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }
}

extension Localizations {

    static var photoSuggestionsHeaderTitle: String {
        NSLocalizedString("photosuggestionsheader.title", value: "New post suggestions", comment: "title for photo suggestions section")
    }
}
