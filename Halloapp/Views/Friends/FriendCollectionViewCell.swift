//
//  FriendCollectionViewCell.swift
//  HalloApp
//
//  Created by Tanveer on 8/28/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon

class BaseFriendCollectionViewCell: UICollectionViewCell {

    private let separator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separatorGray
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])

        layer.masksToBounds = true
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
    }

    required init(coder: NSCoder) {
        fatalError("BaseFriendCollectionViewCell coder init not implemented...")
    }

    fileprivate func configure(isFirst: Bool, isLast: Bool) {
        var mask = CACornerMask()

        if isFirst {
            mask.insert([.layerMinXMinYCorner, .layerMaxXMinYCorner])
        }

        if isLast {
            mask.insert([.layerMinXMaxYCorner, .layerMaxXMaxYCorner])
        }

        layer.maskedCorners = mask
        separator.isHidden = isLast
    }
}

class FriendCollectionViewCell: BaseFriendCollectionViewCell {

    private let avatarView: AvatarView = {
        let view = AvatarView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .scaledSystemFont(ofSize: 17)
        return label
    }()

    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .scaledSystemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        return label
    }()

    fileprivate let trailingView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .feedPostBackground

        contentView.layoutMargins = .init(top: 10, left: 11, bottom: 10, right: 11)

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(nameLabel)
        container.addSubview(usernameLabel)

        contentView.addSubview(avatarView)
        contentView.addSubview(container)
        contentView.addSubview(trailingView)

        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 33),
            avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor, multiplier: 1),
            avatarView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            avatarView.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            container.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            container.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            container.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            container.trailingAnchor.constraint(equalTo: trailingView.leadingAnchor, constant: -10),

            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            nameLabel.topAnchor.constraint(equalTo: container.topAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            usernameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            usernameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            usernameLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            usernameLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            trailingView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            trailingView.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            trailingView.centerYAnchor.constraint(equalTo: contentView.layoutMarginsGuide.centerYAnchor),
        ])
    }

    required init(coder: NSCoder) {
        fatalError("FriendCollectionViewCell coder init not implemented...")
    }

    func configure(with friend: FriendsDataSource.Friend, isFirst: Bool, isLast: Bool) {
        avatarView.configure(with: friend.id, using: MainAppContext.shared.avatarStore)
        nameLabel.text = friend.name
        usernameLabel.text = "@" + friend.username

        configure(isFirst: isFirst, isLast: isLast)
    }
}

// MARK: - IncomingFriendCollectionViewCell

class IncomingFriendCollectionViewCell: FriendCollectionViewCell {

    class var reuseIdentifier: String {
        "incomingFriendCell"
    }

    var onConfirm: (() -> Void)?
    var onIgnore: (() -> Void)?

    private let confirmButton: UIButton = {
        let button = UIButton()
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .primaryBlue
        configuration.contentInsets = .init(top: 8, leading: 13, bottom: 8, trailing: 13)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = configuration
        return button
    }()

    private let ignoreButton: UIButton = {
        let button = UIButton(type: .custom)
        let image = UIImage(systemName: "xmark")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 6, weight: .regular))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .lightGray
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        confirmButton.setContentHuggingPriority(.breakable, for: .horizontal)
        ignoreButton.setContentHuggingPriority(.breakable, for: .horizontal)

        trailingView.addSubview(confirmButton)
        trailingView.addSubview(ignoreButton)

        NSLayoutConstraint.activate([
            confirmButton.leadingAnchor.constraint(equalTo: trailingView.leadingAnchor),
            confirmButton.topAnchor.constraint(equalTo: trailingView.topAnchor),
            confirmButton.bottomAnchor.constraint(equalTo: trailingView.bottomAnchor),

            ignoreButton.leadingAnchor.constraint(equalTo: confirmButton.trailingAnchor, constant: 12),
            ignoreButton.trailingAnchor.constraint(equalTo: trailingView.trailingAnchor),
            ignoreButton.topAnchor.constraint(equalTo: trailingView.topAnchor),
            ignoreButton.bottomAnchor.constraint(equalTo: trailingView.bottomAnchor),
        ])

        confirmButton.configuration?.attributedTitle = .init(Localizations.confirmTitle.uppercased(),
                                                             attributes: .init([.font: UIFont.scaledSystemFont(ofSize: 14, weight: .medium)]))

        confirmButton.addTarget(self, action: #selector(confirmButtonPushed), for: .touchUpInside)
        ignoreButton.addTarget(self, action: #selector(ignoreButtonPushed), for: .touchUpInside)
    }

    required init(coder: NSCoder) {
        fatalError("IncomingFriendCollectionViewCell coder init not implemented...")
    }

    @objc
    private func confirmButtonPushed(_ button: UIButton) {
        onConfirm?()
    }

    @objc
    private func ignoreButtonPushed(_ button: UIButton) {
        onIgnore?()
    }
}

