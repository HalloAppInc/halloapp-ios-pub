//
//  FriendHeaderViews.swift
//  HalloApp
//
//  Created by Tanveer on 8/29/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon

class DefaultFriendHeaderView: UICollectionReusableView {

    class var reuseIdentifier: String {
        "defaultFriendHeader"
    }

    fileprivate let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .feedBackground

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            label.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            label.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])

        label.font = .scaledSystemFont(ofSize: 12)
        label.textColor = .label.withAlphaComponent(0.5)
    }

    required init(coder: NSCoder) {
        fatalError("FriendCollectionReusableView coder init not implemented...")
    }

    func configure(title: String) {
        label.text = title
    }
}

// MARK: - FriendInitialHeaderView

class FriendInitialHeaderView: DefaultFriendHeaderView {

    override class var reuseIdentifier: String {
        "friendInitialHeader"
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        label.font = .scaledSystemFont(ofSize: 16, weight: .medium, scalingTextStyle: .footnote)
        label.textColor = .darkGray
    }

    required init(coder: NSCoder) {
        fatalError("FriendCollectionReusableView coder init not implemented...")
    }
}

// MARK: - FriendInviteHeaderView

class FriendInviteHeaderView: UICollectionReusableView {

    class var reuseIdentifier: String {
        "friendInviteHeader"
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        layoutMargins = .init(top: 12, left: 10, bottom: 12, right: 10)

        let emojiLabel = UILabel()
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        emojiLabel.font = .systemFont(ofSize: 32)
        emojiLabel.text = "💌"

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .scaledGothamFont(ofSize: 18, weight: .medium, scalingTextStyle: .footnote)
        titleLabel.numberOfLines = 0
        titleLabel.textColor = .label.withAlphaComponent(0.9)
        titleLabel.text = Localizations.friendInviteHeaderTitle

        addSubview(emojiLabel)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            emojiLabel.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            emojiLabel.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
            emojiLabel.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            emojiLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: emojiLabel.bottomAnchor, constant: 3),
            titleLabel.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    required init(coder: NSCoder) {
        fatalError("FriendInviteHeaderView coder init not implemented...")
    }
}

// MARK: - FriendRequestsHeaderView

class FriendRequestsHeaderView: UICollectionReusableView {

    class var reuseIdentifier: String {
        "friendRequestsHeader"
    }

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .scaledSystemFont(ofSize: 21, weight: .semibold, scalingTextStyle: .footnote)
        label.numberOfLines = 0
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])
    }

    required init(coder: NSCoder) {
        fatalError("FriendRequestsHeaderView coder init not implemented...")
    }

    func configure(title: String) {
        titleLabel.text = title
    }
}

// MARK: - Localization

extension Localizations {

    static var friendInviteHeaderTitle: String {
        NSLocalizedString("friend.invite.header.title",
                          value: "Who else do you want to see here?",
                          comment: "Title of a header that appears before a list of contacts that can be invited to register.")
    }
}
