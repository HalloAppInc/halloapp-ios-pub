//
//  GroupsListViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 1/12/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import SwiftUI
import UIKit

fileprivate struct Constants {
    static let AvatarSize: CGFloat = 56
    static let LastMsgFont = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize + 1) // 14
    static let LastMsgColor = UIColor.secondaryLabel
}

fileprivate enum ChatListViewSection {
    case main
}

class GroupsListViewController: UIViewController, NSFetchedResultsControllerDelegate {

    private static let cellReuseIdentifier = "ThreadListCell"
    private static let inviteFriendsReuseIdentifier = "GroupsListInviteFriendsCell"
    private let tableView = UITableView(frame: CGRect.zero, style: .grouped)
    
    private var fetchedResultsController: NSFetchedResultsController<ChatThread>?
    
    private var isVisible: Bool = false
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var filteredChats: [ChatThread] = []
    private var searchController: HAUISearchController!
    
    private var isSearchBarEmpty: Bool {
        return searchController.searchBar.text?.isEmpty ?? true
    }
    private var isFiltering: Bool {
        return searchController.isActive && !isSearchBarEmpty
    }
        
    // MARK: Lifecycle
    
    init(title: String) {
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("GroupsListViewController/viewDidLoad")

        navigationItem.standardAppearance = .transparentAppearance
        navigationItem.standardAppearance?.backgroundColor = UIColor.feedBackground
        installLargeTitleUsingGothamFont()
        
        searchController = HAUISearchController(searchResultsController: nil)
        searchController.delegate = self
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .none
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.definesPresentationContext = true
        searchController.hidesNavigationBarDuringPresentation = false

        searchController.searchBar.showsCancelButton = false
        
        searchController.searchBar.backgroundImage = UIImage()
        searchController.searchBar.searchTextField.backgroundColor = .searchBarBg

        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.constrain(to: view)

        installEmptyView()
        installFloatingActionMenu()
        
        tableView.register(GroupsListHeaderView.self, forHeaderFooterViewReuseIdentifier: "sectionHeader")
        tableView.register(ThreadListCell.self, forCellReuseIdentifier: GroupsListViewController.cellReuseIdentifier)
        tableView.delegate = self
        tableView.dataSource = self
        
        tableView.backgroundView = UIView() // fixes issue where bg color was off when pulled down from top
        tableView.backgroundColor = .primaryBg
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0) // -10 to hide top padding on searchBar
                
        tableView.tableHeaderView = searchController.searchBar
        tableView.tableHeaderView?.layoutMargins = UIEdgeInsets(top: 0, left: 21, bottom: 0, right: 21) // requested to be 21
        
        setupFetchedResultsController()
                
        // When the user was on this view
        cancellableSet.insert(
            MainAppContext.shared.didTapNotification.sink { [weak self] (metadata) in
                guard let self = self else { return }
                self.processNotification(metadata: metadata)
            }
        )
        
        // When the user was not on this view, and HomeView sends user to here
        if let metadata = NotificationMetadata.fromUserDefaults() {
            processNotification(metadata: metadata)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("GroupsListViewController/viewWillAppear")
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
//        showNUXIfNecessary()
    }

    override func viewWillDisappear(_ animated: Bool) {
        DDLogInfo("GroupsListViewController/viewWillDisappear")
        super.viewWillDisappear(animated)
        isVisible = false

        floatingMenu.setState(.collapsed, animated: true)
        
        searchController.isActive = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == tableView {
            updateNavigationBarStyleUsing(scrollView: scrollView)
        }
    }

    // MARK: NUX

