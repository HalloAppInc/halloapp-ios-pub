//
//  AlbumSuggestionLoadIndicatorCollectionViewCell.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 7/20/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit

class AlbumSuggestionLoadIndicatorCollectionViewCell: UICollectionViewCell {

    static let reuseIdentifier = "AlbumSuggestionLoadIndicatorCollectionViewCell"

    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        activityIndicator.startAnimating()
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
}
