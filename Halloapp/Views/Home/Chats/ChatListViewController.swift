//
//  ChatListViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/25/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import CoreData
import Intents
import SwiftUI
import UIKit

typealias ChatThread = CommonThread

fileprivate struct Constants {
    static let AvatarSize: CGFloat = 56
}

class ChatListViewController: UIViewController, NSFetchedResultsControllerDelegate {

    private lazy var tableView: UITableView = {
        // a table view's headers are sticky only when its style is `.plain`
        // when there aren't contact permissions, we display a sticky banner
        let style: UITableView.Style = ContactStore.contactsAccessAuthorized ? .grouped : .plain
        return UITableView(frame: .zero, style: style)
    }()

    private static let cellReuseIdentifier = "ThreadListCell"
    private static let inviteFriendsReuseIdentifier = "ChatListInviteFriendsCell"
    
    private var fetchedResultsController: NSFetchedResultsController<ChatThread>?
    private var dataSource: ChatsListDataSource?
    
    private var isVisible: Bool = false
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var filteredChats: [ChatThread] = []
    private var searchController = UISearchController(searchResultsController: nil)

    private var groupIdToPresent: GroupID? = nil
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

    // MARK: Lifecycle

    init(title: String) {
        super.init(nibName: nil, bundle: nil)
        self.title = title

        cancellableSet.insert(
            MainAppContext.shared.openChatThreadRequest.sink { [weak self] (threadID) in
                guard let self = self else { return }
                self.routeTo(userID: threadID, animated: false)
            }
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let height = layoutHeight, height != view.bounds.height {
            // Search bar can become misaligned if view height changes (e.g., because bar appears for active call)
            resetSearchBarIfActive()
        }
        layoutHeight = view.bounds.height
    }

    private var layoutHeight: CGFloat?

    private func resetSearchBarIfActive() {
        if searchController.isActive {
            let searchText = searchController.searchBar.text
            searchController.isActive = false
            searchController.isActive = true
            searchController.searchBar.text = searchText
        }
    }

    override func viewDidLoad() {
        DDLogInfo("ChatListViewController/viewDidLoad")

        installAvatarBarButton()

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

        installEmptyView()

        tableView.register(AllowContactsPermissionTableViewHeader.self, forHeaderFooterViewReuseIdentifier: AllowContactsPermissionTableViewHeader.reuseIdentifier)
        tableView.register(ChatListHeaderView.self, forHeaderFooterViewReuseIdentifier: ChatListHeaderView.reuseIdentifier)
        tableView.register(ThreadListCell.self, forCellReuseIdentifier: ChatListViewController.cellReuseIdentifier)
        tableView.register(ChatListInviteFriendsTableViewCell.self, forCellReuseIdentifier: ChatListViewController.inviteFriendsReuseIdentifier)
        tableView.delegate = self
        
        tableView.backgroundView = UIView() // fixes issue where bg color was off when pulled down from top
        tableView.backgroundColor = .primaryBg
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0) // -10 to hide top padding on searchBar

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60 // set a number close to default to prevent cells overlapping issue, can't be auto

        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 44
        tableView.sectionHeaderTopPadding = .zero

        dataSource = ChatsListDataSource(tableView: tableView) { [weak self] (tableView, indexPath, row) in
            guard let self = self else { return UITableViewCell() }
            if indexPath.section == 0 {
                switch row {
                case .chat:
                    guard let chatThread = self.chatThread(at: indexPath) else {
                        let cell = tableView.dequeueReusableCell(withIdentifier: ChatListViewController.inviteFriendsReuseIdentifier, for: indexPath)
                        return cell
                    }
                    let cell = tableView.dequeueReusableCell(withIdentifier: ChatListViewController.cellReuseIdentifier, for: indexPath) as! ThreadListCell

                    cell.configureAvatarSize(Constants.AvatarSize)
                    switch chatThread.type {
                    case .oneToOne:
                        cell.configureForChatsList(with: chatThread, squareSize: Constants.AvatarSize)
                    case .groupChat:
                        cell.configureForGroupsList(with: chatThread, squareSize: Constants.AvatarSize)
                    case .groupFeed:
                        DDLogError("ChatListViewController/viewDidLoad/ error type groupFeed")
                    }
                    self.updateCellWithChatState(cell: cell, chatThread: chatThread, chatStateInfo: nil)

                    if self.isFiltering {
                        let searchStr = self.searchController.searchBar.text!.trimmingCharacters(in: CharacterSet.whitespaces)
                        cell.highlightTitle([searchStr])
                    }
                    return cell
                case .inviteFriendsAndFamily:
                    let cell = tableView.dequeueReusableCell(withIdentifier: ChatListViewController.inviteFriendsReuseIdentifier, for: indexPath)
                    return cell
                }
            }
            return UITableViewCell()
        }

        setupFetchedResultsController()
        reloadData(animated: false)

        // watch for any changes in the iOS address book (name changes, deletions) and reflect it immediately,
        // especially in cases where the user is on the chats list screen and doing changes in the address book at the same time
        // note: iOS sometimes sends out notifications for address book changes even when there isn't any and also sometimes multiple
        // notifications for one change
        cancellableSet.insert(MainAppContext.shared.contactStore.didAddressBookChange.sink { [weak self] in
            DDLogInfo("ChatListViewController/sink/didAddressBookChange")
            DispatchQueue.main.async { [weak self] in
                MainAppContext.shared.chatData.pruneEmptyChatThreads()
                if let self = self, self.isVisible {
                    self.reloadData()
                }
            }
        })

        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetChatStateInfo.sink { [weak self] chatStateInfo in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.updateVisibleCellsWithTypingIndicator(chatStateInfo: chatStateInfo)
                }
            }
        )

        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetAGroupEvent.sink { [weak self] (groupId) in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if self.groupIdToPresent == groupId {
                        DDLogDebug("ChatListViewController/presentGroup \(groupId)")
                        self.routeTo(groupId: groupId, animated: true)
                        self.groupIdToPresent = nil
                    }
                }
        })

        cancellableSet.insert(
            MainAppContext.shared.didTapIntent.sink(receiveValue: { [weak self] intent in
                guard let intent = intent as? INSendMessageIntent else { return }
                guard let rawConversationID = intent.conversationIdentifier else { return }
                guard let conversationID = ConversationID(rawConversationID), conversationID.conversationType == .chat else { return }
                
                self?.view.window?.rootViewController?.dismiss(animated: true, completion: nil)
                guard let self = self else { return }
                let vc = ChatViewControllerNew(for: conversationID.id, with: nil, at: 0)
                vc.chatViewControllerDelegate = self
                self.navigationController?.pushViewController(vc, animated: true)
            })
        )

        if !ContactStore.contactsAccessAuthorized, !showThreadsWithoutContactsPermission {
            showPermissionsViewController()
        }
    }

    private var showThreadsWithoutContactsPermission: Bool {
        guard let results = fetchedResultsController?.fetchedObjects else {
            return false
        }

        return results.contains(where: { thread in
            switch thread.type {
            case .oneToOne where thread.userID != MainAppContext.shared.userData.userId:
                return true
            case .groupChat:
                return true
            default:
                return false
            }
        })
    }

    private func showPermissionsViewController() {
        let vc = InAppPermissionsViewController(configuration: .chat)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(vc.view)
        addChild(vc)

        NSLayoutConstraint.activate([
            vc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            vc.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            vc.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("ChatListViewController/viewWillAppear")
        super.viewWillAppear(animated)
        reloadData(animated: false)

        Analytics.openScreen(.chatList)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        DDLogInfo("ChatListViewController/viewWillDisappear")
        super.viewWillDisappear(animated)
        isVisible = false
        if(searchController.isActive && isSearchBarEmpty) {
            searchController.isActive = false
        }
    }

    private lazy var rightBarButtonItem: UIBarButtonItem = {
        let image = UIImage(named: "NavComposeChat", in: nil, with: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))?.withTintColor(UIColor.primaryBlue, renderingMode: .alwaysOriginal)
        let button = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(openComposeChatAction))
        return button
    }()

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
    
    // in the case when user is in zero zone and a message comes in
    private func dismissInviteScreenIfNeeded() {
        guard MainAppContext.shared.nux.state == .zeroZone else { return }
        guard (fetchedResultsController?.sections?.first?.numberOfObjects ?? 0) > 0 else { return }
        if let inviteSubView = view.viewWithTag(1000) {
            inviteSubView.removeFromSuperview()
        }
    }

    // MARK: New Chat

    private func showComposeChat() {
        guard ContactStore.contactsAccessAuthorized else {
            present(UINavigationController(rootViewController: NewChatPermissionDeniedController()), animated: true)
            return
        }

        let sharedNux = MainAppContext.shared.nux
        let isZeroZone = sharedNux.state == .zeroZone

        if isZeroZone {
            InviteManager.shared.requestInvitesIfNecessary()
            let inviteVC = InviteViewController(manager: InviteManager.shared, title: Localizations.titleChatNewMessage, showDividers: false, dismissAction: { [weak self] in self?.dismiss(animated: true, completion: nil) })
            let navController = UINavigationController(rootViewController: inviteVC)
            present(navController, animated: true)
        } else {
            present(UINavigationController(rootViewController: NewChatViewController(delegate: self)), animated: true)
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
        let fetchRequest = NSFetchRequest<ChatThread>(entityName: "CommonThread")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "lastTimestamp", ascending: false),
            NSSortDescriptor(key: "title", ascending: true)
        ]

        // TODO: Should this use type field instead?
        fetchRequest.predicate = NSPredicate(format: "(userID != nil && typeValue == %d) || (groupID != nil && typeValue == %d)", ChatType.oneToOne.rawValue , ChatType.groupChat.rawValue)
        
        return fetchRequest
    }

    private func setupFetchedResultsController() {
        fetchedResultsController = createFetchedResultsController()
        do {
            try fetchedResultsController?.performFetch()
            updateEmptyView()
        } catch {
            fatalError("ChatListView/frc/setup failure: \(error)")
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

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogVerbose("ChatListView/frc/controllerDidChangeContent")
        reloadData(animated: false)
        updateEmptyView()
        dismissInviteScreenIfNeeded()
    }

    private func reloadData(animated: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            self?.reloadDataInMainQueue(animated: animated)
        }
    }

    private func reloadDataInMainQueue(animated: Bool = false) {
        var chatThreads: [ChatThread] = []

        if isFiltering {
            chatThreads.append(contentsOf: filteredChats.map {$0} )
        } else if let objects = fetchedResultsController?.fetchedObjects {
            chatThreads.append(contentsOf: objects.map {$0} )
        }

        var chatRows = [Row]()
        chatThreads.forEach { thread in
            var recipientId: String?
            switch thread.type {
            case .oneToOne:
                recipientId = thread.userID
            case .groupChat:
                recipientId = thread.groupId
            case .groupFeed:
                break
            }
            guard let recipientId = recipientId else {
                // all chat threads should have a userID or groupID, logging to attempt to catch the time when it does not
                DDLogDebug("ChatListView/reloadDataInMainQueue/empty recipientId: threadType: \(thread.type) userdId: \(String(describing: thread.userID)) groupId: \(String(describing: thread.groupId))")
                return
            }
            var chatThreadData = ChatThreadData(recipientID: recipientId, lastMsgID: thread.lastMsgId ?? "", lastMsgMediaType: thread.lastMsgMediaType, lastMsgStatus: thread.lastMsgStatus, isNew: thread.isNew, unreadCount: thread.unreadCount)
            if isFiltering {
                if let searchStr = searchController.searchBar.text?.trimmingCharacters(in: CharacterSet.whitespaces) {
                    chatThreadData.searchStr = searchStr
                }
            }
            chatRows.append(Row.chat(chatThreadData))
        }

        if !isFiltering {
            chatRows.append(Row.inviteFriendsAndFamily)
        }

        /* apply snapshot */
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
      
        snapshot.appendSections([ .chats ])
        snapshot.appendItems(chatRows, toSection: .chats)

        dataSource?.defaultRowAnimation = .fade
        dataSource?.apply(snapshot, animatingDifferences: animated)
    }

    // MARK: Actions

    @objc private func openComposeChatAction() {
        showComposeChat()
    }

    // MARK: Helpers

    func isScrolledFromTop(by fromTop: CGFloat) -> Bool {
        return tableView.contentOffset.y < fromTop
    }

    private func updateVisibleCellsWithTypingIndicator(chatStateInfo: ChatStateInfo?) {
        guard isVisible else { return }
        for tableCell in tableView.visibleCells {
            guard let cell = tableCell as? ThreadListCell else { continue }
            guard let chatThread = cell.chatThread else { continue }
            updateCellWithChatState(cell: cell, chatThread: chatThread, chatStateInfo: chatStateInfo)
        }
    }

    private func updateCellWithChatState(cell: ThreadListCell, chatThread: ChatThread, chatStateInfo: ChatStateInfo?) {
        var typingIndicatorStr: String? = nil

        switch chatThread.type {
        case .oneToOne:
            typingIndicatorStr = MainAppContext.shared.chatData.getTypingIndicatorString(type: chatThread.type, id: chatThread.userID, fromUserID: chatThread.userID)
        case .groupChat:
            typingIndicatorStr = MainAppContext.shared.chatData.getTypingIndicatorString(type: .groupChat, id: chatThread.groupId, fromUserID: chatStateInfo?.from)
        default:
            return
        }

        if typingIndicatorStr == nil && !cell.isShowingTypingIndicator {
            return
        }

        cell.configureTypingIndicator(typingIndicatorStr)
    }
}

