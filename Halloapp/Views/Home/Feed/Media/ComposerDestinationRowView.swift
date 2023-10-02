//
//  ComposerDestinationRowView.swift
//  HalloApp
//
//  Created by Stefan Fidanov on 27.07.22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import Foundation
import UIKit

fileprivate struct Constants {
    static let defaultFont = UIFont.systemFont(ofSize: 10, weight: .medium)
    static let selectedFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
}

protocol ComposerDestinationRowDelegate: AnyObject {
    func destinationRowOpenContacts(_ destinationRowView: ComposerDestinationRowView)
    func destinationRowOpenInvites(_ destinationRowView: ComposerDestinationRowView)
    func destinationRow(_ destinationRowView: ComposerDestinationRowView, selected destination: ShareDestination)
    func destinationRow(_ destinationRowView: ComposerDestinationRowView, deselected destination: ShareDestination)
}

class ComposerDestinationRowView: UICollectionView {

    weak var destinationDelegate: ComposerDestinationRowDelegate?

    public var destinations: [ShareDestination] {
        (indexPathsForSelectedItems ?? []).compactMap { destinationDataSource.itemIdentifier(for: $0) }
    }

    private let contactsCount: Int

    private lazy var openInvitesGestureRecognizer: UITapGestureRecognizer = {
        UITapGestureRecognizer(target: self, action: #selector(openInvitesAction))
    }()

    @objc func openInvitesAction() {
        destinationDelegate?.destinationRowOpenInvites(self)
    }

    private lazy var destinationDataSource: UICollectionViewDiffableDataSource<Int, ShareDestination> = {
        let source = UICollectionViewDiffableDataSource<Int, ShareDestination>(collectionView: self) { [weak self] collectionView, indexPath, item in
            guard let self = self else { return nil }

            switch item {
            case .feed:
                guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ContactsViewCell.reuseIdentifier, for: indexPath) as? ContactsViewCell else {
                    return nil
                }

                cell.configure(count: self.contactsCount)

                return cell
            case .group(let groupId, _, let title):
                guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ItemViewCell.reuseIdentifier, for: indexPath) as? ItemViewCell else {
                    return nil
                }

                cell.configure(groupId: groupId, title: title)

                return cell
            case .user(let userId, let title, _):
                guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ItemViewCell.reuseIdentifier, for: indexPath) as? ItemViewCell else {
                    return nil
                }
                guard let title = title else { return nil }

                cell.configure(userId: userId, title: title)

                return cell
            }
        }

        source.supplementaryViewProvider = { [weak self] (collectionView, kind, indexPath) in
            guard let self = self else { return nil }

            if kind == UICollectionView.elementKindSectionFooter {
                guard let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: InvitesView.reuseIdentifier, for: indexPath) as? InvitesView else { return nil }

                if  view.gestureRecognizers?.contains(self.openInvitesGestureRecognizer) != true {
                    view.addGestureRecognizer(self.openInvitesGestureRecognizer)
                }

                return view
            }

            return nil
        }

        return source
    } ()

    init(destination: ShareDestination, groups: [Group], friends: [UserProfile]) {
        contactsCount = friends.count

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.sectionInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        layout.itemSize = CGSize(width: 62, height: 80)
        layout.footerReferenceSize = CGSize(width: 62, height: 80)
        layout.minimumInteritemSpacing = 8

        super.init(frame: .zero, collectionViewLayout: layout)
        translatesAutoresizingMaskIntoConstraints = false
        allowsMultipleSelection = true
        showsHorizontalScrollIndicator = false

        register(ContactsViewCell.self, forCellWithReuseIdentifier: ContactsViewCell.reuseIdentifier)
        register(ItemViewCell.self, forCellWithReuseIdentifier: ItemViewCell.reuseIdentifier)
        register(InvitesView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: InvitesView.reuseIdentifier)

        backgroundColor = .clear
        alwaysBounceHorizontal = true
        delegate = self

        destinationDataSource.apply(makeSnapshot(groups: groups, friends: friends), animatingDifferences: false)

        if case .feed = destination {
            // no selection
        } else if let indexPath = destinationDataSource.indexPath(for: destination) {
            selectItem(at: indexPath, animated: false, scrollPosition: .top)
        } else {
            selectItem(at: IndexPath(row: 0, section: 0), animated: false, scrollPosition: .top)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeSnapshot(groups: [Group], friends: [UserProfile]) -> NSDiffableDataSourceSnapshot<Int, ShareDestination> {
        let groupDesinations = groups
            .sorted { $0.name < $1.name }
            .map { ShareDestination.destination(from: $0) }

        var items: [ShareDestination] = [.feed(.all)]
        items.append(contentsOf: groupDesinations)

        var snapshot = NSDiffableDataSourceSnapshot<Int, ShareDestination>()
        snapshot.appendSections([0])
        snapshot.appendItems(items)

        return snapshot
    }
}

extension ComposerDestinationRowView: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = destinationDataSource.itemIdentifier(for: indexPath) else  { return }
        destinationDelegate?.destinationRow(self, selected: item)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard let item = destinationDataSource.itemIdentifier(for: indexPath) else  { return }
        destinationDelegate?.destinationRow(self, deselected: item)
    }

    func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
        guard let item = destinationDataSource.itemIdentifier(for: indexPath) else  { return true }

        if case .feed = item, contactsCount == 0 {
            destinationDelegate?.destinationRowOpenContacts(self)
            return false
        }

        return true
    }
}

