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

    private var cancellableSet: Set<AnyCancellable> = []
    private lazy var collectionView: UICollectionView = {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.interSectionSpacing = 8

        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] in self?.sectionProvider(section: $0, layoutEnvironment: $1) },
                                                         configuration: configuration)

        let emptyView = UIView()

        let emptyImageView = UIImageView(image: UIImage(named: "ChatEmpty")?.withRenderingMode(.alwaysTemplate))
        emptyImageView.tintColor = .label.withAlphaComponent(0.2)

        let emptyLabel = UILabel()
        emptyLabel.numberOfLines = 0
        emptyLabel.text = Localizations.nuxGroupsListEmpty
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .secondaryLabel

        let emptyStackView = UIStackView(arrangedSubviews: [emptyImageView, emptyLabel])
        emptyStackView.axis = .vertical
        emptyStackView.alignment = .center
        emptyStackView.spacing = 12
        emptyStackView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.addSubview(emptyStackView)

        NSLayoutConstraint.activate([
            emptyStackView.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
            emptyStackView.centerYAnchor.constraint(equalTo: emptyView.centerYAnchor),
            emptyStackView.widthAnchor.constraint(equalTo: emptyView.widthAnchor, multiplier: 0.6),
        ])

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = nil
        collectionView.backgroundView = emptyView
        collectionView.contentInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0) // Hide top of search bar
        collectionView.register(GroupGridCollectionViewCell.self,
                                forCellWithReuseIdentifier: GroupGridCollectionViewCell.reuseIdentifier)
        collectionView.register(GroupGridHeader.self,
                                forSupplementaryViewOfKind: GroupGridHeader.elementKind,
                                withReuseIdentifier: GroupGridHeader.reuseIdentifier)
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

    private lazy var searchController: UISearchController = {
        let searchController = UISearchController()
        searchController.delegate = self
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.backgroundImage = UIImage()
        searchController.searchBar.tintColor = .primaryBlue
        searchController.searchBar.searchTextField.backgroundColor = .searchBarBg
        searchController.searchResultsUpdater = dataSource
        searchController.automaticallyShowsSearchResultsController = false
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.layoutMargins = UIEdgeInsets(top: 0, left: 21, bottom: 0, right: 21)
        return searchController
    }()

    private var isEmptyCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var lastDisappearDate: Date?

    override func viewDidLoad() {
        super.viewDidLoad()

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

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        dataSource.performFetch()

        isEmptyCancellable = dataSource.$isEmpty.sink { [weak self] isEmpty in
            self?.collectionView.backgroundView?.isHidden = !isEmpty
        }

        dataSource.requestScrollToTopAnimatedSubject
            .sink { [weak self] animated in
                self?.scrollToTop(animated: animated)
            }
            .store(in: &cancellables)

        dataSource.requestScrollToIndexPathSubject
            .sink { [weak self] indexPath in
                self?.collectionView.scrollToItem(at: indexPath, at: [.top, .centeredHorizontally], animated: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillChangeFrame(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)
        cancellableSet.insert(
            MainAppContext.shared.groupFeedFromGroupTabPresentRequest.sink { [weak self] (groupID) in
                guard let self = self else { return }
                guard let groupID = groupID, let group = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: MainAppContext.shared.chatData.viewContext) else { return }
                self.navigationController?.popToRootViewController(animated: false)
                switch group.type {
                case .groupFeed:
                    let vc = GroupFeedViewController(group: group)
                    self.navigationController?.pushViewController(vc, animated: false)
                case .groupChat:
                    let vc = GroupChatViewController(for: group)
                    self.navigationController?.pushViewController(vc, animated: false)
                case .oneToOne:
                    break
                }
            }
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        Analytics.openScreen(.groupList)

        // reload contents if we've been gone for > 10 min
        if let lastDisappearDate = lastDisappearDate, -lastDisappearDate.timeIntervalSinceNow > 60 * 10 {
            self.lastDisappearDate = nil
            dataSource.reload(animated: false)
            scrollToTop(animated: false)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        lastDisappearDate = Date()

        if searchController.isActive, searchController.searchBar.text?.isEmpty ?? true {
            searchController.isActive = false
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

        let section = NSCollectionLayoutSection(group: group)
        section.boundarySupplementaryItems = [
            NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44)),
                                                        elementKind: GroupGridHeader.elementKind,
                                                        alignment: .top)
        ]
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: isSectionEmpty ? 0 : 16, trailing: 14)
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
                self?.navigationController?.pushViewController(FlatCommentsViewController(feedPostId: postID), animated: true)
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
            if let header = header as? GroupGridHeader, let group = dataSource.group(at: indexPath.section) {
                let groupID = group.id
                header.configure(with: group)
                header.openGroupFeed = { [weak self] in
                    self?.navigationController?.pushViewController(GroupFeedViewController(group: group), animated: true)
                }
                header.composeGroupPost = { [weak self] in self?.createPost(in: groupID) }
                header.menuActions = { [weak self] in self?.menuActionsForGroup(groupID: groupID) ?? [] }
            }
            return header
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

    @objc func refreshControlDidRefresh(_ refreshControl: UIRefreshControl?) {
        if searchController.isActive {
            refreshControl?.endRefreshing()
            searchController.isActive = false
        } else {
            dataSource.reload(animated: true) {
                refreshControl?.endRefreshing()
            }
        }
    }

    @objc private func createGroup() {
        navigationController?.pushViewController(CreateGroupViewController(groupType: GroupType.groupFeed, completion: { [weak self] groupID in
            guard let self = self, let navigationController = self.navigationController else {
                return
            }

            Analytics.log(event: .createGroup, properties: [.groupType: "feed"])

            // Use setViewControllers to animate in the GroupFeedViewController while removing the group creation assiciated ones.
            var viewControllers = navigationController.viewControllers
            while viewControllers.last != self {
                viewControllers.removeLast()
            }
            if let group = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: MainAppContext.shared.chatData.viewContext) {
                viewControllers.append(GroupFeedViewController(group: group, shouldShowInviteSheet: true))
            }

            // A new group should be the first item in the list, scroll to top
            self.scrollToTop(animated: false)

            navigationController.setViewControllers(viewControllers, animated: true)
        }), animated: true)
    }

    private func createPost(in groupID: GroupID) {
        guard let group = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: MainAppContext.shared.chatData.viewContext) else {
            DDLogError("GroupGridViewController/Cannot find chat group to create tpost")
            return
        }

        let state = NewPostState(mediaSource: .unified)
        let destination = ShareDestination.destination(from: group)
        var viewControllerToDismiss: UIViewController?
        let newPostViewController = NewPostViewController(state: state, destination: destination, showDestinationPicker: false) { didPost, _ in
            guard let viewControllerToDismiss = viewControllerToDismiss else {
                DDLogError("GroupGridViewController/Missing NewPostViewController to dismiss")
                return
            }
            viewControllerToDismiss.dismiss(animated: true)
        }
        viewControllerToDismiss = newPostViewController
        newPostViewController.modalPresentationStyle = .fullScreen
        present(newPostViewController, animated: true)
    }

    private func leaveGroup(id: GroupID) {
        guard let group = MainAppContext.shared.chatData.chatGroup(groupId: id, in: MainAppContext.shared.chatData.viewContext) else {
            DDLogError("GroupGridViewController/Cannot find chat group to leave")
            return
        }

        let actionSheet = UIAlertController(title: nil, message: Localizations.leaveGroupConfirmation(groupName: group.name), preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: Localizations.chatGroupInfoLeaveGroup, style: .destructive) { _ in
            MainAppContext.shared.service.leaveGroup(groupID: id) { _ in }
         })
         actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
         present(actionSheet, animated: true)
    }

    private func deleteGroup(id: GroupID) {
        let chatData = MainAppContext.shared.chatData!
        guard let group = chatData.chatGroup(groupId: id, in: chatData.viewContext) else {
            DDLogError("GroupGridViewController/deleteGroup/ group not found")
            return
        }
        let actionSheet = UIAlertController(title: group.name,
                                            message: Localizations.groupsListRemoveMessage,
                                            preferredStyle: .alert)
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonRemove, style: .destructive) { [weak self] _ in
            let isMember = chatData.chatGroupMember(groupId: id, memberUserId: MainAppContext.shared.userData.userId, in: chatData.viewContext) != nil

            if isMember {
                MainAppContext.shared.service.leaveGroup(groupID: id) { result in
                    switch result {
                    case .success:
                        chatData.deleteChatGroup(groupId: id, type: group.type)
                    case .failure(let error):
                        DDLogError("GroupGridViewController/Failed to leave group during deletion: \(error)")

                        let alertController = UIAlertController(title: nil, message: Localizations.groupsGridDeleteGroupFailed, preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default))
                        self?.present(alertController, animated: true)
                    }
                }
            } else {
                chatData.deleteChatGroup(groupId: id, type: group.type)
            }
        })
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        present(actionSheet, animated: true)
    }

    func menuActionsForGroup(groupID: GroupID) -> [UIMenuElement] {
        let chatData = MainAppContext.shared.chatData!
        guard let group = chatData.chatGroup(groupId: groupID, in: chatData.viewContext) else {
            return []
        }

        var actions: [UIMenuElement] = []

        let isMember = chatData.chatGroupMember(groupId: group.id, memberUserId: MainAppContext.shared.userData.userId, in: chatData.viewContext) != nil
        if isMember {
            actions.append(UIAction(title: Localizations.newPost, image: UIImage(systemName: "plus.circle"), handler: { [weak self] _ in
                self?.createPost(in: groupID)
            }))
        }

        actions.append(UIAction(title: Localizations.groupsGridHeaderMoreInfo, image: UIImage(systemName: "info.circle"), handler: { [weak self] _ in
            self?.navigationController?.pushViewController(GroupInfoViewController(for: groupID), animated: true)
        }))

        if isMember {
            actions.append(UIAction(title: Localizations.chatGroupInfoLeaveGroup, image: UIImage(systemName: "rectangle.portrait.and.arrow.right"), handler: { [weak self] _ in
                self?.leaveGroup(id: groupID)
            }))
        }

        return [
            UIMenu(options: .displayInline, children: actions),
            UIAction(title: Localizations.groupsGridButtonDelete, image: UIImage(systemName: "trash"), attributes: [.destructive]) { [weak self] _ in
                self?.deleteGroup(id: groupID)
            }
        ]
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
        let group = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: MainAppContext.shared.chatData.viewContext)
        guard let group = group else {
            DDLogError("GroupGridViewController/ group not found")
            return
        }
        let groupFeedViewController = GroupFeedViewController(group: group)
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

