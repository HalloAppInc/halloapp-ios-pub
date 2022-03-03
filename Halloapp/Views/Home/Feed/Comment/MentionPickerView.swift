//
//  MentionPickerView.swift
//  HalloApp
//
//  Created by Garrett on 7/21/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

private let MentionPickerItemReuse = "MentionPickerItemReuse"
private let MentionPickerItemHeight: CGFloat = 40

private enum MentionPickerViewSection: CaseIterable {
    case contacts
}

final class MentionPickerView: UIView {

    init(avatarStore: AvatarStore) {
        self.avatarStore = avatarStore
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        if itemWidth != bounds.width {
            itemWidth = bounds.width
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(
            width: UIView.noIntrinsicMetric,
            height: MentionPickerItemHeight * CGFloat(dataSource.snapshot().numberOfItems))
    }
    
    var items = [MentionableUser]() {
        didSet {
            updateItems(items, animated: false)
        }
    }
    
    var didSelectItem: ((MentionableUser) -> Void)? = nil
    
    var cornerRadius: CGFloat = 0 {
        didSet { self.layer.cornerRadius = cornerRadius }
    }

    var borderWidth: CGFloat = 0 {
        didSet {
            self.layer.borderWidth = borderWidth
        }
    }

    var borderColor = UIColor.black {
        didSet {
            self.layer.borderColor = borderColor.cgColor
        }
    }
    
    // MARK: Private

    private let avatarStore: AvatarStore

    private lazy var collectionView: UICollectionView = {
        return UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    }()

    private var itemWidth: CGFloat = 0 {
        didSet {
            let layout = UICollectionViewFlowLayout()
            layout.itemSize = CGSize(width: bounds.width, height: MentionPickerItemHeight)
            layout.minimumLineSpacing = 1
            collectionView.setCollectionViewLayout(layout, animated: true)
        }
    }
    
    private lazy var dataSource = makeDataSource()
    
    private func updateItems(_ mentionItems: [MentionableUser], animated: Bool = true) {
        var snapshot = NSDiffableDataSourceSnapshot<MentionPickerViewSection, MentionableUser>()

        snapshot.appendSections(MentionPickerViewSection.allCases)
        snapshot.appendItems(mentionItems, toSection: .contacts)

        dataSource.apply(snapshot, animatingDifferences: animated)

        invalidateIntrinsicContentSize()
    }
    
    private func setupView() {
        collectionView.register(MentionPickerItemCell.self, forCellWithReuseIdentifier: MentionPickerItemReuse)
        collectionView.dataSource = dataSource
        collectionView.delegate = self
        collectionView.backgroundColor = .systemGray

        addSubview(collectionView)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.constrain(to: self)
    }
    
    private func makeDataSource() -> UICollectionViewDiffableDataSource<MentionPickerViewSection, MentionableUser> {
        return UICollectionViewDiffableDataSource(
            collectionView: collectionView, cellProvider: { [weak self] collectionView, indexPath, item in
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MentionPickerItemReuse, for: indexPath)
                if let itemCell = cell as? MentionPickerItemCell, let avatarStore = self?.avatarStore {
                    itemCell.configure(item: item, avatarStore: avatarStore)
                }
                return cell
        })
    }
}

extension MentionPickerView: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.row < items.count else { return }
        didSelectItem?(items[indexPath.row])
    }
}

final class MentionPickerItemCell: UICollectionViewCell {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    override func prepareForReuse() {
        avatarView.prepareForReuse()
        nameLabel.text = nil
    }
    
    func configure(item: MentionableUser, avatarStore: AvatarStore) {
        avatarView.configure(with: item.userID, using: avatarStore)
        nameLabel.text = item.fullName
    }
    
    // MARK: Private
    
    private let nameLabel = UILabel()
    private let avatarView = AvatarView()
    
    private func setupView() {
        backgroundColor = UIColor.systemBackground
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)

        nameLabel.font = .preferredFont(forTextStyle: .subheadline)
        nameLabel.textColor = .label
        
        let stackView = UIStackView(arrangedSubviews: [avatarView, nameLabel])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 5
        
        addSubview(stackView)
        
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.constrainMargins(to: self)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.heightAnchor.constraint(equalToConstant: 25).isActive = true
        avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor).isActive = true
    }
}
