//
//  GroupGridHeader.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 5/11/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import UIKit

class GroupGridHeader: UICollectionReusableView {

    static let elementKind = "header"
    static let reuseIdentifier = String(describing: GroupGridHeader.self)

    var openGroupFeed: (() -> Void)?
    var composeGroupPost: (() -> Void)?

    private struct Constants {
        static let postButtonSize: CGFloat = 22
        static let avatarSize: CGFloat = 32
    }

    private let groupAvatarView: AvatarView = AvatarView()

    private let groupNameLabel: UILabel = {
        let groupNameLabel = UILabel()
        groupNameLabel.adjustsFontForContentSizeCategory = true
        groupNameLabel.font = .gothamFont(forTextStyle: .subheadline, weight: .medium)
        groupNameLabel.textColor = .label.withAlphaComponent(0.75)
        return groupNameLabel
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(headerTapped)))

        let groupAvatarAndNameStackView = UIStackView(arrangedSubviews: [groupAvatarView, groupNameLabel])
        groupAvatarAndNameStackView.alignment = .center
        groupAvatarAndNameStackView.axis = .horizontal
        groupAvatarAndNameStackView.isLayoutMarginsRelativeArrangement = true
        groupAvatarAndNameStackView.layoutMargins = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        groupAvatarAndNameStackView.spacing = 12
        groupAvatarAndNameStackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(groupAvatarAndNameStackView)

        let postButton = RoundedRectButton()
        postButton.addTarget(self, action: #selector(composeButtonTapped), for: .touchUpInside)
        postButton.backgroundTintColor = .lavaOrange
        postButton.imageView?.tintColor = .primaryWhiteBlack
        postButton.setImage(UIImage(systemName: "plus")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)),
                            for: .normal)
        postButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(postButton)

        // prevent constraint breakage on initial sizing
        let groupAvatarAndNameStackViewBottomConstraint = groupAvatarAndNameStackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        groupAvatarAndNameStackViewBottomConstraint.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            groupAvatarView.widthAnchor.constraint(equalToConstant: Constants.avatarSize),
            groupAvatarView.heightAnchor.constraint(equalToConstant: Constants.avatarSize),

            groupAvatarAndNameStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            groupAvatarAndNameStackView.topAnchor.constraint(equalTo: topAnchor),
            groupAvatarAndNameStackViewBottomConstraint,
            groupAvatarAndNameStackView.trailingAnchor.constraint(lessThanOrEqualTo: postButton.leadingAnchor),

            postButton.widthAnchor.constraint(equalToConstant: Constants.postButtonSize),
            postButton.heightAnchor.constraint(equalToConstant: Constants.postButtonSize),
            postButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            postButton.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(with groupID: GroupID) {
        groupAvatarView.configure(groupId: groupID, squareSize: Constants.avatarSize, using: MainAppContext.shared.avatarStore)
        groupNameLabel.text = MainAppContext.shared.chatData.chatGroup(groupId: groupID)?.name
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        groupAvatarView.prepareForReuse()
    }

    @objc private func headerTapped() {
        openGroupFeed?()
    }

    @objc private func composeButtonTapped() {
        composeGroupPost?()
    }
}
