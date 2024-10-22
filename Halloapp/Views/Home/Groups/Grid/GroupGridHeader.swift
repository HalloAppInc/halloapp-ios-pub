//
//  GroupGridHeader.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 5/11/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Combine
import CoreCommon
import Core
import UIKit

class GroupGridHeader: UICollectionReusableView {

    static let elementKind = "header"
    static let reuseIdentifier = String(describing: GroupGridHeader.self)

    var openGroupFeed: (() -> Void)?
    var composeGroupPost: (() -> Void)?
    var menuActions: (() -> [UIMenuElement])?

    private struct Constants {
        static let avatarSize: CGFloat = 32
    }

    private let groupAvatarAndNameStackView: UIStackView = {
        let groupAvatarAndNameStackView = UIStackView()
        groupAvatarAndNameStackView.alignment = .center
        groupAvatarAndNameStackView.axis = .horizontal
        groupAvatarAndNameStackView.isLayoutMarginsRelativeArrangement = true
        groupAvatarAndNameStackView.layoutMargins = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        groupAvatarAndNameStackView.spacing = 12
        return groupAvatarAndNameStackView
    }()

    private let groupAvatarView: AvatarView = AvatarView()

    private let groupNameLabel: UILabel = {
        let groupNameLabel = UILabel()
        groupNameLabel.adjustsFontForContentSizeCategory = true
        groupNameLabel.font = .scaledGothamFont(ofSize: 21, weight: .medium)
        groupNameLabel.textColor = .label.withAlphaComponent(0.75)
        return groupNameLabel
    }()

    private var groupNameChangedCancellable: AnyCancellable?

    override init(frame: CGRect) {
        super.init(frame: frame)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(headerTapped)))
        addInteraction(UIContextMenuInteraction(delegate: self))

        groupAvatarAndNameStackView.addArrangedSubview(groupAvatarView)
        groupAvatarAndNameStackView.addArrangedSubview(groupNameLabel)
        groupAvatarAndNameStackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(groupAvatarAndNameStackView)

        var postButtonConfiguration = UIButton.Configuration.filled()
        postButtonConfiguration.baseBackgroundColor = .systemGray5
        postButtonConfiguration.baseForegroundColor = .primaryBlue
        postButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 8)
        postButtonConfiguration.cornerStyle = .capsule
        postButtonConfiguration.imagePadding = 2
        postButtonConfiguration.imagePlacement = .trailing
        postButtonConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        postButtonConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributeContainer in
            var updatedAttributeContainer = attributeContainer
            updatedAttributeContainer.font = .quicksandFont(ofFixedSize: 16, weight: .bold)
            return updatedAttributeContainer
        }

        let postButton = UIButton(type: .system)
        postButton.configuration = postButtonConfiguration
        postButton.addTarget(self, action: #selector(composeButtonTapped), for: .touchUpInside)
        postButton.setImage(UIImage(systemName: "plus"), for: .normal)
        postButton.setTitle(Localizations.fabPostButton, for: .normal)
        postButton.setContentCompressionResistancePriority(.required, for: .horizontal)
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
            groupAvatarAndNameStackView.trailingAnchor.constraint(lessThanOrEqualTo: postButton.leadingAnchor, constant: -12),

            postButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            postButton.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(with group: Group) {
        groupAvatarView.configure(groupId: group.id, squareSize: Constants.avatarSize, using: MainAppContext.shared.avatarStore)
        groupNameChangedCancellable = group.publisher(for: \.name).sink { [weak self] in
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
        let items = menuActions?() ?? []
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            return UIMenu(title: groupName, image: nil, identifier: nil, options: [], children: items)
        }
    }

    private func targetedPreview() -> UITargetedPreview {
        let params = UIPreviewParameters()
        params.visiblePath = UIBezierPath(roundedRect: groupAvatarAndNameStackView.bounds.insetBy(dx: -12, dy: 0), cornerRadius: 6)
        return UITargetedPreview(view: groupAvatarAndNameStackView, parameters: params)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        return targetedPreview()
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        return targetedPreview()
    }
}