fileprivate class ContactsViewCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: ContactsViewCell.self)
    }

    private let defaultImage = UIImage(named: "PrivacySettingMyContacts")?.withTintColor(.primaryBlackWhite.withAlphaComponent(0.6), renderingMode: .alwaysOriginal)
    private let selectedImage = UIImage(named: "PrivacySettingMyContacts")?.withTintColor(.white, renderingMode: .alwaysOriginal)

    override var isSelected: Bool {
        didSet {
            if isSelected {
                titleView.font = Constants.selectedFont
                titleView.textColor = .primaryBlue
                selectedView.isHidden = false
                imageView.image = selectedImage
                imageBackgroundView.fillColor = .primaryBlue
                imageBackgroundView.strokeColor = .clear
            } else {
                titleView.font = Constants.defaultFont
                titleView.textColor = .primaryBlackWhite.withAlphaComponent(0.6)
                selectedView.isHidden = true
                imageView.image = defaultImage
                imageBackgroundView.fillColor = .clear
                imageBackgroundView.strokeColor = .primaryBlackWhite.withAlphaComponent(0.6)
            }
        }
    }

    private lazy var imageBackgroundView: RoundedRectView = {
        let backgroundView = RoundedRectView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.fillColor = .clear
        backgroundView.strokeColor = .primaryBlackWhite.withAlphaComponent(0.6)
        backgroundView.lineWidth = 2
        backgroundView.cornerRadius = 10

        NSLayoutConstraint.activate([
            backgroundView.widthAnchor.constraint(equalToConstant: 44),
            backgroundView.heightAnchor.constraint(equalToConstant: 44),
        ])

        return backgroundView
    }()


    private lazy var imageView: UIImageView = {
        let imageView = UIImageView(image: defaultImage)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 24),
            imageView.heightAnchor.constraint(equalToConstant: 24),
        ])

        return imageView
    }()

    private lazy var titleView: UILabel = {
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = Constants.defaultFont
        title.textColor = .primaryBlackWhite.withAlphaComponent(0.6)
        title.textAlignment = .center
        title.numberOfLines = 2

        return title
    }()

    private lazy var selectedView: UIImageView = {
        let image = UIImage(systemName: "checkmark.circle.fill")?.withTintColor(.primaryBlue, renderingMode: .alwaysOriginal)
        let selectedView = UIImageView(image: image)
        selectedView.translatesAutoresizingMaskIntoConstraints = false
        selectedView.layer.cornerRadius = 11
        selectedView.isHidden = true

        let borderView = RoundedRectView()
        borderView.translatesAutoresizingMaskIntoConstraints = false
        borderView.fillColor = .clear
        borderView.strokeColor = .feedBackground
        borderView.lineWidth = 2
        borderView.cornerRadius = 11

        selectedView.addSubview(borderView)

        NSLayoutConstraint.activate([
            selectedView.widthAnchor.constraint(equalToConstant: 22),
            selectedView.heightAnchor.constraint(equalToConstant: 22),
            borderView.topAnchor.constraint(equalTo: selectedView.topAnchor, constant: 1),
            borderView.bottomAnchor.constraint(equalTo: selectedView.bottomAnchor, constant: -1),
            borderView.leadingAnchor.constraint(equalTo: selectedView.leadingAnchor, constant: 1),
            borderView.trailingAnchor.constraint(equalTo: selectedView.trailingAnchor, constant: -1),
        ])

        return selectedView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(imageBackgroundView)
        contentView.addSubview(imageView)
        contentView.addSubview(titleView)
        contentView.addSubview(selectedView)

        NSLayoutConstraint.activate([
            imageBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            imageBackgroundView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.centerXAnchor.constraint(equalTo: imageBackgroundView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: imageBackgroundView.centerYAnchor),
            titleView.topAnchor.constraint(equalTo: imageBackgroundView.bottomAnchor, constant: 5),
            titleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            selectedView.bottomAnchor.constraint(equalTo: imageBackgroundView.bottomAnchor, constant: 10),
            selectedView.trailingAnchor.constraint(equalTo: imageBackgroundView.trailingAnchor, constant: 10),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(count: Int) {
        titleView.text = Localizations.friendsShare + " (\(count))"
    }
}

fileprivate class ItemViewCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: ItemViewCell.self)
    }

    private lazy var avatarView: AvatarView = {
        let avatarView = AvatarView()
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.isUserInteractionEnabled = false
        avatarView.borderWidth = 2

        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 44),
            avatarView.heightAnchor.constraint(equalToConstant: 44),
        ])

        return avatarView
    }()

    private lazy var titleView: UILabel = {
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = Constants.defaultFont
        title.textColor = .primaryBlackWhite.withAlphaComponent(0.6)
        title.textAlignment = .center
        title.numberOfLines = 2

        return title
    }()

    private lazy var selectedView: UIImageView = {
        let image = UIImage(systemName: "checkmark.circle.fill")?.withTintColor(.primaryBlue, renderingMode: .alwaysOriginal)
        let selectedView = UIImageView(image: image)
        selectedView.translatesAutoresizingMaskIntoConstraints = false
        selectedView.layer.cornerRadius = 11
        selectedView.isHidden = true

        let borderView = RoundedRectView()
        borderView.translatesAutoresizingMaskIntoConstraints = false
        borderView.fillColor = .clear
        borderView.strokeColor = .feedBackground
        borderView.lineWidth = 2
        borderView.cornerRadius = 11

        selectedView.addSubview(borderView)

        NSLayoutConstraint.activate([
            selectedView.widthAnchor.constraint(equalToConstant: 22),
            selectedView.heightAnchor.constraint(equalToConstant: 22),
            borderView.topAnchor.constraint(equalTo: selectedView.topAnchor, constant: 1),
            borderView.bottomAnchor.constraint(equalTo: selectedView.bottomAnchor, constant: -1),
            borderView.leadingAnchor.constraint(equalTo: selectedView.leadingAnchor, constant: 1),
            borderView.trailingAnchor.constraint(equalTo: selectedView.trailingAnchor, constant: -1),
        ])

        return selectedView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(avatarView)
        contentView.addSubview(titleView)
        contentView.addSubview(selectedView)

        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            avatarView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleView.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 5),
            titleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            selectedView.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 10),
            selectedView.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
        ])
    }

    override var isSelected: Bool {
        didSet {
            if isSelected {
                avatarView.borderColor =  UIColor.primaryBlue
                titleView.font = Constants.selectedFont
                titleView.textColor = .primaryBlue
                selectedView.isHidden = false
            } else {
                avatarView.borderColor = nil
                titleView.font = Constants.defaultFont
                titleView.textColor = .primaryBlackWhite.withAlphaComponent(0.6)
                selectedView.isHidden = true
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(groupId: GroupID, title: String) {
        avatarView.configure(groupId: groupId, squareSize: 44, using: MainAppContext.shared.avatarStore)
        titleView.text = title
    }

    public func configure(userId: UserID, title: String) {
        avatarView.configure(with: userId, using: MainAppContext.shared.avatarStore)
        titleView.text = title
    }
}

fileprivate class InvitesView: UICollectionReusableView {
    static var reuseIdentifier: String {
        return String(describing: InvitesView.self)
    }

    private lazy var imageBackgroundView: UIView = {
        let backgroundView = UIView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = .white
        backgroundView.layer.cornerRadius = 22
        backgroundView.layer.borderColor = UIColor.primaryBlackWhite.withAlphaComponent(0.6).cgColor
        backgroundView.layer.borderWidth = 1

        NSLayoutConstraint.activate([
            backgroundView.widthAnchor.constraint(equalToConstant: 44),
            backgroundView.heightAnchor.constraint(equalToConstant: 44),
        ])

        return backgroundView
    }()

    private lazy var imageView: UIImageView = {
        let image = UIImage(systemName: "person.2.fill")?.withTintColor(.black.withAlphaComponent(0.6), renderingMode: .alwaysOriginal)
        let imageView = UIImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 32),
            imageView.heightAnchor.constraint(equalToConstant: 32),
        ])

        return imageView
    }()

    private lazy var titleView: UILabel = {
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = Constants.defaultFont
        title.textColor = .primaryBlackWhite.withAlphaComponent(0.6)
        title.textAlignment = .center
        title.text = Localizations.inviteTitle
        title.numberOfLines = 2

        return title
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(imageBackgroundView)
        addSubview(imageView)
        addSubview(titleView)

        NSLayoutConstraint.activate([
            imageBackgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            imageBackgroundView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerXAnchor.constraint(equalTo: imageBackgroundView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: imageBackgroundView.centerYAnchor),
            titleView.topAnchor.constraint(equalTo: imageBackgroundView.bottomAnchor, constant: 5),
            titleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension Localizations {
    static var friendsShare: String {
        NSLocalizedString("composer.destination.friendsShare", value: "My Friends", comment: "Share to all friends")
    }
}
