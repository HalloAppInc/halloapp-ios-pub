//
//  Notifications.swift
//  Halloapp
//
//  Created by Tony Jiang on 11/17/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Core
import CoreData
import UIKit

private extension Localizations {

    static var titleActivity: String {
        NSLocalizedString("activity.center.title", value: "Activity", comment: "Title for the activity center screen.")
    }

    static var readAll: String {
        NSLocalizedString("activity.center.button.read.all", value: "Read All", comment: "Short title for the button in activity center.")
    }

    static var markAllRead: String {
        NSLocalizedString("activity.center.button.mark.all.read", value: "Mark All as Read", comment: "Longer title for the button that confirms marking all items in the activity center as read.")
    }
}

class NotificationsViewController: UITableViewController, NSFetchedResultsControllerDelegate {

    private static let cellReuseIdentifier = "NotificationsTableViewCell"

    private var dataSource: UITableViewDiffableDataSourceReference!
    private var fetchedResultsController: NSFetchedResultsController<FeedNotification>!

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = Localizations.titleActivity
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(cancelAction))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Localizations.readAll, style: .plain, target: self, action: #selector(markAllNotificationsRead))

        tableView.register(NotificationTableViewCell.self, forCellReuseIdentifier: NotificationsViewController.cellReuseIdentifier)
        tableView.separatorStyle = .none

        dataSource = UITableViewDiffableDataSourceReference(tableView: tableView) { tableView, indexPath, objectID in
            let cell = tableView.dequeueReusableCell(withIdentifier: NotificationsViewController.cellReuseIdentifier, for: indexPath) as! NotificationTableViewCell
            if let notification = try? MainAppContext.shared.feedData.viewContext.existingObject(with: objectID as! NSManagedObjectID) as? FeedNotification {
                cell.configure(with: notification)
            }
            return cell
        }

        let fetchRequest: NSFetchRequest<FeedNotification> = FeedNotification.fetchRequest()
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedNotification.timestamp, ascending: false) ]
        fetchedResultsController =
            NSFetchedResultsController<FeedNotification>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.feedData.viewContext,
                                                         sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = self
        do {
            try fetchedResultsController!.performFetch()
        } catch { }
    }

    // MARK: Fetched Results Controller

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        var reloadData = false
        if let currentObjectIDs = dataSource.snapshot().itemIdentifiers as? [NSManagedObjectID],
            let updatedObjectIDs = snapshot.itemIdentifiers as? [NSManagedObjectID] {
            // If this method is called, but list of object IDs is the same it means
            // that one or more FeedNotification objects have been changed.
            // To reflect changes we call UITableView.reloadData.
            reloadData = currentObjectIDs == updatedObjectIDs
        }
        dataSource.applySnapshot(snapshot, animatingDifferences: view.window != nil) {
            if reloadData {
                self.tableView.reloadData()
            }
        }
    }

    // MARK: Table View

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let notification = fetchedResultsController.object(at: indexPath)
        guard let feedPost = MainAppContext.shared.feedData.feedPost(with: notification.postId) else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        let commentsViewController = CommentsViewController(feedPostId: feedPost.id)
        commentsViewController.highlightedCommentId = notification.commentId
        navigationController?.pushViewController(commentsViewController, animated: true)
    }

    // MARK: UI Actions

    @objc private func cancelAction() {
        dismiss(animated: true)
    }

    @objc private func markAllNotificationsRead() {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: Localizations.markAllRead, style:.destructive) { _ in
            MainAppContext.shared.feedData.markNotificationsAsRead()
        })
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        present(actionSheet, animated: true)
    }
}

fileprivate class NotificationTableViewCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private lazy var contactImage: AvatarView = {
        let imageView = AvatarView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
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
        return badge
    }()

    private lazy var mediaPreview: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.layer.cornerRadius = 8
        return imageView
    }()

    private func setupView() {
        contentView.addSubview(unreadBadge)
        contentView.addSubview(contactImage)
        contentView.addSubview(notificationTextLabel)
        contentView.addSubview(mediaPreview)

        contentView.addConstraints([
            unreadBadge.heightAnchor.constraint(equalToConstant: 6),
            unreadBadge.widthAnchor.constraint(equalTo: unreadBadge.heightAnchor),
            unreadBadge.centerYAnchor.constraint(equalTo: contactImage.centerYAnchor),
            unreadBadge.trailingAnchor.constraint(equalTo: contactImage.leadingAnchor, constant: -4),

            contactImage.heightAnchor.constraint(equalToConstant: 44),
            contactImage.heightAnchor.constraint(equalTo: contactImage.widthAnchor),
            contactImage.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            contactImage.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),

            notificationTextLabel.leadingAnchor.constraint(equalToSystemSpacingAfter: contactImage.trailingAnchor, multiplier: 1),
            notificationTextLabel.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            notificationTextLabel.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),

            mediaPreview.heightAnchor.constraint(equalToConstant: 44),
            mediaPreview.heightAnchor.constraint(equalTo: mediaPreview.widthAnchor),
            mediaPreview.leadingAnchor.constraint(equalToSystemSpacingAfter: notificationTextLabel.trailingAnchor, multiplier: 1),
            mediaPreview.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            mediaPreview.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
        ])
    }

    func configure(with notification: FeedNotification) {
        backgroundColor = notification.read ? .systemBackground : .systemGray5

        unreadBadge.isHidden = notification.read
        notificationTextLabel.attributedText = notification.formattedText
        mediaPreview.image = notification.image
        contactImage.configure(with: notification.userId, using: MainAppContext.shared.avatarStore)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        contactImage.prepareForReuse()
    }
}
