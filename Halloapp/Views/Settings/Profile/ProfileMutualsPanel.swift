//
//  ProfileMutualsPanel.swift
//  HalloApp
//
//  Created by Tanveer on 12/12/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon
import Core

class ProfileMutualsPanel: UIView {

    private let facePileView: StackedFacePileView = {
        let view = StackedFacePileView()
        return view
    }()

    private let label: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.font = .scaledSystemFont(ofSize: 14, scalingTextStyle: .footnote)
        label.adjustsFontSizeToFitWidth = true
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let stack = UIStackView(arrangedSubviews: [facePileView, label])
        stack.spacing = 7

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init(coder: NSCoder) {
        fatalError("ProfileMutualsPanel coder init not implemented...")
    }

    func configure(with friends: [UserID], groups: [GroupID]) {
        let text: String
        if !friends.isEmpty, !groups.isEmpty {
            text = String.localizedStringWithFormat(Localizations.mutualFriendsAndGroups,
                                                    friends.count, groups.count)
        } else if friends.count >= 1 {
            text = String.localizedStringWithFormat(Localizations.mutualFriends,
                                                    friends.count)
        } else {
            text = String.localizedStringWithFormat(Localizations.mutualGroups,
                                                    groups.count)
        }

        label.text = text
        facePileView.configure(with: friends, groups: groups)
    }
}

fileprivate class StackedFacePileView: UIStackView {

    private let numberOfFaces = 3

    private lazy var avatarViews: [AvatarView] = {
        (0..<numberOfFaces).map { _ in AvatarView() }
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        spacing = -5

        for avatarView in avatarViews {
            avatarView.borderWidth = 2
            avatarView.borderColor = .feedBackground
            avatarView.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                avatarView.heightAnchor.constraint(equalToConstant: 24),
                avatarView.widthAnchor.constraint(equalTo: avatarView.heightAnchor)
            ])

            addArrangedSubview(avatarView)
        }
    }

    required init(coder: NSCoder) {
        fatalError("StackedFacePileView coder init not implemented...")
    }

    func configure(with users: [UserID], groups: [GroupID]) {
        avatarViews.forEach { $0.isHidden = true }
        var numberOfFacesUsed = 0

        for (index, (friendID, avatarView)) in zip(users, avatarViews).enumerated() {
            avatarView.configure(with: friendID, using: MainAppContext.shared.avatarStore)
            avatarView.isHidden = false

            numberOfFacesUsed = index + 1
        }

        if numberOfFacesUsed == numberOfFaces, let groupID = groups.first {
            // face pile is already filled with friends; change last friend to a group
            avatarViews.last?.configure(groupId: groupID, using: MainAppContext.shared.avatarStore)
        } else {
            for (groupID, avatarView) in zip(groups, avatarViews[numberOfFacesUsed...]) {
                avatarView.configure(groupId: groupID, squareSize: 50, using: MainAppContext.shared.avatarStore)
                avatarView.isHidden = false
            }
        }
    }
}

// MARK: - Localization

extension Localizations {

    static var mutualFriendsAndGroups: String {
        NSLocalizedString("profile.mutual.friends.groups",
                          comment: "Indicates mutual friends and groups with another user.")
    }

    static var mutualFriends: String {
        NSLocalizedString("profile.n.mutual.friends",
                          comment: "Indicates mutual friends with another user.")
    }

    static var mutualGroups: String {
        NSLocalizedString("profile.n.mutual.groups",
                          comment: "Indicates mutual groups with another user.")
    }
}
