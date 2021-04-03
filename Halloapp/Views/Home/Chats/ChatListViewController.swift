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
    static let AvatarSize: CGFloat = 56
}

fileprivate enum ChatListViewSection {
    case main
}

class ChatListViewController: UIViewController, NSFetchedResultsControllerDelegate {

    private static let cellReuseIdentifier = "ThreadListCell"
    private static let inviteFriendsReuseIdentifier = "ChatListInviteFriendsCell"
    private let tableView = UITableView(frame: CGRect.zero, style: .grouped)
    
    private var fetchedResultsController: NSFetchedResultsController<ChatThread>?
    
    private var isVisible: Bool = false
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var filteredChats: [ChatThread] = []
    private var searchController: UISearchController!
    
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("ChatListViewController/viewDidLoad")

        navigationItem.standardAppearance = .transparentAppearance
        navigationItem.standardAppearance?.backgroundColor = UIColor.feedBackground
        installLargeTitleUsingGothamFont()

        navigationItem.rightBarButtonItem = rightBarButtonItem

        definesPresentationContext = true
        
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.definesPresentationContext = true
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.delegate = self

        searchController.searchBar.backgroundImage = UIImage()
        searchController.searchBar.tintColor = UIColor.primaryBlue
        searchController.searchBar.searchTextField.backgroundColor = .searchBarBg

        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.constrain(to: view)

        installEmptyView()

        tableView.register(ChatListHeaderView.self, forHeaderFooterViewReuseIdentifier: "sectionHeader")
        tableView.register(ThreadListCell.self, forCellReuseIdentifier: ChatListViewController.cellReuseIdentifier)
        tableView.register(ChatListInviteFriendsTableViewCell.self, forCellReuseIdentifier: ChatListViewController.inviteFriendsReuseIdentifier)
        tableView.delegate = self
        tableView.dataSource = self
        
        tableView.backgroundView = UIView() // fixes issue where bg color was off when pulled down from top
        tableView.backgroundColor = .primaryBg
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0) // -10 to hide top padding on searchBar

        tableView.tableHeaderView = searchController.searchBar
        tableView.tableHeaderView?.layoutMargins = UIEdgeInsets(top: 0, left: 21, bottom: 0, right: 21) // requested to be 21

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
        super.viewDidAppear(animated)
        isVisible = true
        showNUXIfNecessary()
    }

    override func viewWillDisappear(_ animated: Bool) {
        DDLogInfo("ChatListViewController/viewWillDisappear")
        super.viewWillDisappear(animated)
        isVisible = false

        floatingMenu.setState(.collapsed, animated: true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == tableView {
            updateNavigationBarStyleUsing(scrollView: scrollView)
        }
    }

    private lazy var rightBarButtonItem: UIBarButtonItem = {
        let image = UIImage(named: "NavComposeChat", in: nil, with: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))?.withTintColor(UIColor.primaryBlue, renderingMode: .alwaysOriginal)
        let button = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(openComposeChatAction))
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
                action: { [weak self] in self?.showComposeChat() }))
    }()

    private func showComposeChat() {
        present(UINavigationController(rootViewController: NewChatViewController(delegate: self)), animated: true)
    }

    // MARK: Invite friends

    @objc
    private func startInviteFriendsFlow() {
        InviteManager.shared.requestInvitesIfNecessary()
        let inviteVC = InviteViewController(manager: InviteManager.shared, dismissAction: { [weak self] in self?.dismiss(animated: true, completion: nil) })
        let navController = UINavigationController(rootViewController: inviteVC)
        present(navController, animated: true)
    }
    
    // MARK: Fetched Results Controller
    
    public var fetchRequest: NSFetchRequest<ChatThread> {
        let fetchRequest = NSFetchRequest<ChatThread>(entityName: "ChatThread")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "lastMsgTimestamp", ascending: false),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        
        fetchRequest.predicate = NSPredicate(format: "chatWithUserId != nil")
        
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
            if trackPerRowFRCChanges && !isFiltering {
                tableView.insertRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .delete:
            guard let indexPath = indexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("ChatListView/frc/delete [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] at [\(indexPath)]")
      
            if trackPerRowFRCChanges && !isFiltering {
                tableView.deleteRows(at: [ indexPath ], with: .left)
            } else {
                reloadTableViewInDidChangeContent = true
            }
            
        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("ChatListView/frc/move [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges && !isFiltering {
                tableView.moveRow(at: fromIndexPath, to: toIndexPath)
                reloadTableViewInDidChangeContent = true
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .update:
            guard let indexPath = indexPath, let chatThread = anObject as? ChatThread else { return }
            DDLogDebug("ChatListView/frc/update [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] at [\(indexPath)]")
            
            // reload table instead of reloadRows due to overlapping issue when table exceeds 100+ rows
            // ex: overlap can occur when user scrolls down, select a chat, send a msg, and then go back
            reloadTableViewInDidChangeContent = true
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
        
    // MARK: Actions
    
    @objc private func openComposeChatAction() {
        showComposeChat()
    }
    
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
            guard let cell = tableCell as? ThreadListCell else { continue }
            guard let chatThread = cell.chatThread else { continue }
            updateCellWithChatState(cell: cell, chatThread: chatThread)
        }
    }
    
    private func updateCellWithChatState(cell: ThreadListCell, chatThread: ChatThread) {
        var typingIndicatorStr: String? = nil
        
        if chatThread.type == .oneToOne {
            typingIndicatorStr = MainAppContext.shared.chatData.getTypingIndicatorString(type: chatThread.type, id: chatThread.chatWithUserId)
        }

        if typingIndicatorStr == nil && !cell.isShowingTypingIndicator {
            return
        }
        
        cell.configureTypingIndicator(typingIndicatorStr)
    }
   
    // MARK: Tap Notification
    
    private func processNotification(metadata: NotificationMetadata) {
        // If the user tapped on the chat notification or inviter/friend notification - show the chat screen.
        guard metadata.isChatNotification || metadata.isContactNotification else {
            return
        }

        // If the user tapped on a notification, move to the chat view
        DDLogInfo("ChatListViewController/processNotification/open chat \(metadata.fromId)")

        navigationController?.popToRootViewController(animated: false)

        if metadata.contentType == .chatMessage || metadata.isContactNotification {
            navigationController?.pushViewController(ChatViewController(for: metadata.fromId, with: nil, at: 0), animated: true)
        }

        metadata.removeFromUserDefaults()
    }

    private func openFeed(forGroupId groupId: GroupID) {
        let viewController = GroupFeedViewController(groupId: groupId)
        viewController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(viewController, animated: true)
    }
}

