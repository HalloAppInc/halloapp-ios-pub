//
//  FeedSuggestionsCarouselCell.swift
//  HalloApp
//
//  Created by Tanveer on 10/10/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon
import Core

extension FeedSuggestionsCarouselCell {

    typealias Suggestion = FriendSuggestionsManager.Suggestion

    enum Item: Hashable {
        case suggestion(Suggestion)
        case added(Suggestion)
        case search
    }
}

class FeedSuggestionsCarouselCell: UICollectionViewCell {

    static let reuseIdentifier = "feedSuggestionsCarousel"

    var onAdd: ((Suggestion) -> Void)?
    var onCancel: ((Suggestion) -> Void)?
    var onHide: ((Suggestion) -> Void)?

    private lazy var collectionView: UICollectionView = {
        let collectionView = FeedCarouselCollectionView(frame: .zero, collectionViewLayout: FeedCarouselCollectionView.layout)
        return collectionView
    }()

    private lazy var dataSource: UICollectionViewDiffableDataSource<Int, Item> = {
        UICollectionViewDiffableDataSource<Int, Item>(collectionView: collectionView) { [weak self] in
            self?.cellProvider(collectionView: $0, indexPath: $1, item: $2)
        }
    }()

    private let titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.numberOfLines = 0
        titleLabel.textColor = .label.withAlphaComponent(0.9)
        titleLabel.text = Localizations.friendSuggestions
        return titleLabel
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        preservesSuperviewLayoutMargins = true
        contentView.preservesSuperviewLayoutMargins = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        collectionView.clipsToBounds = false
        collectionView.backgroundColor = nil
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.setContentCompressionResistancePriority(UILayoutPriority(751), for: .vertical)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(collectionView)

        let bottomAnchor = collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        bottomAnchor.priority = .breakable

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomAnchor,
        ])

        collectionView.register(SuggestionCarouselCell.self,
                                forCellWithReuseIdentifier: SuggestionCarouselCell.reuseIdentifier)
        collectionView.register(SearchCarouselCell.self,
                                forCellWithReuseIdentifier: SearchCarouselCell.reuseIdentifier)
        updateCollectionViewInsets()
    }

    required init(coder: NSCoder) {
        fatalError("SuggestionsCarouselCell coder init not implemented...")
    }

    func configure(with suggestions: [Suggestion], animateChanges: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        let items = suggestions.compactMap {
            switch $0.friendshipStatus {
            case .none:
                return Item.suggestion($0)
            case .outgoingPending:
                return Item.added($0)
            default:
                return nil
            }
        }

        snapshot.appendSections([0])
        snapshot.appendItems(items, toSection: 0)

        dataSource.apply(snapshot, animatingDifferences: animateChanges)
    }

    private func cellProvider(collectionView: UICollectionView, indexPath: IndexPath, item: Item) -> UICollectionViewCell {
        let cell: UICollectionViewCell
        switch item {
        case .suggestion(let suggestion):
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: SuggestionCarouselCell.reuseIdentifier, for: indexPath)
            if let cell = cell as? SuggestionCarouselCell {
                cell.configure(with: suggestion, added: false)
                cell.delegate = self
            }
        case .added(let suggestion):
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: SuggestionCarouselCell.reuseIdentifier, for: indexPath)
            if let cell = cell as? SuggestionCarouselCell {
                cell.configure(with: suggestion, added: true)
                cell.delegate = self
            }
        case .search:
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: SearchCarouselCell.reuseIdentifier, for: indexPath)
            (cell as? SearchCarouselCell)?.delegate = self
        }

        return cell
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

// MARK: - FeedSuggestionsCarouselCell + FeedCarouselCellDelegate

extension FeedSuggestionsCarouselCell: FeedCarouselCellDelegate {
    
    func feedCarouselCellDidTapPrimaryButton(_ cell: FeedCarouselCell) {
        guard let indexPath = collectionView.indexPath(for: cell),
              let item = dataSource.itemIdentifier(for: indexPath) else {
            return
        }

        switch item {
        case .suggestion(let suggestion):
            onAdd?(suggestion)
        case .added(let suggestion):
            onCancel?(suggestion)
        default:
            break
        }
    }
    
    func feedCarouselCellDidDismiss(_ cell: FeedCarouselCell) {
        guard let indexPath = collectionView.indexPath(for: cell),
              let item = dataSource.itemIdentifier(for: indexPath) else {
            return
        }

        switch item {
        case .suggestion(let suggestion), .added(let suggestion):
            onHide?(suggestion)
        default:
            break
        }
    }
}
