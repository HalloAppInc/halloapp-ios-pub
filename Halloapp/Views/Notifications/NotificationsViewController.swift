//
//  Notifications.swift
//  Halloapp
//
//  Created by Tony Jiang on 11/17/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Combine
import Core
import CoreData
import UIKit

class NotificationsViewController: UITableViewController, NSFetchedResultsControllerDelegate {
    private static let cellReuseIdentifier = "NotificationsTableViewCell"

    private var dataSource: UITableViewDiffableDataSourceReference?
    private var fetchedResultsController: NSFetchedResultsController<FeedNotification>?

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = "Activity"
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(cancelAction))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Read All", style: .plain, target: self, action: #selector(markAllNotificationsRead))

        self.tableView.register(NotificationTableViewCell.self, forCellReuseIdentifier: NotificationsViewController.cellReuseIdentifier)
        self.tableView.separatorStyle = .none

        self.dataSource = UITableViewDiffableDataSourceReference(tableView: self.tableView) { tableView, indexPath, objectID in
            let cell = tableView.dequeueReusableCell(withIdentifier: NotificationsViewController.cellReuseIdentifier, for: indexPath) as! NotificationTableViewCell
            if let notification = try? MainAppContext.shared.feedData.viewContext.existingObject(with: objectID as! NSManagedObjectID) as? FeedNotification {
                cell.configure(with: notification)
            }
            return cell
        }

        let fetchRequest: NSFetchRequest<FeedNotification> = FeedNotification.fetchRequest()
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedNotification.timestamp, ascending: false) ]
        self.fetchedResultsController =
            NSFetchedResultsController<FeedNotification>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.feedData.viewContext,
                                                         sectionNameKeyPath: nil, cacheName: nil)
        self.fetchedResultsController?.delegate = self
        do {
            try self.fetchedResultsController!.performFetch()
        } catch {
            return
        }
    }

    // MARK: Fetched Results Controller

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        var reloadData = false
        if let currentObjectIDs = self.dataSource?.snapshot().itemIdentifiers as? [NSManagedObjectID],
            let updatedObjectIDs = snapshot.itemIdentifiers as? [NSManagedObjectID] {
            // If this method is called, but list of object IDs is the same it means
            // that one or more FeedNotification objects have been changed.
            // To reflect changes we call UITableView.reloadData.
            reloadData = currentObjectIDs == updatedObjectIDs
        }
        self.dataSource?.applySnapshot(snapshot, animatingDifferences: self.view.window != nil) {
            if reloadData {
                self.tableView.reloadData()
            }
        }
    }

    // MARK: Table View

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let notification = self.fetchedResultsController?.object(at: indexPath),
              let feedPost = MainAppContext.shared.feedData.feedPost(with: notification.postId) else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        let commentsViewController = CommentsViewController(feedPostId: feedPost.id)
        commentsViewController.highlightedCommentId = notification.commentId
        self.navigationController?.pushViewController(commentsViewController, animated: true)
    }

    // MARK: UI Actions

    @objc(cancelAction)
    private func cancelAction() {
        self.dismiss(animated: true)
    }

    @objc(markAllNotificationsRead)
    private func markAllNotificationsRead() {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: "Mark All as Read", style:.destructive) { _ in
            MainAppContext.shared.feedData.markNotificationsAsRead()
        })
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        self.present(actionSheet, animated: true)
    }
}

fileprivate class NotificationTableViewCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setupView()
    }

    private lazy var contactImage: AvatarView = {
        let imageView = AvatarView()
        imageView.heightAnchor.constraint(equalToConstant: 44).isActive = true
        imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor).isActive = true
        return imageView
    }()

    private lazy var notificationTextLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var unreadBadge: CircleView = {
        let badge = CircleView()
        badge.fillColor = .systemGreen
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.heightAnchor.constraint(equalToConstant: 6).isActive = true
        badge.widthAnchor.constraint(equalToConstant: 6).isActive = true
        return badge
    }()

    private lazy var mediaPreview: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.layer.cornerRadius = 8
        imageView.heightAnchor.constraint(equalToConstant: 44).isActive = true
        imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor).isActive = true
        return imageView
    }()

    private func setupView() {
        let hStack = UIStackView(arrangedSubviews: [ self.contactImage, self.notificationTextLabel, self.mediaPreview ])
        hStack.axis = .horizontal
        hStack.spacing = 8
        hStack.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(hStack)
        hStack.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        hStack.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor).isActive = true

        self.contentView.addSubview(self.unreadBadge)
        self.unreadBadge.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor).isActive = true
        self.unreadBadge.trailingAnchor.constraint(equalTo: hStack.leadingAnchor, constant: -4).isActive = true
    }

    func configure(with notification: FeedNotification) {
        self.unreadBadge.isHidden = notification.read
        self.backgroundColor = notification.read ? .systemBackground : .systemGray5
        self.notificationTextLabel.attributedText = notification.formattedText
        self.mediaPreview.image = notification.image
        
        contactImage.configure(with: notification.userId, using: MainAppContext.shared.avatarStore)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        contactImage.prepareForReuse()
    }
}