extension ChatListViewController: UIViewControllerScrollsToTop {

    func scrollToTop(animated: Bool) {
        guard let firstSection = fetchedResultsController?.sections?.first else { return }
        guard firstSection.numberOfObjects > 0 else { return }
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .middle, animated: animated)
    }
}

// MARK: Table Header Delegate
extension ChatListViewController: ChatListHeaderViewDelegate {
    func chatListHeaderView(_ chatListHeaderView: ChatListHeaderView) {
        startInviteFriendsFlow()
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

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: "sectionHeader") as! ChatListHeaderView
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
            let cell = tableView.dequeueReusableCell(withIdentifier: ChatListViewController.inviteFriendsReuseIdentifier, for: indexPath)
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatListViewController.cellReuseIdentifier, for: indexPath) as! ThreadListCell

        cell.configureAvatarSize(Constants.AvatarSize)
        cell.configure(with: chatThread, squareSize: Constants.AvatarSize)
        updateCellWithChatState(cell: cell, chatThread: chatThread)
  
        if isFiltering {
            let strippedString = searchController.searchBar.text!.trimmingCharacters(in: CharacterSet.whitespaces)
            let searchItems = strippedString.components(separatedBy: " ")
            cell.highlightTitle(searchItems)
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
        
        guard let chatWithUserId = chatThread.chatWithUserId else { return }
        
        let vc = ChatViewController(for: chatWithUserId, with: nil, at: 0)
        vc.hidesBottomBarWhenPushed = true
        self.navigationController?.pushViewController(vc, animated: true)
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let chatThread = self.chatThread(at: indexPath) else { return UISwipeActionsConfiguration(actions: []) }
        guard let chatWithUserId = chatThread.chatWithUserId else { return UISwipeActionsConfiguration(actions: []) }

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
        DDLogDebug("ChatListViewController/updateSearchResults/filteredChats count \(filteredChats.count) for: \(searchBarText)")
        
        tableView.reloadData()
    }
}

// MARK: UISearchController SearchBar Delegates
extension ChatListViewController: UISearchBarDelegate {
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        DispatchQueue.main.async {
            self.scrollToTop(animated: false)
        }
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

        vStack.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 20)
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
