//
//  GroupsListViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 1/12/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreData
import Intents
import SwiftUI
import UIKit

fileprivate struct Constants {
    static let AvatarSize: CGFloat = 56
    static let LastMsgFont = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize + 1) // 14
    static let LastMsgColor = UIColor.secondaryLabel
}

class GroupsListViewController: UIViewController, NSFetchedResultsControllerDelegate {

    private static let cellReuseIdentifier = "ThreadListCell"
    private let tableView = UITableView(frame: CGRect.zero, style: .grouped)

    private var fetchedResultsController: NSFetchedResultsController<ChatThread>?
    private var dataSource: GroupsListDataSource?
    
    private var isVisible: Bool = false
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var filteredChatsTitles: [ChatThread] = []
    private var filteredChatsMembers: [ChatThread] = []

    private var searchController = UISearchController(searchResultsController: nil)
    
    private var isSearchBarEmpty: Bool {
        return searchController.searchBar.text?.isEmpty ?? true
    }
    private var isFiltering: Bool {
        if searchController.isActive {
            navigationItem.rightBarButtonItem = nil
        } else {
            navigationItem.rightBarButtonItem = rightBarButtonItem
        }
        return searchController.isActive && !isSearchBarEmpty
    }
    private var groupIdToPresent: GroupID? = nil

    // MARK: Lifecycle
    
    init(title: String) {
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("GroupsListViewController/viewDidLoad")

        let navAppearance = UINavigationBarAppearance()
        navAppearance.backgroundColor = UIColor.primaryBg
        navAppearance.shadowColor = nil
        navAppearance.setBackIndicatorImage(UIImage(named: "NavbarBack"), transitionMaskImage: UIImage(named: "NavbarBack"))
        navigationItem.standardAppearance = navAppearance
        navigationItem.scrollEdgeAppearance = navAppearance
        navigationItem.compactAppearance = navAppearance

        installLargeTitleUsingGothamFont()

        navigationItem.rightBarButtonItem = rightBarButtonItem

        definesPresentationContext = true

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.definesPresentationContext = true
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.delegate = self

        searchController.searchBar.backgroundImage = UIImage()
        searchController.searchBar.tintColor = UIColor.primaryBlue
        searchController.searchBar.searchTextField.backgroundColor = .searchBarBg
        searchController.searchBar.searchTextField.placeholder = Localizations.labelSearch

        tableView.tableHeaderView = searchController.searchBar
        tableView.tableHeaderView?.layoutMargins = UIEdgeInsets(top: 0, left: 21, bottom: 0, right: 21) // requested to be 21

        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.constrain(to: view)

        installEmptyView() // might be deprecated after NUX zero zone roll out, keep until certain

        tableView.register(GroupsListHeaderView.self, forHeaderFooterViewReuseIdentifier: "sectionHeader")
        tableView.register(ThreadListCell.self, forCellReuseIdentifier: GroupsListViewController.cellReuseIdentifier)
        tableView.delegate = self

        tableView.backgroundView = UIView() // fixes issue where bg color was off when pulled down from top
        tableView.backgroundColor = .primaryBg
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0) // -10 to hide top padding on searchBar

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60 // set a number close to default to prevent cells overlapping issue, can't be auto

        dataSource = GroupsListDataSource(tableView: tableView) { [weak self] (tableView, indexPath, row) in
            guard let self = self else { return UITableViewCell() }
            if [0, 1].contains(indexPath.section) {
                switch row {
                case .group:
                    guard let chatThread = self.chatThread(at: indexPath) else {
                        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                        cell.isHidden = true
                        return cell
                    }

                    let cell = tableView.dequeueReusableCell(withIdentifier: GroupsListViewController.cellReuseIdentifier, for: indexPath) as! ThreadListCell

                    cell.configureAvatarSize(Constants.AvatarSize)
                    cell.configureForGroupsList(with: chatThread, squareSize: Constants.AvatarSize)

                    if self.isFiltering {
                        let strippedString = self.searchController.searchBar.text!.trimmingCharacters(in: CharacterSet.whitespaces)
                        let searchItems = strippedString.components(separatedBy: " ")
                        cell.highlightTitle(searchItems)
                    }
                    return cell
                }
            }
            return UITableViewCell()
        }
        
