//
//  FriendsViewController.swift
//  HalloApp
//
//  Created by Tanveer on 8/28/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon
import Core

class FriendsViewController: UIViewController, UserActionHandler {

    enum `Type` {
        case existing, incomingRequests, allRequests, search
    }

    let type: `Type`

    private lazy var collectionView: UICollectionView = {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.interSectionSpacing = 20

        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] in
            self?.sectionProvider(sectionIndex: $0, layoutEnvironment: $1)
        }, configuration: configuration)

        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()

    private(set) lazy var dataSource: FriendsDataSource = {
        let cellProvider = { [weak self] in
            self?.cellProvider(collectionView: $0, indexPath: $1, item: $2)
        }
        let supplementaryViewProvider = { [weak self] in
            self?.supplementaryViewProvider(collectionView: $0, elementKind: $1, indexPath: $2)
        }

        let dataSource: FriendsDataSource
        switch type {
        case .existing:
            return CurrentFriendsDataSource(collectionView: collectionView,
                                            cellProvider: cellProvider,
                                            supplementaryViewProvider: supplementaryViewProvider)
        case .incomingRequests:
            return FriendRequestsDataSource(collectionView: collectionView,
                                            cellProvider: cellProvider,
                                            supplementaryViewProvider: supplementaryViewProvider)
        case .allRequests:
            return FriendAllRequestsDataSource(collectionView: collectionView,
                                               cellProvider: cellProvider,
                                               supplementaryViewProvider: supplementaryViewProvider)
        case .search:
            return FriendSearchDataSource(collectionView: collectionView,
                                          cellProvider: cellProvider,
                                          supplementaryViewProvider: supplementaryViewProvider)
        }
    }()

    let inviteManager: InviteManager

    init(type: `Type`) {
        self.type = type
        self.inviteManager = InviteManager()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("FriendViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .feedBackground
        collectionView.backgroundColor = nil

        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        collectionView.register(IncomingFriendCollectionViewCell.self,
                                forCellWithReuseIdentifier: IncomingFriendCollectionViewCell.reuseIdentifier)
        collectionView.register(OutgoingFriendCollectionViewCell.self,
                                forCellWithReuseIdentifier: OutgoingFriendCollectionViewCell.reuseIdentifier)
        collectionView.register(SuggestedFriendCollectionViewCell.self,
                                forCellWithReuseIdentifier: SuggestedFriendCollectionViewCell.reuseIdentifier)
        collectionView.register(ExistingFriendCollectionViewCell.self,
                                forCellWithReuseIdentifier: ExistingFriendCollectionViewCell.reuseIdentifier)
        collectionView.register(FriendsEmptyStateCollectionViewCell.self,
                                forCellWithReuseIdentifier: FriendsEmptyStateCollectionViewCell.reuseIdentifier)
        collectionView.register(FriendInviteCollectionViewCell.self,
                                forCellWithReuseIdentifier: FriendInviteCollectionViewCell.reuseIdentifier)
        collectionView.register(FriendRequestsIndicatorCollectionViewCell.self,
                                forCellWithReuseIdentifier: FriendRequestsIndicatorCollectionViewCell.reuseIdentifier)

        collectionView.register(DefaultFriendHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: DefaultFriendHeaderView.reuseIdentifier)
        collectionView.register(FriendInitialHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: FriendInitialHeaderView.reuseIdentifier)
        collectionView.register(FriendInviteHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: FriendInviteHeaderView.reuseIdentifier)
        collectionView.register(FriendRequestsHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: FriendRequestsHeaderView.reuseIdentifier)

        _ = dataSource

        collectionView.allowsSelection = true
        collectionView.delegate = self

        let title: String
        switch type {
        case .allRequests:
            title = Localizations.allRequests
        default:
            title = ""
        }

        navigationItem.title = title
    }

    private func sectionProvider(sectionIndex: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
        let defaultSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                                 heightDimension: .estimated(44))
        let item = NSCollectionLayoutItem(layoutSize: defaultSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: defaultSize,
                                                     subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        let header: NSCollectionLayoutBoundarySupplementaryItem?
        var pinHeader = false

        switch dataSource.section(for: IndexPath(row: 0, section: sectionIndex)) {
        case .blank:
            header = nil
        case .friends, .suggestions, .requests:
            pinHeader = true
            fallthrough
        default:
            header = .init(layoutSize: defaultSize,
                           elementKind: UICollectionView.elementKindSectionHeader,
                           alignment: .top)
        }

        header?.pinToVisibleBounds = pinHeader
        section.boundarySupplementaryItems = [header].compactMap { $0 }
        section.contentInsets = .init(top: 0, leading: 15, bottom: 0, trailing: 15)

        return section
    }

    private func cellProvider(collectionView: UICollectionView, indexPath: IndexPath, item: FriendsDataSource.Item) -> UICollectionViewCell {
        let cell: UICollectionViewCell
        let isFirst = indexPath.row == 0
        let isLast = indexPath.row == collectionView.numberOfItems(inSection: indexPath.section) - 1

        switch item {
        case .incoming(let friend):
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: IncomingFriendCollectionViewCell.reuseIdentifier,
                                                      for: indexPath)
            guard let cell = cell as? IncomingFriendCollectionViewCell else {
                break
            }
            cell.configure(with: friend, isFirst: isFirst, isLast: isLast)
            cell.onConfirm = { [weak self, id = friend.id] in
                self?.acceptFriend(userID: id)
            }
            cell.onIgnore = { [weak self, id = friend.id] in
                self?.ignoreRequest(userID: id)
            }
            cell.onSelect = { [weak self, friend] in
                self?.openProfile(for: friend)
            }

        case .outgoing(let friend):
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: OutgoingFriendCollectionViewCell.reuseIdentifier,
                                                      for: indexPath)
            guard let cell = cell as? OutgoingFriendCollectionViewCell else {
                break
            }
            cell.configure(with: friend, isFirst: isFirst, isLast: isLast)
            cell.onCancel = { [weak self, id = friend.id] in
                self?.cancelRequest(userID: id)
            }
            cell.onSelect = { [weak self, friend] in
                self?.openProfile(for: friend)
            }

        case .suggested(let friend):
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: SuggestedFriendCollectionViewCell.reuseIdentifier,
                                                      for: indexPath)
            guard let cell = cell as? SuggestedFriendCollectionViewCell else {
                break
            }
            cell.configure(with: friend, isFirst: isFirst, isLast: isLast)
            cell.onAdd = { [weak self, id = friend.id] in
                self?.addFriend(userID: id)
            }
            cell.onSelect = { [weak self, friend] in
                self?.openProfile(for: friend)
            }

        case .existing(let friend):
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: ExistingFriendCollectionViewCell.reuseIdentifier,
                                                      for: indexPath)
            guard let cell = cell as? ExistingFriendCollectionViewCell else {
                break
            }
            cell.configure(with: friend, isFirst: isFirst, isLast: isLast)
            cell.menuButton.configureWithMenu { [weak self] in
                HAMenu.menu(for: friend.id, options: [.viewProfile, .updateFriendship, .block, .favorite]) { action, userID in
                    guard let self else {
                        return
                    }
                    switch action {
                    case .removeFriend:
                        self.removeFriend(userID: userID)
                    case .viewProfile:
                        let viewController = UserFeedViewController(userId: userID)
                        let navigationController = UINavigationController(rootViewController: viewController)
                        self.present(navigationController, animated: true)
                    default:
                        Task { try await self.handle(action, for: userID) }
                    }
                }
            }
            cell.onSelect = { [weak self, friend] in
                self?.openProfile(for: friend)
            }

        case .allRequests(let count):
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: FriendRequestsIndicatorCollectionViewCell.reuseIdentifier,
                                                      for: indexPath)
            guard let cell = cell as? FriendRequestsIndicatorCollectionViewCell else {
                break
            }
            cell.configure(title: Localizations.seeAllRequests, count: count, showCircle: true, isFirst: isFirst, isLast: isLast)

        case .sentRequests(let count):
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: FriendRequestsIndicatorCollectionViewCell.reuseIdentifier,
                                                      for: indexPath)
            guard let cell = cell as? FriendRequestsIndicatorCollectionViewCell else {
                break
            }
            cell.configure(title: Localizations.seeSentRequests, count: count, showCircle: false, isFirst: isFirst, isLast: isLast)

        case .noFriends:
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: FriendsEmptyStateCollectionViewCell.reuseIdentifier,
                                                      for: indexPath)

        case .invite(let contact):
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: FriendInviteCollectionViewCell.reuseIdentifier,
                                                      for: indexPath)
            guard let cell = cell as? FriendInviteCollectionViewCell else {
                break
            }

            var actionTypes = [InviteActionType]()
            if isIMessageAvailable {
                actionTypes.append(.sms)
            }
            if isWhatsAppAvailable {
                actionTypes.append(.whatsApp)
            }

            let actions = InviteActions(action: { [weak self] action in
                self?.inviteAction(action, contact: contact)
            }, types: actionTypes)

            cell.configure(with: contact, actions: actions, isFirst: isFirst, isLast: isLast)
        }

        return cell
    }

    private func supplementaryViewProvider(collectionView: UICollectionView, elementKind: String, indexPath: IndexPath) -> UICollectionReusableView {
        let header: UICollectionReusableView

        switch dataSource.section(for: indexPath) {
        case .requests:
            header = collectionView.dequeueReusableSupplementaryView(ofKind: elementKind,
                                                                     withReuseIdentifier: DefaultFriendHeaderView.reuseIdentifier,
                                                                     for: indexPath)
            (header as? DefaultFriendHeaderView)?.configure(title: Localizations.friendRequests.uppercased())
        case .suggestions:
            header = collectionView.dequeueReusableSupplementaryView(ofKind: elementKind,
                                                                     withReuseIdentifier: DefaultFriendHeaderView.reuseIdentifier,
                                                                     for: indexPath)
            (header as? DefaultFriendHeaderView)?.configure(title: Localizations.friendSuggestions.uppercased())
        case .friends:
            header = collectionView.dequeueReusableSupplementaryView(ofKind: elementKind,
                                                                     withReuseIdentifier: DefaultFriendHeaderView.reuseIdentifier,
                                                                     for: indexPath)
            (header as? DefaultFriendHeaderView)?.configure(title: Localizations.myFriends.uppercased())
        case .invites:
            header = collectionView.dequeueReusableSupplementaryView(ofKind: elementKind,
                                                                     withReuseIdentifier: FriendInviteHeaderView.reuseIdentifier,
                                                                     for: indexPath)
        case .incomingRequests(let count):
            header = collectionView.dequeueReusableSupplementaryView(ofKind: elementKind,
                                                                     withReuseIdentifier: FriendRequestsHeaderView.reuseIdentifier,
                                                                     for: indexPath)
            (header as? FriendRequestsHeaderView)?.configure(title: String(format: Localizations.requestsReceivedFormat, count))
        case .outgoingRequests:
            header = collectionView.dequeueReusableSupplementaryView(ofKind: elementKind,
                                                                     withReuseIdentifier: FriendRequestsHeaderView.reuseIdentifier,
                                                                     for: indexPath)
            (header as? FriendRequestsHeaderView)?.configure(title: Localizations.seeSentRequests)
        default:
            fatalError()
        }

        return header
    }

    @HAMenuContentBuilder
    private func friendMenu(for userID: UserID) -> HAMenu.Content {
        HAMenuButton(title: Localizations.removeFriend, image: UIImage(systemName: "person.badge.minus")) { [weak self] in
            self?.removeFriend(userID: userID)
        }
        .destructive()
    }

    private func addFriend(userID: UserID) {
        dataSource.update(userID, to: .outgoingPending)

        let previousStatus = UserProfile.FriendshipStatus.none
        Task(priority: .userInitiated) {
            do {
                try await MainAppContext.shared.userProfileData.addFriend(userID: userID)
            } catch {
                dataSource.update(userID, to: previousStatus)
            }
        }
    }

    private func acceptFriend(userID: UserID) {
        dataSource.update(userID, to: .friends)

        let previousStatus = UserProfile.FriendshipStatus.none
        Task(priority: .userInitiated) {
            do {
                try await MainAppContext.shared.userProfileData.acceptFriend(userID: userID)
            } catch {
                dataSource.update(userID, to: previousStatus)
            }
        }
    }

    private func removeFriend(userID: UserID) {
        let profile = UserProfile.find(with: userID, in: MainAppContext.shared.mainDataStore.viewContext)
        let previousStatus = UserProfile.FriendshipStatus.friends

        let alert = UIAlertController(title: Localizations.removeFriendTitle(name: profile?.name ?? ""),
                                      message: Localizations.removeFriendBody(name: profile?.name ?? ""),
                                      preferredStyle: .alert)
        let removeAction = UIAlertAction(title: Localizations.buttonRemove, style: .destructive) { [weak self] _ in
            self?.dataSource.update(userID, to: .none)
            Task(priority: .userInitiated) {
                do {
                    try await MainAppContext.shared.userProfileData.removeFriend(userID: userID)
                } catch {
                    self?.dataSource.update(userID, to: previousStatus)
                }
            }
        }
        let cancelAction = UIAlertAction(title: Localizations.buttonCancel, style: .cancel)

        alert.addAction(removeAction)
        alert.addAction(cancelAction)

        self.present(alert, animated: true)
    }

    private func cancelRequest(userID: UserID) {
        dataSource.update(userID, to: .none)

        let previousStatus = UserProfile.FriendshipStatus.outgoingPending
        Task(priority: .userInitiated) {
            do {
                try await MainAppContext.shared.userProfileData.cancelRequest(userID: userID)
            } catch {
                dataSource.update(userID, to: previousStatus)
            }
        }
    }

    private func ignoreRequest(userID: UserID) {
        dataSource.update(userID, to: .none)

        let previousStatus = UserProfile.FriendshipStatus.incomingPending
        Task(priority: .userInitiated) {
            do {
                try await MainAppContext.shared.userProfileData.ignoreRequest(userID: userID)
            } catch {
                dataSource.update(userID, to: previousStatus)
            }
        }
    }

    private func openProfile(for friend: FriendsDataSource.Friend) {
        let viewController: UIViewController
        switch friend.friendshipStatus {
        case .none, .incomingPending, .outgoingPending:
            viewController = UserFeedViewController(profile: friend)
        case .friends:
            viewController = UserFeedViewController(userId: friend.id, showHeader: true)
        }

        let navigationController = UINavigationController(rootViewController: viewController)
        present(navigationController, animated: true)
    }
}

