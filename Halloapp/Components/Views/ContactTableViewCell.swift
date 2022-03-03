//
//  ContactTableViewCell.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/5/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit
import CocoaLumberjackSwift

class ContactTableViewCell: UITableViewCell {

    override var isUserInteractionEnabled: Bool {
        didSet {
            if isUserInteractionEnabled {
                nameLabel.textColor = .label
                checkMark.tintAdjustmentMode = .normal
            } else {
                nameLabel.textColor = .systemGray
                checkMark.tintAdjustmentMode = .dimmed
            }
        }
    }
    
    let contactImage: AvatarView = {
        return AvatarView()
    }()

    private var profilePictureSizeConstraint: NSLayoutConstraint!
    private var profilePictureVisibleConstraints: [NSLayoutConstraint]!
    private var profilePictureHiddenConstraints: [NSLayoutConstraint]!

    var profilePictureSize: CGFloat = 30 {
        didSet {
            profilePictureSizeConstraint.constant = profilePictureSize
        }
    }

    struct Options: OptionSet {
        let rawValue: Int

        static let hasImage = Options(rawValue: 1 << 0)
        static let hasCheckmark = Options(rawValue: 1 << 1)
        static let useBlueCheckmark = Options(rawValue: 1 << 2)
    }
    var options: Options = [ .hasImage ] {
        didSet {
            if options.contains(.hasImage) {
                contactImage.isHidden = false
                contentView.removeConstraints(profilePictureHiddenConstraints)
                contentView.addConstraints(profilePictureVisibleConstraints)
            } else {
                contactImage.isHidden = true
                contentView.removeConstraints(profilePictureVisibleConstraints)
                contentView.addConstraints(profilePictureHiddenConstraints)
            }

            if options.contains(.hasCheckmark) {
                selectionStyle = .none
                accessoryView = checkMark
            } else {
                selectionStyle = .default
                accessoryView = nil
            }
            
            if options.contains(.useBlueCheckmark) {
                checkMark.tintColor = .systemBlue
            } else {
                checkMark.tintColor = .lavaOrange
            }
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
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let accessoryLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .tertiaryLabel
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh + 50, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private static var checkmarkUnchecked: UIImage {
        UIImage(systemName: "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 25))!.withRenderingMode(.alwaysTemplate)
    }

    private static var checkmarkChecked: UIImage {
        UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 25))!.withRenderingMode(.alwaysTemplate)
    }

    private lazy var checkMark: UIImageView = {
        let imageView = UIImageView(image: ContactTableViewCell.checkmarkUnchecked)
        imageView.tintColor = .lavaOrange
        return imageView
    }()

    private var vStack: UIStackView!
    private var hStack: UIStackView!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        contactImage.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contactImage)

        vStack = UIStackView(arrangedSubviews: [ nameLabel, subtitleLabel ])
        vStack.distribution = .fillProportionally
        vStack.axis = .vertical
        vStack.spacing = 3

        hStack = UIStackView(arrangedSubviews: [ vStack, accessoryLabel ])
        hStack.spacing = 8
        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.distribution = .fill
        hStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hStack)

        accessoryLabel.textAlignment = effectiveUserInterfaceLayoutDirection == .leftToRight ? .right : .left

        profilePictureSizeConstraint = contactImage.heightAnchor.constraint(equalToConstant: profilePictureSize)

        profilePictureVisibleConstraints = [
            hStack.leadingAnchor.constraint(equalTo: contactImage.trailingAnchor, constant: 10)
        ]

        profilePictureHiddenConstraints = [
            hStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor)
        ]

        contentView.addConstraints([
            profilePictureSizeConstraint,
            contactImage.heightAnchor.constraint(equalTo: contactImage.widthAnchor),
            contactImage.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            contactImage.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            hStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            hStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)
        ])

        if options.contains(.hasImage) {
            contentView.addConstraints(profilePictureVisibleConstraints)
        } else {
            contentView.addConstraints(profilePictureHiddenConstraints)
        }

        // Priority is lower than "required" because cell's height might not be enough temporarily.
        contentView.addConstraint({
            let constraint = contactImage.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 8)
            constraint.priority = .defaultHigh
            return constraint
            }())
        contentView.addConstraint({
            let constraint = hStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor)
            constraint.priority = .defaultHigh
            return constraint
            }())
    }

    private(set) var isContactSelected: Bool = false

    func setContact(selected: Bool, animated: Bool = false) {
        guard options.contains(.hasCheckmark) else { return }

        isContactSelected = selected
        checkMark.image = isContactSelected ? Self.checkmarkChecked : Self.checkmarkUnchecked
        if animated {
            checkMark.layer.add({
                let transition = CATransition()
                transition.duration = 0.2
                transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                transition.type = .fade
                return transition
            }(), forKey: nil)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contactImage.prepareForReuse()
        isUserInteractionEnabled = true
    }

}