        setupFetchedResultsController()
        reloadData(animated: false)

        // When the user was on this view
        cancellableSet.insert(
            MainAppContext.shared.didTapNotification.sink { [weak self] (metadata) in
                guard let self = self else { return }
                self.processNotification(metadata: metadata)
            }
        )
        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetAGroupEvent.sink { [weak self] (groupId) in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if self.groupIdToPresent == groupId {
                        DDLogDebug("GroupsListViewController/presentGroup \(groupId)")
                        self.openFeed(forGroupId: groupId)
                        self.groupIdToPresent = nil
                    }
                }
        })

        // When the user was not on this view, and HomeView sends user to here
        if let metadata = NotificationMetadata.fromUserDefaults() {
            processNotification(metadata: metadata)
        }

        cancellableSet.insert(
            MainAppContext.shared.groupFeedFromGroupTabPresentRequest.sink { [weak self] (groupID) in
                guard let self = self else { return }
                guard let groupID = groupID else { return }
                self.navigationController?.popToRootViewController(animated: false)
                let vc = GroupFeedViewController(groupId: groupID)
                vc.delegate = self
                self.navigationController?.pushViewController(vc, animated: false)
            }
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("GroupsListViewController/viewWillAppear")
        super.viewWillAppear(animated)
        createSampleGroupIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        DDLogInfo("GroupsListViewController/viewWillDisappear")
        super.viewWillDisappear(animated)
        isVisible = false
        if(searchController.isActive && isSearchBarEmpty) {
            searchController.isActive = false
        }

    }

    private lazy var rightBarButtonItem: UIBarButtonItem = {
        let image = UIImage(named: "NavCreateGroup", in: nil, with: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))?.withTintColor(UIColor.primaryBlue, renderingMode: .alwaysOriginal)
        image?.accessibilityLabel = Localizations.chatCreateNewGroup
        let button = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(openNewGroupAction))
        return button
    }()

    // MARK: NUX

    private lazy var overlayContainer: OverlayContainer = {
        let overlayContainer = OverlayContainer()
        overlayContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayContainer)
        overlayContainer.constrain(to: view)
        return overlayContainer
    }()

    private lazy var emptyView: UIView = {
        let image = UIImage(named: "ChatEmpty")?.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.tintColor = UIColor.label.withAlphaComponent(0.2)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.text = Localizations.nuxGroupsListEmpty
        label.textAlignment = .center
        label.textColor = .secondaryLabel

        let stackView = UIStackView(arrangedSubviews: [imageView, label])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12

        return stackView
    }()

    private func installEmptyView() {
        view.addSubview(emptyView)

        emptyView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6).isActive = true
        emptyView.constrain([.centerX, .centerY], to: view)
    }

    private func updateEmptyView() {
        let isEmpty = (fetchedResultsController?.sections?.first?.numberOfObjects ?? 0) == 0
        emptyView.alpha = isEmpty ? 1 : 0
    }

    private func createSampleGroupIfNeeded() {
        let sharedNUX = MainAppContext.shared.nux
        let sharedUserData = MainAppContext.shared.userData

        // continue only if in zero zone or if groups list is empty
        let isZeroZone = sharedNUX.state == .zeroZone
        let isGroupsListEmpty = (fetchedResultsController?.sections?.first?.numberOfObjects ?? 0) == 0
        guard (isZeroZone || isGroupsListEmpty) else { return }

        // continue only if sample group hasn't been created
        let sampleGroupExist = sharedNUX.sampleGroupID() != nil
        guard !sampleGroupExist else { return }

        // secondary check if another group with the same name already exist
        // useful for edge cases like running demo multiple times or if user does a fresh re-install
        guard let allChats = fetchedResultsController?.fetchedObjects else { return }
        let sampleGroupName = Localizations.groupsNUXuserGroupName(sharedUserData.name)
        let groupWithSampleGroupNameExist = allChats.first(where: { $0.title == sampleGroupName }) != nil
        guard !groupWithSampleGroupNameExist else { return }

        // create sample group
        DDLogInfo("GroupsListViewController/viewWillAppear/NUX/creating sample group for user")
        MainAppContext.shared.chatData.createGroup(name: sampleGroupName, description: "", members: [], data: nil) { result in
            switch result {
            case .success(let groupID):
                sharedNUX.recordWelcomePost(id: groupID, type: .sampleGroup)
            case .failure(let error):
                DDLogError("GroupsListViewController/viewWillAppear/NUX/creating sample group error \(error)")
            }
        }
    }

    // MARK: Invite friends

    @objc
    private func startInviteFriendsFlow() {
        guard ContactStore.contactsAccessAuthorized else {
            let inviteVC = InvitePermissionDeniedViewController()
            present(UINavigationController(rootViewController: inviteVC), animated: true)
            return
        }
        InviteManager.shared.requestInvitesIfNecessary()
        let inviteVC = InviteViewController(manager: InviteManager.shared, dismissAction: { [weak self] in self?.dismiss(animated: true, completion: nil) })
        let navController = UINavigationController(rootViewController: inviteVC)
        present(navController, animated: true)
    }
    
    // MARK: Fetched Results Controller
    
    public var fetchRequest: NSFetchRequest<ChatThread> {
        let fetchRequest = NSFetchRequest<ChatThread>(entityName: "ChatThread")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "lastFeedTimestamp", ascending: false),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        fetchRequest.predicate = NSPredicate(format: "groupId != nil")
        return fetchRequest
    }

    private func setupFetchedResultsController() {
        fetchedResultsController = createFetchedResultsController()
        do {
            try fetchedResultsController?.performFetch()
            updateEmptyView()
        } catch {
            fatalError("GroupsListView/frc/setup failure: \(error)")
        }
    }

    private func createFetchedResultsController() -> NSFetchedResultsController<ChatThread> {
        let fetchedResultsController = NSFetchedResultsController<ChatThread>(fetchRequest: fetchRequest,
                                                                              managedObjectContext: MainAppContext.shared.chatData.viewContext,
                                                                              sectionNameKeyPath: nil,
                                                                              cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogVerbose("GroupsListView/frc/controllerDidChangeContent")
        reloadData(animated: false)
        updateEmptyView()
    }

    private func reloadData(animated: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            self?.reloadDataInMainQueue(animated: animated)
        }
    }

    private func reloadDataInMainQueue(animated: Bool = false) {
        var chatThreads: [ChatThread] = []
        var threadsOfFoundMembers: [ChatThread] = []

        if isFiltering {
            chatThreads.append(contentsOf: filteredChatsTitles.map {$0} )
            threadsOfFoundMembers.append(contentsOf: filteredChatsMembers.map {$0} )
        } else if let objects = fetchedResultsController?.fetchedObjects {
            chatThreads.append(contentsOf: objects.map {$0} )
        }

        var groupRows = [Row]()
        var groupRowsOfFoundMembers = [Row]()

        chatThreads.forEach { thread in
            guard let groupID = thread.groupId else { return }
            var threadData = ThreadData(type: .group, groupID: groupID, title: thread.title ?? "", lastFeedID: thread.lastFeedId ?? "", lastFeedStatus: thread.lastFeedStatus, lastFeedText: thread.lastFeedText ?? "", unreadFeedCount: thread.unreadFeedCount)
            if isFiltering {
                if let searchStr = searchController.searchBar.text?.trimmingCharacters(in: CharacterSet.whitespaces) {
                    threadData.type = .groupOfFoundTitle
                    threadData.searchStr = searchStr
                }
            }
            groupRows.append(Row.group(threadData))
        }

        if isFiltering, filteredChatsMembers.count > 0  {
            threadsOfFoundMembers.forEach { thread in
                guard let groupID = thread.groupId else { return }
                var threadDataOfFoundMembers = ThreadData(type: .groupOfFoundMember, groupID: groupID, title: thread.title ?? "", lastFeedID: thread.lastFeedId ?? "", lastFeedStatus: thread.lastFeedStatus, lastFeedText: thread.lastFeedText ?? "", unreadFeedCount: thread.unreadFeedCount)
                if let searchStr = searchController.searchBar.text?.trimmingCharacters(in: CharacterSet.whitespaces) {
                    threadDataOfFoundMembers.searchStr = searchStr
                }
                groupRowsOfFoundMembers.append(Row.group(threadDataOfFoundMembers))
            }
        }

        /* apply snapshot */
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
      
        snapshot.appendSections([ .groups ])
        snapshot.appendItems(groupRows, toSection: .groups)
        
        if isFiltering, filteredChatsMembers.count > 0  {
            snapshot.appendSections([ .groupsWithFoundMembers ])
            snapshot.appendItems(groupRowsOfFoundMembers, toSection: .groupsWithFoundMembers)
        }

        dataSource?.defaultRowAnimation = .fade
        dataSource?.apply(snapshot, animatingDifferences: animated)
    }

    // MARK: Actions
    
    @objc private func openNewGroupAction() {
        openNewGroup()
    }

    // MARK: Helpers
    
    func isScrolledFromTop(by fromTop: CGFloat) -> Bool {
        return tableView.contentOffset.y < fromTop
    }

    // MARK: Tap Notification
    
    private func processNotification(metadata: NotificationMetadata) {
        guard metadata.isGroupNotification else {
            return
        }
        
        // If the user tapped on a notification, move to group feed
        DDLogDebug("GroupsListViewController/processNotification/open group feed [\(metadata.groupId ?? "")], contentType: \(metadata.contentType)")

        navigationController?.popToRootViewController(animated: false)
        
        switch metadata.contentType {
        case .groupFeedPost, .groupFeedComment:
            if let groupId = metadata.groupId, let _ = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                let vc = GroupFeedViewController(groupId: groupId)
                vc.delegate = self
                self.navigationController?.pushViewController(vc, animated: false)
            }
            break
        case .groupAdd:
            if let groupId = metadata.groupId {
                if let _ = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                    openFeed(forGroupId: groupId)
                } else {
                    // for offline groupAdd notifications, the app needs some time to get and create the new group when the user
                    // taps on the notification so we just wait for the group event here.
                    DispatchQueue.main.async{
                        self.groupIdToPresent = groupId
                    }
                }
            }
            metadata.removeFromUserDefaults()
            break
        case .groupChatMessage:
            metadata.removeFromUserDefaults()
            break
        default:
            break
        }
        
