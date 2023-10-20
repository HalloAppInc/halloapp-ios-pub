//
//  FeedCarouselCell.swift
//  HalloApp
//
//  Created by Tanveer on 10/10/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon

protocol FeedCarouselCellDelegate: AnyObject {
    func feedCarouselCellDidTapPrimaryButton(_ cell: FeedCarouselCell)
    func feedCarouselCellDidDismiss(_ cell: FeedCarouselCell)
    func feedCarouselCellDidTapUser(_ cell: FeedCarouselCell)
}

class FeedCarouselCell: UICollectionViewCell {

    private struct Constants {
        static let avatarTopSpacing: CGFloat = 22
        static let avatarSize: CGFloat = 36
        static let avatarNameLabelSpacing: CGFloat = 8
        static let nameLabelUsernameLabelSpacing: CGFloat = 0
        static let usernameLabelBodyLabelSpacing: CGFloat = 8
        static let bodyLabelButtonSpacing: CGFloat = 12
        static let buttonBottomSpacing: CGFloat = 16
        static let buttonVerticalPadding: CGFloat = 8
        static let nameLabelFont = UIFont.gothamFont(ofFixedSize: 15, weight: .medium)
        static let usernameLabelFont = UIFont.systemFont(ofSize: 14)
        static let bodyLabelFont = UIFont.systemFont(ofSize: 13, weight: .regular)
        static let buttonFont = UIFont.systemFont(ofSize: 15, weight: .medium)
    }

    fileprivate class var nameLabelLineCount: CGFloat {
        2
    }

    fileprivate class var usernameLabelLineCount: CGFloat {
        0
    }

    static var height: CGFloat {
        var height: CGFloat = 0
        height += Constants.avatarTopSpacing
        height += Constants.avatarSize
        height += Constants.avatarNameLabelSpacing
        height += Constants.nameLabelFont.lineHeight * nameLabelLineCount
        height += Constants.nameLabelUsernameLabelSpacing
        height += Constants.usernameLabelFont.lineHeight * usernameLabelLineCount
        height += Constants.usernameLabelBodyLabelSpacing
        height += Constants.bodyLabelFont.lineHeight * 2.0
        height += Constants.bodyLabelButtonSpacing
        height += Constants.buttonVerticalPadding
        height += Constants.buttonFont.lineHeight
        height += Constants.buttonVerticalPadding
        height += Constants.buttonBottomSpacing
        return height
    }

    weak var delegate: FeedCarouselCellDelegate?

    fileprivate let avatarView: AvatarView = {
        let avatarView = AvatarView()
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = Constants.avatarSize / 2.0
        return avatarView
    }()

    fileprivate let searchIconImageView: UIImageView = {
        let searchIconImageView = UIImageView()
        searchIconImageView.backgroundColor = AvatarView.defaultBackgroundColor
        searchIconImageView.contentMode = .center
        searchIconImageView.image = UIImage(systemName: "magnifyingglass")
        searchIconImageView.layer.cornerRadius = Constants.avatarSize / 2.0
        searchIconImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        searchIconImageView.tintColor = .avatarDefaultIcon
        return searchIconImageView
    }()

    fileprivate let nameLabel: UILabel = {
        let nameLabel = UILabel()
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.font = Constants.nameLabelFont
        nameLabel.textAlignment = .center
        nameLabel.textColor = .label
        nameLabel.minimumScaleFactor = 0.5
        return nameLabel
    }()

    fileprivate let usernameLabel: UILabel = {
        let usernameLabel = UILabel()
        usernameLabel.adjustsFontSizeToFitWidth = true
        usernameLabel.font = Constants.usernameLabelFont
        usernameLabel.textAlignment = .center
        usernameLabel.textColor = .secondaryLabel
        usernameLabel.minimumScaleFactor = 0.5
        return usernameLabel
    }()

    fileprivate let secondaryLabel: UILabel = {
        let secondaryLabel = UILabel()
        secondaryLabel.font = Constants.bodyLabelFont
        secondaryLabel.numberOfLines = 2
        secondaryLabel.textAlignment = .center
        secondaryLabel.textColor = .label.withAlphaComponent(0.5)
        return secondaryLabel
    }()

