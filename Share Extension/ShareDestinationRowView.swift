//
//  ShareDestinationRowView.swift
//  Share Extension
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import Foundation
import UIKit

private extension Localizations {
    static var newPost: String {
        NSLocalizedString("share.destination.new", value: "New Post", comment: "Share on the home feed selection cell")
    }

    static var home: String {
        NSLocalizedString("share.destination.home", value: "My Contacts", comment: "Share to all contacts")
    }
}

class ShareDestinationRowView: UICollectionView {
    private var onRemove: (Int) -> Void

    private lazy var destinationDataSource: UICollectionViewDiffableDataSource<Int, ShareDestination> = {
        UICollectionViewDiffableDataSource<Int, ShareDestination>(collectionView: self) { [weak self] collectionView, indexPath, destination in
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DestinationViewCell.reuseIdentifier, for: indexPath) as? DestinationViewCell else {
                return nil
            }

            switch destination {
            case .feed(let privacyType):
                cell.configureHome(privacyType: privacyType)
            case .group(let group):
                cell.configure(group)
            case .chat(let chat):
                cell.configure(chat)
            }

            cell.removeAction = { [weak self] in
                guard let self = self else { return }
                guard let indexPath = self.destinationDataSource.indexPath(for: destination) else { return }
                self.onRemove(indexPath.row)
            }

            return cell
        }
    } ()

    init(onRemove: @escaping (Int) -> Void) {
        self.onRemove = onRemove

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        layout.itemSize = CGSize(width: 64, height: 100)
        layout.minimumInteritemSpacing = 0

        super.init(frame: .zero, collectionViewLayout: layout)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .primaryBg

        register(DestinationViewCell.self, forCellWithReuseIdentifier: DestinationViewCell.reuseIdentifier)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with destinations: [ShareDestination]) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, ShareDestination>()
        snapshot.appendSections([0])
        snapshot.appendItems(destinations)

        let scrollToTheRight = destinations.count > destinationDataSource.snapshot().numberOfItems
        let animate = destinationDataSource.snapshot().numberOfItems > 0 && destinations.count > 0

        destinationDataSource.apply(snapshot, animatingDifferences: animate) {
            if scrollToTheRight {
                self.scrollToItem(at: IndexPath(row: destinations.count - 1, section: 0), at: .right, animated: true)
            }
        }
    }
}

fileprivate class DestinationViewCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: DestinationViewCell.self)
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

    private lazy var avatar: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true

        imageView.widthAnchor.constraint(equalToConstant: 34).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 34).isActive = true

        return imageView
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
        contentView.addSubview(avatar)
        contentView.addSubview(title)
        contentView.addSubview(removeButton)

        homeView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor).isActive = true
        homeView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12).isActive = true
        avatar.centerXAnchor.constraint(equalTo: contentView.centerXAnchor).isActive = true
        avatar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12).isActive = true
        title.centerXAnchor.constraint(equalTo: contentView.centerXAnchor).isActive = true
        title.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 8).isActive = true
        title.widthAnchor.constraint(equalToConstant: 60).isActive = true
        removeButton.topAnchor.constraint(equalTo: avatar.topAnchor, constant: -9).isActive = true
        removeButton.trailingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 9).isActive = true
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
        avatar.isHidden = true
        homeView.isHidden = true
    }

    public func configureHome(privacyType: PrivacyListType) {
        switch privacyType {
        case .whitelist:
            title.text = Localizations.favoritesTitle
            homeImageView.image = Self.favoritesIcon
            homeView.backgroundColor = .favoritesBg
        default:
            title.text = Localizations.home
            homeImageView.image = Self.homeIcon
            homeView.backgroundColor = .avatarHomeBg
        }
        homeView.isHidden = false
    }

    public func configure(_ group: GroupListSyncItem) {
        title.text = group.name
        avatar.isHidden = false
        avatar.layer.cornerRadius = 6

        loadAvatar(group: group.id)
    }

    public func configure(_ chat: ChatListSyncItem) {
        title.text = chat.displayName
        avatar.isHidden = false
        avatar.layer.cornerRadius = 17

        loadAvatar(user: chat.userId)
    }

    private func loadAvatar(group id: GroupID) {
        cancellable?.cancel()

        let avatarData = ShareExtensionContext.shared.avatarStore.groupAvatarData(for: id)

        if let image = avatarData.image {
            avatar.image = image
        } else {
            avatar.image = AvatarView.defaultGroupImage

            if !avatarData.isEmpty {
                avatarData.loadImage(using: ShareExtensionContext.shared.avatarStore)
            }
        }

        cancellable = avatarData.imageDidChange.sink { [weak self] image in
            guard let self = self else { return }

            if let image = image {
                self.avatar.image = image
            } else {
                self.avatar.image = AvatarView.defaultGroupImage
            }
        }
    }

    private func loadAvatar(user id: UserID) {
        cancellable?.cancel()

        let userAvatar = ShareExtensionContext.shared.avatarStore.userAvatar(forUserId: id)

        if let image = userAvatar.image {
            avatar.image = image
        } else {
            avatar.image = AvatarView.defaultGroupImage

            if !userAvatar.isEmpty {
                userAvatar.loadThumbnailImage(using: ShareExtensionContext.shared.avatarStore)
            }
        }

        cancellable = userAvatar.imageDidChange.sink { [weak self] image in
            guard let self = self else { return }

            if let image = image {
                self.avatar.image = image
            } else {
                self.avatar.image = AvatarView.defaultGroupImage
            }
        }
    }

    static var homeIcon: UIImage {
        UIImage(named: "HomeFill")!.withRenderingMode(.alwaysTemplate)
    }

    static var favoritesIcon: UIImage {
       UIImage(named: "PrivacySettingFavoritesWithBackground")!.withRenderingMode(.alwaysOriginal)
    }

    private static var removeIcon: UIImage {
        UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18))!.withRenderingMode(.alwaysTemplate)
    }
}
