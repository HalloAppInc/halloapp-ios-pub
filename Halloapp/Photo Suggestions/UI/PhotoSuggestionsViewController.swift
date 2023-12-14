//
//  PhotoSuggestionsViewController.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 11/30/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import CoreData
import Photos
import UIKit

class PhotoSuggestionsViewController: UIViewController {

    private lazy var collectionView: UICollectionView = {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(130)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(130)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 15
        section.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15)
        let layout = UICollectionViewCompositionalLayout(section: section)
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()

    private lazy var dataSource = PhotoSuggestionsDataSource()

    private lazy var collectionViewDataSource: UICollectionViewDiffableDataSource<PhotoSuggestionsDataSource.Section, PhotoSuggestionsDataSource.Item> = {
        let ctaCellRegistration = UICollectionView.CellRegistration<AlbumSuggestionCallToActionCollectionViewCell, AlbumSuggestionCallToActionCollectionViewCell.CallToActionType> { [weak self] cell, _, ctaType in
            cell.configure(type: ctaType) { [weak self] in
                self?.dataSource.didDismissFirstTimeUseExplainer()
            }
        }

        let headerCellRegistration = UICollectionView.CellRegistration<PhotoSuggestionsHeaderCollectionViewCell, Void> { cell, _, _ in

        }

        let locatedClusterCellRegistration = UICollectionView.CellRegistration<AlbumSuggestionCollectionViewCell, AssetLocatedCluster> { cell, _, assetLocatedCluster in
            cell.configure(locatedCluster: assetLocatedCluster)
        }

        return UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, itemIdentifier in
            switch itemIdentifier {
            case .callToAction(let ctaType):
                return collectionView.dequeueConfiguredReusableCell(using: ctaCellRegistration, for: indexPath, item: ctaType)
            case .header:
                return collectionView.dequeueConfiguredReusableCell(using: headerCellRegistration, for: indexPath, item: ())
            case .locatedCluster(let managedObjectID):
                guard let locatedCluster = self?.dataSource.assetLocatedCluster(objectID: managedObjectID) else {
                    return nil
                }
                return collectionView.dequeueConfiguredReusableCell(using: locatedClusterCellRegistration, for: indexPath, item: locatedCluster)
            }
        }
    }()

    private var cancellables: Set<AnyCancellable> = []

    override func viewDidLoad() {
        super.viewDidLoad()

        installAvatarBarButton()

        collectionView.backgroundColor = .feedBackground
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        installFloatingActionMenu()

        dataSource.photoSuggestionsSnapshotSubject
            .sink { [weak self] snapshot in
                self?.applySnapshot(snapshot)
            }
            .store(in: &cancellables)

        dataSource.performFetch()
        applySnapshot(dataSource.photoSuggestionsSnapshotSubject.value, animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let numberOfSuggestions = collectionViewDataSource.snapshot().itemIdentifiers
            .filter {
                switch $0 {
                case .locatedCluster:
                    return true
                default:
                    return false
                }
            }
            .count
        Analytics.openScreen(.photoSuggestions, properties: [.numPhotoSuggestions: numberOfSuggestions])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let triggerButtonFrame = floatingMenu.triggerButton.convert(floatingMenu.triggerButton.bounds, to: view)
        collectionView.contentInset.bottom = view.bounds.maxY - triggerButtonFrame.minY
    }

    private func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<PhotoSuggestionsDataSource.Section, PhotoSuggestionsDataSource.Item>, animated: Bool = true) {
        if snapshot.numberOfItems == 0 {
            let hasPhotoPermissions = PhotoPermissionsHelper.authorizationStatus(for: .readWrite) == .authorized
            collectionView.backgroundView = PhotoSuggestionsEmptyStateView(hasPhotoPermissions ? .magicPostsExplainer : .allowPhotoAccess)
        } else {
            collectionView.backgroundView = nil
        }
        collectionViewDataSource.apply(snapshot, animatingDifferences: animated)
    }

    // MARK: - Floating Post Menu

    private var composeVoiceNoteButton: FloatingMenuButton?
    private var composeCamPostButton: FloatingMenuButton?

    private(set) lazy var floatingMenu: FloatingMenu = {
        let camButton = FloatingMenuButton.standardActionButton(
            iconTemplate: UIImage(named: "icon_fab_moment")?.withRenderingMode(.alwaysTemplate),
            accessibilityLabel: Localizations.fabMoment,
            action: { [weak self] in
                Analytics.log(event: .fabSelect, properties: [.fabSelection: "moment"])
                let vc = NewMomentViewController(context: .normal)
                self?.present(vc, animated: true)
            })
        composeCamPostButton = camButton

        let voiceNoteButton = FloatingMenuButton.standardActionButton(
            iconTemplate: UIImage(named: "icon_fab_compose_voice")?.withRenderingMode(.alwaysTemplate),
            accessibilityLabel: Localizations.fabAccessibilityVoiceNote,
            action: { [weak self] in
                Analytics.log(event: .fabSelect, properties: [.fabSelection: "audio"])
                self?.presentNewPostViewController(source: .voiceNote)
            })
        composeVoiceNoteButton = voiceNoteButton

        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold, scale: .medium)
        let textIconName = view.effectiveUserInterfaceLayoutDirection == .leftToRight ? "text.alignleft" : "text.alignright"
        let textIcon = UIImage(systemName: textIconName)?.withConfiguration(symbolConfiguration)

        var expandedButtons: [FloatingMenuButton] = [
            .standardActionButton(
                iconTemplate: UIImage(systemName: "photo.fill")?.withConfiguration(symbolConfiguration),
                accessibilityLabel: Localizations.fabAccessibilityPhotoLibrary,
                action: { [weak self] in
                    Analytics.log(event: .fabSelect, properties: [.fabSelection: "photo_video"])
                    self?.presentNewPostViewController(source: .library)
                }),
            voiceNoteButton,
            .standardActionButton(
                iconTemplate: textIcon,
                accessibilityLabel: Localizations.fabAccessibilityTextPost,
                action: { [weak self] in
                    Analytics.log(event: .fabSelect, properties: [.fabSelection: "text"])
                    self?.presentNewPostViewController(source: .noMedia)
                }),
            camButton
        ]

        return FloatingMenu(presenter: self, expandedButtons: expandedButtons)
    }()

    private func installFloatingActionMenu() {
        let trigger = floatingMenu.triggerButton

        trigger.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(trigger)

        NSLayoutConstraint.activate([
            trigger.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            trigger.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor, constant: -20),
        ])
    }

    private func presentNewPostViewController(source: NewPostMediaSource) {
        let fabActionType: FabActionType?
        switch source {
        case .library:
            fabActionType = .gallery
        case .camera:
            fabActionType = .camera
        case .noMedia:
            fabActionType = .text
        case .voiceNote:
            fabActionType = .audio
        case .unified:
            fabActionType = nil
        }

        if let fabActionType = fabActionType {
            AppContext.shared.observeAndSave(event: .fabAction(type: fabActionType))
        }

        let state = NewPostState(mediaSource: source)

        if source == .voiceNote && MainAppContext.shared.callManager.isAnyCallActive {
            // When we have an active call ongoing: we should not record audio.
            // We should present an alert saying that this action is not allowed.
            let alert = UIAlertController(
                title: Localizations.failedActionDuringCallTitle,
                message: Localizations.failedActionDuringCallNoticeText,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: { action in
                DDLogInfo("SharedAlbumViewController/presentNewPostViewController/failedActionDuringCall/dismiss")
            }))
            present(alert, animated: true)
        } else {
            let newPostViewController = NewPostViewController(state: state, destination: .feed(.all), showDestinationPicker: true) { didPost, _ in
                // Reset back to all
                MainAppContext.shared.privacySettings.activeType = .all
                self.dismiss(animated: true)
            }
            newPostViewController.modalPresentationStyle = .fullScreen
            present(newPostViewController, animated: true)
        }
    }
}