    fileprivate lazy var buttonConfiguration: UIButton.Configuration = {
        var inviteButtonConfiguration = UIButton.Configuration.filled()
        inviteButtonConfiguration.baseBackgroundColor = .primaryBlue
        inviteButtonConfiguration.baseForegroundColor = .white
        inviteButtonConfiguration.cornerStyle = .capsule
        // adjust down for visual alignment
        inviteButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: Constants.buttonVerticalPadding - 1,
                                                                          leading: 16,
                                                                          bottom: Constants.buttonVerticalPadding + 1,
                                                                          trailing: 16)
        return inviteButtonConfiguration
    }()

    fileprivate lazy var buttonSelectedConfiguration: UIButton.Configuration = {
        var inviteButtonInvitedConfiguration = buttonConfiguration
        inviteButtonInvitedConfiguration.baseBackgroundColor = .systemGray
        return inviteButtonInvitedConfiguration
    }()

    fileprivate lazy var primaryButton: UIButton = {
        let primaryButton = UIButton(type: .system)
        primaryButton.configuration = buttonConfiguration
        primaryButton.titleLabel?.adjustsFontSizeToFitWidth = true
        primaryButton.titleLabel?.font = Constants.buttonFont
        primaryButton.titleLabel?.minimumScaleFactor = 0.5
        return primaryButton
    }()

    fileprivate let dismissButton: UIButton = {
        var dismissButtonConfiguration = UIButton.Configuration.plain()
        dismissButtonConfiguration.baseForegroundColor = .label.withAlphaComponent(0.2)
        dismissButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)

        let dismissButton = UIButton(type: .system)
        dismissButton.configuration = dismissButtonConfiguration
        let dismissButtonImage = UIImage(systemName: "xmark")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
        dismissButton.setImage(dismissButtonImage, for: .normal)
        return dismissButton
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = UIColor.feedPostBackground
        contentView.layer.borderColor = UIColor.label.cgColor
        contentView.layer.borderWidth = 1.0 / UIScreen.main.scale
        contentView.layer.cornerRadius = 15
        contentView.layer.shadowColor = UIColor.black.cgColor
        contentView.layer.shadowOffset = CGSize(width: 0, height: 3)
        contentView.layer.shadowOpacity = 0.08
        contentView.layer.shadowRadius = 5

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)

        searchIconImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(searchIconImageView)

        nameLabel.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        nameLabel.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.numberOfLines = Int(Self.nameLabelLineCount)
        contentView.addSubview(nameLabel)

        usernameLabel.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        usernameLabel.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        usernameLabel.numberOfLines = Int(Self.usernameLabelLineCount)
        contentView.addSubview(usernameLabel)

        secondaryLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(secondaryLabel)

        primaryButton.addTarget(self, action: #selector(primaryButtonTapped), for: .touchUpInside)
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(primaryButton)

        dismissButton.addTarget(self, action: #selector(dismissButtonTapped), for: .touchUpInside)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dismissButton)

        // Prevent layout breakage when sized at parent's estimated size
        let inviteButtonBottomConstraint = primaryButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.buttonBottomSpacing)
        inviteButtonBottomConstraint.priority = .breakable

        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: Constants.avatarSize),
            avatarView.heightAnchor.constraint(equalToConstant: Constants.avatarSize),

            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.avatarTopSpacing),
            avatarView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            searchIconImageView.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            searchIconImageView.topAnchor.constraint(equalTo: avatarView.topAnchor),
            searchIconImageView.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            searchIconImageView.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),

            nameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            nameLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            nameLabel.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: Constants.avatarNameLabelSpacing),

            usernameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            usernameLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            usernameLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Constants.nameLabelUsernameLabelSpacing),

            secondaryLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            secondaryLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            secondaryLabel.topAnchor.constraint(equalTo: usernameLabel.bottomAnchor, constant: Constants.usernameLabelBodyLabelSpacing),

            primaryButton.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            primaryButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            primaryButton.topAnchor.constraint(equalTo: secondaryLabel.bottomAnchor, constant: Constants.bodyLabelButtonSpacing),
            inviteButtonBottomConstraint,

            dismissButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            dismissButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        [avatarView, nameLabel, usernameLabel].forEach { $0.isUserInteractionEnabled = true }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture))
        contentView.addGestureRecognizer(tap)

        updateBorderColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.layer.shadowPath = UIBezierPath(roundedRect: contentView.bounds,
                                                    cornerRadius: contentView.layer.cornerRadius).cgPath
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateBorderColor()
        }
    }

    private func updateBorderColor() {
        contentView.layer.borderColor = UIColor.label.withAlphaComponent(0.18).resolvedColor(with: traitCollection).cgColor
    }

    @objc
    private func primaryButtonTapped(_ button: UIButton) {
        delegate?.feedCarouselCellDidTapPrimaryButton(self)
    }

    @objc
    private func dismissButtonTapped(_ button: UIButton) {
        delegate?.feedCarouselCellDidDismiss(self)
    }

    @objc
    private func handleTapGesture(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: contentView)
        let hit = contentView.hitTest(location, with: nil)

        if hit === avatarView || hit === nameLabel || hit === usernameLabel {
            delegate?.feedCarouselCellDidTapUser(self)
        }
    }
}

