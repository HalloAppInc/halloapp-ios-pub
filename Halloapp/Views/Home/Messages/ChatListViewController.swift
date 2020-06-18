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
import SwiftUI

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

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        DDLogInfo("ChatListViewController/viewDidLoad")

        installLargeTitleUsingGothamFont()
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
        
        let rightButton = UIButton(type: .system)
        rightButton.tintColor = .lavaOrange
        rightButton.setImage(UIImage(named: "ChatNavbarCompose"), for: .normal)
        rightButton.addTarget(self, action: #selector(showContacts), for: .touchUpInside)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: rightButton)
        
        self.navigationItem.standardAppearance = .transparentAppearance
        
        self.tableView.backgroundColor = .feedBackgroundColor
        self.tableView.separatorStyle = .none
        self.tableView.allowsSelection = true
        self.tableView.register(ChatListViewCell.self, forCellReuseIdentifier: ChatListViewController.cellReuseIdentifier)

        self.setupFetchedResultsController()
        
        // When the user was on this view
        self.cancellableSet.insert(
            MainAppContext.shared.didTapNotification.sink { [weak self] (status) in
                if !status { return }
                guard let self = self else { return }

                self.onTapNotification()
            }
        )

        // When the user was not on this view, and HomeView sends user to here
        self.onTapNotification()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("ChatListViewController/viewWillAppear")
        super.viewWillAppear(animated)
        self.tableView.reloadData()
        self.populateWithSymmetricContacts()
    }

    override func viewDidAppear(_ animated: Bool) {
        DDLogInfo("ChatListViewController/viewDidAppear")
        super.viewDidAppear(animated)
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == tableView {
            updateNavigationBarStyleUsing(scrollView: scrollView)
        }
    }
    
    // MARK: Top Nav Button Actions
    
    @objc(showContacts)
    private func showContacts() {
        let controller = NewMessageViewController()
        controller.delegate = self
        self.present(UINavigationController(rootViewController: controller), animated: true)
    }
    
    // MARK: Fetched Results Controller
    
    public var fetchRequest: NSFetchRequest<ChatThread> {
        get {
            let fetchRequest = NSFetchRequest<ChatThread>(entityName: "ChatThread")
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(key: "lastMsgTimestamp", ascending: false),
                NSSortDescriptor(key: "title", ascending: true)
            ]
            fetchRequest.predicate = NSPredicate(format: "chatWithUserId != nil")
            
            return fetchRequest
        }
    }

    private var trackPerRowFRCChanges = false

    private var reloadTableViewInDidChangeContent = false

    private func setupFetchedResultsController() {
        self.fetchedResultsController = self.newFetchedResultsController()
        do {
            try self.fetchedResultsController?.performFetch()
        } catch {
            fatalError("Failed to fetch feed items \(error)")
        }
    }

    private func newFetchedResultsController() -> NSFetchedResultsController<ChatThread> {
        // Setup fetched results controller the old way because it allows granular control over UI update operations.
        let fetchedResultsController = NSFetchedResultsController<ChatThread>(fetchRequest: self.fetchRequest, managedObjectContext: MainAppContext.shared.chatData.viewContext,
                                                                            sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        reloadTableViewInDidChangeContent = false
        trackPerRowFRCChanges = self.view.window != nil && UIApplication.shared.applicationState == .active
        DDLogDebug("ChatListView/frc/will-change perRowChanges=[\(trackPerRowFRCChanges)]")
        if trackPerRowFRCChanges {
            self.tableView.beginUpdates()
        }
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            guard let indexPath = newIndexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("ChatListView/frc/insert [\(chatThread)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.insertRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .delete:
            guard let indexPath = indexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("ChatListView/frc/delete [\(chatThread)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.deleteRows(at: [ indexPath ], with: .left)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("ChatListView/frc/move [\(chatThread)] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.moveRow(at: fromIndexPath, to: toIndexPath)
                reloadTableViewInDidChangeContent = true
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .update:
            guard let indexPath = indexPath, let chatThread = anObject as? ChatThread else { return }
            DDLogDebug("ChatListView/frc/update [\(chatThread)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.reloadRows(at: [ indexPath ], with: .automatic)
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
            self.tableView.endUpdates()
        }
        if reloadTableViewInDidChangeContent {
            self.tableView.reloadData()
        }
    }

    private var timeIntervalToCheck: TimeInterval = 60
    private var lastCheckedForNewContacts: Date?
    
    private func populateWithSymmetricContacts() {
        var isTimeToCheck = false
        if let lastCheckedForNewContacts = self.lastCheckedForNewContacts {
            isTimeToCheck = Date().timeIntervalSince(lastCheckedForNewContacts) >= self.timeIntervalToCheck
        } else {
            isTimeToCheck = true
        }

        if isTimeToCheck {
            DDLogDebug("ChatList/populateWithSymmetricContacts")
            MainAppContext.shared.chatData.populateThreadsWithSymmetricContacts()
            self.lastCheckedForNewContacts = Date()
        }
    }
    
    // MARK: UITableView Delegates

    override func numberOfSections(in tableView: UITableView) -> Int {
        return self.fetchedResultsController?.sections?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sections = self.fetchedResultsController?.sections else { return 0 }
        return sections[section].numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatListViewController.cellReuseIdentifier, for: indexPath) as! ChatListViewCell
        
        if let chatThread = fetchedResultsController?.object(at: indexPath) {
            cell.configure(with: chatThread)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let chatThread = fetchedResultsController?.object(at: indexPath) {
            self.navigationController?.pushViewController(ChatViewController(for: chatThread.chatWithUserId, with: nil, at: 0), animated: true)
        }
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if (editingStyle == .delete) {
            let uiAlert = UIAlertController(title: "Delete", message: "Are you sure you want to delete this chat?", preferredStyle: UIAlertController.Style.alert)
            self.present(uiAlert, animated: true, completion: nil)

            uiAlert.addAction(UIAlertAction(title: "Yes", style: .default, handler: { action in

                if let chatThread = self.fetchedResultsController?.object(at: indexPath) {
                    MainAppContext.shared.chatData.deleteChat(chatThreadId: chatThread.chatWithUserId)
                }
                
                
            }))

            uiAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        }
    }

    // MARK: New Message Delegates
    
    func newMessageViewController(_ newMessageViewController: NewMessageViewController, chatWithUserId: String) {
        self.navigationController?.pushViewController(ChatViewController(for: chatWithUserId), animated: true)
    }
    
    // MARK: Tap Notification
    
    private func onTapNotification() {
        // If the user tapped on a notification, move to the chat view
        if let metadata = NotificationUtility.Metadata.fromUserDefaults() {
            if metadata.contentType == .chat {
                DDLogInfo("appdelegate/tap-notifications/didDetect/changedToChatViewForUser \(metadata.fromId)")

                self.navigationController?.popToRootViewController(animated: false)
                self.navigationController?.pushViewController(ChatViewController(for: metadata.fromId, with: nil, at: 0), animated: true)
                
                metadata.removeFromUserDefaults()
                MainAppContext.shared.didTapNotification.send(false)
            }
        }
    }
}


fileprivate class ChatListViewCell: UITableViewCell {

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
        self.nameLabel.text = nil
        
        self.sentTickView.isHidden = true
        self.deliveredTicksView.isHidden = true
        
        self.lastMsgMediaPhotoIcon.isHidden = true
        self.lastMsgMediaVideoIcon.isHidden = true

        self.lastMsgLabel.text = nil
        
        self.timeLabel.text = nil
        self.unreadNumButton.isHidden = true
    }

    public func configure(with chatThread: ChatThread) {
        self.nameLabel.text = MainAppContext.shared.contactStore.fullName(for: chatThread.chatWithUserId)

        switch chatThread.lastMsgStatus {
        case .seen:
            self.sentTickView.isHidden = true
            self.sentTickView.tintColor = UIColor.systemBlue
            self.deliveredTicksView.isHidden = false
            self.deliveredTicksView.tintColor = UIColor.systemBlue
        case .delivered:
            self.sentTickView.isHidden = true
            self.sentTickView.tintColor = UIColor.systemGray3
            self.deliveredTicksView.isHidden = false
            self.deliveredTicksView.tintColor = UIColor.systemGray3
        case .sentOut:
            self.sentTickView.isHidden = false
            self.sentTickView.tintColor = UIColor.systemGray3
            self.deliveredTicksView.isHidden = true
            self.deliveredTicksView.tintColor = UIColor.systemGray3
        default:
            self.sentTickView.isHidden = true
            self.sentTickView.tintColor = UIColor.systemGray3
            self.deliveredTicksView.isHidden = true
            self.deliveredTicksView.tintColor = UIColor.systemGray3
        }
        
        if chatThread.lastMsgMediaType == .image {
            self.lastMsgMediaPhotoIcon.isHidden = false
            self.lastMsgMediaVideoIcon.isHidden = true
            self.lastMsgLabel.text = "Photo"
        } else if chatThread.lastMsgMediaType == .video {
            self.lastMsgMediaPhotoIcon.isHidden = true
            self.lastMsgMediaVideoIcon.isHidden = false
            self.lastMsgLabel.text = "Video"
        } else {
            self.lastMsgMediaPhotoIcon.isHidden = true
            self.lastMsgMediaVideoIcon.isHidden = true
            self.lastMsgLabel.text = nil
        }
        
        if chatThread.lastMsgText != nil && chatThread.lastMsgText != "" {
            self.lastMsgLabel.text = chatThread.lastMsgText
        }
        
        if chatThread.unreadCount == 0 {
            self.unreadNumButton.isHidden = true
            self.timeLabel.textColor = .secondaryLabel
        } else {
            self.unreadNumButton.isHidden = false
            self.unreadNumButton.setTitle(String(chatThread.unreadCount), for: .normal)
            self.timeLabel.textColor = .systemBlue
        }
        
        if let timestamp = chatThread.lastMsgTimestamp {
            self.timeLabel.text = timestamp.chatListTimestamp()
        }
    }
    
    // MARK: Avatar Column
    
    private lazy var avatarColumn: UIImageView = {
        let view = UIImageView(image: UIImage.init(systemName: "person.crop.circle"))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.tintColor = UIColor.systemGray
        return view
    }()
    
    // MARK: Text Column
    
    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()
    
    private lazy var sentTickView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "CheckmarkSingle")?.withRenderingMode(.alwaysTemplate))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor.systemGray3
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        imageView.isHidden = true
        return imageView
    }()
    
    private lazy var deliveredTicksView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "CheckmarkDouble")?.withRenderingMode(.alwaysTemplate))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor.systemGray3
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        imageView.isHidden = true
        return imageView
    }()
    
    private lazy var lastMsgMediaPhotoIcon: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "photo"))
        view.tintColor = UIColor.systemGray
        
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        
        view.isHidden = true
        return view
    }()
        
    private lazy var lastMsgMediaVideoIcon: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "video.fill"))
        view.tintColor = UIColor.systemGray
        
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        
        view.isHidden = true
        return view
    }()
    
    private lazy var lastMsgLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()
    
    private lazy var unreadNumButton: UIButton = {
        let view = UIButton()
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBlue
        view.contentEdgeInsets = UIEdgeInsets(top: 1, left: 6, bottom: 1, right: 6)
        view.titleLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
        view.tintColor = UIColor.systemGray6
        view.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        view.layer.cornerRadius = 10
        view.clipsToBounds = true
        view.isHidden = true
        
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: 15.0).isActive = true
        return view
    }()
    
    private lazy var lastMsgRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [
            self.sentTickView,
            self.deliveredTicksView,
            self.lastMsgMediaPhotoIcon,
            self.lastMsgMediaVideoIcon,
            self.lastMsgLabel,
            self.unreadNumButton])
        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 10
        
        view.translatesAutoresizingMaskIntoConstraints = false
        self.lastMsgMediaPhotoIcon.heightAnchor.constraint(equalTo: self.lastMsgLabel.heightAnchor).isActive = true
        self.lastMsgMediaVideoIcon.heightAnchor.constraint(equalTo: self.lastMsgLabel.heightAnchor).isActive = true
        
        self.sentTickView.heightAnchor.constraint(equalTo: self.lastMsgLabel.heightAnchor).isActive = true
        self.deliveredTicksView.heightAnchor.constraint(equalTo: self.lastMsgLabel.heightAnchor).isActive = true
        
        return view
    }()
    
    private lazy var nameRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [self.nameLabel, self.timeLabel])
        view.axis = .horizontal
        view.alignment = .leading
        view.spacing = 5
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
        
    private lazy var textColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [self.nameRow, self.lastMsgRow])
        view.axis = .vertical
        view.spacing = 2
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var mainRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [self.avatarColumn, self.textColumn])
        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 10
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private func setup() {
        self.backgroundColor = .clear
        
        let imageSize: CGFloat = 40.0
        self.avatarColumn.widthAnchor.constraint(equalToConstant: imageSize).isActive = true
        self.avatarColumn.heightAnchor.constraint(equalTo: self.avatarColumn.widthAnchor).isActive = true
        
        self.contentView.addSubview(mainRow)
        mainRow.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        mainRow.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor).isActive = true
        mainRow.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor).isActive = true
        mainRow.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor).isActive = true
    }
}