// MARK: - OutgoingFriendCollectionViewCell

class OutgoingFriendCollectionViewCell: FriendCollectionViewCell {

    class var reuseIdentifier: String {
        "outgoingFriendCell"
    }

    var onCancel: (() -> Void)?

    private let cancelButton: UIButton = {
        let button = UIButton()
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .secondarySystemBackground
        configuration.baseForegroundColor = .primaryBlue
        configuration.contentInsets = .init(top: 8, leading: 13, bottom: 8, trailing: 13)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = configuration
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        cancelButton.setContentHuggingPriority(.breakable, for: .horizontal)
        trailingView.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: trailingView.leadingAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: trailingView.trailingAnchor),
            cancelButton.topAnchor.constraint(equalTo: trailingView.topAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: trailingView.bottomAnchor),
        ])

        cancelButton.configuration?.attributedTitle = .init(Localizations.buttonCancel.uppercased(),
                                                            attributes: .init([.font: UIFont.scaledSystemFont(ofSize: 14, weight: .medium)]))
        cancelButton.addTarget(self, action: #selector(cancelPushed), for: .touchUpInside)
    }

    required init(coder: NSCoder) {
        fatalError("OutgoingFriendCollectionViewCell coder init not implemented...")
    }

    @objc
    private func cancelPushed(_ button: UIButton) {
        onCancel?()
    }
}

// MARK: - SuggestedFriendCollectionViewCell

class SuggestedFriendCollectionViewCell: FriendCollectionViewCell {

    class var reuseIdentifier: String {
        "suggestedFriendCell"
    }

    var onAdd: (() -> Void)?

    private let addButton: UIButton = {
        let button = UIButton()
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .secondarySystemBackground
        configuration.baseForegroundColor = .primaryBlue
        configuration.contentInsets = .init(top: 8, leading: 13, bottom: 8, trailing: 13)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = configuration
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addButton.setContentHuggingPriority(.breakable, for: .horizontal)
        trailingView.addSubview(addButton)

        NSLayoutConstraint.activate([
            addButton.leadingAnchor.constraint(equalTo: trailingView.leadingAnchor),
            addButton.trailingAnchor.constraint(equalTo: trailingView.trailingAnchor),
            addButton.topAnchor.constraint(equalTo: trailingView.topAnchor),
            addButton.bottomAnchor.constraint(equalTo: trailingView.bottomAnchor),
        ])

        addButton.configuration?.attributedTitle = .init(Localizations.buttonAdd.uppercased(),
                                                         attributes: .init([.font: UIFont.scaledSystemFont(ofSize: 14, weight: .medium)]))
        addButton.addTarget(self, action: #selector(addButtonPushed), for: .touchUpInside)
    }

    required init(coder: NSCoder) {
        fatalError("SuggestedFriendCollectionViewCell coder init not implemented...")
    }

    @objc
    private func addButtonPushed(_ button: UIButton) {
        onAdd?()
    }
}

// MARK: - ExistingFriendCollectionViewCell

class ExistingFriendCollectionViewCell: FriendCollectionViewCell {

    class var reuseIdentifier: String {
        "existingFriendCell"
    }

    let menuButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let image = UIImage(systemName: "ellipsis")?
            .withConfiguration(UIImage.SymbolConfiguration(font: .systemFont(ofSize: 16, weight: .medium)))
        menuButton.setImage(image, for: .normal)
        menuButton.tintColor = .primaryBlue
        menuButton.setContentHuggingPriority(.breakable, for: .horizontal)

        trailingView.addSubview(menuButton)

