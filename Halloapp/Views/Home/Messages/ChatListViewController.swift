//
//  ChatListViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/25/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import CoreData
import SwiftUI
import UIKit

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

        self.navigationItem.title = "Messages"
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)

        self.navigationItem.largeTitleDisplayMode = .automatic
        self.navigationItem.standardAppearance = .noShadowAppearance
        self.navigationItem.standardAppearance?.backgroundColor = UIColor.systemGray6

        let titleLabel = UILabel()
        titleLabel.attributedText = self.largeTitleUsingGothamFont
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(customView: titleLabel)
        self.navigationItem.title = nil

        self.navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "ChatNavbarCompose"), style: .plain, target: self, action: #selector(showContacts))

        self.tableView.backgroundColor = .clear
        self.tableView.separatorStyle = .none
        self.tableView.allowsSelection = true
        self.tableView.register(ChatListViewCell.self, forCellReuseIdentifier: ChatListViewController.cellReuseIdentifier)
        self.tableView.backgroundColor = UIColor.systemGray6

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
    
    func dismantle() {
        DDLogInfo("ChatListViewController/dismantle")
        self.cancellableSet.forEach{ $0.cancel() }
        self.cancellableSet.removeAll()
    }
    
    private lazy var newMessageViewController: NewMessageViewController = {
        let controller = NewMessageViewController()
        controller.delegate = self
        return controller
    }()

    // MARK: Top Nav Button Actions
    
    @objc(showContacts)
    private func showContacts() {
        self.present(UINavigationController(rootViewController: self.newMessageViewController), animated: true)
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
                self.tableView.deleteRows(at: [ indexPath ], with: .automatic)
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
    
    // MARK: UITableView

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
            self.navigationController?.pushViewController(ChatViewController(for: chatThread.chatWithUserId, with: nil, at: 0, status: chatThread.status, lastSeen: nil), animated: true)
//            let lastSeen = chatThread.lastSeenTimestamp
//            self.navigationController?.pushViewController(ChatViewController(for: chatThread.chatWithUserId, with: nil, at: 0, status: chatThread.status, lastSeen: lastSeen), animated: true)
        }
    }
    
    // MARK: New Message Delegates
    
    func newMessageViewController(_ newMessageViewController: NewMessageViewController, chatWithUserId: String) {
        self.navigationController?.pushViewController(ChatViewController(for: chatWithUserId), animated: true)
    }
    
    // MARK: Tap Notification
    
    private func onTapNotification() {
        // If the user tapped on a notification, move to the chat view
        if let metadata = UserDefaults.standard.object(forKey: NotificationKey.keys.userDefaults) as? [String: String] {
            guard metadata[NotificationKey.keys.contentType] == NotificationKey.contentType.chat else { return }

            if let senderId = metadata[NotificationKey.keys.fromId] {
                DDLogInfo("appdelegate/tap-notifications/didDetect/changedToChatViewForUser \(senderId)")

                self.navigationController?.popToRootViewController(animated: false)
                self.navigationController?.pushViewController(ChatViewController(for: senderId, with: nil, at: 0, status: .none, lastSeen: nil), animated: true)
            }

            UserDefaults.standard.removeObject(forKey: NotificationKey.keys.userDefaults)
            MainAppContext.shared.didTapNotification.send(false)
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
        self.lastMessageLabel.text = nil
        self.timeLabel.text = nil
        self.unreadNumButton.isHidden = true
    }

    public func configure(with chatThread: ChatThread) {
        self.nameLabel.text = MainAppContext.shared.contactStore.fullName(for: chatThread.chatWithUserId)
        self.lastMessageLabel.text = chatThread.lastMsgText
        if chatThread.unreadCount == 0 {
            self.unreadNumButton.isHidden = true
            self.timeLabel.textColor = UIColor.secondaryLabel
        } else {
            self.unreadNumButton.isHidden = false
            self.unreadNumButton.setTitle(String(chatThread.unreadCount), for: .normal)
            self.timeLabel.textColor = .lavaOrange
        }
        if let timestamp = chatThread.lastMsgTimestamp {
            self.timeLabel.text = timestamp.chatTimestamp()
        }
    }
    
    private lazy var contactImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage.init(systemName: "person.crop.circle"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.tintColor = UIColor.systemGray
        return imageView
    }()
    
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
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return label
    }()
    
    private lazy var lastMessageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        return label
    }()
    
    private lazy var unreadNumButton: UIButton = {
        let view = UIButton()
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .lavaOrange
        view.contentEdgeInsets = UIEdgeInsets(top: 1, left: 6, bottom: 1, right: 6)
        view.titleLabel?.font = UIFont.preferredFont(forTextStyle: .footnote)
        view.tintColor = UIColor.systemGray6
        view.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        view.layer.cornerRadius = 9
        view.clipsToBounds = true
        view.isHidden = true
        
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: 15.0).isActive = true
        return view
    }()
    
    private lazy var lastMsgRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.fittingSizeLevel, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.fittingSizeLevel, for: .horizontal)
        
        let view = UIStackView(arrangedSubviews: [self.lastMessageLabel, spacer, self.unreadNumButton])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .horizontal
        view.spacing = 5
        return view
    }()

    private func setup() {
        self.backgroundColor = .clear
        
        let imageSize: CGFloat = 40.0
        self.contactImageView.widthAnchor.constraint(equalToConstant: imageSize).isActive = true
        self.contactImageView.heightAnchor.constraint(equalTo: self.contactImageView.widthAnchor).isActive = true
        
        let hStackName = UIStackView(arrangedSubviews: [self.nameLabel, self.timeLabel])
        hStackName.translatesAutoresizingMaskIntoConstraints = false
        hStackName.axis = .horizontal
        hStackName.alignment = .leading
        hStackName.spacing = 5
        
        let vStack = UIStackView(arrangedSubviews: [hStackName, self.lastMsgRow])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        vStack.spacing = 2
        
        let hStack = UIStackView(arrangedSubviews: [self.contactImageView, vStack])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.axis = .horizontal
        hStack.alignment = .leading
        hStack.spacing = 10

        self.contentView.addSubview(hStack)
        hStack.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        hStack.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor).isActive = true
    }
    
}