extension ChatListViewController: UIViewControllerHandleTapNotification {
    // MARK: Tap Notification

    func processNotification(metadata: NotificationMetadata) {
        // If the user tapped on the chat notification or inviter/friend notification - show the chat screen.
        guard metadata.isChatNotification || metadata.isContactNotification || metadata.isChatGroupAddNotification else {
            return
        }

        // If the user tapped on a notification, move to the chat view
        if metadata.isGroupNotification, let groupId = metadata.groupId {
            // route to group chat view
            if let _ = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: MainAppContext.shared.chatData.viewContext) {
                routeTo(groupId: groupId, animated: true)
            } else {
                // for offline groupAdd notifications, the app needs some time to get and create the new group when the user
                // taps on the notification so we just wait for the group event here.
                DispatchQueue.main.async{
                    self.groupIdToPresent = groupId
                }
            }
        } else if metadata.contentType == .chatMessage || metadata.isContactNotification {
            // route to oneToOne chat view
            routeTo(userID: metadata.fromId, animated: true)
        }
        metadata.removeFromUserDefaults()
    }
    
    private func routeTo(groupId: GroupID, animated: Bool) {
        if let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: MainAppContext.shared.chatData.viewContext) {
            let vc = GroupChatViewController(for: group)
            self.navigationController?.pushViewController(vc, animated: true)
        } else {
            AppContext.shared.errorLogger?.logError(NSError(domain: "missingGroup", code: 1013))
        }
    }

    private func routeTo(userID: UserID, animated: Bool) {
        DDLogInfo("ChatListViewController/routeTo/\(userID)")

        navigationController?.popToRootViewController(animated: false)

        let vc = ChatViewControllerNew(for: userID, with: nil, at: 0)
        vc.chatViewControllerDelegate = self
        self.navigationController?.pushViewController(vc, animated: animated)
    }
}