//        metadata.removeFromUserDefaults()
    }

    private func openFeed(forGroupId groupId: GroupID) {
        let vc = GroupFeedViewController(groupId: groupId)
        vc.delegate = self
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openNewGroup() {
        guard ContactStore.contactsAccessAuthorized else {
            present(UINavigationController(rootViewController: NewGroupMembersPermissionDeniedController()), animated: true)
            return
        }
        let viewController = NewGroupMembersViewController(currentMembers: [])
        viewController.delegate = self
        present(UINavigationController(rootViewController: viewController), animated: true)
    }
}

extension GroupsListViewController: UIViewControllerScrollsToTop {
    func scrollToTop(animated: Bool) {
        let indexPath = IndexPath(row: 0, section: 0)
        guard indexPath.section < tableView.numberOfSections else { return }
        guard indexPath.row < tableView.numberOfRows(inSection: indexPath.section) else { return }
        tableView.scrollToRow(at: indexPath, at: .middle, animated: animated)
    }
}

extension GroupsListViewController: FeedCollectionViewControllerDelegate {
    func feedCollectionViewController(_ controller: FeedCollectionViewController, userActioned: Bool) {
        searchController.isActive = false
        DispatchQueue.main.async {
            self.scrollToTop(animated: false)
        }
    }
}

