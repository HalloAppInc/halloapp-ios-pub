//
//  PhotoSuggestionsHeader.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 8/31/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CoreCommon
import UIKit

class PhotoSuggestionsHeader: UICollectionReusableView {

    static let reuseIdentifier = "PhotoSuggestionsHeader"

    override init(frame: CGRect) {
        super.init(frame: frame)

        let titleLabel = UILabel()
        titleLabel.font = .scaledSystemFont(ofSize: 17, weight: .medium)
        titleLabel.text = Localizations.photoSuggestionsHeaderTitle
        titleLabel.textColor = .primaryBlackWhite
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
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
