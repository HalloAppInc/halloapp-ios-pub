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
import UIKit

// MARK: Constraint Constants
fileprivate struct LayoutConstants {
    static let avatarSize: CGFloat = 50
}

fileprivate enum ChatListViewSection {
    case main
}

class ChatListViewController: UITableViewController, NSFetchedResultsControllerDelegate, NewMessageViewControllerDelegate {

    private static let cellReuseIdentifier = "ChatListViewCell"
    private var fetchedResultsController: NSFetchedResultsController<ChatThread>?
    private var cancellableSet: Set<AnyCancellable> = []
    
    // MARK: Lifecycle
    
    init(title: String) {
        super.init(style: .plain)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("ChatListViewController/viewDidLoad")

        installLargeTitleUsingGothamFont()
        installFloatingActionMenu()
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
        navigationItem.standardAppearance = .opaqueAppearance
        
        tableView.backgroundColor = .feedBackground
        tableView.separatorStyle = .none
        tableView.register(ChatListTableViewCell.self, forCellReuseIdentifier: ChatListViewController.cellReuseIdentifier)

        setupFetchedResultsController()
        
        // When the user was on this view
        cancellableSet.insert(
            MainAppContext.shared.didTapNotification.sink { [weak self] (metadata) in
                guard let self = self else { return }
                guard metadata.contentType == .chat else { return }
                self.processNotification(metadata: metadata)
            }
        )

        // When the user was not on this view, and HomeView sends user to here
        if let metadata = NotificationUtility.Metadata.fromUserDefaults(), metadata.contentType == .chat {
            processNotification(metadata: metadata)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("ChatListViewController/viewWillAppear")
        super.viewWillAppear(animated)

        tableView.reloadData()
        populateWithSymmetricContacts()

        // Floating menu is hidden while our view is obscured
        floatingMenu.isHidden = false
    }

    override func viewDidAppear(_ animated: Bool) {
        DDLogInfo("ChatListViewController/viewDidAppear")
        super.viewDidAppear(animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Floating menu is in the navigation controller's view so we have to hide it
        floatingMenu.setState(.collapsed, animated: true)
        floatingMenu.isHidden = true
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
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
    
    // MARK: New Chat

    private lazy var floatingMenu: FloatingMenu = {
        FloatingMenu(
            permanentButton: .standardActionButton(
                iconTemplate: UIImage(named: "icon_fab_compose_message")?.withRenderingMode(.alwaysTemplate),
                accessibilityLabel: "New message",
                action: { [weak self] in self?.showContacts() }))
    }()

    private func installFloatingActionMenu() {
        // Install in NavigationController's view because our own view is a table view (complicates position and z-ordering)
        guard let container = navigationController?.view else {
            DDLogError("Cannot install FAB on chat list without navigation controller")
            return
        }

        floatingMenu.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(floatingMenu)
        floatingMenu.constrain(to: container)
    }

    private func showContacts() {
        let controller = NewMessageViewController()
        controller.delegate = self
        present(UINavigationController(rootViewController: controller), animated: true)
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
        if reloadTableViewInDidChangeContent {
            tableView.reloadData()
        }
    }

    private var lastCheckedForNewContacts: Date?
    
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
    
    // MARK: UITableView Delegates

    override func numberOfSections(in tableView: UITableView) -> Int {
        return fetchedResultsController?.sections?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sections = fetchedResultsController?.sections else { return 0 }
        return sections[section].numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatListViewController.cellReuseIdentifier, for: indexPath) as! ChatListTableViewCell
        if let chatThread = fetchedResultsController?.object(at: indexPath) {
            cell.configure(with: chatThread)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let chatThread = fetchedResultsController?.object(at: indexPath) else {
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
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if (editingStyle == .delete) {
            let actionSheet = UIAlertController(title: "Are you sure you want to delete this chat?", message: nil, preferredStyle: .actionSheet)
            actionSheet.addAction(UIAlertAction(title: "Delete Chat", style: .destructive) { action in
                if let chatThread = self.fetchedResultsController?.object(at: indexPath) {
                    if chatThread.type == .oneToOne {
                        guard let chatWithUserId = chatThread.chatWithUserId else { return }
                        MainAppContext.shared.chatData.deleteChat(chatThreadId: chatWithUserId)
                    } else {
                        guard let groupId = chatThread.groupId else { return }
                        MainAppContext.shared.chatData.deleteChatGroup(groupId: groupId)
                    }
                }
            })
            actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(actionSheet, animated: true)
        }
    }

    // MARK: New Message Delegates
    
    func newMessageViewController(_ newMessageViewController: NewMessageViewController, chatWithUserId: String) {
        newMessageViewController.dismiss(animated: true) {
            self.navigationController?.pushViewController(ChatViewController(for: chatWithUserId), animated: true)
        }
    }
    
    // MARK: Tap Notification
    
    private func processNotification(metadata: NotificationUtility.Metadata) {
        // If the user tapped on a notification, move to the chat view
        DDLogInfo("ChatListViewController/notification/open-chat \(metadata.fromId)")

        navigationController?.popToRootViewController(animated: false)
        navigationController?.pushViewController(ChatViewController(for: metadata.fromId, with: nil, at: 0), animated: true)

        metadata.removeFromUserDefaults()
    }
}


private class ChatListTableViewCell: UITableViewCell {

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

        nameLabel.text = nil
        timeLabel.text = nil
        lastMsgLabel.text = nil
        unreadCountView.isHidden = true
        
        avatarView.prepareForReuse()
    }

    private func lastMessageText(for chatThread: ChatThread) -> NSAttributedString {

        let textColor = UIColor.secondaryLabel
        let font = UIFont.preferredFont(forTextStyle: .footnote)

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
                return UIImage(named: "CheckmarkDouble")?.withTintColor(.systemBlue)

            case .delivered:
                return UIImage(named: "CheckmarkDouble")?.withTintColor(textColor)

            case .sentOut:
                return UIImage(named: "CheckmarkSingle")?.withTintColor(textColor)

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
            avatarView.configure(with: chatThread.chatWithUserId ?? "", using: MainAppContext.shared.avatarStore)
        }
    }
    
    private func setup() {
        backgroundColor = .clear

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

        contentView.addConstraints([
            avatarView.widthAnchor.constraint(equalToConstant: LayoutConstants.avatarSize),
            avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            avatarView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 8),

            vStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            vStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            vStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            vStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)
        ])
    }

    private lazy var avatarView: AvatarView = {
        return AvatarView()
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .gothamFont(forTextStyle: .subheadline, weight: .medium)
        label.textColor = .label
        return label
    }()
    
    private lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh + 50, for: .horizontal)
        return label
    }()

    private lazy var lastMsgLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()
    
    private lazy var unreadCountView: UnreadBadgeView = {
        let view = UnreadBadgeView(frame: .zero)
        view.label.font = .preferredFont(forTextStyle: .footnote)
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
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        label.widthAnchor.constraint(greaterThanOrEqualTo: label.heightAnchor, multiplier: 1).isActive = true
        label.constrainMargins(to: self)
    }
}
