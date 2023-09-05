//
//  MagicPhotosExplainerCollectionViewCell.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 9/5/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CoreCommon
import UIKit

class MagicPhotosExplainerCollectionViewCell: UICollectionViewCell {

    static let reuseIdentifier = "MagicPhotosExplainerCollectionViewCell"

    var dismissAction: (() -> Void)?

    private let closeButton: UIButton = {
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)), for: .normal)
        closeButton.tintColor = .primaryBlackWhite.withAlphaComponent(0.5)
        return closeButton
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        closeButton.addTarget(self, action: #selector(dismiss), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(closeButton)

        let magicPostsImageView = UIImageView(image: UIImage(named: "MagicPostsEmptyStateIcon"))

        let magicPostsTitleLabel = UILabel()
        magicPostsTitleLabel.font = .scaledSystemFont(ofSize: 16, weight: .medium)
        magicPostsTitleLabel.text = Localizations.magicPostsExplainerTitle
        magicPostsTitleLabel.textColor = .primaryBlue

        let magicPostsSubtitleLabel = UILabel()
        magicPostsSubtitleLabel.font = .scaledSystemFont(ofSize: 15, weight: .regular)
        magicPostsSubtitleLabel.numberOfLines = 0
        magicPostsSubtitleLabel.text = Localizations.magicPostsExplainerSubtitle
        magicPostsSubtitleLabel.textAlignment = .center
        magicPostsSubtitleLabel.textColor = .primaryBlackWhite.withAlphaComponent(0.5)

        let contentStackView = UIStackView(arrangedSubviews: [magicPostsImageView, magicPostsTitleLabel, magicPostsSubtitleLabel])
        contentStackView.alignment = .center
        contentStackView.axis = .vertical
        contentStackView.setCustomSpacing(20, after: magicPostsImageView)
        contentStackView.setCustomSpacing(4, after: magicPostsTitleLabel)
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStackView)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            contentStackView.topAnchor.constraint(equalTo: closeButton.bottomAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            contentStackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func dismiss() {
        dismissAction?()
    }
}

extension Localizations {

    static var magicPostsExplainerTitle: String {
        NSLocalizedString("photosuggestions.explainer.title",
                          value: "Try Magic Posts",
                          comment: "title for explanation of photo suggestions")
    }

    static var magicPostsExplainerSubtitle: String {
        NSLocalizedString("photosuggestions.explainer.subtitle",
                          value: "When you take new photos, we find the best shots and organize them into a post draft, so it’s ready for you if you feel like posting.",
                          comment: "explanation for photo suggestions")
    }
}
