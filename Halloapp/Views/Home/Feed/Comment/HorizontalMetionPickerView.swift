//
//  MentionPickerView.swift
//  HalloApp
//
//  Created by Garrett on 7/21/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CoreCommon
import Core
import UIKit

private enum MentionPickerViewSection: CaseIterable {
    case contacts
}

fileprivate struct MentionPickerConstants {
    static let cellReuse = "MentionPickerItemReuse"
    static let cellLayoutMargins = NSDirectionalEdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8)
    static let avatarDiameter: CGFloat = 30
}

struct HorizontalMentionPickerConfig {
    var contentInsets: NSDirectionalEdgeInsets

    var rowHeight: CGFloat {
        let contentHeight = max(UIFont.preferredFont(forTextStyle: .footnote).lineHeight, MentionPickerConstants.avatarDiameter)
        return contentHeight + MentionPickerConstants.cellLayoutMargins.top + MentionPickerConstants.cellLayoutMargins.bottom + contentInsets.top + contentInsets.bottom
    }

    static var `default`: HorizontalMentionPickerConfig {
        HorizontalMentionPickerConfig(
            contentInsets: NSDirectionalEdgeInsets(top: 9, leading: 10, bottom: 0, trailing: 10)
        )
    }

    static var composer: HorizontalMentionPickerConfig {
        HorizontalMentionPickerConfig(
            contentInsets: NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12)
        )
    }
}

final class HorizontalMentionPickerView: UIView {
    init(config: HorizontalMentionPickerConfig, avatarStore: AvatarStore) {
        self.config = config
        self.avatarStore = avatarStore

        super.init(frame: .zero)

        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric,
               height: items.isEmpty ? 0 : config.rowHeight)
    }
    
    private var items: [MentionableUser] = []
    var didSelectItem: ((MentionableUser) -> Void)? = nil
    
    // MARK: Private

    private let config: HorizontalMentionPickerConfig
    private let avatarStore: AvatarStore
    private lazy var collectionView: UICollectionView = UICollectionView(frame: .zero, collectionViewLayout: createLayout())

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.setNeedsDisplay()
    }
    
    private func createLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .estimated(44), heightDimension: .fractionalHeight(1))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        
        let groupSize = NSCollectionLayoutSize(widthDimension: .estimated(44), heightDimension: .fractionalHeight(1))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
        
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = 8
        section.contentInsets = config.contentInsets
        
        let layout = UICollectionViewCompositionalLayout(section: section)
        layout.configuration.scrollDirection = .horizontal
        
        return layout
    }
    
    private lazy var dataSource = makeDataSource()
    
    func updateItems(_ mentionItems: [MentionableUser], animated: Bool = true) {
        var snapshot = NSDiffableDataSourceSnapshot<MentionPickerViewSection, MentionableUser>()

        snapshot.appendSections(MentionPickerViewSection.allCases)
        snapshot.appendItems(mentionItems, toSection: .contacts)
        
        dataSource.apply(snapshot, animatingDifferences: animated)
        items = mentionItems
        invalidateIntrinsicContentSize()
    }
    
    private func setupView() {
        collectionView.register(HorizontalMentionPickerItemCell.self, forCellWithReuseIdentifier: HorizontalMentionPickerItemCell.reuseIdentifier)
        collectionView.dataSource = dataSource
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = nil
        
        addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.constrain(to: self)
    }
    
    private func makeDataSource() -> UICollectionViewDiffableDataSource<MentionPickerViewSection, MentionableUser> {
        return UICollectionViewDiffableDataSource(
            collectionView: collectionView, cellProvider: { [weak self] collectionView, indexPath, item in
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: HorizontalMentionPickerItemCell.reuseIdentifier, for: indexPath)
                if let itemCell = cell as? HorizontalMentionPickerItemCell, let avatarStore = self?.avatarStore {
                    itemCell.configure(item: item, avatarStore: avatarStore)
                }
                
                return cell
        })
    }
}

// MARK: - collection view delegate methods

extension HorizontalMentionPickerView: UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let mentionable = dataSource.itemIdentifier(for: indexPath) else {
            return
        }
        
        didSelectItem?(mentionable)
    }
}

// MARK: - mention cell

final class HorizontalMentionPickerItemCell: UICollectionViewCell {
    static let reuseIdentifier = "h.mention.picker.cell"

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
        nameLabel.text = nil
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()

        let path = UIBezierPath(rect: self.bounds)
        layer.shadowPath = path.cgPath
    }
    
    func configure(item: MentionableUser, avatarStore: AvatarStore) {
        avatarView.configure(with: item.userID, using: avatarStore)
        nameLabel.text = item.fullName
    }
    
    // MARK: Private
    
    private let nameLabel = UILabel()
    private let avatarView = AvatarView()

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        nameLabel.font = .preferredFont(forTextStyle: .footnote)
    }
    
    private func setupView() {
        backgroundColor = .feedPostBackground
        contentView.directionalLayoutMargins = MentionPickerConstants.cellLayoutMargins

        nameLabel.font = .preferredFont(forTextStyle: .footnote)
        nameLabel.textColor = .label

        let stackView = UIStackView(arrangedSubviews: [avatarView, nameLabel])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 5

        contentView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.constrainMargins(to: contentView)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarView.heightAnchor.constraint(equalToConstant: MentionPickerConstants.avatarDiameter),
            avatarView.widthAnchor.constraint(equalToConstant: MentionPickerConstants.avatarDiameter)
        ])
        
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.black.withAlphaComponent(0.1).cgColor
        layer.cornerRadius = 14
        layer.shadowColor = UIColor.black.withAlphaComponent(0.08).cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 1.5
    }
}