extension ChatListViewController: UIViewControllerScrollsToTop {
    func scrollToTop(animated: Bool) {
        let indexPath = IndexPath(row: 0, section: 0)
        // check tableView instead of fetchedresults (potential fix for an out-of-bounds crash)
        guard indexPath.section < tableView.numberOfSections else { return }
        guard indexPath.row < tableView.numberOfRows(inSection: indexPath.section) else { return }
        tableView.scrollToRow(at: indexPath, at: .middle, animated: animated)
    }
}

// MARK: - UIViewControllerHandleShareDestination methods

extension ChatListViewController: UIViewControllerHandleShareDestination {

    func route(to destination: ShareDestination) {
        var viewController: UIViewController?
        switch destination {
        case .group(id: let id, type: let type, _) where type == .groupChat:
            if let group = MainAppContext.shared.chatData.chatGroup(groupId: id, in: MainAppContext.shared.chatData.viewContext) {
                let vc = GroupChatViewController(for: group)
                vc.chatViewControllerDelegate = self
                viewController = vc
            }
        case .user(id: let id, _, _):
            let vc = ChatViewControllerNew(for: id)
            vc.chatViewControllerDelegate = self
            viewController = vc
        default:
            break
        }

        if let viewController {
            navigationController?.pushViewController(viewController, animated: false)
        }
    }
}