// MARK: - InviteCarouselCell

class InviteCarouselCell: FeedCarouselCell {

    static let reuseIdentifier = "inviteCarouselCell"

    override init(frame: CGRect) {
        super.init(frame: frame)
        avatarView.isHidden = false
        searchIconImageView.isHidden = true

        // Prevent title fade animation
        UIView.performWithoutAnimation {
            primaryButton.setTitle(Localizations.buttonInvite, for: .normal)
            primaryButton.layoutIfNeeded()
        }
        dismissButton.isHidden = false
    }

    required init(coder: NSCoder) {
        fatalError()
    }

    func configure(with contact: InviteContact, invited: Bool) {
        if let userID = contact.userID {
            avatarView.configure(with: userID, using: MainAppContext.shared.avatarStore)
        } else {
            avatarView.configure(contactIdentfier: contact.identifier, using: MainAppContext.shared.avatarStore)
        }

        nameLabel.text = contact.fullName
        secondaryLabel.text = contact.friendCount.flatMap { Localizations.contactsOnHalloApp($0) }
        primaryButton.configuration = invited ? buttonSelectedConfiguration : buttonConfiguration
    }
}

// MARK: - SuggestionCarouselCell

class SuggestionCarouselCell: FeedCarouselCell {

    static let reuseIdentifier = "suggestionCarouselCell"

    override class var nameLabelLineCount: CGFloat {
        1
    }

    override class var usernameLabelLineCount: CGFloat {
        1
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        avatarView.isHidden = false
        searchIconImageView.isHidden = true
        dismissButton.isHidden = false
    }

    required init(coder: NSCoder) {
        fatalError()
    }

    func configure(with suggestion: FeedSuggestionsCarouselCell.Suggestion, added: Bool) {
        avatarView.configure(with: suggestion.id, using: MainAppContext.shared.avatarStore)
        nameLabel.text = suggestion.name
        usernameLabel.text = "@\(suggestion.username)"
        primaryButton.configuration = added ? buttonSelectedConfiguration : buttonConfiguration

        // Prevent title fade animation
        UIView.performWithoutAnimation {
            primaryButton.setTitle(added ? Localizations.buttonCancel : Localizations.addFriend, for: .normal)
            primaryButton.layoutIfNeeded()
        }
    }
}

// MARK: - SearchCarouselCell

class SearchCarouselCell: FeedCarouselCell {

    static let reuseIdentifier = "searchCarouselCell"

    override init(frame: CGRect) {
        super.init(frame: frame)
        avatarView.isHidden = true
        searchIconImageView.isHidden = false
        nameLabel.numberOfLines = 0
        nameLabel.text = Localizations.feedInviteCarouselSearchPrompt
        secondaryLabel.text = nil
        primaryButton.configuration = buttonConfiguration
        // Prevent title fade animation
        UIView.performWithoutAnimation {
            primaryButton.setTitle(Localizations.labelSearch, for: .normal)
            primaryButton.layoutIfNeeded()
        }
        dismissButton.isHidden = true
    }

    required init(coder: NSCoder) {
        fatalError()
    }
}
