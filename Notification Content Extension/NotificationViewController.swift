//
//  NotificationViewController.swift
//  Notification Content Extension
//
//  Created by Chris Leonavicius on 12/12/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import Photos
import UIKit
import UserNotifications
import UserNotificationsUI

class NotificationViewController: UIViewController {

    private enum Section {
        case main
    }

    private enum Item: Hashable {
        case photo(PHAsset)
    }

    private lazy var collectionView: UICollectionView = {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = .horizontal

        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] section, environment in
            let numberOfItems = self?.collectionViewDataSource.snapshot().numberOfItems ?? 0

            let subitems: [NSCollectionLayoutItem]
            switch numberOfItems {
            case 1:
                subitems = [
                    .init(layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0))),
                ]
            case 2:
                subitems = [
                    .init(layoutSize: .init(widthDimension: .fractionalWidth(0.55), heightDimension: .fractionalHeight(1.0))),
                    .init(layoutSize: .init(widthDimension: .fractionalWidth(0.45), heightDimension: .fractionalHeight(1.0))),
                ]
            case 3:
                subitems = [
                    NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(0.55)),
                                                       subitems: [
                                                        .init(layoutSize: .init(widthDimension: .fractionalWidth(0.4), heightDimension: .fractionalHeight(1.0))),
                                                        .init(layoutSize: .init(widthDimension: .fractionalWidth(0.6), heightDimension: .fractionalHeight(1.0))),
                                                       ]),
                    .init(layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(0.45))),
                ]
            default:
                subitems = [
                    NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(0.55)),
                                                       subitems: [
                                                        .init(layoutSize: .init(widthDimension: .fractionalWidth(0.4), heightDimension: .fractionalHeight(1.0))),
                                                        .init(layoutSize: .init(widthDimension: .fractionalWidth(0.6), heightDimension: .fractionalHeight(1.0))),
                                                       ]),
                    NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(0.45)),
                                                       subitems: [
                                                        .init(layoutSize: .init(widthDimension: .fractionalWidth(0.7), heightDimension: .fractionalHeight(1.0))),
                                                        .init(layoutSize: .init(widthDimension: .fractionalWidth(0.3), heightDimension: .fractionalHeight(1.0))),
                                                       ]),
                ]
            }
            return .init(group: .vertical(layoutSize: .init(widthDimension: .fractionalWidth(numberOfItems > 4 ? 0.95 : 1.0),
                                                            heightDimension: .fractionalWidth(1.0)), subitems: subitems))
        }, configuration: configuration)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.alwaysBounceHorizontal = false
        collectionView.showsHorizontalScrollIndicator = false
        return collectionView
    }()

    private lazy var collectionViewDataSource: UICollectionViewDiffableDataSource<Section, Item> = {

        let cellRegistration = UICollectionView.CellRegistration<PhotoSuggestionCell, PHAsset> { cell, indexPath, asset in
            cell.configure(with: asset)
        }

        return UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            switch itemIdentifier {
            case .photo(let asset):
                return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: asset)
            }
        }
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        collectionView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapNotification)))

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.widthAnchor.constraint(equalTo: collectionView.heightAnchor),
        ])
    }

    private static func assets(with localIdentifiers: [String], options: PHFetchOptions? = nil) -> [PHAsset] {
        var assets: [PHAsset] = []
        PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: options).enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    @objc private func didTapNotification() {
        extensionContext?.performNotificationDefaultAction()
    }
}

extension NotificationViewController: UNNotificationContentExtension {

    func didReceive(_ notification: UNNotification) {
        if let assetLocalIdentifiers = notification.request.content.userInfo["com.halloapp.visit.photos"] as? [String] {
            let assets = Self.assets(with: assetLocalIdentifiers)
            var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
            snapshot.appendSections([.main])
            snapshot.appendItems(assets.map { Item.photo($0) })
            collectionViewDataSource.apply(snapshot, animatingDifferences: false)
        }
    }
}
