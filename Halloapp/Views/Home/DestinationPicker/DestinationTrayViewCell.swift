//
//  DestinationTrayViewCell.swift
//  HalloApp
//
//  Created by Nandini Shetty on 7/25/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import Combine
import UIKit

class DestinationTrayViewCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: DestinationTrayViewCell.self)
    }

    public var removeAction: (() -> ())?
    private var cancellable: AnyCancellable?

    private lazy var homeImageView: UIImageView = {
        let homeImageView = UIImageView(image: Self.homeIcon)
        homeImageView.translatesAutoresizingMaskIntoConstraints = false
        homeImageView.tintColor = .avatarHomeIcon
        homeImageView.contentMode = .scaleAspectFit
        return homeImageView
    }()

    private lazy var homeView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .avatarHomeBg
        container.layer.cornerRadius = 6
        container.clipsToBounds = true
        container.isHidden = true

        container.addSubview(homeImageView)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 34),
            container.heightAnchor.constraint(equalTo: container.widthAnchor),
            homeImageView.widthAnchor.constraint(equalToConstant: 24),
            homeImageView.heightAnchor.constraint(equalTo: homeImageView.widthAnchor),
            homeImageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            homeImageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }()

    private lazy var avatarView: AvatarView = {
        let view = AvatarView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        view.widthAnchor.constraint(equalToConstant: 32).isActive = true
        view.heightAnchor.constraint(equalTo: view.widthAnchor).isActive = true

        return view
    }()

    private lazy var title: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    private lazy var removeButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(Self.removeIcon, for: .normal)
        button.tintColor = .systemGray
        button.backgroundColor = .primaryBg
        button.clipsToBounds = true
        button.layer.cornerRadius = 10
        button.addTarget(self, action: #selector(removeButtonPressed), for: [.touchUpInside, .touchUpOutside])

        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(homeView)
        contentView.addSubview(avatarView)
        contentView.addSubview(title)
        contentView.addSubview(removeButton)

        homeView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor).isActive = true
        homeView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12).isActive = true
        avatarView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor).isActive = true
        avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12).isActive = true
        title.centerXAnchor.constraint(equalTo: contentView.centerXAnchor).isActive = true
        title.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 8).isActive = true
        title.widthAnchor.constraint(equalToConstant: 60).isActive = true
        removeButton.topAnchor.constraint(equalTo: avatarView.topAnchor, constant: -9).isActive = true
        removeButton.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 9).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func removeButtonPressed() {
        if let removeAction = removeAction {
            removeAction()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancellable?.cancel()
        avatarView.isHidden = true
        homeView.isHidden = true
    }

    public func configureHome(privacyType: PrivacyListType) {
        switch privacyType {
        case .whitelist:
            title.text = PrivacyList.name(forPrivacyListType: .whitelist)
            homeImageView.image = Self.favoritesIcon
            homeView.backgroundColor = .favoritesBg
        default:
            title.text = PrivacyList.name(forPrivacyListType: .all)
            homeImageView.image = Self.homeIcon
            homeView.backgroundColor = .avatarHomeBg
        }
        homeView.isHidden = false
        avatarView.isHidden = true
    }

    public func configureGroup(with groupID: GroupID, name: String?) {
        title.text = name
        avatarView.isHidden = false
        avatarView.configure(groupId: groupID, squareSize: 32, using: MainAppContext.shared.avatarStore)
    }

    public func configureUser(with userID: UserID, name: String?) {
        title.text = name
        avatarView.isHidden = false
        avatarView.configure(with: userID, using: MainAppContext.shared.avatarStore)
    }

    static var homeIcon: UIImage {
        UIImage(named: "PrivacySettingMyContacts")!.withRenderingMode(.alwaysTemplate)
    }

    static var favoritesIcon: UIImage {
       UIImage(named: "PrivacySettingFavoritesWithBackground")!.withRenderingMode(.alwaysOriginal)
    }

    private static var removeIcon: UIImage {
        UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18))!.withRenderingMode(.alwaysTemplate)
    }
}
