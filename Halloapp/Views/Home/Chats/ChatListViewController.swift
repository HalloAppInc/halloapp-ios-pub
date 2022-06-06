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

    private let tableView = UITableView(frame: CGRect.zero, style: .grouped)
    private static let cellReuseIdentifier = "ThreadListCell"
    private static let inviteFriendsReuseIdentifier = "ChatListInviteFriendsCell"
    
    private var fetchedResultsController: NSFetchedResultsController<ChatThread>?
    private var dataSource: ChatsListDataSource?
    
    private var isVisible: Bool = false
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var filteredChats: [ChatThread] = []
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

    // MARK: Lifecycle

    init(title: String) {
        super.init(nibName: nil, bundle: nil)
        self.title = title

        cancellableSet.insert(
            MainAppContext.shared.openChatThreadRequest.sink { [weak self] (threadID) in
                guard let self = self else { return }
                self.routeTo(threadID, animated: false)
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

        tableView.register(ChatListHeaderView.self, forHeaderFooterViewReuseIdentifier: "sectionHeader")
        tableView.register(ThreadListCell.self, forCellReuseIdentifier: ChatListViewController.cellReuseIdentifier)
        tableView.register(ChatListInviteFriendsTableViewCell.self, forCellReuseIdentifier: ChatListViewController.inviteFriendsReuseIdentifier)
        tableView.delegate = self
        
        tableView.backgroundView = UIView() // fixes issue where bg color was off when pulled down from top
        tableView.backgroundColor = .primaryBg
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0) // -10 to hide top padding on searchBar
        
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60 // set a number close to default to prevent cells overlapping issue, can't be auto

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
                    cell.configureForChatsList(with: chatThread, squareSize: Constants.AvatarSize)
                    self.updateCellWithChatState(cell: cell, chatThread: chatThread)

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

        showInviteViewControllerIfNeeded()

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
            MainAppContext.shared.chatData.didGetChatStateInfo.sink { [weak self] in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.updateVisibleCellsWithTypingIndicator()
                }
            }
        )

        cancellableSet.insert(
            MainAppContext.shared.didTapIntent.sink(receiveValue: { [weak self] intent in
                guard let intent = intent as? INSendMessageIntent else { return }
                guard let rawConversationID = intent.conversationIdentifier else { return }
                guard let conversationID = ConversationID(rawConversationID), conversationID.conversationType == .chat else { return }
                
                self?.view.window?.rootViewController?.dismiss(animated: true, completion: nil)
                guard let self = self else { return }
                if AppContext.shared.userDefaults.bool(forKey: "enableNewChat") {
                    let vc = ChatViewControllerNew(for: conversationID.id, with: nil, at: 0)
                    vc.chatViewControllerDelegate = self
                    self.navigationController?.pushViewController(vc, animated: true)
                } else {
                    let vc = ChatViewController(for: conversationID.id, with: nil, at: 0)
                    vc.delegate = self
                    self.navigationController?.pushViewController(vc, animated: true)
                }
            })
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("ChatListViewController/viewWillAppear")
        super.viewWillAppear(animated)
        reloadData(animated: false)
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

    // MARK: NUX

    private func showInviteViewControllerIfNeeded() {
        let isZeroZone = MainAppContext.shared.nux.state == .zeroZone

        // check if list is empty since someone could've messaged the user
        let isEmpty = (fetchedResultsController?.sections?.first?.numberOfObjects ?? 0) == 0

        guard isZeroZone, isEmpty else { return }

        guard ContactStore.contactsAccessAuthorized else {
            let inviteVC = InvitePermissionDeniedViewController()
            present(UINavigationController(rootViewController: inviteVC), animated: true)
            return
        }
        InviteManager.shared.requestInvitesIfNecessary()
        let inviteVC = InviteViewController(manager: InviteManager.shared, showDividers: false, dismissAction: { [weak self] in self?.dismiss(animated: true, completion: nil) })
        inviteVC.view.frame = self.view.bounds
        view.addSubview(inviteVC.view)
        inviteVC.view.tag = 1000
        inviteVC.view.translatesAutoresizingMaskIntoConstraints = false
        inviteVC.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
        inviteVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        inviteVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        inviteVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true

        addChild(inviteVC)
        inviteVC.didMove(toParent: self)
    }

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
        fetchRequest.predicate = NSPredicate(format: "userID != nil")
        
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
            guard let chatWithUserID = thread.userID else {
                // all chat threads should have a userID, logging to attempt to catch the time when it does not
                DDLogDebug("ChatListView/reloadDataInMainQueue/empty chatWithUserID: \(thread)")
                return
            }
            var chatThreadData = ChatThreadData(chatWithUserID: chatWithUserID, lastMsgID: thread.lastMsgId ?? "", lastMsgMediaType: thread.lastMsgMediaType, lastMsgStatus: thread.lastMsgStatus, isNew: thread.isNew, unreadCount: thread.unreadCount)
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

    private func updateVisibleCellsWithTypingIndicator() {
        guard isVisible else { return }
        for tableCell in tableView.visibleCells {
            guard let cell = tableCell as? ThreadListCell else { continue }
            guard let chatThread = cell.chatThread else { continue }
            updateCellWithChatState(cell: cell, chatThread: chatThread)
        }
    }

    private func updateCellWithChatState(cell: ThreadListCell, chatThread: ChatThread) {
        var typingIndicatorStr: String? = nil

        if chatThread.type == .oneToOne {
            typingIndicatorStr = MainAppContext.shared.chatData.getTypingIndicatorString(type: chatThread.type, id: chatThread.userID)
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
        guard metadata.isChatNotification || metadata.isContactNotification else {
            return
        }

        // If the user tapped on a notification, move to the chat view
        if metadata.contentType == .chatMessage || metadata.isContactNotification {
            routeTo(metadata.fromId, animated: true)
        }

        metadata.removeFromUserDefaults()
    }

    private func routeTo(_ userID: UserID, animated: Bool) {
        DDLogInfo("ChatListViewController/routeTo/\(userID)")

        navigationController?.popToRootViewController(animated: false)
        if AppContext.shared.userDefaults.bool(forKey: "enableNewChat") {
            let vc = ChatViewControllerNew(for: userID, with: nil, at: 0)
            vc.chatViewControllerDelegate = self
            self.navigationController?.pushViewController(vc, animated: animated)
        } else {
            let vc = ChatViewController(for: userID, with: nil, at: 0)
            vc.delegate = self
            self.navigationController?.pushViewController(vc, animated: animated)
        }
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
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: "sectionHeader") as! ChatListHeaderView
        view.delegate = self
        return view
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 25
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let chatThread = chatThread(at: indexPath) else {
            // Must be invite friends cell
            startInviteFriendsFlow()
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }

        guard let chatWithUserId = chatThread.userID else { return }

        if AppContext.shared.userDefaults.bool(forKey: "enableNewChat") {
            let vc = ChatViewControllerNew(for: chatWithUserId, with: nil, at: 0)
            vc.chatViewControllerDelegate = self
            self.navigationController?.pushViewController(vc, animated: true)
        } else {
            let vc = ChatViewController(for: chatWithUserId, with: nil, at: 0)
            vc.delegate = self
            self.navigationController?.pushViewController(vc, animated: true)
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let chatThread = self.chatThread(at: indexPath) else { return UISwipeActionsConfiguration(actions: []) }
        guard let chatWithUserId = chatThread.userID else { return UISwipeActionsConfiguration(actions: []) }

        let removeAction = UIContextualAction(style: .destructive, title: Localizations.buttonRemove) { [weak self] (_, _, completionHandler) in
            guard let self = self else { return }
            let actionSheet = UIAlertController(title: chatThread.title, message: Localizations.chatsListRemoveMessage, preferredStyle: .actionSheet)
            actionSheet.addAction(UIAlertAction(title: Localizations.buttonRemove, style: .destructive) { [weak self] action in
                guard let self = self else { return }
                MainAppContext.shared.chatData.deleteChat(chatThreadId: chatWithUserId)
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
            guard let chatWithUserID = $0.userID else { return false }
            let title = MainAppContext.shared.contactStore.fullName(for: chatWithUserID, in: MainAppContext.shared.contactStore.viewContext)
            if title.lowercased().contains(searchStr) {
                return true
            }
            return false
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
            let vc = ChatViewController(for: userId)
            self.navigationController?.pushViewController(vc, animated: true)
            DispatchQueue.main.async {
                vc.showKeyboard()
            }
        }
    }
}

extension ChatListViewController: ChatViewControllerDelegate {
    func chatViewController(_ controller: ChatViewController, userActioned: Bool) {
        searchController.isActive = false
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
    let chatWithUserID: UserID
    let lastMsgID: String
    var lastMsgMediaType: ChatThread.LastMediaType
    let lastMsgStatus: ChatThread.LastMsgStatus
    let isNew: Bool
    var searchStr: String? = nil
    var unreadCount: Int32
}

extension ChatThreadData : Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(chatWithUserID)
        hasher.combine(lastMsgID)
        hasher.combine(lastMsgStatus)
        hasher.combine(isNew)
        hasher.combine(searchStr)
        hasher.combine(unreadCount)
    }
}

extension ChatThreadData : Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        return  lhs.chatWithUserID == rhs.chatWithUserID &&
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