extension GroupGridViewController: UIViewControllerHandleTapNotification {
    // MARK: Tap Notification
    func processNotification(metadata: NotificationMetadata) {
        guard metadata.isGroupNotification else {
            return
        }

        metadata.removeFromUserDefaults()
        // If the user tapped on a notification, move to group feed
        DDLogDebug("GroupGridViewController/processNotification/open group feed [\(metadata.groupId ?? "")], contentType: \(metadata.contentType)")

        navigationController?.popToRootViewController(animated: false)

        switch metadata.contentType {
        case .groupFeedPost, .groupFeedComment:
            if let groupId = metadata.groupId, let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: MainAppContext.shared.chatData.viewContext) {
                if let vc = GroupFeedViewController(metadata: metadata) {
                    vc.delegate = self
                    self.navigationController?.pushViewController(vc, animated: false)
                } else {
                    let vc = GroupFeedViewController(group: group)
                    vc.delegate = self
                    self.navigationController?.pushViewController(vc, animated: false)
                }
            }
            break
        case .groupAdd:
            if let groupId = metadata.groupId {
                if let _ = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: MainAppContext.shared.chatData.viewContext) {
                    openFeed(forGroupId: groupId)
                } else {
                    AppContext.shared.errorLogger?.logError(NSError(domain: "missingGroup", code: 1013))
                }
            }
        case .groupChatMessage:
            break
        default:
            break
        }
    }

    private func openFeed(forGroupId groupId: GroupID) {
        guard let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: MainAppContext.shared.chatData.viewContext) else { return }
        switch group.type {
        case .groupFeed:
            let groupFeedViewController = GroupFeedViewController(group: group)
            navigationController?.pushViewController(groupFeedViewController, animated: true)
        case .groupChat:
            let groupChatViewController = GroupChatViewController(for: group)
            navigationController?.pushViewController(groupChatViewController, animated: true)
        case .oneToOne:
            break
        }
    }
}

extension GroupGridViewController: FeedCollectionViewControllerDelegate {
    func feedCollectionViewController(_ controller: FeedCollectionViewController, userActioned: Bool) {
        searchController.isActive = false
        DispatchQueue.main.async {
            self.scrollToTop(animated: false)
        }
    }
}

extension Localizations {

    static var groupsGridDeleteGroupFailed: String {
        NSLocalizedString("groupGrid.deletion.error", value: "Failed to delete group", comment: "Error message when a group fails to delete")
    }

    static var groupsGridButtonDelete: String {
        NSLocalizedString("groupGrid.deletion.title", value: "Delete Group", comment: "Title of button that deletes a group")
    }

    static var groupsGridHeaderMoreInfo: String {
        NSLocalizedString("groupGridHeader.moreInfo", value: "More Info", comment: "More info menu item")
    }

    static var groupsListRemoveMessage: String {
        NSLocalizedString("groups.list.remove.message", value: "Are you sure you want to remove this group and its content from your device?", comment: "Text shown when user is about to remove the group")
    }
}