// MARK: Table Header Delegate
extension ChatListViewController: ChatListHeaderViewDelegate {
    func chatListHeaderView(_ chatListHeaderView: ChatListHeaderView) {
        startInviteFriendsFlow()
    }
}

// MARK: UITableView Delegates
extension ChatListViewController: UITableViewDelegate {

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
        guard ContactStore.contactsAccessAuthorized else {
            let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: AllowContactsPermissionTableViewHeader.reuseIdentifier)
            let inset = tableView.contentInset.top
            header?.layoutMargins.top = inset < 0 ? -inset : inset
            return header
        }

        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: ChatListHeaderView.reuseIdentifier)
        (header as? ChatListHeaderView)?.delegate = self

        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let chatThread = chatThread(at: indexPath) else {
            // Must be invite friends cell
            startInviteFriendsFlow()
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        DDLogInfo("ChatListViewController/ didSelect chatThread type: \(chatThread.type) userID: \(chatThread.userID ?? "") groupId: \(String(describing: chatThread.groupId ?? ""))")
        switch chatThread.type {
        case .oneToOne:
            if let chatWithUserId = chatThread.userID {
                let vc = ChatViewControllerNew(for: chatWithUserId, with: nil, at: 0)
                vc.chatViewControllerDelegate = self
                self.navigationController?.pushViewController(vc, animated: true)
            }
        case .groupChat:
            if let groupId = chatThread.groupId, let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: MainAppContext.shared.chatData.viewContext) {
                let vc = GroupChatViewController(for: group)
                self.navigationController?.pushViewController(vc, animated: true)
            }
        case .groupFeed:
            DDLogError("ChatListViewController/chat thread type groupFeed")
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let chatThread = self.chatThread(at: indexPath) else { return UISwipeActionsConfiguration(actions: []) }
        // User cannot delete a group chat thread when they are still members of the group
        if let groupId = chatThread.groupId, MainAppContext.shared.chatData.chatGroupMember(groupId: groupId, memberUserId: MainAppContext.shared.userData.userId, in: MainAppContext.shared.chatData.viewContext) != nil {
            return UISwipeActionsConfiguration(actions: [])
        }

        var chatThreadId: String? = nil
        switch chatThread.type {
        case .oneToOne:
            chatThreadId = chatThread.userID
        case .groupChat:
            chatThreadId = chatThread.groupId
        case .groupFeed:
            break
        }
        guard let chatThreadId = chatThreadId else { return UISwipeActionsConfiguration(actions: []) }

        let removeAction = UIContextualAction(style: .destructive, title: Localizations.buttonRemove) { [weak self] (_, _, completionHandler) in
            guard let self = self else { return }
            let actionSheet = UIAlertController(title: chatThread.title, message: Localizations.chatsListRemoveMessage, preferredStyle: .actionSheet)
            actionSheet.addAction(UIAlertAction(title: Localizations.buttonRemove, style: .destructive) { [weak self] action in
                guard let self = self else { return }
                switch chatThread.type {
                case .oneToOne:
                    MainAppContext.shared.chatData.deleteChat(chatThreadId: chatThreadId)
                case .groupChat:
                    MainAppContext.shared.chatData.deleteChatGroup(groupId: chatThreadId, type: .groupChat)
                case .groupFeed:
                    break
                }
                if self.isFiltering {
                    self.filteredChats.remove(at: indexPath.row)
                }
            })
            actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
            self.present(actionSheet, animated: true)
            completionHandler(true)
        }

        return UISwipeActionsConfiguration(actions: [removeAction])
    }
        
    // resign keyboard so the entire tableview can be seen
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        searchController.searchBar.resignFirstResponder()
    }

}

