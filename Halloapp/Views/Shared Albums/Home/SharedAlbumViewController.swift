//
//  SharedAlbumViewController.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 7/13/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
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
        case header
        case magicPhotosExplainer
    }

    private lazy var dataSource: UICollectionViewDiffableDataSource<Section, Item> = {
        return UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            switch itemIdentifier {
            case .suggestion(let photoCluster):
                if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AlbumSuggestionCollectionViewCell.reuseIdentifier, for: indexPath) as? AlbumSuggestionCollectionViewCell {
                    cell.configure(photoCluster: photoCluster)
                    return cell
                }
            case .loadIndicator:
                return collectionView.dequeueReusableCell(withReuseIdentifier: AlbumSuggestionLoadIndicatorCollectionViewCell.reuseIdentifier, for: indexPath)
            case .header:
                return collectionView.dequeueReusableCell(withReuseIdentifier: PhotoSuggestionsHeaderCollectionViewCell.reuseIdentifier, for: indexPath)
            case .magicPhotosExplainer:
                if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MagicPhotosExplainerCollectionViewCell.reuseIdentifier, for: indexPath) as? MagicPhotosExplainerCollectionViewCell {
                    cell.dismissAction = { [weak self] in
                        DeveloperSetting.didHidePhotoSuggestionsFirstUse = true
                        self?.refreshSuggestions(showLoadIndicator: false)
                    }
                    return cell
                }
            }

            return nil
        }
    }()

    private lazy var collectionView: UICollectionView = {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(130)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(130)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 15
        section.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15)
        let layout = UICollectionViewCompositionalLayout(section: section)
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()

    private var cancellables: Set<AnyCancellable> = []

    override func viewDidLoad() {
        super.viewDidLoad()

        installAvatarBarButton()

        collectionView.backgroundColor = .feedBackground
        collectionView.delegate = self
        collectionView.register(AlbumSuggestionCollectionViewCell.self,
                                forCellWithReuseIdentifier: AlbumSuggestionCollectionViewCell.reuseIdentifier)
        collectionView.register(AlbumSuggestionLoadIndicatorCollectionViewCell.self,
                                forCellWithReuseIdentifier: AlbumSuggestionLoadIndicatorCollectionViewCell.reuseIdentifier)
        collectionView.register(PhotoSuggestionsHeaderCollectionViewCell.self,
                                forCellWithReuseIdentifier: PhotoSuggestionsHeaderCollectionViewCell.reuseIdentifier)
        collectionView.register(MagicPhotosExplainerCollectionViewCell.self,
                                forCellWithReuseIdentifier: MagicPhotosExplainerCollectionViewCell.reuseIdentifier)
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

        installFloatingActionMenu()

        NotificationCenter.default.publisher(for: PhotoSuggestions.suggestionsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSuggestions()
            }
            .store(in: &cancellables)

        refreshSuggestions()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let triggerButtonFrame = floatingMenu.triggerButton.convert(floatingMenu.triggerButton.bounds, to: view)
        collectionView.contentInset.bottom = view.bounds.maxY - triggerButtonFrame.minY
    }

    func refreshSuggestions(showLoadIndicator: Bool = true) {
        collectionView.backgroundView = nil

        if showLoadIndicator {
            var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
            snapshot.appendSections([.suggestions])
            snapshot.appendItems([.loadIndicator])
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        Task {
            guard let suggestions = try? await MainAppContext.shared.photoSuggestions.generateSuggestions().sorted(by: { $0.end > $1.end }) else {
                return
            }
            var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
            if suggestions.isEmpty {
                let hasPhotoPermissions = PhotoPermissionsHelper.authorizationStatus(for: .readWrite) == .authorized
                collectionView.backgroundView = PhotoSuggestionsEmptyStateView(hasPhotoPermissions ? .magicPostsExplainer : .allowPhotoAccess)
            } else {
                snapshot.appendSections([.suggestions])
                if DeveloperSetting.didHidePhotoSuggestionsFirstUse {
                    snapshot.appendItems([.header])
                } else {
                    snapshot.appendItems([.magicPhotosExplainer])
                }
                snapshot.appendItems(suggestions.map { .suggestion($0) })
            }
            dataSource.apply(snapshot, animatingDifferences: true)
        }
    }

    // MARK: Post menu

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

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView == collectionView else {
            return
        }

        guard scrollView.contentSize.height > scrollView.bounds.inset(by: scrollView.adjustedContentInset).height else {
            DispatchQueue.main.async { [weak self] in self?.floatingMenu.setAccessoryState(.accessorized, animated: true) }
            return
        }

        let fabAccessoryState: FloatingMenu.AccessoryState = scrollView.contentOffset.y <= 0 ? .accessorized : .plain
        // if we didn't use a DispatchQueue here, we'd get some issues when restoring scroll position
        DispatchQueue.main.async { [weak self] in self?.floatingMenu.setAccessoryState(fabAccessoryState, animated: true) }
    }
}

extension SharedAlbumViewController: FloatingMenuPresenter {

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

extension SharedAlbumViewController: UIViewControllerScrollsToTop {
    
    func scrollToTop(animated: Bool) {
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: animated)
    }
}
