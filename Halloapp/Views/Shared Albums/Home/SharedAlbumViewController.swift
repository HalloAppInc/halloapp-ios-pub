//
//  SharedAlbumViewController.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 7/13/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import Combine
import Core
import Photos
import UIKit

class SharedAlbumViewController: UIViewController {

    private enum Section {
        case suggestions
        case albums
    }

    private enum Item: Hashable {
        case suggestion(PhotoSuggestions.PhotoCluster)
        case loadIndicator
    }

    private lazy var dataSource: UICollectionViewDiffableDataSource<Section, Item> = {
        return UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            switch itemIdentifier {
            case .suggestion(let photoCluster):
                if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AlbumSuggestionCollectionViewCell.reuseIdentifier, for: indexPath) as? AlbumSuggestionCollectionViewCell {
                    cell.configure(photoCluster: photoCluster)
                    return cell
                }
            case .loadIndicator:
                return collectionView.dequeueReusableCell(withReuseIdentifier: AlbumSuggestionLoadIndicatorCollectionViewCell.reuseIdentifier, for: indexPath)
            }

            return nil
        }
    }()

    private lazy var collectionView: UICollectionView = {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(88)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 16
        section.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)

        let layout = UICollectionViewCompositionalLayout(section: section)

        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()

    private var cancellables: Set<AnyCancellable> = []

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView.backgroundColor = .lightGray
        collectionView.delegate = self
        collectionView.register(AlbumSuggestionCollectionViewCell.self,
                                forCellWithReuseIdentifier: AlbumSuggestionCollectionViewCell.reuseIdentifier)
        collectionView.register(AlbumSuggestionLoadIndicatorCollectionViewCell.self,
                                forCellWithReuseIdentifier: AlbumSuggestionLoadIndicatorCollectionViewCell.reuseIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        let enableLocationBanner = EnableLocationBanner()
        enableLocationBanner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(enableLocationBanner)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            enableLocationBanner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            enableLocationBanner.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 42),
            enableLocationBanner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
        ])

        NotificationCenter.default.publisher(for: PhotoSuggestions.suggestionsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSuggestions()
            }
            .store(in: &cancellables)

        refreshSuggestions()
    }

    func refreshSuggestions() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.suggestions])
        snapshot.appendItems([.loadIndicator])
        dataSource.apply(snapshot, animatingDifferences: false)

        Task {
            guard let suggestions = try? await MainAppContext.shared.photoSuggestions.generateSuggestions().sorted(by: { $0.end > $1.end }) else {
                return
            }
            var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
            snapshot.appendSections([.suggestions])
            snapshot.appendItems(suggestions.map { .suggestion($0) })
            dataSource.apply(snapshot, animatingDifferences: true)
        }
    }
}

extension SharedAlbumViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath), case .suggestion(let photoCluster) = item else {
            return
        }

        Task {
            let newPostState = await photoCluster.newPostState
            let newPostViewController = NewPostViewController(state: newPostState,
                                                              destination: .feed(.all),
                                                              showDestinationPicker: true) { didPost, _ in
                // Reset back to all
                MainAppContext.shared.privacySettings.activeType = .all
                self.dismiss(animated: true)
            }
            await MainActor.run() {
                newPostViewController.modalPresentationStyle = .fullScreen
                present(newPostViewController, animated: true)
            }
        }
    }
}
