//
//  AlbumPreviewViewController.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 7/17/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import Photos

class AlbumPreviewViewController: UIViewController {

    private enum Section {
        case main
    }

    private lazy var dataSource: UICollectionViewDiffableDataSource<Section, PHAsset> = {
        return UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoCollectionViewCell.reuseIdentifier, for: indexPath) as? PhotoCollectionViewCell {
                cell.configure(asset: itemIdentifier)
                return cell
            }
            return nil
        }
    }()

    private lazy var collectionView: UICollectionView = {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(0.33), heightDimension: .fractionalHeight(1.0)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalWidth(0.33)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)

        let layout = UICollectionViewCompositionalLayout(section: section)

        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()

    private let photoCluster: PhotoSuggestions.PhotoCluster

    init(photoCluster: PhotoSuggestions.PhotoCluster) {
        self.photoCluster = photoCluster
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView.register(PhotoCollectionViewCell.self, forCellWithReuseIdentifier: PhotoCollectionViewCell.reuseIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        var snapshot = NSDiffableDataSourceSnapshot<Section, PHAsset>()
        snapshot.appendSections([.main])
        snapshot.appendItems(photoCluster.assets.sorted { $0.creationDate ?? .distantPast < $1.creationDate ?? .distantPast })
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

extension AlbumPreviewViewController {

    class PhotoCollectionViewCell: UICollectionViewCell {

        static let reuseIdentifier = "PhotoCollectionViewCell"

        private let imageView: AssetImageView = {
            let imageView = AssetImageView()
            imageView.assetMode = .thumbnail
            imageView.clipsToBounds = true
            imageView.contentMode = .scaleAspectFill
            return imageView
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)

            imageView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(imageView)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
                imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }
        
        required init?(coder: NSCoder) {
            fatalError()
        }

        func configure(asset: PHAsset) {
            imageView.asset = asset
        }
    }
}
