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

// MARK: Constraint Constants
fileprivate struct LayoutConstants {
    static let avatarSize: CGFloat = 50
    static let avatarRingWidth: CGFloat = 4
}

fileprivate enum ChatListViewSection {
    case main
}

class ChatListViewController: UIViewController, NSFetchedResultsControllerDelegate {

    private static let cellReuseIdentifier = "ChatListViewCell"
    private static let inviteFriendsReuseIdentifier = "ChatListInviteFriendsCell"
    private var fetchedResultsController: NSFetchedResultsController<ChatThread>?
    private var cancellableSet: Set<AnyCancellable> = []
    private let tableView = UITableView()

    private var filteredChats: [ChatThread] = []
    private var searchController: DismissableUISearchController!
    var isSearchBarEmpty: Bool {
      return searchController.searchBar.text?.isEmpty ?? true
    }
    var isFiltering: Bool {
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
        searchController.searchBar.layer.borderWidth = 1
        searchController.searchBar.layer.borderColor = UIColor.feedBackground.cgColor
        searchController.searchBar.barTintColor = UIColor.feedBackground
        searchController.searchBar.tintColor = UIColor.systemBlue
        searchController.searchBar.searchTextField.backgroundColor = UIColor.feedBackground
        
        if #available(iOS 14, *) {
            navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(openSearchAction))
        } else {
            // don't present searchbar in ios 13 since it jumps below the navbar when presented
            navigationItem.searchController = searchController
        }
        
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.constrain(to: view)

        installLargeTitleUsingGothamFont()
        installFloatingActionMenu()
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)

        tableView.backgroundColor = .feedBackground
        tableView.separatorStyle = .none
        tableView.register(ChatListTableViewCell.self, forCellReuseIdentifier: ChatListViewController.cellReuseIdentifier)
        tableView.register(ChatListInviteFriendsTableViewCell.self, forCellReuseIdentifier: ChatListViewController.inviteFriendsReuseIdentifier)
        tableView.delegate = self
        tableView.dataSource = self
        
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 13))
        tableView.tableHeaderView = header
        
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
            self.processNotification(metadata: metadata)
        }        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("ChatListViewController/viewWillAppear")
        super.viewWillAppear(animated)

        tableView.reloadData()
        populateWithSymmetricContacts()
    }

    override func viewDidAppear(_ animated: Bool) {
        DDLogInfo("ChatListViewController/viewDidAppear")
        super.viewDidAppear(animated)

        showNUXIfNecessary()
    }

    override func viewWillDisappear(_ animated: Bool) {
        DDLogInfo("ChatListViewController/viewWillDisappear")
        super.viewWillDisappear(animated)

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
    
    func scrollToTop(animated: Bool) {
        guard let firstSection = fetchedResultsController?.sections?.first else { return }
        if firstSection.numberOfObjects > 0 {
            tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
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

    // MARK: New Chat

    private lazy var floatingMenu: FloatingMenu = {
        FloatingMenu(
            permanentButton: .standardActionButton(
                iconTemplate: UIImage(named: "icon_fab_compose_message")?.withRenderingMode(.alwaysTemplate),
                accessibilityLabel: "New message",
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
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            guard let indexPath = newIndexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("ChatListView/frc/insert [\(chatThread)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                tableView.insertRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .delete:
            guard let indexPath = indexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("ChatListView/frc/delete [\(chatThread)] at [\(indexPath)]")
      
            if trackPerRowFRCChanges {
                tableView.deleteRows(at: [ indexPath ], with: .left)
            } else {
                reloadTableViewInDidChangeContent = true
            }
            
        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("ChatListView/frc/move [\(chatThread)] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges {
                tableView.moveRow(at: fromIndexPath, to: toIndexPath)
                reloadTableViewInDidChangeContent = true
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .update:
            guard let indexPath = indexPath, let chatThread = anObject as? ChatThread else { return }
            DDLogDebug("ChatListView/frc/update [\(chatThread)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                tableView.reloadRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        default:
            break
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogDebug("ChatListView/frc/did-change perRowChanges=[\(trackPerRowFRCChanges)]  reload=[\(reloadTableViewInDidChangeContent)]")
        if trackPerRowFRCChanges {
            tableView.endUpdates()
        }
        if reloadTableViewInDidChangeContent || isFiltering {
            tableView.reloadData()
        }
    }

    private var lastCheckedForNewContacts: Date?
    
    // MARK: Actions
    
    @objc private func openSearchAction() {
        present(searchController, animated: false, completion: nil)
    }
    
    // MARK: Helpers
    
    private func populateWithSymmetricContacts() {
        var isTimeToCheck = true
        if let lastCheckedForNewContacts = lastCheckedForNewContacts {
            isTimeToCheck = abs(lastCheckedForNewContacts.timeIntervalSinceNow) >= Date.minutes(1)
        }

        if isTimeToCheck {
            DDLogDebug("ChatList/populateWithSymmetricContacts")
            MainAppContext.shared.chatData.populateThreadsWithSymmetricContacts()
            lastCheckedForNewContacts = Date()
        }
    }
    
    private func updateVisibleCellsWithTypingIndicator() {
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
            navigationController?.pushViewController(vc, animated: true)
        } else {
            guard let groupId = chatThread.groupId else { return }
            let vc = ChatGroupViewController(for: groupId)
            vc.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(vc, animated: true)
        }
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
    func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
        searchController.searchBar.resignFirstResponder()
    }
}

// MARK: Search Delegates
extension ChatListViewController: UISearchControllerDelegate {
    func willDismissSearchController(_ searchController: UISearchController) {
        searchController.dismiss(animated: false)

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
        view.layer.cornerRadius = LayoutConstants.avatarSize / 2
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
            iconView.widthAnchor.constraint(equalToConstant: LayoutConstants.avatarSize),
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

        let textColor = UIColor.secondaryLabel
        let footnoteFont = UIFont.preferredFont(forTextStyle: .footnote)
        let font = UIFont.systemFont(ofSize: footnoteFont.pointSize + 1)

        var contactNamePart = ""
        if chatThread.type == .group {
            if let userId = chatThread.lastMsgUserId, userId != MainAppContext.shared.userData.userId {
                contactNamePart = MainAppContext.shared.contactStore.fullName(for: userId) + ": "
            }
        }

        var messageText = chatThread.lastMsgText ?? ""
        var mediaIcon: UIImage?
        switch chatThread.lastMsgMediaType {
        case .image:
            mediaIcon = UIImage(systemName: "photo")
            if messageText.isEmpty {
                messageText = "Photo"
            }

        case .video:
            mediaIcon = UIImage(systemName: "video.fill")
            if messageText.isEmpty {
                messageText = "Video"
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
            let scale = font.capHeight / imageSize.height

            let iconAttachment = NSTextAttachment(image: messageStatusIcon)
            iconAttachment.bounds.size = CGSize(width: ceil(imageSize.width * scale), height: ceil(imageSize.height * scale))

            result.append(NSAttributedString(attachment: iconAttachment))
            result.append(NSAttributedString(string: " "))
        }

        result.append(NSAttributedString(string: messageText))

        result.addAttributes([ .font: font, .foregroundColor: textColor ],
                             range: NSRange(location: 0, length: result.length))
        if !contactNamePart.isEmpty {
            // Note that the assumption is that we are using system font for the rest of the text.
            let participantNameFont = UIFont.systemFont(ofSize: font.pointSize, weight: .medium)
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

        if chatThread.unreadCount == 0 {
            unreadCountView.isHidden = true
            timeLabel.textColor = .secondaryLabel
        } else {
            unreadCountView.isHidden = false
            unreadCountView.label.text = String(chatThread.unreadCount)
            timeLabel.textColor = .systemBlue
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
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: UIColor.systemGray,
        ]
        
        let attributedString = NSMutableAttributedString(string: typingIndicatorStr, attributes: attributes)
        lastMsgLabel.attributedText = attributedString
        
        isShowingTypingIndicator = true
    }
    
    private func setup() {
        backgroundColor = .clear

        avatarView = AvatarViewButton(type: .custom)
        avatarView.hasNewPostsIndicator = ServerProperties.isGroupFeedEnabled
        avatarView.newPostsIndicatorRingWidth = LayoutConstants.avatarRingWidth
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

        let avatarSize: CGFloat = LayoutConstants.avatarSize + (avatarView.hasNewPostsIndicator ? 2*(avatarView.newPostsIndicatorRingSpacing + avatarView.newPostsIndicatorRingWidth) : 0)
        contentView.addConstraints([
            avatarView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.centerXAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor, constant: 0.5*LayoutConstants.avatarSize),
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
