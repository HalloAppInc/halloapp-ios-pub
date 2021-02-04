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
    private let tableView = UITableView()
    
    private var fetchedResultsController: NSFetchedResultsController<ChatThread>?
    
    private var isVisible: Bool = false
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var filteredChats: [ChatThread] = []
    private var searchController: UISearchController!
    private var searchBarHeight: CGFloat = 0
    
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
        
        searchController = UISearchController(searchResultsController: nil)
        searchController.delegate = self
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .none
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.definesPresentationContext = true
        searchController.hidesNavigationBarDuringPresentation = false

        searchController.searchBar.showsCancelButton = false
        
        searchController.searchBar.searchTextField.backgroundColor = .searchBarBg

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        
        searchBarHeight = searchController.searchBar.frame.height
        
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.constrain(to: view)

        installEmptyView()
        installFloatingActionMenu()
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)

        tableView.backgroundColor = .feedBackground
        tableView.separatorStyle = .none
        tableView.register(ThreadListCell.self, forCellReuseIdentifier: GroupsListViewController.cellReuseIdentifier)
        tableView.delegate = self
        tableView.dataSource = self
        
        let groupsListHeaderView = GroupsListHeaderView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: 21)) // height is 21, not 20, as requested
        groupsListHeaderView.delegate = self
        tableView.tableHeaderView = groupsListHeaderView
        
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
        
        // after showing searchbar on top, turn on hidesSearchBarWhenScrolling so search will disappear when scrolling
        navigationItem.hidesSearchBarWhenScrolling = true
        
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
        label.text = Localizations.nuxChatEmpty
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
                action: { [weak self] in self?.showContacts() }))
    }()

    private func installFloatingActionMenu() {
        floatingMenu.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingMenu)
        floatingMenu.constrain(to: view)
    }

    private func showContacts() {
        present(UINavigationController(rootViewController: NewGroupMembersViewController(currentMembers: [])), animated: true)
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
            if trackPerRowFRCChanges && !isFiltering {
                tableView.reloadRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

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

    private var lastCheckedForNewContacts: Date?
        
    // MARK: Helpers
    
    func isScrolledFromTop(by fromTop: CGFloat) -> Bool {
        return tableView.contentOffset.y < fromTop
    }

    // MARK: Tap Notification
    
    private func processNotification(metadata: NotificationMetadata) {
        guard metadata.isGroupNotification else {
            return
        }

        // If the user tapped on a notification, move to the chat view
        DDLogInfo("GroupsListViewController/notification/open-chat \(metadata.fromId)")

        navigationController?.popToRootViewController(animated: false)
        
        switch metadata.contentType {
        case .groupFeedPost, .groupFeedComment:
            if let groupId = metadata.groupId, let _ = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                navigationController?.pushViewController(GroupFeedViewController(groupId: groupId), animated: false)
            }
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
}

extension GroupsListViewController: UIViewControllerScrollsToTop {

    func scrollToTop(animated: Bool) {
        guard let firstSection = fetchedResultsController?.sections?.first else { return }
        guard firstSection.numberOfObjects > 0 else { return }

        guard let keyWindow = UIApplication.shared.windows.filter({$0.isKeyWindow}).first else { return }
        let safeAreaHeight = keyWindow.safeAreaInsets.top
        guard let navHeight = navigationController?.navigationBar.frame.size.height else { return }

        var searchHeight: CGFloat = 0

        // when search is visible navHeight contains the searchBarHeight already but not when table is scrolled up
        if searchController.searchBar.frame.height == 0 {
            searchHeight = searchBarHeight
        }

        let fromTop = CGFloat(safeAreaHeight) + CGFloat(navHeight) + CGFloat(searchHeight)

        let offsetFromTop = CGPoint(x: 0, y: -(fromTop))

        if tableView.contentOffset.y <= offsetFromTop.y { return }

        // use row instead of offset to get to the top since table can change size after reloads
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: animated)

        // after scrolling to the first row, move offset so the searchBar is shown
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self = self else { return }
            self.tableView.setContentOffset(offsetFromTop, animated: animated)
        }
    }
}

// MARK: Table Header Delegate
extension GroupsListViewController: GroupsListHeaderViewDelegate {
    func groupsListHeaderView(_ groupsListHeaderView: GroupsListHeaderView) {
        present(UINavigationController(rootViewController: NewGroupMembersViewController()), animated: true)
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

extension GroupsListViewController: NewChatViewControllerDelegate {
    func newChatViewController(_ controller: NewChatViewController, didSelect userId: UserID) {
        controller.dismiss(animated: true) {
            let vc = ChatViewController(for: userId)
            self.navigationController?.pushViewController(vc, animated: true)
            DispatchQueue.main.async {
                vc.showKeyboard()
            }
        }
    }
}

protocol GroupsListHeaderViewDelegate: AnyObject {
    func groupsListHeaderView(_ groupsListHeaderView: GroupsListHeaderView)
}

class GroupsListHeaderView: UIView {
    weak var delegate: GroupsListHeaderViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    private func setup() {
        preservesSuperviewLayoutMargins = true

        vStack.addArrangedSubview(textLabel)
        addSubview(vStack)

        vStack.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 20)
        vStack.isLayoutMarginsRelativeArrangement = true
        
        vStack.topAnchor.constraint(equalTo: topAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true

        let vStackBottomConstraint = vStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        vStackBottomConstraint.priority = UILayoutPriority(rawValue: 999)
        vStackBottomConstraint.isActive = true
    }
    
    private lazy var textLabel: UILabel = {
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
        let vStack = UIStackView()
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        return vStack
    }()

    @objc func openNewGroupView (_ sender: UITapGestureRecognizer) {
        self.delegate?.groupsListHeaderView(self)
    }
}