// MARK: Table Header Delegate
extension GroupsListViewController: GroupsListHeaderViewDelegate {
    func groupsListHeaderView(_ groupsListHeaderView: GroupsListHeaderView) {
        openNewGroup()
    }
}

// MARK: UITableView Delegates
extension GroupsListViewController: UITableViewDelegate {

    func chatThread(at indexPath: IndexPath) -> ChatThread? {
        
        if isFiltering {
            if (indexPath.section == 0 && filteredChatsTitles.count > 0) {
                return filteredChatsTitles[indexPath.row]
            } else if (indexPath.section == 1 && filteredChatsMembers.count > 0) {
                return filteredChatsMembers[indexPath.row]
            }
        }
        
        guard let fetchedObjects = fetchedResultsController?.fetchedObjects, indexPath.row < fetchedObjects.count else {
            return nil
        }
        return fetchedObjects[indexPath.row]
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: "sectionHeader") as! GroupsListHeaderView
        view.delegate = self
        return view
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return section == 1 ? CGFloat.leastNormalMagnitude : 25
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let chatThread = chatThread(at: indexPath) else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        guard let groupId = chatThread.groupId else { return }

        openFeed(forGroupId: groupId)

        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let chatThread = self.chatThread(at: indexPath) else { return UISwipeActionsConfiguration(actions: []) }
        guard let groupId = chatThread.groupId else { return UISwipeActionsConfiguration(actions: []) }
        
