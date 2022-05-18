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

    var didSelectGroupHeader: ((GroupGridHeader) -> Void)?

    private let groupAvatarView: AvatarView = AvatarView()

    private let groupNameLabel: UILabel = {
        let groupNameLabel = UILabel()
        groupNameLabel.font = .gothamFont(forTextStyle: .subheadline, weight: .medium)
        groupNameLabel.textColor = .label.withAlphaComponent(0.75)
        return groupNameLabel
    }()

    private let unreadPostCountLabel: UILabel = {
        let unreadPostCountLabel = UILabel()
        unreadPostCountLabel.font = .gothamFont(forTextStyle: .subheadline, weight: .medium)
        unreadPostCountLabel.textColor = .label.withAlphaComponent(0.75)
        return unreadPostCountLabel
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))

        groupAvatarView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(groupAvatarView)

        groupNameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(groupNameLabel)

        unreadPostCountLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(unreadPostCountLabel)

        let disclosureIndicatorImageView = UIImageView(image: UIImage(systemName: "chevron.forward"))
        disclosureIndicatorImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18)
        disclosureIndicatorImageView.tintColor = UIColor.label.withAlphaComponent(0.25)
        disclosureIndicatorImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(disclosureIndicatorImageView)

        let minimizeHeightConstraint = heightAnchor.constraint(equalToConstant: 0)
        minimizeHeightConstraint.priority = UILayoutPriority(1)

        NSLayoutConstraint.activate([
            groupAvatarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            groupAvatarView.centerYAnchor.constraint(equalTo: centerYAnchor),
            groupAvatarView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10),

            groupNameLabel.leadingAnchor.constraint(equalTo: groupAvatarView.trailingAnchor, constant: 10),
            groupNameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            groupNameLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10),

            unreadPostCountLabel.trailingAnchor.constraint(equalTo: disclosureIndicatorImageView.leadingAnchor, constant: -10),
            unreadPostCountLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            unreadPostCountLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10),

            disclosureIndicatorImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            disclosureIndicatorImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            disclosureIndicatorImageView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(with groupID: GroupID) {
        groupAvatarView.configure(groupId: groupID, squareSize: 32, using: MainAppContext.shared.avatarStore)
        groupNameLabel.text = MainAppContext.shared.chatData.chatGroup(groupId: groupID)?.name
        unreadPostCountLabel.text = "1"
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        groupAvatarView.prepareForReuse()
    }

    @objc private func didTap() {
        didSelectGroupHeader?(self)
    }
}
