//
//  ProfileHeaderCollectionViewCell.swift
//  HalloApp
//
//  Created by Tanveer on 12/12/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit

class ProfileHeaderCollectionViewCell: UICollectionViewCell {

    class var reuseIdentifier: String {
        "profileHeaderCell"
    }

    fileprivate var configuration: ProfileHeaderViewController.Configuration {
        .default
    }

    private(set) lazy var profileHeader: ProfileHeaderViewController = {
        let viewController = ProfileHeaderViewController(configuration: configuration)
        return viewController
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        profileHeader.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(profileHeader.view)

        NSLayoutConstraint.activate([
            profileHeader.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            profileHeader.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            profileHeader.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            profileHeader.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    required init(coder: NSCoder) {
        fatalError("ProfileHeaderCollectionViewCell coder init not implemented...")
    }
}

// MARK: - OwnProfileHeaderCollectionViewCell

final class OwnProfileHeaderCollectionViewCell: ProfileHeaderCollectionViewCell {

    override class var reuseIdentifier: String {
        "ownProfileHeaderCell"
    }

    override var configuration: ProfileHeaderViewController.Configuration {
        .ownProfile
    }
}
