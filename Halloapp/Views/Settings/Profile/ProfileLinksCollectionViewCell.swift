//
//  ProfileLinksCollectionViewCell.swift
//  HalloApp
//
//  Created by Tanveer on 11/12/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon
import CocoaLumberjackSwift

class ProfileLinksCollectionViewCell: UICollectionViewCell {

    static let reuseIdentifier = "profileLinksCell"

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .scaledSystemFont(ofSize: 16, weight: .medium)
        return label
    }()

    private let linkRows: [LinkRow] = {
        (0..<4).map { _ in LinkRow() }
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layoutMargins = .init(top: 11, left: 50, bottom: 11, right: 50)

        let stack = UIStackView(arrangedSubviews: linkRows)
        stack.axis = .vertical
        stack.spacing = 7

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.trailingAnchor),
            nameLabel.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),

            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 15),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        contentView.addGestureRecognizer(tap)
    }

    required init(coder: NSCoder) {
        fatalError("ProfileLinksCollectionViewCell coder init not implemented...")
    }

    func configure(with name: String, links: [ProfileLink]) {
        for (index, row) in linkRows.enumerated() {
            if index < links.count {
                row.configure(with: links[index])
            } else if !row.isHidden {
                row.isHidden = true
            }
        }

        nameLabel.text = String(format: Localizations.profileLinksFormat, name)
    }

    @objc
    private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let hit = contentView.hitTest(gesture.location(in: gesture.view), with: nil),
              let string = (hit as? UILabel)?.text else {
            return
        }

        if let url = URL(string: string), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "https://" + string), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            DDLogError("ProfileLinksCollectionViewCell/tapHandler/failed to open link \(string)")
        }
    }
}

// MARK: - LinkRow

fileprivate class LinkRow: UIStackView {

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.tintColor = .primaryBlue
        view.contentMode = .center
        return view
    }()

    private let label: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.font = .scaledSystemFont(ofSize: 16)
        label.adjustsFontSizeToFitWidth = true
        label.isUserInteractionEnabled = true
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        spacing = 10

        addArrangedSubview(imageView)
        addArrangedSubview(label)

        imageView.translatesAutoresizingMaskIntoConstraints = false

        let width = imageView.widthAnchor.constraint(equalToConstant: 28)
        let height = imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor)

        width.priority = .breakable
        NSLayoutConstraint.activate([width, height])
    }

    required init(coder: NSCoder) {
        fatalError("LinkRow coder init not implemented...")
    }

    func configure(with link: ProfileLink) {
        imageView.image = link.image
        label.text = (link.type.base ?? "") + link.string
    }
}

// MARK: - Localization

extension Localizations {

    static var profileLinksFormat: String {
        NSLocalizedString("profile.links.format",
                          value: "%@’s links:",
                          comment: "Indicates a user's social media links where the variable is the user's name.")
    }
}
