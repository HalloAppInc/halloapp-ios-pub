//
//  ChatListViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/25/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import SwiftUI
import UIKit

fileprivate struct Constants {
    static let AvatarSize: CGFloat = 50
    static let LastMsgFont = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize + 1) // 14
    static let LastMsgColor = UIColor.secondaryLabel
}

fileprivate enum ChatListViewSection {
    case main
}

class ChatListViewController: UIViewController, NSFetchedResultsControllerDelegate {

    private static let cellReuseIdentifier = "ChatListViewCell"
    private static let inviteFriendsReuseIdentifier = "ChatListInviteFriendsCell"
    private let tableView = UITableView()
    
    private var fetchedResultsController: NSFetchedResultsController<ChatThread>?
    
    private var isVisible: Bool = false
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var filteredChats: [ChatThread] = []
    private var searchController: DismissableUISearchController!
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
        DDLogInfo("ChatListViewController/viewDidLoad")

        navigationItem.standardAppearance = .transparentAppearance
        navigationItem.standardAppearance?.backgroundColor = UIColor.feedBackground
        
        searchController = DismissableUISearchController(searchResultsController: nil)
        searchController.delegate = self
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .none
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.definesPresentationContext = true
        searchController.hidesNavigationBarDuringPresentation = false

        // set bg first before cornerRadius due to ios 13 bug where corners get reset by bg
        searchController.searchBar.setSearchFieldBackgroundImage(UIImage(), for: .normal)
        
        searchController.searchBar.searchTextField.layer.cornerRadius = 20
        searchController.searchBar.searchTextField.layer.masksToBounds = true
        searchController.searchBar.searchTextField.backgroundColor = .secondarySystemGroupedBackground
        
        searchController.searchBar.backgroundColor = .feedBackground
        searchController.searchBar.tintColor = UIColor.systemBlue
        
//        searchController.searchBar.setImage(UIImage(systemName: "xmark"), for: .clear, state: .normal)
        searchController.searchBar.showsCancelButton = false

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        
        searchBarHeight = searchController.searchBar.frame.height
        
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.constrain(to: view)