    private lazy var overlayContainer: OverlayContainer = {
        let overlayContainer = OverlayContainer()
        overlayContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayContainer)
        overlayContainer.constrain(to: view)
        return overlayContainer
    }()

    private func showNUXIfNecessary() {
        if MainAppContext.shared.nux.isIncomplete(.chatListIntro) {
            let popover = NUXPopover(Localizations.nuxChatIntroContent) { MainAppContext.shared.nux.didComplete(.chatListIntro) }
            overlayContainer.display(popover)
        }
    }

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


    // MARK: New Chat

    private lazy var floatingMenu: FloatingMenu = {
        FloatingMenu(
            permanentButton: .standardActionButton(
                iconTemplate: UIImage(named: "icon_fab_group_add")?.withRenderingMode(.alwaysTemplate),
                accessibilityLabel: Localizations.fabAccessibilityNewGroup,
                action: { [weak self] in self?.openNewGroup() }))
    }()

    private func installFloatingActionMenu() {
        floatingMenu.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingMenu)
        floatingMenu.constrain(to: view)
    }

    // MARK: Invite friends

    @objc
    private func startInviteFriendsFlow() {
        InviteManager.shared.requestInvitesIfNecessary()
        let inviteView = InvitePeopleView(dismiss: { [weak self] in self?.dismiss(animated: true, completion: nil) })
        let inviteVC = UIHostingController(rootView: inviteView)
        let navController = UINavigationController(rootViewController: inviteVC)
        present(navController, animated: true)
    }
    
    // MARK: Fetched Results Controller
    
    public var fetchRequest: NSFetchRequest<ChatThread> {
        let fetchRequest = NSFetchRequest<ChatThread>(entityName: "ChatThread")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "lastFeedTimestamp", ascending: false),
            NSSortDescriptor(key: "lastMsgTimestamp", ascending: false),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        fetchRequest.predicate = NSPredicate(format: "groupId != nil")
        return fetchRequest
    }

    private var trackPerRowFRCChanges = false

    private var reloadTableViewInDidChangeContent = false

    private func setupFetchedResultsController() {
        fetchedResultsController = createFetchedResultsController()
        do {
            try fetchedResultsController?.performFetch()
            updateEmptyView()
        } catch {
            fatalError("Failed to fetch thread items \(error)")
        }
    }

    private func createFetchedResultsController() -> NSFetchedResultsController<ChatThread> {
        // Setup fetched results controller the old way because it allows granular control over UI update operations.
        let fetchedResultsController = NSFetchedResultsController<ChatThread>(fetchRequest: fetchRequest,
                                                                              managedObjectContext: MainAppContext.shared.chatData.viewContext,
                                                                              sectionNameKeyPath: nil,
                                                                              cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        reloadTableViewInDidChangeContent = false
        trackPerRowFRCChanges = self.view.window != nil && UIApplication.shared.applicationState == .active
        DDLogDebug("GroupsListView/frc/will-change perRowChanges=[\(trackPerRowFRCChanges)]")
        
        if trackPerRowFRCChanges {
            tableView.beginUpdates()
        }

        updateEmptyView()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            guard let indexPath = newIndexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("GroupsListView/frc/insert [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] at [\(indexPath)]")
            if trackPerRowFRCChanges && !isFiltering {
                tableView.insertRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .delete:
            guard let indexPath = indexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("GroupsListView/frc/delete [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] at [\(indexPath)]")
      
            if trackPerRowFRCChanges && !isFiltering {
                tableView.deleteRows(at: [ indexPath ], with: .left)
            } else {
                reloadTableViewInDidChangeContent = true
            }
            
        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("GroupsListView/frc/move [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges && !isFiltering {
                tableView.moveRow(at: fromIndexPath, to: toIndexPath)
                reloadTableViewInDidChangeContent = true
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .update:
            guard let indexPath = indexPath, let chatThread = anObject as? ChatThread else { return }
            DDLogDebug("GroupsListView/frc/update [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] at [\(indexPath)]")

            reloadTableViewInDidChangeContent = true
        default:
            break
        }

        updateEmptyView()
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogDebug("GroupsListView/frc/did-change perRowChanges=[\(trackPerRowFRCChanges)]  reload=[\(reloadTableViewInDidChangeContent)]")
        if trackPerRowFRCChanges {
            tableView.endUpdates()
        }
        if reloadTableViewInDidChangeContent || isFiltering {
            tableView.reloadData()
        }

        updateEmptyView()
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
        DDLogInfo("GroupsListViewController/processNotification/open group feed [\(metadata.groupId ?? "")]")

        navigationController?.popToRootViewController(animated: false)
        
        switch metadata.contentType {
        case .groupFeedPost, .groupFeedComment:
            if let groupId = metadata.groupId, let _ = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                self.navigationController?.pushViewController(GroupFeedViewController(groupId: groupId), animated: false)
            }
            break
        case .groupAdd:
            if let groupId = metadata.groupId, let _ = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                self.navigationController?.pushViewController(GroupFeedViewController(groupId: groupId), animated: false)
            } else {
                // for offline groupAdd notifications, the app needs some time to get and create the new group when the user
                // taps on the notification so we do a simple retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if let groupId = metadata.groupId, let _ = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                        self.navigationController?.pushViewController(GroupFeedViewController(groupId: groupId), animated: false)
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
        let viewController = GroupFeedViewController(groupId: groupId)
        viewController.hidesBottomBarWhenPushed = false
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func openProfile(forUserId userId: UserID) {
        let viewController = UserFeedViewController(userId: userId)
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    private func openNewGroup() {
        let viewController = NewGroupMembersViewController(currentMembers: [])
        viewController.delegate = self
        present(UINavigationController(rootViewController: viewController), animated: true)
    }
}

extension GroupsListViewController: UIViewControllerScrollsToTop {

    func scrollToTop(animated: Bool) {
        guard let firstSection = fetchedResultsController?.sections?.first else { return }
        guard firstSection.numberOfObjects > 0 else { return }
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .middle, animated: animated)
    }
}

// MARK: Table Header Delegate
extension GroupsListViewController: GroupsListHeaderViewDelegate {
    func groupsListHeaderView(_ groupsListHeaderView: GroupsListHeaderView) {
        openNewGroup()
    }
}

// MARK: UITableView Delegates
extension GroupsListViewController: UITableViewDelegate, UITableViewDataSource {
    
    func chatThread(at indexPath: IndexPath) -> ChatThread? {
        
        if isFiltering {
            return filteredChats[indexPath.row]
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
        return 25
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        
        if isFiltering {
            return 1
        }
        
        return fetchedResultsController?.sections?.count ?? 0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        if isFiltering {
            return filteredChats.count
        }
        
        guard let sections = fetchedResultsController?.sections else { return 0 }
        return sections[section].numberOfObjects + 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let chatThread = chatThread(at: indexPath) else {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.isHidden = true
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: GroupsListViewController.cellReuseIdentifier, for: indexPath) as! ThreadListCell

        cell.configureAvatarSize(Constants.AvatarSize)
        cell.configureForGroupsList(with: chatThread, squareSize: Constants.AvatarSize)
  
        if isFiltering {
            let strippedString = searchController.searchBar.text!.trimmingCharacters(in: CharacterSet.whitespaces)
            let searchItems = strippedString.components(separatedBy: " ")
            cell.highlightTitle(searchItems)
        }
        
        switch chatThread.type {
        case .oneToOne:
            cell.avatarTappedAction = { [weak self] in
                guard let self = self, let userId = chatThread.chatWithUserId else { return }
                self.openProfile(forUserId: userId)
            }
        case .group:
            let groupId = chatThread.groupId
            cell.avatarTappedAction = { [weak self] in
                guard let self = self, let groupId = groupId else { return }
                self.openFeed(forGroupId: groupId)
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        guard let chatThread = chatThread(at: indexPath) else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        
        switch chatThread.type {
        case .oneToOne:
            guard let chatWithUserId = chatThread.chatWithUserId else { return }
            let vc = ChatViewController(for: chatWithUserId, with: nil, at: 0)
            vc.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(vc, animated: true)
        case .group:
            guard let groupId = chatThread.groupId else { return }
            openFeed(forGroupId: groupId)
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if (editingStyle == .delete) {
            let actionSheet = UIAlertController(title: "Are you sure you want to clear this group?", message: nil, preferredStyle: .actionSheet)
            actionSheet.addAction(UIAlertAction(title: "Clear Group", style: .destructive) { [weak self] action in
                guard let self = self else { return }
                if let chatThread = self.chatThread(at: indexPath) {
                    if chatThread.type == .oneToOne {
                        guard let chatWithUserId = chatThread.chatWithUserId else { return }
                        MainAppContext.shared.chatData.deleteChat(chatThreadId: chatWithUserId)
                    } else {
                        guard let groupId = chatThread.groupId else { return }
                        MainAppContext.shared.chatData.deleteChatGroup(groupId: groupId)
                    }
                }
                
                if self.isFiltering {
                    self.filteredChats.remove(at: indexPath.row)
                }
                
            })
            actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
            present(actionSheet, animated: true)
        }
    }
    
    // resign keyboard so the entire tableview can be seen
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        searchController.searchBar.resignFirstResponder()
    }

}

extension GroupsListViewController: UISearchControllerDelegate {
    func willDismissSearchController(_ searchController: UISearchController) {
        searchController.dismiss(animated: false, completion: {
        })
    }

}

// MARK: Search Updating Delegates
extension GroupsListViewController: UISearchResultsUpdating {
    
    func updateSearchResults(for searchController: UISearchController) {
        guard let allChats = fetchedResultsController?.fetchedObjects else { return }
        guard let searchBarText = searchController.searchBar.text else { return }
    
        let strippedString = searchBarText.trimmingCharacters(in: CharacterSet.whitespaces)
        
        let searchItems = strippedString.components(separatedBy: " ")
        
        filteredChats = allChats.filter {
            var titleText: String? = nil
            if $0.type == .group {
                titleText = $0.title
            } else {
                titleText = MainAppContext.shared.contactStore.fullName(for: $0.chatWithUserId ?? "")
            }

            guard let title = titleText else { return false }
        
            for item in searchItems {
                if title.lowercased().contains(item.lowercased()) {
                    return true
                }
            }
            return false
        }
        DDLogDebug("GroupsListViewController/updateSearchResults/filteredChats count \(filteredChats.count) for: \(searchBarText)")
        
        tableView.reloadData()
    }
}

extension GroupsListViewController: NewGroupMembersViewControllerDelegate {
    func newGroupMembersViewController(_ viewController: NewGroupMembersViewController, selected: [UserID]) {}
    
    func newGroupMembersViewController(_ viewController: NewGroupMembersViewController, didCreateGroup: GroupID) {
        navigationController?.pushViewController(GroupFeedViewController(groupId: didCreateGroup), animated: true)
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

        vStack.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 20)
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

private class HAUISearchController: UISearchController {
    override func viewWillDisappear(_ animated: Bool) {
        // to avoid black screen when switching tabs while searching
        isActive = false
        dismiss(animated: false, completion: nil)
    }
}