// MARK: - FriendViewController + UICollectionViewDelegate

extension FriendsViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.item(at: indexPath) else {
            return false
        }

        switch item {
        case .sentRequests, .allRequests:
            return true
        default:
            return false
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.item(at: indexPath) else {
            return
        }

        switch item {
        case .sentRequests, .allRequests:
            let viewController = FriendsViewController(type: .allRequests)
            navigationController?.pushViewController(viewController, animated: true)
        default:
            return
        }

        collectionView.deselectItem(at: indexPath, animated: true)
    }
}

// MARK: - FriendViewController + InviteContactViewController

extension FriendsViewController: InviteContactViewController {

    func showLoadIndicator(_ isLoading: Bool) {

    }

    func didInviteContact(_ contact: InviteContact, with action: InviteActionType) {

    }
}

// MARK: - Localization

extension Localizations {

    static var friendRequests: String {
        NSLocalizedString("friend.requests",
                          value: "Friend Requests",
                          comment: "Indicating friend requests")
    }

    static var friendSuggestions: String {
        NSLocalizedString("friend.suggestions",
                          value: "Friend Suggestions",
                          comment: "Indicating suggested friends.")
    }

    static var removeFriend: String {
        NSLocalizedString("remove.friend",
                          value: "Remove Friend",
                          comment: "Title of a button to remove a friend.")
    }

    static var seeAllRequests: String {
        NSLocalizedString("see.all.requests",
                          value: "See All Requests",
                          comment: "Title of a button that shows all friend requests.")
    }

    static var seeSentRequests: String {
        NSLocalizedString("see.sent.requests",
                          value: "Requests Sent",
                          comment: "Title of a button that shows sent friend requests.")
    }

    static var allRequests: String {
        NSLocalizedString("all.requests",
                          value: "All Requests",
                          comment: "Indicating all pending friend requests.")
    }

    static var requestsReceivedFormat: String {
        NSLocalizedString("requests.received",
                          value: "Requests Received (%d)",
                          comment: "Format string to display how many incoming friend requests there are.")
    }

    static var myFriends: String {
        NSLocalizedString("my.friends",
                          value: "My Friends",
                          comment: "Indicates the user's current friends.")
    }
}