        let moreInfoAction = UIContextualAction(style: .normal, title: "") { [weak self] (_, _, completionHandler) in
            guard let self = self else { return }
            let vc = GroupInfoViewController(for: groupId)
            self.navigationController?.pushViewController(vc, animated: true)
            completionHandler(true)
        }
        moreInfoAction.backgroundColor = .primaryBlue
        moreInfoAction.image = UIImage(systemName: "ellipsis")

        let removeAction = UIContextualAction(style: .destructive, title: Localizations.buttonRemove) { [weak self] (_, _, completionHandler) in
            guard let self = self else { return }
            let actionSheet = UIAlertController(title: chatThread.title, message: Localizations.groupsListRemoveMessage, preferredStyle: .actionSheet)
            actionSheet.addAction(UIAlertAction(title: Localizations.buttonRemove, style: .destructive) { [weak self] action in
                guard let self = self else { return }
                // remove filters first since indexPath will not be valid anymore once group is deleted
                if self.isFiltering {
                    if (indexPath.section == 0 && self.filteredChatsTitles.count > 0) {
                        self.filteredChatsTitles.remove(at: indexPath.row)
                    } else {
                        self.filteredChatsMembers.remove(at: indexPath.row)
                    }
                }
                MainAppContext.shared.chatData.deleteChatGroup(groupId: groupId)
                self.tableView.reloadData()
            })
            actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
            self.present(actionSheet, animated: true)
            completionHandler(true)
        }

        if MainAppContext.shared.chatData.chatGroupMember(groupId: groupId, memberUserId: MainAppContext.shared.userData.userId) != nil {
            return UISwipeActionsConfiguration(actions: [moreInfoAction])
        } else {
            return UISwipeActionsConfiguration(actions: [removeAction])
        }
    }

    // resign keyboard so the entire tableview can be seen
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        searchController.searchBar.resignFirstResponder()
    }

}

// MARK: UISearchController SearchBar Delegates
extension GroupsListViewController: UISearchBarDelegate {
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.scrollToTop(animated: false)
        }
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
        searchBar.setCancelButtonTitleIfNeeded()
    }
}

// MARK: UISearchController Updating Delegates
extension GroupsListViewController: UISearchResultsUpdating {
    
    // room for improvement: searches can be debounced by 200ms so that not each keypress searches the whole list
    func updateSearchResults(for searchController: UISearchController) {
        guard let threads = fetchedResultsController?.fetchedObjects else { return }
        guard let searchBarText = searchController.searchBar.text else { return }
        let searchStr = searchBarText.trimmingCharacters(in: CharacterSet.whitespaces).lowercased()

        filteredChatsTitles = threads.filter {
            guard let title = $0.title else { return false }
            if title.lowercased().contains(searchStr) {
                return true
            }
            return false
        }

        let remainingThreads = Array(Set(threads).subtracting(filteredChatsTitles))

        filteredChatsMembers = remainingThreads.filter {
            guard let groupID = $0.groupId else { return false }
            let group = MainAppContext.shared.chatData.chatGroup(groupId: groupID)
            guard let members = group?.members else { return false }

            for member in members {
                let name = MainAppContext.shared.contactStore.fullName(for: member.userId)
                if name.lowercased().contains(searchStr) {
                    return true
                }
            }
            return false
        }

        reloadData(animated: false)
    }
}

