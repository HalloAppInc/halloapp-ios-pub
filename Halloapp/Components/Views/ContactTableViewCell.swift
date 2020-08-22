//
//  ContactTableViewCell.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/5/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit

class ContactTableViewCell: UITableViewCell {

    override var isUserInteractionEnabled: Bool {
        didSet {
            if isUserInteractionEnabled {
                nameLabel.textColor = .label
            } else {
                nameLabel.textColor = .systemGray
            }
        }
    }
    
    let contactImage: AvatarView = {
        return AvatarView()
    }()

    private var profilePictureSizeConstraint: NSLayoutConstraint!

    var profilePictureSize: CGFloat = 30 {
        didSet {
            profilePictureSizeConstraint.constant = profilePictureSize
        }
    }
    
    let nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let subtitleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var vStack: UIStackView!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        contentView.addSubview(contactImage)
        contactImage.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        contactImage.centerYAnchor.constraint(equalTo: contentView.layoutMarginsGuide.centerYAnchor).isActive = true
        profilePictureSizeConstraint = contactImage.heightAnchor.constraint(equalToConstant: profilePictureSize)
        profilePictureSizeConstraint.isActive = true
        contactImage.heightAnchor.constraint(equalTo: contactImage.widthAnchor).isActive = true

        vStack = UIStackView(arrangedSubviews: [ nameLabel, subtitleLabel ])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        vStack.spacing = 4
        contentView.addSubview(vStack)
        vStack.constrainMargins([ .top, .trailing, .bottom ], to: contentView)
        vStack.leadingAnchor.constraint(equalToSystemSpacingAfter: contactImage.trailingAnchor, multiplier: 1).isActive = true
    }

    override func prepareForReuse() {
        contactImage.prepareForReuse()
        accessoryView = nil
        nameLabel.text = ""
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let labelSpacing: CGFloat = subtitleLabel.text?.isEmpty ?? true ? 0 : 4
        if vStack.spacing != labelSpacing {
            vStack.spacing = labelSpacing
        }
    }

}
