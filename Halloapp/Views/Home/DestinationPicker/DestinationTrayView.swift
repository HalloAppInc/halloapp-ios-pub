//
//  DestinationTrayView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 7/15/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//
import Combine
import Core
import CoreCommon
import CoreData
import UIKit

class DestinationTrayView: UICollectionView {
    private var onRemove: (Int) -> Void

    private lazy var destinationDataSource: UICollectionViewDiffableDataSource<Int, ShareDestination> = {
        UICollectionViewDiffableDataSource<Int, ShareDestination>(collectionView: self) { [weak self] collectionView, indexPath, destination in
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DestinationTrayViewCell.reuseIdentifier, for: indexPath) as? DestinationTrayViewCell else {
                return nil
            }

            switch destination {
            case .feed(let privacyType):
                cell.configureHome(privacyType: privacyType)
            case .group(let groupID, let name):
                cell.configureGroup(with: groupID, name: name)
            case .contact(let userID, let name, _):
                cell.configureUser(with: userID, name: name)
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

        register(DestinationTrayViewCell.self, forCellWithReuseIdentifier: DestinationTrayViewCell.reuseIdentifier)
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