// MARK: UISearchController Updating Delegates
extension ChatListViewController: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        guard let allChats = fetchedResultsController?.fetchedObjects else { return }
        guard let searchBarText = searchController.searchBar.text else { return }

        let searchStr = searchBarText.trimmingCharacters(in: CharacterSet.whitespaces).lowercased()

        filteredChats = allChats.filter {
            var title = ""
            if let chatWithUserID = $0.userID {
                title = UserProfile.findOrCreate(with: chatWithUserID, in: AppContext.shared.mainDataStore.viewContext).displayName
            } else if let chatInGroupID = $0.groupId {
                guard let group = MainAppContext.shared.chatData.chatGroup(groupId: chatInGroupID, in: MainAppContext.shared.chatData.viewContext) else { return false }
                title = group.name
            } else {
                return false
            }
            return title.lowercased().contains(searchStr)
        }
        DDLogDebug("ChatListViewController/updateSearchResults/filteredChats count \(filteredChats.count) for: \(searchBarText)")

        reloadData(animated: false)
    }
}

// MARK: UISearchController SearchBar Delegates
extension ChatListViewController: UISearchBarDelegate {
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchController.isActive = false
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

extension ChatListViewController: NewChatViewControllerDelegate {
    func newChatViewController(_ controller: NewChatViewController, didSelect userId: UserID) {
        controller.dismiss(animated: true) {
            let vc = ChatViewControllerNew(for: userId)
            self.navigationController?.pushViewController(vc, animated: true)
            DispatchQueue.main.async {
                vc.showKeyboard()
            }
        }
    }

