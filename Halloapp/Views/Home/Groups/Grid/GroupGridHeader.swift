//
//  GroupGridHeader.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 5/11/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Combine
import Core
import UIKit

class GroupGridHeader: UICollectionReusableView {

    static let elementKind = "header"
    static let reuseIdentifier = String(describing: GroupGridHeader.self)

    var openGroupFeed: (() -> Void)?
    var composeGroupPost: (() -> Void)?
    var menuActionsForGroup: ((GroupID) -> [UIMenuElement])?

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

    private var group: Group?
    private var groupNameChangedCancellable: AnyCancellable?

    override init(frame: CGRect) {
        super.init(frame: frame)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(headerTapped)))
        addInteraction(UIContextMenuInteraction(delegate: self))

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
        postButton.setImage(UIImage(systemName: "plus")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)),
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

        group = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: MainAppContext.shared.chatData.viewContext)
        groupNameChangedCancellable = group?.publisher(for: \.name).sink { [weak self] in
            self?.groupNameLabel.text = $0
        }
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

extension GroupGridHeader: UIContextMenuInteractionDelegate {

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        let groupName = groupNameLabel.text ?? ""
        let items = group.flatMap { menuActionsForGroup?($0.id) ?? [] } ?? []
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            return UIMenu(title: groupName, image: nil, identifier: nil, options: [], children: items)
        }
    }
}