// MARK: NewGroupMembersViewController Delegates
extension GroupsListViewController: NewGroupMembersViewControllerDelegate {
    func newGroupMembersViewController(_ viewController: NewGroupMembersViewController, selected: [UserID]) {}
    
    func newGroupMembersViewController(_ viewController: NewGroupMembersViewController, didCreateGroup: GroupID) {
        let vc = GroupFeedViewController(groupId: didCreateGroup)
        vc.delegate = self
        view.window?.rootViewController?.dismiss(animated: true, completion: nil)

        // skip animation to prevent user from having to see the groups list first
        navigationController?.pushViewController(vc, animated: false)
    }
}

fileprivate class GroupsListDataSource: UITableViewDiffableDataSource<Section, Row> {

    // when using UITableViewDiffableDataSource, canEditRowAt needs to be set to enable swipe to delete
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
}

fileprivate enum ThreadDataType {
    case group
    case groupOfFoundTitle
    case groupOfFoundMember
}

fileprivate struct ThreadData {
    var type: ThreadDataType
    let groupID: GroupID
    let title: String
    let lastFeedID: String
    let lastFeedStatus: ChatThread.LastFeedStatus
    let lastFeedText: String
    let unreadFeedCount: Int32
    var searchStr: String? = nil
}

extension ThreadData : Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(groupID)
    }
}

extension ThreadData : Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        return  lhs.groupID == rhs.groupID &&
                lhs.title == rhs.title &&
                lhs.lastFeedID == rhs.lastFeedID &&
                lhs.lastFeedStatus == rhs.lastFeedStatus &&
                lhs.lastFeedText == rhs.lastFeedText &&
                lhs.unreadFeedCount == rhs.unreadFeedCount &&
                lhs.searchStr == rhs.searchStr
    }
}

fileprivate enum Section: Hashable {
    case groups
    case groupsWithFoundMembers
}

fileprivate enum Row: Hashable, Equatable {
    case group(ThreadData)

    var group: ThreadData? {
        switch self {
        case .group(let threadData): return threadData
        }
    }
}

protocol GroupsListHeaderViewDelegate: AnyObject {
    func groupsListHeaderView(_ groupsListHeaderView: GroupsListHeaderView)
}

class GroupsListHeaderView: UITableViewHeaderFooterView {
    weak var delegate: GroupsListHeaderViewDelegate?
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    private func setup() {
        preservesSuperviewLayoutMargins = true

        vStack.addArrangedSubview(createGroupLabel)
        addSubview(vStack)

        vStack.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        vStack.isLayoutMarginsRelativeArrangement = true
        
        vStack.topAnchor.constraint(equalTo: topAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true

        let vStackBottomConstraint = vStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        vStackBottomConstraint.priority = UILayoutPriority(rawValue: 999)
        vStackBottomConstraint.isActive = true
    }
    
    private lazy var createGroupLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17)
        label.textColor = .systemBlue
        label.textAlignment = .right
        label.text = Localizations.chatCreateNewGroup
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.openNewGroupView(_:)))
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(tapGesture)

        return label
    }()

    private let vStack: UIStackView = {
        let view = UIStackView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical
        return view
    }()

    @objc func openNewGroupView (_ sender: UITapGestureRecognizer) {
        self.delegate?.groupsListHeaderView(self)
    }
}

extension Localizations {

    static func groupsNUXuserGroupName(_ username: String) -> String {
        return String(format: NSLocalizedString("groups.NUX.user.group.name", value: "%@'s Group", comment: "The name of the group that is created for the user when they are new and in the zero zone (no contacts and no content)"), username)
    }

    static var groupsListRemoveMessage: String {
        NSLocalizedString("groups.list.remove.message", value: "Are you sure you want to remove this group and its content from your device?", comment: "Text shown when user is about to remove the group")
    }

}
