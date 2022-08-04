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
    func destinationRow(_ destinationRowView: ComposerDestinationRowView, selected destination: PostComposerDestination)
    func destinationRow(_ destinationRowView: ComposerDestinationRowView, deselected destination: PostComposerDestination)
}

class ComposerDestinationRowView: UICollectionView {

    weak var destinationDelegate: ComposerDestinationRowDelegate?

    public var destinations: [PostComposerDestination] {
        (indexPathsForSelectedItems ?? [])
            .compactMap { destinationDataSource.itemIdentifier(for: $0) }
            .map { $0.postComposerDestination }
    }

    private lazy var openInvitesGestureRecognizer: UITapGestureRecognizer = {
        UITapGestureRecognizer(target: self, action: #selector(openInvitesAction))
    }()

    @objc func openInvitesAction() {
        destinationDelegate?.destinationRowOpenInvites(self)
    }

    private lazy var destinationDataSource: UICollectionViewDiffableDataSource<Int, DestinationItem> = {
        let source = UICollectionViewDiffableDataSource<Int, DestinationItem>(collectionView: self) { [weak self] collectionView, indexPath, item in
            guard let self = self else { return nil }

            switch item {
            case .userFeed(let count):
                guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ContactsViewCell.reuseIdentifier, for: indexPath) as? ContactsViewCell else {
                    return nil
                }

                cell.configure(count: count)

                return cell
            case .group(let groupId, let title):
                guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ItemViewCell.reuseIdentifier, for: indexPath) as? ItemViewCell else {
                    return nil
                }

                cell.configure(groupId: groupId, title: title)

                return cell
            case .contact(let userId, let title):
                guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ItemViewCell.reuseIdentifier, for: indexPath) as? ItemViewCell else {
                    return nil
                }

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

    init(groups: [Group], contacts: [ABContact]) {
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

        destinationDataSource.apply(makeSnapshot(groups: groups, contacts: contacts), animatingDifferences: false)

        if contacts.count == 0 {
            selectItem(at: IndexPath(row: 0, section: 0), animated: false, scrollPosition: .top)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeSnapshot(groups: [Group], contacts: [ABContact]) -> NSDiffableDataSourceSnapshot<Int, DestinationItem> {
        var items: [DestinationItem] = [.userFeed(contacts.count)]

        for group in groups {
            items.append(.group(group.id, group.name))
        }

        for contact in contacts {
            guard let userId = contact.userId, let name = contact.fullName else { continue }
            items.append(.contact(userId, name))
        }

        items.sort {
            let title0: String
            let title1: String

            switch $0 {
            case .userFeed(_):
                return true
            case .group(_, let title):
                title0 = title
            case .contact(_, let title):
                title0 = title
            }

            switch $1 {
            case .userFeed(_):
                return false
            case .group(_, let title):
                title1 = title
            case .contact(_, let title):
                title1 = title
            }

            return title0 < title1
        }

        var snapshot = NSDiffableDataSourceSnapshot<Int, DestinationItem>()
        snapshot.appendSections([0])
        snapshot.appendItems(items)

        return snapshot
    }
}

extension ComposerDestinationRowView: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = destinationDataSource.itemIdentifier(for: indexPath) else  { return }
        destinationDelegate?.destinationRow(self, selected: item.postComposerDestination)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard let item = destinationDataSource.itemIdentifier(for: indexPath) else  { return }
        destinationDelegate?.destinationRow(self, deselected: item.postComposerDestination)
    }

    func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
        guard let item = destinationDataSource.itemIdentifier(for: indexPath) else  { return true }

        if case .userFeed(let count) = item, count == 0 {
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

    private let defaultImage = UIImage(named: "PrivacySettingMyContacts")?.withTintColor(.black.withAlphaComponent(0.6), renderingMode: .alwaysOriginal)
    private let selectedImage = UIImage(named: "PrivacySettingMyContacts")?.withTintColor(.white, renderingMode: .alwaysOriginal)

    override var isSelected: Bool {
        didSet {
            if isSelected {
                titleView.font = Constants.selectedFont
                titleView.textColor = .primaryBlue
                selectedView.isHidden = false
                imageView.image = selectedImage
                imageBackgroundView.backgroundColor = .primaryBlue
                imageBackgroundView.layer.borderWidth = 0
            } else {
                titleView.font = Constants.defaultFont
                titleView.textColor = .black.withAlphaComponent(0.6)
                selectedView.isHidden = true
                imageView.image = defaultImage
                imageBackgroundView.backgroundColor = .clear
                imageBackgroundView.layer.borderWidth = 2
                imageBackgroundView.layer.borderColor = UIColor.black.withAlphaComponent(0.6).cgColor
            }
        }
    }

    private lazy var imageBackgroundView: UIView = {
        let backgroundView = UIView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.layer.cornerRadius = 10

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
        title.textColor = .black.withAlphaComponent(0.6)
        title.textAlignment = .center
        title.numberOfLines = 2

        return title
    }()

    private lazy var selectedView: UIImageView = {
        let image = UIImage(systemName: "checkmark.circle.fill")?.withTintColor(.primaryBlue, renderingMode: .alwaysOriginal)
        let selectedView = UIImageView(image: image)
        selectedView.translatesAutoresizingMaskIntoConstraints = false
        selectedView.layer.borderWidth = 2
        selectedView.layer.borderColor = UIColor.feedBackground.cgColor
        selectedView.layer.cornerRadius = 11
        selectedView.isHidden = true

        NSLayoutConstraint.activate([
            selectedView.widthAnchor.constraint(equalToConstant: 22),
            selectedView.heightAnchor.constraint(equalToConstant: 22),
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
        titleView.text = Localizations.contactsShare + " (\(count))"
    }
}

fileprivate class ItemViewCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: ItemViewCell.self)
    }

    private var cornerRadius: CGFloat = 0

    private lazy var avatarView: AvatarView = {
        let avatarView = AvatarView()
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.isUserInteractionEnabled = false

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
        title.textColor = .black.withAlphaComponent(0.6)
        title.textAlignment = .center
        title.numberOfLines = 2

        return title
    }()

    private lazy var selectedView: UIImageView = {
        let image = UIImage(systemName: "checkmark.circle.fill")?.withTintColor(.primaryBlue, renderingMode: .alwaysOriginal)
        let selectedView = UIImageView(image: image)
        selectedView.translatesAutoresizingMaskIntoConstraints = false
        selectedView.layer.borderWidth = 2
        selectedView.layer.borderColor = UIColor.feedBackground.cgColor
        selectedView.layer.cornerRadius = 11
        selectedView.isHidden = true

        NSLayoutConstraint.activate([
            selectedView.widthAnchor.constraint(equalToConstant: 22),
            selectedView.heightAnchor.constraint(equalToConstant: 22),
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
                avatarView.layer.borderColor =  UIColor.primaryBlue.cgColor
                avatarView.layer.borderWidth = 2
                avatarView.layer.cornerRadius = cornerRadius
                titleView.font = Constants.selectedFont
                titleView.textColor = .primaryBlue
                selectedView.isHidden = false
            } else {
                avatarView.layer.borderWidth = 0
                titleView.font = Constants.defaultFont
                titleView.textColor = .black.withAlphaComponent(0.6)
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
        cornerRadius = 11
    }

    public func configure(userId: UserID, title: String) {
        avatarView.configure(with: userId, using: MainAppContext.shared.avatarStore)
        titleView.text = title
        cornerRadius = 22
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
        backgroundView.layer.borderColor = UIColor.black.withAlphaComponent(0.6).cgColor
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
        title.textColor = .black.withAlphaComponent(0.6)
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

fileprivate enum DestinationItem: Hashable, Equatable {
    case userFeed(Int)
    case group(GroupID, String)
    case contact(UserID, String)

    var postComposerDestination: PostComposerDestination {
        switch self {
        case .userFeed(_):
            return .userFeed
        case .group(let groupId, _):
            return .groupFeed(groupId)
        case .contact(let userId, _):
            return .chat(userId)
        }
    }
}

private extension Localizations {
    static var contactsShare: String {
        NSLocalizedString("composer.destination.contactsShare", value: "My Contacts", comment: "Share to all contacts")
    }
}
