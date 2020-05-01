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
    
    init(title: String) {
        super.init(style: .plain)
        self.title = title
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private lazy var newMessageViewController: NewMessageViewController = {
        let controller = NewMessageViewController()
        controller.delegate = self
        return controller
    }()
    
    func dismantle() {
        DDLogInfo("ChatListViewController/dismantle")
        self.cancellableSet.forEach{ $0.cancel() }
        self.cancellableSet.removeAll()
    }

    override func viewDidLoad() {
        DDLogInfo("ChatListViewController/viewDidLoad")

        self.navigationItem.title = "Messages"
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
        
        self.navigationItem.largeTitleDisplayMode = .automatic
        self.navigationItem.standardAppearance = Self.noBorderNavigationBarAppearance
        self.navigationItem.standardAppearance?.backgroundColor = UIColor.systemGray6

        let titleLabel = UILabel()
        titleLabel.text = self.title
        titleLabel.font = .gothamFont(ofSize: 33, weight: .bold)
        titleLabel.textColor = UIColor.label.withAlphaComponent(0.1)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(customView: titleLabel)
        self.navigationItem.title = nil
        
        self.navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "square.and.pencil"), style: .plain, target: self, action: #selector(showContacts)) ]
   
        self.tableView.backgroundColor = .clear
        self.tableView.separatorStyle = .none
        self.tableView.allowsSelection = true
        self.tableView.register(ChatListViewCell.self, forCellReuseIdentifier: ChatListViewController.cellReuseIdentifier)
        self.tableView.backgroundColor = UIColor.systemGray6
        
        self.setupFetchedResultsController()
        
    }

    // MARK: Appearance


    
    static var noBorderNavigationBarAppearance: UINavigationBarAppearance {
        get {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            appearance.shadowColor = nil
            return appearance
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("ChatListViewController/viewWillAppear")
        super.viewWillAppear(animated)
        self.tableView.reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        DDLogInfo("ChatListViewController/viewDidAppear")
        super.viewDidAppear(animated)
    }

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
                NSSortDescriptor(keyPath: \ChatThread.lastMsgTimestamp, ascending: false)
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
        let fetchedResultsController = NSFetchedResultsController<ChatThread>(fetchRequest: self.fetchRequest, managedObjectContext: AppContext.shared.chatData.viewContext,
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
        } else if reloadTableViewInDidChangeContent {
            self.tableView.reloadData()
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
            let contentWidth = tableView.frame.size.width - tableView.layoutMargins.left - tableView.layoutMargins.right
            cell.configure(with: chatThread, contentWidth: contentWidth)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let chatThread = fetchedResultsController?.object(at: indexPath) {
   
            self.navigationController?.pushViewController(ChatViewController(fromUserId: chatThread.chatWithUserId), animated: true)
            
        }
        
    }
    
    // MARK: New Message Delegates
    
    func newMessageViewController(_ newMessageViewController: NewMessageViewController, chatWithUserId: String) {
        print("here")
        self.navigationController?.pushViewController(ChatViewController(fromUserId: chatWithUserId), animated: true)
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
    
    private lazy var lastMessageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
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
    
    private lazy var unreadBadge: CircleView = {
        let badge = CircleView()
        badge.fillColor = .systemGreen
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.heightAnchor.constraint(equalToConstant: 10).isActive = true
        badge.widthAnchor.constraint(equalToConstant: 10).isActive = true
        return badge
    }()
    
    
    private func setup() {

        let imageSize: CGFloat = 40.0
        self.contactImageView.widthAnchor.constraint(equalToConstant: imageSize).isActive = true
        self.contactImageView.heightAnchor.constraint(equalTo: self.contactImageView.widthAnchor).isActive = true
        
        let hStackName = UIStackView(arrangedSubviews: [ self.nameLabel, self.timeLabel])
        hStackName.translatesAutoresizingMaskIntoConstraints = false
        hStackName.axis = .horizontal
        hStackName.alignment = .leading
        hStackName.spacing = 5
        
        let hStackLastMsg = UIStackView(arrangedSubviews: [ self.lastMessageLabel, self.unreadBadge])
        hStackLastMsg.translatesAutoresizingMaskIntoConstraints = false
        hStackLastMsg.axis = .horizontal
        hStackLastMsg.alignment = .leading
        hStackLastMsg.spacing = 5
        
        let vStack = UIStackView(arrangedSubviews: [hStackName, hStackLastMsg])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        vStack.spacing = 2
        
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.fittingSizeLevel, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.fittingSizeLevel, for: .horizontal)

        let hStack = UIStackView(arrangedSubviews: [ self.contactImageView, vStack])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.axis = .horizontal
        hStack.alignment = .leading
        hStack.spacing = 10

        self.contentView.addSubview(hStack)
        hStack.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        hStack.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor).isActive = true
    
        self.backgroundColor = .clear
        
    }


    public func configure(with chatThread: ChatThread, contentWidth: CGFloat) {
        self.nameLabel.text = AppContext.shared.contactStore.fullName(for: chatThread.chatWithUserId)
        self.lastMessageLabel.text = chatThread.lastMsgText
        if chatThread.unreadCount == 0 {
            self.unreadBadge.isHidden = true
            self.timeLabel.textColor = UIColor.secondaryLabel
        } else {
            self.unreadBadge.isHidden = false
            self.timeLabel.textColor = UIColor.systemGreen
        }
        if let timestamp = chatThread.lastMsgTimestamp {
            self.timeLabel.text = timestamp.commentTimestamp()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
    }

}