    func newChatViewController(_ controller: NewChatViewController, didSelectGroup groupId: GroupID) {
        guard let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: MainAppContext.shared.chatData.viewContext) else { return }
        let vc = GroupChatViewController(for: group)
        self.navigationController?.pushViewController(vc, animated: true)
        DispatchQueue.main.async {
            vc.showKeyboard()
        }
    }
}

extension ChatListViewController: ChatViewControllerDelegate {
    func chatViewController(_ chatViewController: GroupChatViewController, userActioned: Bool) {
        DispatchQueue.main.async {
            self.scrollToTop(animated: false)
        }
    }

    func chatViewController(_ controller: ChatViewControllerNew, userActioned: Bool) {
        searchController.isActive = false
        DispatchQueue.main.async {
            self.scrollToTop(animated: false)
        }
    }
}

protocol ChatListHeaderViewDelegate: AnyObject {
    func chatListHeaderView(_ chatListHeaderView: ChatListHeaderView)
}

class ChatListHeaderView: UITableViewHeaderFooterView {

    static let reuseIdentifier = "chatListHeader"

    weak var delegate: ChatListHeaderViewDelegate?
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setup()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    private func setup() {
        preservesSuperviewLayoutMargins = true

        vStack.addArrangedSubview(inviteLabel)
        addSubview(vStack)

        vStack.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        vStack.isLayoutMarginsRelativeArrangement = true
        
        vStack.topAnchor.constraint(equalTo: topAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true

        let vStackBottomConstraint = vStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        vStackBottomConstraint.priority = UILayoutPriority(rawValue: 999)
        vStackBottomConstraint.isActive = true
    }
    
    private lazy var inviteLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17)
        label.textColor = .systemBlue
        label.textAlignment = .right
        label.text = Localizations.chatInviteFriends
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.openInviteView(_:)))
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

    @objc func openInviteView (_ sender: UITapGestureRecognizer) {
        self.delegate?.chatListHeaderView(self)
    }
}

fileprivate class ChatsListDataSource: UITableViewDiffableDataSource<Section, Row> {

    // when using UITableViewDiffableDataSource, canEditRowAt needs to be set to enable swipe to delete
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
}

fileprivate struct ChatThreadData {
    let recipientID: String
    let lastMsgID: String
    var lastMsgMediaType: ChatThread.LastMediaType
    let lastMsgStatus: ChatThread.LastMsgStatus
    let isNew: Bool
    var searchStr: String? = nil
    var unreadCount: Int32
}

extension ChatThreadData : Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(recipientID)
        hasher.combine(lastMsgID)
        hasher.combine(lastMsgStatus)
        hasher.combine(isNew)
        hasher.combine(searchStr)
        hasher.combine(unreadCount)
    }
}

extension ChatThreadData : Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        return  lhs.recipientID == rhs.recipientID &&
                lhs.lastMsgID == rhs.lastMsgID &&
                lhs.lastMsgMediaType == rhs.lastMsgMediaType &&
                lhs.lastMsgStatus == rhs.lastMsgStatus &&
                lhs.isNew == rhs.isNew &&
                lhs.searchStr == rhs.searchStr &&
                lhs.unreadCount == rhs.unreadCount
    }
}

fileprivate enum Section: Hashable {
    case chats
}

fileprivate enum Row: Hashable, Equatable {
    case chat(ChatThreadData)
    case inviteFriendsAndFamily

    var chat: ChatThreadData? {
        switch self {
        case .chat(let chatThreadData): return chatThreadData
        case .inviteFriendsAndFamily: return nil
        }
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

private extension Localizations {

    static var chatsListRemoveMessage: String {
        NSLocalizedString("chats.list.remove.message", value: "By removing this chat you'll be clearing its chat history and content from your device.", comment: "Text shown when user is about to remove the chat")
    }
    
}