extension PhotoSuggestionsViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let itemIdentifier = collectionViewDataSource.itemIdentifier(for: indexPath),
              case .locatedCluster(let managedObjectID) = itemIdentifier,
              let locatedCluster = dataSource.assetLocatedCluster(objectID: managedObjectID) else {
            DDLogError("PhotoSuggestionsViewController/didSelect")
            return
        }

        let localIdentifiers = locatedCluster.assetRecordsAsSet.compactMap(\.localIdentifier)
        let postText = locatedCluster.geocodedLocationName
        let albumTitle = locatedCluster.geocodedLocationName ?? locatedCluster.geocodedAddress ?? Localizations.suggestionAlbumTitle

        Task {
            let newPostState = await PhotoSuggestionsUtilities.newPostState(assetLocalIdentifiers: localIdentifiers, postText: postText, albumTitle: albumTitle)

            await MainActor.run() {
                let newPostViewController = NewPostViewController(state: newPostState,
                                                                  destination: .feed(.all),
                                                                  showDestinationPicker: true) { didPost, _ in
                    // Reset back to all
                    MainAppContext.shared.privacySettings.activeType = .all
                    self.dismiss(animated: true)
                }
                newPostViewController.modalPresentationStyle = .fullScreen
                present(newPostViewController, animated: true)
            }
        }
    }
}

extension PhotoSuggestionsViewController: FloatingMenuPresenter {

    func makeTriggerButton() -> FloatingMenuButton {
        let postLabel = UILabel()
        postLabel.translatesAutoresizingMaskIntoConstraints = false
        postLabel.font = .quicksandFont(ofFixedSize: 21, weight: .bold)
        postLabel.text = Localizations.fabPostButton
        postLabel.textColor = .white

        let labelContainer = UIView()
        labelContainer.translatesAutoresizingMaskIntoConstraints = false
        labelContainer.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 1, right: 0)
        labelContainer.addSubview(postLabel)
        postLabel.constrainMargins(to: labelContainer)

        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        let plusImage = UIImage(systemName: "plus", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)

        return .rotatingToggleButton(collapsedIconTemplate: plusImage,
                                             accessoryView: labelContainer,
                                          expandedRotation: 45)
    }

    func floatingMenuExpansionStateWillChange(to state: FloatingMenu.ExpansionState) {
        // no-op
    }
}

extension PhotoSuggestionsViewController: UIViewControllerScrollsToTop {

    func scrollToTop(animated: Bool) {
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: animated)
    }
}