        NSLayoutConstraint.activate([
            menuButton.leadingAnchor.constraint(equalTo: trailingView.leadingAnchor),
            menuButton.trailingAnchor.constraint(equalTo: trailingView.trailingAnchor, constant: -10),
            menuButton.topAnchor.constraint(equalTo: trailingView.topAnchor),
            menuButton.bottomAnchor.constraint(equalTo: trailingView.bottomAnchor),
        ])
    }

    required init(coder: NSCoder) {
        fatalError("ExistingFriendCollectionViewCell coder init not implemented...")
    }
}

// MARK: - FriendsEmptyStateCollectionViewCell

class FriendsEmptyStateCollectionViewCell: UICollectionViewCell {

    class var reuseIdentifier: String {
        "emptyFriendsCell"
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        let emojiLabel = UILabel()
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        emojiLabel.font = .systemFont(ofSize: 32)
        emojiLabel.text = "🤗"

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .scaledSystemFont(ofSize: 18, weight: .medium)
        titleLabel.textColor = .label.withAlphaComponent(0.5)
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.text = Localizations.noFriendsMessage

        contentView.addSubview(emojiLabel)
        contentView.addSubview(titleLabel)

        contentView.layoutMargins.top = 20
        contentView.layoutMargins.bottom = 20

        NSLayoutConstraint.activate([
            emojiLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.leadingAnchor),
            emojiLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.trailingAnchor),
            emojiLabel.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            emojiLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: emojiLabel.bottomAnchor, constant: 5),
        ])
    }

    required init(coder: NSCoder) {
        fatalError("FriendsEmptyStateCollectionViewCell coder init not implemented...")
    }
}

// MARK: - FriendRequestsIndicatorCollectionViewCell

class FriendRequestsIndicatorCollectionViewCell: BaseFriendCollectionViewCell {

    class var reuseIdentifier: String {
        "requestsIndicatorCell"
    }

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .scaledSystemFont(ofSize: 17)
        return label
    }()

    private let countLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .scaledSystemFont(ofSize: 14, weight: .medium)
        return label
    }()

    private let circleView: UIView = {
        let view = CircleView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.fillColor = .primaryBlue
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let background = UIView()
        background.backgroundColor = .feedPostBackground
        backgroundView = background

        let selected = UIView()
        selected.backgroundColor = .secondarySystemFill
        selectedBackgroundView = selected

        contentView.layoutMargins = .init(top: 14, left: 40, bottom: 14, right: 14)

        let chevronImageView = UIImageView()
        chevronImageView.translatesAutoresizingMaskIntoConstraints = false
        chevronImageView.preferredSymbolConfiguration = .init(pointSize: 14, weight: .regular)
        chevronImageView.tintColor = .lightGray
        chevronImageView.image = UIImage(systemName: "chevron.right")?.imageFlippedForRightToLeftLayoutDirection()

        chevronImageView.setContentHuggingPriority(.breakable, for: .horizontal)
        countLabel.setContentHuggingPriority(.breakable, for: .horizontal)

        contentView.addSubview(titleLabel)
        contentView.addSubview(circleView)
        contentView.addSubview(countLabel)
        contentView.addSubview(chevronImageView)

        circleView.layoutMargins = .init(top: 2, left: 2, bottom: 2, right: 2)

        let minimizeCircle = circleView.widthAnchor.constraint(equalToConstant: 0)
        minimizeCircle.priority = .minimal

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: circleView.leadingAnchor),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            chevronImageView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            chevronImageView.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            chevronImageView.centerYAnchor.constraint(equalTo: contentView.layoutMarginsGuide.centerYAnchor),

            circleView.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            circleView.trailingAnchor.constraint(equalTo: chevronImageView.leadingAnchor, constant: -9),
            circleView.centerYAnchor.constraint(equalTo: contentView.layoutMarginsGuide.centerYAnchor),
            circleView.heightAnchor.constraint(equalTo: circleView.widthAnchor, multiplier: 1),
            minimizeCircle,

            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: circleView.layoutMarginsGuide.leadingAnchor),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: circleView.layoutMarginsGuide.trailingAnchor),
            countLabel.topAnchor.constraint(greaterThanOrEqualTo: circleView.layoutMarginsGuide.topAnchor),
            countLabel.bottomAnchor.constraint(lessThanOrEqualTo: circleView.layoutMarginsGuide.bottomAnchor),
            countLabel.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            countLabel.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
        ])
    }

    required init(coder: NSCoder) {
        fatalError("FriendRequestsIndicatorCollectionViewCell coder init not implemented...")
    }

    func configure(title: String, count: Int, showCircle: Bool, isFirst: Bool, isLast: Bool) {
        titleLabel.text = title
        countLabel.text = count == 0 ? "" : "\(count)"

        let countLabelColor: UIColor
        if showCircle {
            countLabelColor = .white
        } else {
            countLabelColor = .secondaryLabel
        }

        countLabel.textColor = countLabelColor
        circleView.isHidden = !showCircle || count == 0

        configure(isFirst: isFirst, isLast: isLast)
    }
}

