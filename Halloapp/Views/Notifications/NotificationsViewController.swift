//
//  Notifications.swift
//  Halloapp
//
//  Created by Tony Jiang on 11/17/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
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

    private var dataSource: UITableViewDiffableDataSource<ActivityCenterSection, ActivityCenterNotification>!
    private var fetchedResultsController: NSFetchedResultsController<FeedNotification>!

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = Localizations.titleActivity
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(cancelAction))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Localizations.readAll, style: .plain, target: self, action: #selector(markAllNotificationsRead))

        tableView.register(NotificationTableViewCell.self, forCellReuseIdentifier: NotificationsViewController.cellReuseIdentifier)
        tableView.separatorStyle = .none

        dataSource = UITableViewDiffableDataSource<ActivityCenterSection, ActivityCenterNotification>(tableView: tableView) { tableView, indexPath, notification in
            let cell = tableView.dequeueReusableCell(withIdentifier: NotificationsViewController.cellReuseIdentifier, for: indexPath) as! NotificationTableViewCell
            cell.configure(with: notification)
            return cell
        }

        let fetchRequest: NSFetchRequest<FeedNotification> = FeedNotification.fetchRequest()
        if !ContactStore.contactsAccessAuthorized {
            let eligiblePostIdsFetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
            eligiblePostIdsFetchRequest.predicate = NSPredicate(format: "userId = %@ || groupId != nil", MainAppContext.shared.userData.userId)
            do {
                let eligiblePosts = try MainAppContext.shared.feedData.viewContext.fetch(eligiblePostIdsFetchRequest)
                let eligiblePostIds = eligiblePosts.compactMap {$0.id}
                fetchRequest.predicate = NSPredicate(format: "postId IN %@", eligiblePostIds)
            }
            catch {
                DDLogError("NotificationsViewController/viewDidLoad/failed to fetch eligible posts")
            }
        }
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedNotification.timestamp, ascending: false) ]
        fetchedResultsController =
            NSFetchedResultsController<FeedNotification>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.feedData.viewContext,
                                                         sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = self
        do {
            try fetchedResultsController!.performFetch()
            dataSource.apply(makeDataSnapshot())
        } catch { }
    }

    // MARK: Fetched Results Controller
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        dataSource.apply(makeDataSnapshot())
    }
    
    private func makeDataSnapshot() -> NSDiffableDataSourceSnapshot<ActivityCenterSection, ActivityCenterNotification> {
        var snapshot = NSDiffableDataSourceSnapshot<ActivityCenterSection, ActivityCenterNotification>()
        snapshot.appendSections([.main])
        
        if let items = fetchedResultsController.fetchedObjects {
            snapshot.appendItems(activityCenterNotifications(for: items))
        }
        
        return snapshot
    }
    
    private func activityCenterNotifications(for rawNotifications: [FeedNotification]) -> [ActivityCenterNotification] {
        var notifications: [ActivityCenterNotification] = []
        
        var postNotifications: [FeedPostID: [FeedNotification]] = [:]
        
        // Build dictionary of feed posts and the notifications associated with them
        rawNotifications.forEach { rawNotification in
            var dictionaryEntry = postNotifications[rawNotification.postId] ?? []

            if !dictionaryEntry.contains(where: { notification in
                rawNotification.userId == notification.userId
            }) {
                dictionaryEntry.append(rawNotification) // Storing entire feedNotification in case there's only one (in which case we add in non-grouped manner)
            }

            postNotifications[rawNotification.postId] = dictionaryEntry
        }
        
        for post in postNotifications {
            var postNotificationDictionary: [FeedNotification.Event : [FeedNotification]] = [:]
            
            // Build a dictionary of all the different types of notifications for a post
            post.value.forEach { notification in
                var existingNotifications = postNotificationDictionary[notification.event] ?? []
                existingNotifications.append(notification)
                postNotificationDictionary[notification.event] = existingNotifications
            }
            
            // For each type of notification, handle
            postNotificationDictionary.forEach { notificationType in
                switch notificationType.key {
                    case .otherComment: notifications.append(contentsOf: otherCommentNotifications(for: notificationType.value))
                    default: notifications.append(contentsOf: defaultNotifications(for: notificationType.value))
                }
            }
        }
        
        // Sort the notifications from newest to oldest before returning them
        return notifications.sorted { lhs, rhs in
            lhs.timestamp > rhs.timestamp
        }
    }
    
    /// Generates notifications for events where another user commented on a post you did. Groups together notifications for non-contacts.
    /// - Parameter postNotifications: Notifications to process
    /// - Returns: Array of activity center notifications for display
    private func otherCommentNotifications(for postNotifications: [FeedNotification]) -> [ActivityCenterNotification] {
        var notifications: [ActivityCenterNotification] = []
        
        // Get the notifications that came from contacts and add them as normal notifications
        let contactNotifications = postNotifications.filter { notification in
            MainAppContext.shared.contactStore.isContactInAddressBook(userId: notification.userId)
        }
        contactNotifications.forEach { notification in
            if let activityCenterNotification = ActivityCenterNotification(notificationType: .singleNotification(notification)) {
                notifications.append(activityCenterNotification)
            }
        }
        
        // Get the list of notifications that aren't from known contacts
        let nonContactNotifications = postNotifications.filter { notification in
            !MainAppContext.shared.contactStore.isContactInAddressBook(userId: notification.userId)
        }
        
        // Make sure multiple unknown contacts have commented on this post. If not, then simply add the latest non-contact notification
        guard Set<UserID>(nonContactNotifications.map({
            return $0.userId
        })).count > 1 else {
            if let notification = nonContactNotifications.first, let activityNotification = ActivityCenterNotification(notificationType: .singleNotification(notification)) {
                notifications.append(activityNotification)
            }
            
            return notifications
        }
        
        // Otherwise build a notification grouping non-contacts together
        if let activityNotification = ActivityCenterNotification(notificationType: .unknownCommenters(nonContactNotifications)) {
            notifications.append(activityNotification)
        }
        
        return notifications
    }
    
    /// Default handler for notifications. Simply passes them on as `ActivityCenterNotifications` without any modification
    private func defaultNotifications(for postNotifications: [FeedNotification]) -> [ActivityCenterNotification] {
        var notifications: [ActivityCenterNotification] = []
        
        postNotifications.forEach { notification in
            if let activityCenterNotification = ActivityCenterNotification(notificationType: .singleNotification(notification)) {
                notifications.append(activityCenterNotification)
            }
        }
        
        return notifications
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
            contactImage.bottomAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.bottomAnchor),

            notificationTextLabel.leadingAnchor.constraint(equalToSystemSpacingAfter: contactImage.trailingAnchor, multiplier: 1),
            notificationTextLabel.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            notificationTextLabel.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),

            mediaPreview.heightAnchor.constraint(equalToConstant: 44),
            mediaPreview.heightAnchor.constraint(equalTo: mediaPreview.widthAnchor),
            mediaPreview.leadingAnchor.constraint(equalToSystemSpacingAfter: notificationTextLabel.trailingAnchor, multiplier: 1),
            mediaPreview.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            mediaPreview.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            mediaPreview.bottomAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    func configure(with notification: ActivityCenterNotification) {
        backgroundColor = notification.read ? .systemBackground : .systemGray5

        unreadBadge.isHidden = notification.read
        notificationTextLabel.attributedText = notification.text
        mediaPreview.image = notification.image
        
        if let userId = notification.userID {
            contactImage.configure(with: userId, using: MainAppContext.shared.avatarStore)
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        contactImage.prepareForReuse()
    }
}
