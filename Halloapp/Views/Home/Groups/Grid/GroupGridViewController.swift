//
//  GroupGridViewController.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 5/6/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import CoreData
import UIKit

class GroupGridViewController: UIViewController {

    private let newPostToast = GroupGridNewPostToast()

    private lazy var collectionView: UICollectionView = {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.interSectionSpacing = 8

        let layout = UICollectionViewCompositionalLayout(sectionProvider: sectionProvider(_:_:),
                                                         configuration: configuration)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.register(GroupGridCollectionViewCell.self,
                                forCellWithReuseIdentifier: GroupGridCollectionViewCell.reuseIdentifier)
        collectionView.register(GroupGridHeader.self,
                                forSupplementaryViewOfKind: GroupGridHeader.elementKind,
                                withReuseIdentifier: GroupGridHeader.reuseIdentifier)
        collectionView.register(GroupGridSeparator.self,
                                forSupplementaryViewOfKind: GroupGridSeparator.elementKind,
                                withReuseIdentifier: GroupGridSeparator.reuseIdentifier)
        collectionView.scrollsToTop = true
        return collectionView
    }()

    private lazy var dataSource: GroupGridDataSource = {
        let dataSource = GroupGridDataSource(collectionView: collectionView, cellProvider: cellProvider(_:_:_:))
        dataSource.supplementaryViewProvider = supplementaryViewProvider(_:_:_:)
        return dataSource
    }()

    private var unreadPostCountCancellable: AnyCancellable?