        installLargeTitleUsingGothamFont()
        installEmptyView()
        installFloatingActionMenu()
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)

        tableView.backgroundColor = .feedBackground
        tableView.separatorStyle = .none
        tableView.register(ChatListTableViewCell.self, forCellReuseIdentifier: ChatListViewController.cellReuseIdentifier)
        tableView.register(ChatListInviteFriendsTableViewCell.self, forCellReuseIdentifier: ChatListViewController.inviteFriendsReuseIdentifier)
        tableView.delegate = self
        tableView.dataSource = self
        
        if ServerProperties.isInternalUser || ServerProperties.isGroupsEnabled {
            let chatListHeaderView = ChatListHeaderView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: 20))
            chatListHeaderView.delegate = self
            tableView.tableHeaderView = chatListHeaderView
        }
        
        setupFetchedResultsController()
        
        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetChatStateInfo.sink { [weak self] in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.updateVisibleCellsWithTypingIndicator()
                }
            }
        )
        
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
        DDLogInfo("ChatListViewController/viewWillAppear")
        super.viewWillAppear(animated)
        populateWithSymmetricContacts()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        DDLogInfo("ChatListViewController/viewDidAppear")
        super.viewDidAppear(animated)
        isVisible = true
        
        // after showing searchbar on top, turn on hidesSearchBarWhenScrolling so search will disappear when scrolling
        navigationItem.hidesSearchBarWhenScrolling = true
        
        showNUXIfNecessary()
    }

    override func viewWillDisappear(_ animated: Bool) {
        DDLogInfo("ChatListViewController/viewWillDisappear")
        super.viewWillDisappear(animated)
        isVisible = false

        floatingMenu.setState(.collapsed, animated: true)
        
        searchController.isActive = false
        searchController.searchBar.text = ""
        searchController.dismiss(animated: false)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == tableView {
            updateNavigationBarStyleUsing(scrollView: scrollView)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if (traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection)) {
            searchController.searchBar.layer.borderColor = UIColor.feedBackground.cgColor
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
                iconTemplate: UIImage(named: "icon_fab_compose_message")?.withRenderingMode(.alwaysTemplate),
                accessibilityLabel: Localizations.fabAccessibilityNewMessage,
                action: { [weak self] in self?.showContacts() }))
    }()

    private func installFloatingActionMenu() {
        floatingMenu.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingMenu)
        floatingMenu.constrain(to: view)
    }

    private func showContacts() {
        present(UINavigationController(rootViewController: NewChatViewController(delegate: self)), animated: true)
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
            NSSortDescriptor(key: "isNew", ascending: false),
            NSSortDescriptor(key: "lastMsgTimestamp", ascending: false),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        fetchRequest.predicate = NSPredicate(format: "groupId != nil || chatWithUserId != nil")
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
            fatalError("Failed to fetch feed items \(error)")
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
        DDLogDebug("ChatListView/frc/will-change perRowChanges=[\(trackPerRowFRCChanges)]")
        
        if trackPerRowFRCChanges {
            tableView.beginUpdates()
        }

        updateEmptyView()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            guard let indexPath = newIndexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("ChatListView/frc/insert [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                tableView.insertRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .delete:
            guard let indexPath = indexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("ChatListView/frc/delete [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] at [\(indexPath)]")
      
            if trackPerRowFRCChanges {
                tableView.deleteRows(at: [ indexPath ], with: .left)
            } else {
                reloadTableViewInDidChangeContent = true
            }
            
        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("ChatListView/frc/move [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges {
                tableView.moveRow(at: fromIndexPath, to: toIndexPath)
                reloadTableViewInDidChangeContent = true
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .update:
            guard let indexPath = indexPath, let chatThread = anObject as? ChatThread else { return }
            DDLogDebug("ChatListView/frc/update [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] at [\(indexPath)]")
            if trackPerRowFRCChanges {
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
        DDLogDebug("ChatListView/frc/did-change perRowChanges=[\(trackPerRowFRCChanges)]  reload=[\(reloadTableViewInDidChangeContent)]")
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
    
    private func populateWithSymmetricContacts() {
        var isTimeToCheck = true
        if let lastCheckedForNewContacts = lastCheckedForNewContacts {
            isTimeToCheck = abs(lastCheckedForNewContacts.timeIntervalSinceNow) >= Date.minutes(1)
        }
        
        if isTimeToCheck {
            DDLogDebug("ChatListViewController/populateWithSymmetricContacts")
            MainAppContext.shared.chatData.populateThreadsWithSymmetricContacts()
            lastCheckedForNewContacts = Date()
        }
    }
    
    private func updateVisibleCellsWithTypingIndicator() {
        guard isVisible else { return }
        for tableCell in tableView.visibleCells {
            guard let cell = tableCell as? ChatListTableViewCell else { continue }
            guard let chatThread = cell.chatThread else { continue }
            updateCellWithChatState(cell: cell, chatThread: chatThread)
        }
    }
    
    private func updateCellWithChatState(cell: ChatListTableViewCell, chatThread: ChatThread) {
        var typingIndicatorStr: String? = nil
        
        if chatThread.type == .oneToOne {
            typingIndicatorStr = MainAppContext.shared.chatData.getTypingIndicatorString(type: chatThread.type, id: chatThread.chatWithUserId)
        } else if chatThread.type == .group {
            typingIndicatorStr = MainAppContext.shared.chatData.getTypingIndicatorString(type: chatThread.type, id: chatThread.groupId)
        }

        if typingIndicatorStr == nil && !cell.isShowingTypingIndicator {
            return
        }
        
        cell.configureTypingIndicator(typingIndicatorStr)
    }
   
    // MARK: Tap Notification
    
    private func processNotification(metadata: NotificationMetadata) {
        guard metadata.isChatNotification else {
            return
        }

        // If the user tapped on a notification, move to the chat view
        DDLogInfo("ChatListViewController/notification/open-chat \(metadata.fromId)")

        navigationController?.popToRootViewController(animated: false)

        if metadata.contentType == .chatMessage {
            navigationController?.pushViewController(ChatViewController(for: metadata.fromId, with: nil, at: 0), animated: true)
        } else if metadata.contentType == .groupChatMessage, let groupId = metadata.groupId {
            navigationController?.pushViewController(ChatGroupViewController(for: groupId), animated: true)
        }
        metadata.removeFromUserDefaults()
    }

    private func openFeed(forGroupId groupId: GroupID) {
        let viewController = GroupFeedViewController(groupId: groupId)
        viewController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func openProfile(forUserId userId: UserID) {
        let viewController = UserFeedViewController(userId: userId)
        navigationController?.pushViewController(viewController, animated: true)
    }
}

extension ChatListViewController: UIViewControllerScrollsToTop {

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.tableView.setContentOffset(offsetFromTop, animated: animated)
        }
    }
}

// MARK: Table Header Delegate
extension ChatListViewController: ChatListHeaderViewDelegate {
    func chatListHeaderView(_ chatListHeaderView: ChatListHeaderView) {
        present(UINavigationController(rootViewController: NewGroupMembersViewController()), animated: true)
    }
}

// MARK: UITableView Delegates
extension ChatListViewController: UITableViewDelegate, UITableViewDataSource {
    
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
            let cell = tableView.dequeueReusableCell(withIdentifier: ChatListViewController.inviteFriendsReuseIdentifier, for: indexPath)
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatListViewController.cellReuseIdentifier, for: indexPath) as! ChatListTableViewCell

        cell.configure(with: chatThread)
        updateCellWithChatState(cell: cell, chatThread: chatThread)
  
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
            // Must be invite friends cell
            startInviteFriendsFlow()
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        
        if chatThread.type == .oneToOne {
            guard let chatWithUserId = chatThread.chatWithUserId else { return }
            let vc = ChatViewController(for: chatWithUserId, with: nil, at: 0)
            vc.hidesBottomBarWhenPushed = true
            self.navigationController?.pushViewController(vc, animated: true)
        } else {
            guard let groupId = chatThread.groupId else { return }
            let vc = ChatGroupViewController(for: groupId)
            vc.hidesBottomBarWhenPushed = true
            self.navigationController?.pushViewController(vc, animated: true)
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if (editingStyle == .delete) {
            let actionSheet = UIAlertController(title: "Are you sure you want to delete this chat?", message: nil, preferredStyle: .actionSheet)
            actionSheet.addAction(UIAlertAction(title: "Delete Chat", style: .destructive) { [weak self] action in
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

extension ChatListViewController: UISearchControllerDelegate {
    func willDismissSearchController(_ searchController: UISearchController) {
        searchController.dismiss(animated: false, completion: {
        })
    }

}

// MARK: Search Updating Delegates
extension ChatListViewController: UISearchResultsUpdating {
    
    func updateSearchResults(for searchController: UISearchController) {
        DDLogDebug("ChatListViewController/updateSearchResults")
        guard let allChats = fetchedResultsController?.fetchedObjects else { return }
        guard let searchBarText = searchController.searchBar.text else { return }
    
        DDLogDebug("ChatListViewController/updateSearchResults/searchBarText \(searchBarText)")
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
        DDLogDebug("ChatListViewController/updateSearchResults/filteredChats count \(filteredChats.count)")
        
        tableView.reloadData()
    }
}

extension ChatListViewController: NewChatViewControllerDelegate {
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

protocol ChatListHeaderViewDelegate: AnyObject {
    func chatListHeaderView(_ chatListHeaderView: ChatListHeaderView)
}

class ChatListHeaderView: UIView {
    weak var delegate: ChatListHeaderViewDelegate?
    
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
        label.font = UIFont.systemFont(ofSize: 15)
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
        self.delegate?.chatListHeaderView(self)
    }
}

private class ChatListInviteFriendsTableViewCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    lazy var iconView: UIImageView = {
        let image = UIImage(named: "AddFriend")?
            .withRenderingMode(.alwaysTemplate)
            .imageFlippedForRightToLeftLayoutDirection()
        let view = UIImageView(image: image)
        view.contentMode = .center
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = Constants.AvatarSize / 2
        view.tintColor = .white
        view.backgroundColor = .systemBlue
        return view
    }()

    lazy var label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = Localizations.inviteFriendsAndFamily
        label.font = .gothamFont(forTextStyle: .subheadline, weight: .medium)
        label.numberOfLines = 0
        label.textColor = .systemBlue
        return label
    }()

    private func setup() {
        backgroundColor = .clear

        contentView.addSubview(iconView)
        contentView.addSubview(label)

        contentView.addConstraints([
            iconView.widthAnchor.constraint(equalToConstant: Constants.AvatarSize),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            iconView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 8),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            label.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
    }
}

private class ChatListTableViewCell: UITableViewCell {

    public var chatThread: ChatThread? = nil
    public var isShowingTypingIndicator: Bool = false
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()

        chatThread = nil
        isShowingTypingIndicator = false
        
        nameLabel.attributedText = nil
        
        timeLabel.text = nil
        lastMsgLabel.text = nil
        unreadCountView.isHidden = true
        
        avatarView.avatarView.prepareForReuse()
    }

    // 14 points for font
    private func lastMessageText(for chatThread: ChatThread) -> NSAttributedString {

        var contactNamePart = ""
        if chatThread.type == .group {
            if let userId = chatThread.lastMsgUserId, userId != MainAppContext.shared.userData.userId {
                contactNamePart = MainAppContext.shared.contactStore.fullName(for: userId) + ": "
            }
        }

        var messageText = chatThread.lastMsgText ?? Localizations.chatListMessageDefault(name: chatThread.title)
        
        if [.retracting, .retracted].contains(chatThread.lastMsgStatus) {
            messageText = Localizations.chatMessageDeleted
        }
        
        var mediaIcon: UIImage?
        switch chatThread.lastMsgMediaType {
        case .image:
            mediaIcon = UIImage(systemName: "photo")
            if messageText.isEmpty {
                messageText = Localizations.chatMessagePhoto
            }

        case .video:
            mediaIcon = UIImage(systemName: "video.fill")
            if messageText.isEmpty {
                messageText = Localizations.chatMessageVideo
            }

        default:
            break
        }

        let messageStatusIcon: UIImage? = {
            switch chatThread.lastMsgStatus {
            case .seen:
                return UIImage(named: "CheckmarkDouble")?.withTintColor(.chatOwnMsg)

            case .delivered:
                return UIImage(named: "CheckmarkDouble")?.withTintColor(UIColor.chatOwnMsg.withAlphaComponent(0.4))

            case .sentOut:
                return UIImage(named: "CheckmarkSingle")?.withTintColor(UIColor.chatOwnMsg.withAlphaComponent(0.4))

            default:
                return nil
            }
        }()

        let result = NSMutableAttributedString(string: contactNamePart)

        if let mediaIcon = mediaIcon {
            result.append(NSAttributedString(attachment: NSTextAttachment(image: mediaIcon)))
            result.append(NSAttributedString(string: " "))
        }

        if let messageStatusIcon = messageStatusIcon {
            let imageSize = messageStatusIcon.size
            let scale = Constants.LastMsgFont.capHeight / imageSize.height

            let iconAttachment = NSTextAttachment(image: messageStatusIcon)
            iconAttachment.bounds.size = CGSize(width: ceil(imageSize.width * scale), height: ceil(imageSize.height * scale))

            result.append(NSAttributedString(attachment: iconAttachment))
            result.append(NSAttributedString(string: " "))
        }

        result.append(NSAttributedString(string: messageText))

        result.addAttributes([ .font: Constants.LastMsgFont, .foregroundColor: Constants.LastMsgColor ],
                             range: NSRange(location: 0, length: result.length))
        if !contactNamePart.isEmpty {
            // Note that the assumption is that we are using system font for the rest of the text.
            let participantNameFont = UIFont.systemFont(ofSize: Constants.LastMsgFont.pointSize, weight: .medium)
            result.addAttribute(.font, value: participantNameFont, range: NSRange(location: 0, length: contactNamePart.count))
        }

        return result
    }

    func configure(with chatThread: ChatThread) {

        self.chatThread = chatThread
        
        if chatThread.type == .oneToOne {
            nameLabel.text = MainAppContext.shared.contactStore.fullName(for: chatThread.chatWithUserId ?? "")
        } else {
            nameLabel.text = chatThread.title
        }

        lastMsgLabel.attributedText = lastMessageText(for: chatThread)

        if chatThread.unreadCount > 0 {
            unreadCountView.isHidden = false
            unreadCountView.label.text = String(chatThread.unreadCount)
            timeLabel.textColor = .systemBlue
        } else if chatThread.isNew {
            unreadCountView.isHidden = false
            unreadCountView.label.text = " "
            timeLabel.textColor = .systemBlue
        } else {
            unreadCountView.isHidden = true
            timeLabel.textColor = .secondaryLabel
        }
        
        if let timestamp = chatThread.lastMsgTimestamp {
            timeLabel.text = timestamp.chatListTimestamp()
        }
        
        if chatThread.type == .oneToOne {
            avatarView.configure(userId: chatThread.chatWithUserId ?? "", using: MainAppContext.shared.avatarStore)
        } else {
            avatarView.configure(groupId: chatThread.groupId ?? "", using: MainAppContext.shared.avatarStore)
        }
    }
    
    func highlightTitle(_ searchItems: [String]) {
        guard let title = nameLabel.text else { return }
        let titleLowercased = title.lowercased() as NSString
        let attributedString = NSMutableAttributedString(string: title)
        for item in searchItems {
            let range = titleLowercased.range(of: item.lowercased())
            attributedString.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: range)
        }
        nameLabel.attributedText = attributedString
    }
    
    func configureTypingIndicator(_ typingIndicatorStr: String?) {
        guard let chatThread = chatThread else { return }
        
        guard let typingIndicatorStr = typingIndicatorStr else {
            isShowingTypingIndicator = false
            configure(with: chatThread)
            return
        }
        
        let attributedString = NSMutableAttributedString(string: typingIndicatorStr, attributes: [.font: Constants.LastMsgFont, .foregroundColor: Constants.LastMsgColor])
        lastMsgLabel.attributedText = attributedString
        
        isShowingTypingIndicator = true
    }
    
    private func setup() {
        backgroundColor = .clear

        avatarView = AvatarViewButton(type: .custom)
        avatarView.hasNewPostsIndicator = ServerProperties.isGroupFeedEnabled
        avatarView.newPostsIndicatorRingWidth = 5
        avatarView.newPostsIndicatorRingSpacing = 1.5
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)

        let topRow = UIStackView(arrangedSubviews: [ nameLabel, timeLabel ])
        topRow.axis = .horizontal
        topRow.alignment = .firstBaseline
        topRow.spacing = 8

        let bottomRow = UIStackView(arrangedSubviews: [ lastMsgLabel, unreadCountView ])
        bottomRow.axis = .horizontal
        bottomRow.alignment = .center // This works as long as unread label and last message text have the same font.
        bottomRow.spacing = 8

        let vStack = UIStackView(arrangedSubviews: [ topRow, bottomRow ])
        vStack.axis = .vertical
        vStack.spacing = 4
        vStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(vStack)

        let avatarSize: CGFloat = Constants.AvatarSize + (avatarView.hasNewPostsIndicator ? 2*(avatarView.newPostsIndicatorRingSpacing + avatarView.newPostsIndicatorRingWidth) : 0)
        contentView.addConstraints([
            avatarView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.centerXAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor, constant: 0.5*Constants.AvatarSize),
            avatarView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 8),
            
            vStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            vStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            vStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            vStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)
        ])

        if ServerProperties.isGroupFeedEnabled {
            avatarView.addTarget(self, action: #selector(avatarButtonTapped), for: .touchUpInside)
        } else {
            avatarView.isUserInteractionEnabled = false
        }
    }

    private var avatarView: AvatarViewButton!

    var avatarTappedAction: (() -> ())?

    @objc private func avatarButtonTapped() {
        avatarTappedAction?()
    }
    
    // 16 points for font
    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .gothamFont(forTextStyle: .callout, weight: .medium)
        label.textColor = .label
        return label
    }()
    
    // 14 points for font
    private lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        
        let font = UIFont.preferredFont(forTextStyle: .caption1)
        label.font = UIFont.systemFont(ofSize: font.pointSize + 1)
        
        label.textColor = .secondaryLabel
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh + 50, for: .horizontal)
        return label
    }()

    private lazy var lastMsgLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()
    
    private lazy var unreadCountView: UnreadBadgeView = {
        let view = UnreadBadgeView(frame: .zero)
        view.label.font = .preferredFont(forTextStyle: .footnote)
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: 18).isActive = true
        return view
    }()
    
}

private class UnreadBadgeView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    var label: UILabel!

    private func commonInit() {
        backgroundColor = .clear
        layoutMargins = UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)

        let backgroundView = PillView()
        backgroundView.fillColor = .systemBlue
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)
        backgroundView.constrain(to: self)

        label = UILabel()
        label.textAlignment = .center
        label.textColor = .white
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh + 10, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        label.setContentCompressionResistancePriority(.defaultHigh + 10, for: .vertical)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        label.widthAnchor.constraint(greaterThanOrEqualTo: label.heightAnchor, multiplier: 1).isActive = true
        label.constrainMargins(to: self)
    }
}

fileprivate class DismissableUISearchController: UISearchController {

    // dismiss controller when switching tabs while searching
    override func viewWillDisappear(_ animated: Bool) {
        dismiss(animated: true)
    }
}
