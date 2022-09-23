//
//  Notifications.swift
//  Halloapp
//
//  Created by Tony Jiang on 11/17/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import CoreData
import UIKit

private extension Localizations {
    static var readAll: String {
        NSLocalizedString("activity.center.button.read.all", value: "Read All", comment: "Short title for the button in activity center.")
    }

    static var markAllRead: String {
        NSLocalizedString("activity.center.button.mark.all.read", value: "Mark All as Read", comment: "Longer title for the button that confirms marking all items in the activity center as read.")
    }
}

class NotificationsViewController: UIViewController, UITableViewDelegate, NSFetchedResultsControllerDelegate {
    private static let cellReuseIdentifier = "NotificationsTableViewCell"
    
    private let bottomSafeAreaHeight = UIApplication.shared.windows[0].safeAreaInsets.bottom

    private var dataSource: UITableViewDiffableDataSource<ActivityCenterSection, ActivityCenterItem>!
    private lazy var tableView: UITableView = UITableView()
  
    /// - note: Used for when the user marks all notifications as read.
    private var cachedScrollPosition: (indexPath: IndexPath, offset: CGFloat)?

    private var permissionsViewController: InAppPermissionsViewController?

    private lazy var feedActivityFetchedResultsController: NSFetchedResultsController<FeedActivity> = {
        let fetchRequest: NSFetchRequest<FeedActivity> = FeedActivity.fetchRequest()
        if !ContactStore.contactsAccessAuthorized {
            let eligiblePostIdsFetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
            eligiblePostIdsFetchRequest.predicate = NSPredicate(format: "(userID = %@ || groupID != nil) && fromExternalShare == NO",
                                                                MainAppContext.shared.userData.userId)
            do {
                let eligiblePosts = try MainAppContext.shared.feedData.viewContext.fetch(eligiblePostIdsFetchRequest)
                let eligiblePostIds = eligiblePosts.compactMap {$0.id}
                fetchRequest.predicate = NSPredicate(format: "postID IN %@", eligiblePostIds)
            }
            catch {
                DDLogError("NotificationsViewController/viewDidLoad/failed to fetch eligible posts")
            }
        }
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedActivity.timestamp, ascending: false) ]
        return NSFetchedResultsController<FeedActivity>(fetchRequest: fetchRequest,
                                                        managedObjectContext: MainAppContext.shared.mainDataStore.viewContext,
                                                        sectionNameKeyPath: nil,
                                                        cacheName: nil)
    }()

    private lazy var groupEventFetchedResultsController: NSFetchedResultsController<GroupEvent> = {
        let userID = MainAppContext.shared.userData.userId
        let fetchRequest = GroupEvent.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "actionValue = %d && memberActionValue = %d && memberUserID = %@",
                            GroupEvent.Action.modifyMembers.rawValue, GroupEvent.MemberAction.remove.rawValue, userID),
                NSPredicate(format: "actionValue = %d && memberActionValue = %d && memberUserID = %@",
                            GroupEvent.Action.modifyMembers.rawValue, GroupEvent.MemberAction.add.rawValue, userID),
                NSPredicate(format: "actionValue = %d && memberActionValue = %d && memberUserID = %@",
                            GroupEvent.Action.modifyAdmins.rawValue, GroupEvent.MemberAction.demote.rawValue, userID),
                NSPredicate(format: "actionValue = %d && memberActionValue = %d && memberUserID = %@",
                            GroupEvent.Action.modifyAdmins.rawValue, GroupEvent.MemberAction.promote.rawValue, userID),
                NSPredicate(format: "actionValue = %d", GroupEvent.Action.create.rawValue),
                NSPredicate(format: "actionValue = %d", GroupEvent.Action.changeExpiry.rawValue),
                NSPredicate(format: "actionValue = %d", GroupEvent.Action.changeName.rawValue),
                NSPredicate(format: "actionValue = %d", GroupEvent.Action.changeDescription.rawValue),
            ]),
            NSPredicate(format: "senderUserID != %@", userID),
            NSPredicate(format: "timestamp >= %@", Date(timeIntervalSinceNow: Date.days(-31)) as NSDate),
        ])
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \GroupEvent.timestamp, ascending: false)
        ]
        return NSFetchedResultsController(fetchRequest: fetchRequest,
                                          managedObjectContext: MainAppContext.shared.mainDataStore.viewContext,
                                          sectionNameKeyPath: nil,
                                          cacheName: nil)
    }()

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = Localizations.titleActivity
        installAvatarBarButton()

        let readAll = UIBarButtonItem(title: Localizations.readAll, buildMenu: readAllMenu)
        readAll.tintColor = .primaryBlue
        navigationItem.rightBarButtonItem = readAll

        tableView.delegate = self
        tableView.register(AllowContactsPermissionTableViewHeader.self, forHeaderFooterViewReuseIdentifier: AllowContactsPermissionTableViewHeader.reuseIdentifier)
        tableView.register(NotificationTableViewCell.self, forCellReuseIdentifier: NotificationsViewController.cellReuseIdentifier)
        tableView.separatorStyle = .none
        
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.constrain(to: view)
        
        tableView.backgroundColor = .primaryBg
        view.backgroundColor = .primaryBg
        
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60 // set a number close to default to prevent cells overlapping issue, can't be auto

        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 44
        if #available(iOS 15, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        dataSource = UITableViewDiffableDataSource<ActivityCenterSection, ActivityCenterItem>(tableView: tableView) { tableView, indexPath, notification in
            let cell = tableView.dequeueReusableCell(withIdentifier: NotificationsViewController.cellReuseIdentifier, for: indexPath) as! NotificationTableViewCell
            cell.configure(with: notification)
            return cell
        }

        feedActivityFetchedResultsController.delegate = self
        try? feedActivityFetchedResultsController.performFetch()

        groupEventFetchedResultsController.delegate = self
        try? groupEventFetchedResultsController.performFetch()

        updateUI()

        if !ContactStore.contactsAccessAuthorized, dataSource.snapshot().itemIdentifiers.isEmpty {
            showPermissionsViewController()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // remove the red dot when the user navigates to this screen
        navigationController?.tabBarItem.badgeValue = nil
    }

    private func updateUI() {
        let snapshot = makeDataSnapshot()
        let hasUnreadItem = snapshot.itemIdentifiers.contains { $0.read == false }

        dataSource.apply(snapshot, animatingDifferences: false)
        navigationItem.rightBarButtonItem?.isEnabled = hasUnreadItem

        if snapshot.itemIdentifiers.count > 0, let permissionsVC = permissionsViewController {
            permissionsVC.view.removeFromSuperview()
            permissionsVC.removeFromParent()
            permissionsViewController = nil
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if let cachedPosition = cachedScrollPosition, tableView.contains(indexPath: cachedPosition.indexPath) {
            tableView.scrollToRow(at: cachedPosition.indexPath, at: .top, animated: false)
            tableView.layoutIfNeeded()
            let cellRect = tableView.rectForRow(at: cachedPosition.indexPath)
            
            tableView.contentOffset = CGPoint(x: 0, y: cellRect.minY + cachedPosition.offset)
        }
        
        cachedScrollPosition = nil
    }

    private func showPermissionsViewController() {
        let vc = InAppPermissionsViewController(configuration: .activityCenter)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(vc.view)
        addChild(vc)

        NSLayoutConstraint.activate([
            vc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            vc.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            vc.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        permissionsViewController = vc
    }

    // MARK: Fetched Results Controller
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        updateUI()
    }
    
    private func makeDataSnapshot() -> NSDiffableDataSourceSnapshot<ActivityCenterSection, ActivityCenterItem> {
        var snapshot = NSDiffableDataSourceSnapshot<ActivityCenterSection, ActivityCenterItem>()
        snapshot.appendSections([.main])

        var items: [ActivityCenterItem] = []

        if let feedActivities = feedActivityFetchedResultsController.fetchedObjects {
            items += activityCenterItems(for: feedActivities)
        }

        if let groupEvents = groupEventFetchedResultsController.fetchedObjects {
            items += groupEvents.compactMap { ActivityCenterItem(content: .groupEvent($0)) }
        }

        // Sort the notifications from newest to oldest before returning them
        items.sort { lhs, rhs in
            lhs.timestamp > rhs.timestamp
        }

        snapshot.appendItems(items)

        return snapshot
    }
    
    private func activityCenterItems(for rawNotifications: [FeedActivity]) -> [ActivityCenterItem] {
        var displayItems: [ActivityCenterItem] = []
        
        let notificationsPerPost: [FeedPostID: [FeedActivity]] = rawNotifications.reduce(into: [:]) {
            let previousNotificationsForPost: [FeedActivity] = $0[$1.postID] ?? []
            $0[$1.postID] = previousNotificationsForPost + [$1]
        }
        
        for (_, postNotifications) in notificationsPerPost {
            let notificationsPerEventType: [FeedActivity.Event : [FeedActivity]] = postNotifications.reduce(into: [:]) {
                let previousNotificationsForEvent: [FeedActivity] = $0[$1.event] ?? []
                $0[$1.event] = previousNotificationsForEvent + [$1]
            }
            
            // For each type of notification, handle
            notificationsPerEventType.forEach { (eventType, notifications) in
                switch eventType {
                case .otherComment:
                    displayItems.append(contentsOf: otherCommentItems(for: notifications))
                case .groupComment:
                    displayItems.append(contentsOf: mergedCommentItems(for: notifications))
                case .homeFeedComment:
                    displayItems.append(contentsOf: mergedCommentItems(for: notifications))
                default:
                    displayItems.append(contentsOf: defaultItems(for: notifications))
                }
            }
        }
        return displayItems
    }
    
    /// Generates notifications for events where another user commented on a post you did. Groups together notifications for non-contacts.
    /// - Parameter postNotifications: Notifications to process
    /// - Returns: Array of activity center notifications for display
    private func otherCommentItems(for postNotifications: [FeedActivity]) -> [ActivityCenterItem] {
        var items: [ActivityCenterItem] = []
        
        // Add an item for each comment made by a contact
        let contactsViewContext = MainAppContext.shared.contactStore.viewContext
        let contactNotifications = postNotifications.filter { notification in
            MainAppContext.shared.contactStore.isContactInAddressBook(userId: notification.userID, in: contactsViewContext)
        }
        let itemsForContactComments = contactNotifications.compactMap {
            ActivityCenterItem(content: .singleNotification($0))
        }
        items += itemsForContactComments
        
        // Aggregate all comments from non-contacts into a single item
        let nonContactNotifications = postNotifications.filter { notification in
            !MainAppContext.shared.contactStore.isContactInAddressBook(userId: notification.userID, in: contactsViewContext)
        }
        let itemForNonContactComments: ActivityCenterItem? = {
            let nonContactsWhoCommented = Set<UserID>(nonContactNotifications.map { $0.userID })
            if nonContactsWhoCommented.count > 1 {
                // Aggregate comments from multiple non-contacts
                return ActivityCenterItem(content: .unknownCommenters(nonContactNotifications))
            } else if let notification = nonContactNotifications.first {
                // If one non-contact has commented, show his or her latest comment
                return ActivityCenterItem(content: .singleNotification(notification))
            } else {
                // No comments from non-contacts
                return nil
            }
        }()
        if let itemForNonContactComments = itemForNonContactComments {
            items.append(itemForNonContactComments)
        }

        return items
    }

    private func mergedCommentItems(for postNotifications: [FeedActivity]) -> [ActivityCenterItem] {
        var items: [ActivityCenterItem] = []

        // Aggregate all group comments from posts into a single item
        let itemForGroupComments: ActivityCenterItem? = {
            let usersWhoCommented = Set<UserID>(postNotifications.map { $0.userID })
            if usersWhoCommented.count > 1 {
                // Aggregate comments from multiple non-contacts
                return ActivityCenterItem(content: .unknownCommenters(postNotifications))
            } else if let notification = postNotifications.first {
                // If one user has commented, show his or her latest comment
                return ActivityCenterItem(content: .singleNotification(notification))
            } else {
                // No comments from non-contacts
                return nil
            }
        }()
        if let itemForGroupComments = itemForGroupComments {
            items.append(itemForGroupComments)
        }

        return items
    }
    
    /// Default handler for notifications. Simply passes them on as `ActivityCenterItems` without any modification
    private func defaultItems(for postNotifications: [FeedActivity]) -> [ActivityCenterItem] {
        return postNotifications.compactMap {
            ActivityCenterItem(content: .singleNotification($0))
        }
    }

    // MARK: Table View
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let activityCenterItem = dataSource.itemIdentifier(for: indexPath) else {
            DDLogError("NotificationsViewController/didSelectRowAt/missing notification at \(indexPath)")
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)

        switch activityCenterItem.content {
        case .singleNotification(let notification):
            if notification.event == .favoritesPromo {
                MainAppContext.shared.feedData.markNotificationsAsRead(for: "favorites")
                let presentingViewController = presentingViewController
                dismiss(animated: true)
                presentingViewController?.present(FavoritesInformationViewController(), animated: true)
            } else if MainAppContext.shared.feedData.feedPost(with: notification.postID, in: MainAppContext.shared.feedData.viewContext) != nil {
                let commentsViewController = FlatCommentsViewController(feedPostId: notification.postID)
                commentsViewController.initiallyHighlightedCommentID = notification.commentID
                navigationController?.pushViewController(commentsViewController, animated: true)
            }
        case .unknownCommenters(_):
            if let postID = activityCenterItem.postId, MainAppContext.shared.feedData.feedPost(with: postID, in: MainAppContext.shared.feedData.viewContext) != nil {
                let commentsViewController = FlatCommentsViewController(feedPostId: postID)
                commentsViewController.initiallyHighlightedCommentID = activityCenterItem.commentId
                navigationController?.pushViewController(commentsViewController, animated: true)
            }
        case .groupEvent(let groupEvent):
            MainAppContext.shared.chatData.markGroupEventAsRead(groupEvent: groupEvent)
            let groupFeedViewController = GroupFeedViewController(groupId: groupEvent.groupID)
            groupFeedViewController.groupEventToScrollTo = groupEvent
            navigationController?.pushViewController(groupFeedViewController, animated: true)
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard !ContactStore.contactsAccessAuthorized else {
            return nil
        }

        return tableView.dequeueReusableHeaderFooterView(withIdentifier: AllowContactsPermissionTableViewHeader.reuseIdentifier)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        ContactStore.contactsAccessAuthorized ? .zero : UITableView.automaticDimension
    }

    // MARK: UI Actions

    @objc private func cancelAction() {
        dismiss(animated: true)
    }

    private func readAllMenu() -> HAMenu {
        HAMenu {
            HAMenuButton(title: Localizations.markAllRead) { [weak self] in
                MainAppContext.shared.feedData.markNotificationsAsRead()
                MainAppContext.shared.chatData.markAllGroupEventsAsRead()
                self?.memoizeScrollPosition()
            }.destructive()
        }
    }
    
    private func memoizeScrollPosition() {
        guard let firstVisiblePath = tableView.indexPathsForVisibleRows?.first else {
            return
        }
        
        let rect = tableView.rectForRow(at: firstVisiblePath)
        let offset = tableView.contentOffset.y - rect.minY
        cachedScrollPosition = (firstVisiblePath, offset)
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
        badge.fillColor = .commentIndicatorUnread
        badge.translatesAutoresizingMaskIntoConstraints = false
        return badge
    }()

    private lazy var mediaPreview: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.layer.cornerRadius = 8
        imageView.backgroundColor = .feedPostBackground
        imageView.layer.masksToBounds = true
        imageView.layer.borderColor = UIColor.lightGray.withAlphaComponent(0.5).cgColor
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22)
        imageView.tintColor = .darkGray
        return imageView
    }()
    
    private var mediaPreviewWidthAnchor: NSLayoutConstraint?

    private func setupView() {
        contentView.addSubview(unreadBadge)
        contentView.addSubview(contactImage)
        contentView.addSubview(notificationTextLabel)
        contentView.addSubview(mediaPreview)

        mediaPreviewWidthAnchor = mediaPreview.widthAnchor.constraint(equalToConstant: 22)
        mediaPreviewWidthAnchor?.isActive = true
        
        contentView.addConstraints([
            unreadBadge.heightAnchor.constraint(equalToConstant: 7),
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

            mediaPreview.heightAnchor.constraint(equalTo: mediaPreview.widthAnchor),
            mediaPreview.leadingAnchor.constraint(equalToSystemSpacingAfter: notificationTextLabel.trailingAnchor, multiplier: 1),
            mediaPreview.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            mediaPreview.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            mediaPreview.bottomAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.bottomAnchor)
        ])
    }

    func configure(with item: ActivityCenterItem) {
        backgroundColor = item.read ? .primaryBg : .notificationUnreadHighlight

        unreadBadge.isHidden = item.read
        notificationTextLabel.attributedText = item.text
        mediaPreview.image = item.image

        // only text and audio posts get a border
        let displayedMediaType: FeedActivity.MediaType

        switch item.content {
        case .singleNotification(let activity):
            displayedMediaType = activity.mediaType
        case .unknownCommenters(let activities):
            // Fall back to borderless case if activities is empty
            displayedMediaType = activities.first?.mediaType ?? .image
        case .groupEvent(_):
            displayedMediaType = .none
        }

        let visibleBorderWidth: CGFloat = 0.5
        switch displayedMediaType {
        case .audio:
            mediaPreview.contentMode = .center
            mediaPreview.layer.borderWidth = visibleBorderWidth
        case .none, .document:
            mediaPreview.contentMode = .scaleAspectFit
            mediaPreview.layer.borderWidth = visibleBorderWidth
        case .image, .video:
            mediaPreview.contentMode = .scaleAspectFit
            mediaPreview.layer.borderWidth = 0
        }
        
        mediaPreviewWidthAnchor?.constant = item.image == nil ? 0 : 44
        
        if case .singleNotification(let notif) = item.content, notif.event == .favoritesPromo {
            contactImage.configure(image: UIImage(named: "PrivacySettingFavoritesWithBackground"))
        } else if let userId = item.userID {
            contactImage.configure(with: userId, using: MainAppContext.shared.avatarStore)
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        contactImage.prepareForReuse()
        notificationTextLabel.attributedText = nil
    }
}

extension UITableView {
    func contains(indexPath: IndexPath) -> Bool {
        return numberOfSections > indexPath.section && numberOfRows(inSection: indexPath.section) > indexPath.row
    }
}

extension NotificationsViewController: UIViewControllerScrollsToTop {

    func scrollToTop(animated: Bool) {
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: animated)
    }
}
