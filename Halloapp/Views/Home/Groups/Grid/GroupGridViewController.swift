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

        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] in self?.sectionProvider(section: $0, layoutEnvironment: $1) },
                                                         configuration: configuration)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = nil
        collectionView.register(GroupGridCollectionViewCell.self,
                                forCellWithReuseIdentifier: GroupGridCollectionViewCell.reuseIdentifier)
        collectionView.register(GroupGridHeader.self,
                                forSupplementaryViewOfKind: GroupGridHeader.elementKind,
                                withReuseIdentifier: GroupGridHeader.reuseIdentifier)
        collectionView.register(GroupGridSeparator.self,
                                forSupplementaryViewOfKind: GroupGridSeparator.elementKind,
                                withReuseIdentifier: GroupGridSeparator.reuseIdentifier)
        collectionView.scrollsToTop = true
        collectionView.keyboardDismissMode = .interactive
        return collectionView
    }()

    private lazy var dataSource: GroupGridDataSource = {
        let dataSource = GroupGridDataSource(collectionView: collectionView) { [weak self] in self?.cellProvider(collectionView: $0, indexPath: $1, item: $2) }
        dataSource.supplementaryViewProvider = { [weak self] in self?.supplementaryViewProvider(collectionView: $0, elementKind: $1, indexPath: $2) }
        return dataSource
    }()

    private lazy var refreshControl = UIRefreshControl()

    private var unreadPostCountCancellable: AnyCancellable?
    private var requestScrollToTopAnimatedCancellable: AnyCancellable?

    override func viewDidLoad() {
        super.viewDidLoad()

        let searchController = UISearchController()
        searchController.delegate = self
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchResultsUpdater = dataSource
        navigationItem.searchController = searchController

        installAvatarBarButton()

        let image = UIImage(named: "NavCreateGroup", in: nil, with: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))?.withTintColor(UIColor.primaryBlue, renderingMode: .alwaysOriginal)
        image?.accessibilityLabel = Localizations.chatCreateNewGroup
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(createGroup))

        view.backgroundColor = .feedBackground

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

        unreadPostCountCancellable = dataSource.unreadPostsCountSubject.sink { [newPostToast] unreadCount in
            newPostToast.configure(unreadCount: unreadCount, animated: newPostToast.window != nil)
        }

        requestScrollToTopAnimatedCancellable = dataSource.requestScrollToTopAnimatedSubject.sink { [weak self] animated in
            self?.scrollToTop(animated: animated)
        }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillChangeFrame(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Any animated transition back to here will be from some presented / pushed view controller
        // Reload content only if we're switching tabs
        if transitionCoordinator == nil {
            dataSource.reloadSnapshot(animated: false)
            scrollToTop(animated: false)
        }
    }

    private func sectionProvider(section: Int,
                                 layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
        let isSectionEmpty = collectionView.numberOfItems(inSection: section) == 0
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                            heightDimension: .fractionalHeight(1)))

        let size: NSCollectionLayoutSize
        if isSectionEmpty {
            size = .init(widthDimension: .fractionalWidth(1),
                         heightDimension: .estimated(CGFloat.leastNonzeroMagnitude))
        } else {
            size = .init(widthDimension: .fractionalWidth(0.43),
                         heightDimension: .fractionalHeight(0.23))
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
        section.interGroupSpacing = 10
        section.orthogonalScrollingBehavior = .continuous

        return section
    }

    private func cellProvider(collectionView: UICollectionView,
                              indexPath: IndexPath,
                              item: FeedPostID) -> UICollectionViewCell? {
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

    private func supplementaryViewProvider(collectionView: UICollectionView,
                                           elementKind: String,
                                           indexPath: IndexPath) -> UICollectionReusableView? {
        switch elementKind {
        case GroupGridHeader.elementKind:
            let header = collectionView.dequeueReusableSupplementaryView(ofKind: GroupGridHeader.elementKind,
                                                                         withReuseIdentifier: GroupGridHeader.reuseIdentifier,
                                                                         for: indexPath)
            if let header = header as? GroupGridHeader, let groupID = dataSource.groupID(at: indexPath.section) {
                header.configure(with: groupID, unreadPostCountSubject: dataSource.unreadPostCountSubject(for: groupID))
                header.openGroupFeed = { [weak self] in
                    self?.navigationController?.pushViewController(GroupFeedViewController(groupId: groupID), animated: true)
                }
                header.composeGroupPost = { [weak self] in
                    var viewControllerToDismiss: UIViewController?
                    let newPostViewController = NewPostViewController(source: .noMedia, destination: .groupFeed(groupID)) { didPost in
                        guard let viewControllerToDismiss = viewControllerToDismiss else {
                            DDLogError("GroupGridViewController/Missing NewPostViewController to dismiss")
                            return
                        }
                        viewControllerToDismiss.dismiss(animated: true)
                    }
                    viewControllerToDismiss = newPostViewController
                    newPostViewController.modalPresentationStyle = .fullScreen
                    self?.present(newPostViewController, animated: true)
                }
                header.menuActionsForGroup = { [weak self] in self?.menuActionsForGroup(groupID: $0) ?? [] }
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

    @objc func keyboardWillChangeFrame(_ notification: Notification) {
        guard let info = KeyboardNotificationInfo(userInfo: notification.userInfo) else {
            return
        }

        let additionalContentInset = max(0.0, collectionView.frame.intersection(view.convert(info.endFrame, from: nil)).height - collectionView.safeAreaInsets.bottom)
        UIView.animate(withKeyboardNotificationInfo: info) { [collectionView] in
            collectionView.contentInset.bottom = additionalContentInset
            collectionView.verticalScrollIndicatorInsets.bottom = additionalContentInset
        }
    }

    @objc func newPostToastTapped() {
        dataSource.reloadSnapshot(animated: true)
        scrollToTop(animated: true)
    }

    @objc func refreshControlDidRefresh(_ refreshControl: UIRefreshControl?) {
        if let searchController = navigationItem.searchController, searchController.isActive {
            refreshControl?.endRefreshing()
            searchController.isActive = false
        } else {
            dataSource.reloadSnapshot(animated: true) {
                refreshControl?.endRefreshing()
            }
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

            // A new group should be the first item in the list, scroll to top
            self.scrollToTop(animated: false)

            navigationController.setViewControllers(viewControllers, animated: true)
        }), animated: true)
    }

    func menuActionsForGroup(groupID: GroupID) -> [UIMenuElement] {
        let chatData = MainAppContext.shared.chatData!
        guard let group = chatData.chatGroup(groupId: groupID, in: chatData.viewContext) else {
            return []
        }

        let userID = MainAppContext.shared.userData.userId
        if chatData.chatGroupMember(groupId: group.id, memberUserId: userID, in: chatData.viewContext) != nil {
            return [
                UIAction(title: Localizations.groupsGridHeaderMoreInfo) { [weak self] _ in
                    self?.navigationController?.pushViewController(GroupInfoViewController(for: groupID), animated: true)
                }
            ]
        } else {
            let groupName = group.name
            return [
                UIAction(title: Localizations.groupsListRemoveMessage, attributes: [.destructive]) { [weak self] _ in
                    let actionSheet = UIAlertController(title: groupName,
                                                        message: Localizations.groupsListRemoveMessage,
                                                        preferredStyle: .alert)
                    actionSheet.addAction(UIAlertAction(title: Localizations.buttonRemove, style: .destructive) { _ in
                        MainAppContext.shared.chatData.deleteChatGroup(groupId: groupID)
                    })
                    actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
                    self?.present(actionSheet, animated: true)
                }
            ]
        }
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
        collectionView.scrollEmbeddedOrthoginalScrollViewsToOrigin(animated: animated)
    }
}

extension GroupGridViewController: UISearchControllerDelegate {

    func willPresentSearchController(_ searchController: UISearchController) {
        collectionView.refreshControl = nil
    }

    func didDismissSearchController(_ searchController: UISearchController) {
        collectionView.refreshControl = refreshControl
    }
}

extension Localizations {

    static var groupsGridHeaderMoreInfo: String {
        NSLocalizedString("groupGridHeader.moreInfo", value: "More Info", comment: "More info menu item")
    }
}