// MARK: - FriendInviteCollectionViewCell

class FriendInviteCollectionViewCell: BaseFriendCollectionViewCell {

    class var reuseIdentifier: String {
        "friendInviteCell"
    }

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .scaledSystemFont(ofSize: 15, weight: .semibold)
        return label
    }()

    private let phoneNumberLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .scaledSystemFont(ofSize: 11)
        label.textColor = .secondaryLabel
        return label
    }()

    private let numberOfContactsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .scaledSystemFont(ofSize: 11)
        label.textColor = .secondaryLabel
        return label
    }()

    private let inviteButton: UIButton = {
        var inviteButtonConfiguration: UIButton.Configuration = .filledCapsule(backgroundColor: .primaryBlue)
        inviteButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 13, bottom: 8, trailing: 13)
        inviteButtonConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributeContainer in
            var updatedAttributeContainer = attributeContainer
            updatedAttributeContainer.font = .scaledSystemFont(ofSize: 14, weight: .medium)
            return updatedAttributeContainer
        }

        let button = UIButton(type: .system)
        button.configuration = inviteButtonConfiguration
        button.setTitle(Localizations.buttonInvite, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .feedPostBackground
        contentView.layoutMargins = .init(top: 15, left: 15, bottom: 15, right: 15)

        inviteButton.setContentHuggingPriority(.breakable, for: .horizontal)

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(nameLabel)
        container.addSubview(phoneNumberLabel)
        container.addSubview(numberOfContactsLabel)

        contentView.addSubview(container)
        contentView.addSubview(inviteButton)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: inviteButton.leadingAnchor, constant: -10),
            container.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            container.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            inviteButton.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            inviteButton.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            inviteButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            nameLabel.topAnchor.constraint(equalTo: container.topAnchor),

            phoneNumberLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            phoneNumberLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            phoneNumberLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 3),

            numberOfContactsLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            numberOfContactsLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            numberOfContactsLabel.topAnchor.constraint(equalTo: phoneNumberLabel.bottomAnchor, constant: 3),
            numberOfContactsLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    required init(coder: NSCoder) {
        fatalError("FriendInviteCollectionViewCell coder init not implemented...")
    }

    func configure(with contact: InviteContact, actions: InviteActions, isFirst: Bool, isLast: Bool) {
        nameLabel.text = contact.fullName
        phoneNumberLabel.text = contact.formattedPhoneNumber

        if let friendCount = contact.friendCount, friendCount > 0 {
            numberOfContactsLabel.text = Localizations.contactsOnHalloApp(friendCount)
        } else {
            numberOfContactsLabel.text = nil
        }

        inviteButton.configureWithMenu {
            HAMenu {
                HAMenuButton(title: Localizations.appNameSMS) {
                    actions.action(.sms)
                }
                .disabled(!actions.types.contains(.sms))

                HAMenuButton(title: Localizations.appNameWhatsApp) {
                    actions.action(.whatsApp)
                }
                .disabled(!actions.types.contains(.whatsApp))
            }
        }

        configure(isFirst: isFirst, isLast: isLast)
    }
}

// MARK: - Localization

extension Localizations {

    static var confirmTitle: String {
        NSLocalizedString("confirm.title",
                          value: "Confirm",
                          comment: "Title of a button to confirm a friend request.")
    }

    static var noFriendsMessage: String {
        NSLocalizedString("no.friends.message",
                          value: "You're not connected to anyone on HalloApp yet",
                          comment: "Displayed when the user's friends list is empty.")
    }
}
