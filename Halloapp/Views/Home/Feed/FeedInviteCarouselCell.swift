//
//  FeedInviteCarousel.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 2/24/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

class FeedInviteCarouselCell: UICollectionViewCell {

    var inviteContact: ((InviteContact) -> Void)?
    var hideContact: ((InviteContact) -> Void)?
    var openInviteViewController: (() -> Void)?

    var invitedContacts: Set<InviteContact> = Set()

    static let reuseIdentifier = "FeedInviteCarouselCell"

    private enum Section {
        case contacts
    }

    private enum Item: Hashable {
        case contact(InviteContact, Bool)
        case more
    }

    private lazy var dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { [weak self] in
        self?.cellProvider(collectionView: $0, indexPath: $1, item: $2)
    }

    private lazy var collectionView: UICollectionView = {
        let collectionView = FeedCarouselCollectionView(frame: .zero, collectionViewLayout: FeedCarouselCollectionView.layout)
        collectionView.backgroundColor = nil
        collectionView.showsHorizontalScrollIndicator = false

        collectionView.register(InviteCarouselCell.self,
                                forCellWithReuseIdentifier: InviteCarouselCell.reuseIdentifier)
        collectionView.register(SearchCarouselCell.self,
                                forCellWithReuseIdentifier: SearchCarouselCell.reuseIdentifier)

        return collectionView
    }()

    private let titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.numberOfLines = 0
        titleLabel.textColor = .label.withAlphaComponent(0.9)
        titleLabel.text = Localizations.feedInviteCarouselTitle
        return titleLabel
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        preservesSuperviewLayoutMargins = true
        contentView.preservesSuperviewLayoutMargins = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        collectionView.clipsToBounds = false
        collectionView.setContentCompressionResistancePriority(UILayoutPriority(751), for: .vertical)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(collectionView)

        let bottomAnchor = collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        bottomAnchor.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomAnchor,
        ])

        updateCollectionViewInsets()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func cellProvider(collectionView: UICollectionView,
                              indexPath: IndexPath,
                              item: Item) -> UICollectionViewCell? {
        
        let cell: UICollectionViewCell
        switch item {
        case .contact(let contact, let invited):
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: InviteCarouselCell.reuseIdentifier, for: indexPath)
            if let cell = cell as? InviteCarouselCell {
                cell.configure(with: contact, invited: invited)
                cell.delegate = self
            }
        case .more:
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: SearchCarouselCell.reuseIdentifier, for: indexPath)
            (cell as? SearchCarouselCell)?.delegate = self
        }

        return cell
    }

    func configure(with contacts: [InviteContact], invitedContacts: Set<InviteContact>, animated: Bool = false) {
        self.invitedContacts = invitedContacts

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.contacts])
        snapshot.appendItems(contacts.map { Item.contact($0, invitedContacts.contains($0)) }, toSection: .contacts)
        snapshot.appendItems([Item.more], toSection: .contacts)

        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        updateCollectionViewInsets()
    }

    private func updateCollectionViewInsets() {
        let layoutMargins = contentView.layoutMargins
        collectionView.contentInset = UIEdgeInsets(top: 0, left: layoutMargins.left + 8, bottom: 0, right: layoutMargins.right + 8)
    }
}

extension FeedInviteCarouselCell: FeedCarouselCellDelegate {

    func feedCarouselCellDidTapPrimaryButton(_ cell: FeedCarouselCell) {
        guard let indexPath = collectionView.indexPath(for: cell),
              let item = dataSource.itemIdentifier(for: indexPath) else {
            return
        }
        switch item {
        case .contact(let contact, _):
            inviteContact?(contact)
        case .more:
            openInviteViewController?()
        }
    }

    func feedCarouselCellDidDismiss(_ cell: FeedCarouselCell) {
        guard let indexPath = collectionView.indexPath(for: cell),
              let item = dataSource.itemIdentifier(for: indexPath) else {
            return
        }
        switch item {
        case .contact(let contact, _):
            hideContact?(contact)
        case .more:
            // no-op
            break
        }
    }
}

extension Localizations {

    static var feedInviteCarouselTitle: String {
        return NSLocalizedString("feedInviteCarousel.title",
                                 value: "HalloApp is fun with friends & family",
                                 comment: "Title for section of contacts to invite in feed")
    }

    static var feedInviteCarouselSearchPrompt: String {
        return NSLocalizedString("feedInviteCarousel.searchPrompt",
                                 value: "Search for more friends and family",
                                 comment: "Text for 'more' cell prompting users to open the invite screen")
    }
}