    override func viewDidLoad() {
        super.viewDidLoad()

        installLargeTitleUsingGothamFont()

        let image = UIImage(named: "NavCreateGroup", in: nil, with: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))?.withTintColor(UIColor.primaryBlue, renderingMode: .alwaysOriginal)
        image?.accessibilityLabel = Localizations.chatCreateNewGroup
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(createGroup))

        view.backgroundColor = .feedBackground

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshControlDidRefresh(_:)), for: .valueChanged)

        collectionView.delegate = self
        collectionView.refreshControl = refreshControl
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        newPostToast.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(newPostToastTapped)))
        newPostToast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(newPostToast)

        NSLayoutConstraint.activate([
            newPostToast.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            newPostToast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            newPostToast.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 8),

            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        dataSource.performFetch()
        newPostToast.configure(unreadCount: 0, animated: false)

        unreadPostCountCancellable = dataSource.unreadPostsCount.sink { [newPostToast] unreadCount in
            newPostToast.configure(unreadCount: unreadCount, animated: newPostToast.window != nil)
        }
    }

    private func sectionProvider(_ section: Int,
                                 _ layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
        let isSectionEmpty = collectionView.numberOfItems(inSection: section) == 0
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                            heightDimension: .fractionalHeight(1)))

        // Scale a fixed size cell by current font metrics
        let fontMetrics = UIFontMetrics(forTextStyle: .body)
        let size: NSCollectionLayoutSize
        if isSectionEmpty {
            size = .init(widthDimension: .fractionalWidth(1),
                         heightDimension: .estimated(CGFloat.leastNonzeroMagnitude))
        } else {
            size = .init(widthDimension: .absolute(fontMetrics.scaledValue(for: 136, compatibleWith: layoutEnvironment.traitCollection)),
                         heightDimension: .absolute(fontMetrics.scaledValue(for: 182, compatibleWith: layoutEnvironment.traitCollection)))
        }

        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])

        let headerItem = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                                                       heightDimension: .estimated(44)),
                                                                     elementKind: GroupGridHeader.elementKind,
                                                                     alignment: .top)
        let separatorItem = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                                                          heightDimension: .absolute(isSectionEmpty ? 1 : 16)),
                                                                        elementKind: GroupGridSeparator.elementKind,
                                                                        alignment: .bottom)
        separatorItem.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: -14)

        let section = NSCollectionLayoutSection(group: group)
        section.boundarySupplementaryItems = [headerItem, separatorItem]
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        section.interGroupSpacing = 8
        section.orthogonalScrollingBehavior = .continuous

        return section
    }

    private func cellProvider(_ collectionView: UICollectionView,
                              _ indexPath: IndexPath,
                              _ item: FeedPostID) -> UICollectionViewCell? {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: GroupGridCollectionViewCell.reuseIdentifier,
                                                      for: indexPath)
        if let cell = cell as? GroupGridCollectionViewCell, let feedPost = dataSource.feedPost(at: indexPath) {
            cell.configure(with: feedPost)
            let postID = feedPost.id
            cell.openPost = { [weak self] in
                let navigationController = UINavigationController(rootViewController: FlatCommentsViewController(feedPostId: postID))
                navigationController.modalPresentationStyle = .pageSheet
                self?.present(navigationController, animated: true)
            }
        }
        return cell
    }

    private func supplementaryViewProvider(_ collectionView: UICollectionView,
                                           _ elementKind: String,
                                           _ indexPath: IndexPath) -> UICollectionReusableView? {
        switch elementKind {
        case GroupGridHeader.elementKind:
            let header = collectionView.dequeueReusableSupplementaryView(ofKind: GroupGridHeader.elementKind,
                                                                         withReuseIdentifier: GroupGridHeader.reuseIdentifier,
                                                                         for: indexPath)
            if let header = header as? GroupGridHeader, let groupID = dataSource.groupID(at: indexPath.section) {
                header.configure(with: groupID)
                header.openGroupFeed = { [weak self] in
                    self?.navigationController?.pushViewController(GroupFeedViewController(groupId: groupID), animated: true)
                }
                header.composeGroupPost = { [weak self] in
                    let newPostViewController = NewPostViewController(source: .noMedia, destination: .groupFeed(groupID)) { [weak self] didPost in
                        if let self = self {
                            self.dismiss(animated: true)
                            self.dataSource.reloadSnapshot(animated: true)
                        }
                    }
                    newPostViewController.modalPresentationStyle = .fullScreen
                    self?.present(newPostViewController, animated: true)
                }
            }
            return header
        case GroupGridSeparator.elementKind:
            return collectionView.dequeueReusableSupplementaryView(ofKind: GroupGridSeparator.elementKind,
                                                                   withReuseIdentifier: GroupGridSeparator.reuseIdentifier,
                                                                   for: indexPath)
        default:
            return nil
        }
    }

    @objc func newPostToastTapped() {
        dataSource.reloadSnapshot(animated: true)
        scrollToTop(animated: true)
    }

    @objc func refreshControlDidRefresh(_ refreshControl: UIRefreshControl?) {
        dataSource.reloadSnapshot(animated: true) {
            refreshControl?.endRefreshing()
        }
    }

    @objc func createGroup() {
        guard ContactStore.contactsAccessAuthorized else {
            present(UINavigationController(rootViewController: NewGroupMembersPermissionDeniedController()), animated: true)
            return
        }

        navigationController?.pushViewController(CreateGroupViewController(completion: { [weak self] groupID in
            guard let self = self, let navigationController = self.navigationController else {
                return
            }

            // Use setViewControllers to animate in the GroupFeedViewController while removing the group creation assiciated ones.
            var viewControllers = navigationController.viewControllers
            while viewControllers.last != self {
                viewControllers.removeLast()
            }
            viewControllers.append(GroupFeedViewController(groupId: groupID, shouldShowInviteSheet: true))

            navigationController.setViewControllers(viewControllers, animated: true)
        }), animated: true)
    }
}

extension GroupGridViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView,
                        willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        guard let feedPostID = dataSource.feedPostID(at: indexPath) else {
            return
        }
        MainAppContext.shared.feedData.loadImages(postID: feedPostID)
        (cell as? GroupGridCollectionViewCell)?.startAnimations()
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        didEndDisplaying cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        (cell as? GroupGridCollectionViewCell)?.stopAnimations()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let feedPost = dataSource.feedPost(at: indexPath), let groupID = feedPost.groupID else {
            return
        }
        let groupFeedViewController = GroupFeedViewController(groupId: groupID)
        groupFeedViewController.feedPostIdToScrollTo = feedPost.id
        navigationController?.pushViewController(groupFeedViewController, animated: true)
    }
}

extension GroupGridViewController: UIViewControllerScrollsToTop {

    func scrollToTop(animated: Bool) {
        collectionView.setContentOffset(CGPoint(x: 0.0, y: -collectionView.adjustedContentInset.top), animated: animated)
        collectionView.scrollEmbeddedOrthoginalScrollViewsToOrigin(animated: true)
    }
}

