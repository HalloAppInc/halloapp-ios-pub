//
//  ProfileFriendshipToggle.swift
//  HalloApp
//
//  Created by Tanveer on 9/20/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import Core
import CoreCommon

class ProfileFriendshipToggle: UIView {

    private var cancellable: AnyCancellable?

    var onAdd: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    var onIgnore: (() -> Void)?
    var onRemove: (() -> Void)?

    private var primaryAction: (() -> Void)?
    private var secondaryAction: (() -> Void)?

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = .scaledSystemFont(ofSize: 14, scalingTextStyle: .footnote)
        label.adjustsFontSizeToFitWidth = true
        label.setContentCompressionResistancePriority(.breakable, for: .horizontal)
        return label
    }()

    private let primaryButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.contentInsets = .init(top: 10, leading: 12, bottom: 10, trailing: 12)
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .primaryBlue
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentCompressionResistancePriority(.breakable, for: .horizontal)
        return button
    }()

    private let secondaryButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.contentInsets = .init(top: 10, leading: 12, bottom: 10, trailing: 12)
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .secondarySystemFill
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentCompressionResistancePriority(.breakable, for: .horizontal)
        return button
    }()

    private lazy var equalButtonWidthsConstraint: NSLayoutConstraint = {
        primaryButton.widthAnchor.constraint(equalTo: secondaryButton.widthAnchor)
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let hStack = UIStackView(arrangedSubviews: [primaryButton, secondaryButton])
        hStack.spacing = 10
        hStack.distribution = .fillEqually

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.alignment = .center

        addSubview(messageLabel)
        addSubview(hStack)
        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            messageLabel.topAnchor.constraint(equalTo: topAnchor),

            hStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            hStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            hStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            hStack.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 7),
            hStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        primaryButton.addTarget(self, action: #selector(primaryButtonPushed), for: .touchUpInside)
        secondaryButton.addTarget(self, action: #selector(secondaryButtonPushed), for: .touchUpInside)
    }

    required init(coder: NSCoder) {
        fatalError("ProfileFriendshipToggle coder init not implemented...")
    }

    func configure(name: String, status: UserProfile.FriendshipStatus) {
        var messageText = " "
        var primaryText = ""
        var secondaryText = ""
        var hidePrimary = true
        var hideSecondary = true

        var primaryAction: (() -> Void)?
        var secondaryAction: (() -> Void)?

        switch status {
        case .friends:
            hideSecondary = false
            secondaryText = Localizations.friendsTitle
            secondaryAction = onRemove
        case .outgoingPending:
            messageText = String(format: Localizations.outgoingRequestFormat, name)
            hideSecondary = false
            secondaryText = Localizations.cancelRequest
            secondaryAction = onCancel
        case .incomingPending:
            messageText = String(format: Localizations.incomingRequestFormat, name)
            hidePrimary = false
            hideSecondary = false
            primaryText = Localizations.confirmTitle
            secondaryText = Localizations.ignoreTitle
            primaryAction = onConfirm
            secondaryAction = onIgnore
        case .none:
            hidePrimary = false
            primaryText = Localizations.addFriend
            primaryAction = onAdd
        }

        messageLabel.text = messageText

        if primaryButton.isHidden != hidePrimary {
            primaryButton.isHidden = hidePrimary
        }
        if secondaryButton.isHidden != hideSecondary {
            secondaryButton.isHidden = hideSecondary
        }

        primaryButton.configuration?.attributedTitle = AttributedString(primaryText.uppercased(),
                                                                        attributes: .init([.font: UIFont.scaledSystemFont(ofSize: 17, weight: .medium),
                                                                                           .foregroundColor: UIColor.white]))
        secondaryButton.configuration?.attributedTitle = AttributedString(secondaryText.uppercased(),
                                                                          attributes: .init([.font: UIFont.scaledSystemFont(ofSize: 17, weight: .medium),
                                                                                             .foregroundColor: UIColor.primaryBlue]))
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }

    @objc
    private func primaryButtonPushed(_ button: UIButton) {
        primaryAction?()
    }

    @objc
    private func secondaryButtonPushed(_ button: UIButton) {
        secondaryAction?()
    }
}

// MARK: - Localization

extension Localizations {

    static var cancelRequest: String {
        NSLocalizedString("cancel.request",
                          value: "Cancel Request",
                          comment: "Title of a button to cancel a friendship request.")
    }

    static var ignoreTitle: String {
        NSLocalizedString("ignore.title",
                          value: "Ignore",
                          comment: "Title of a button to ignore a friendship request.")
    }

    static var incomingRequestFormat: String {
        NSLocalizedString("incoming.friend.request.format",
                          value: "%@ has sent you a friend request",
                          comment: "Message displayed next to an incoming friend request.")
    }

    static var outgoingRequestFormat: String {
        NSLocalizedString("outgoing.friend.request.format",
                          value: "You have sent %@ a friend request",
                          comment: "Message displayed next to an outgoing friend request.")
    }
}
