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

    private var dataSource: UITableViewDiffableDataSource<ActivityCenterSection, ActivityCenterItem>!
    private lazy var tableView: UITableView = UITableView()
  
    /// - note: Used for when the user marks all notifications as read.
    private var cachedScrollPosition: (indexPath: IndexPath, offset: CGFloat)?

    private lazy var feedActivityFetchedResultsController: NSFetchedResultsController<FeedActivity> = {
        let fetchRequest: NSFetchRequest<FeedActivity> = FeedActivity.fetchRequest()
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedActivity.timestamp, ascending: false) ]
        return NSFetchedResultsController<FeedActivity>(fetchRequest: fetchRequest,
                                                        managedObjectContext: MainAppContext.shared.mainDataStore.viewContext,
                                                        sectionNameKeyPath: nil,
                                                        cacheName: nil)
    }()

    private let feedGroupsFetchedResultsController: NSFetchedResultsController<Group> = {
        let fetchRequest = Group.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "typeValue == %d", GroupType.groupFeed.rawValue)
        fetchRequest.sortDescriptors = []
        fetchRequest.propertiesToFetch = [ "id"]
        return NSFetchedResultsController(fetchRequest: fetchRequest,
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

    private lazy var friendActivityResultsController: NSFetchedResultsController<FriendActivity> = {
        let request = FriendActivity.fetchRequest()
        request.predicate = NSPredicate(format: "statusValue != %d", FriendActivity.Status.none.rawValue)
        request.sortDescriptors = [.init(keyPath: \FriendActivity.timestamp, ascending: false)]
        return NSFetchedResultsController(fetchRequest: request,
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
        tableView.register(StandardNotificationTableViewCell.self, forCellReuseIdentifier: StandardNotificationTableViewCell.reuseIdentifier)
        tableView.register(FriendNotificationTableViewCell.self, forCellReuseIdentifier: FriendNotificationTableViewCell.reuseIdentifier)
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
        tableView.sectionHeaderTopPadding = 0

        dataSource = UITableViewDiffableDataSource<ActivityCenterSection, ActivityCenterItem>(tableView: tableView) { tableView, indexPath, notification in
            let cell: UITableViewCell

            switch notification.content {
            case .incomingFriendNotification:
                cell = tableView.dequeueReusableCell(withIdentifier: FriendNotificationTableViewCell.reuseIdentifier, for: indexPath)
                guard let cell = cell as? FriendNotificationTableViewCell else {
                    break
                }
                cell.configure(with: notification)
                cell.onConfirm = { [weak self] in
                    self?.confirmRequest(using: notification)
                }
                cell.onIgnore = { [weak self] in
                    self?.ignoreRequest(using: notification)
                }
                cell.selectionStyle = .none
            default:
                cell = tableView.dequeueReusableCell(withIdentifier: StandardNotificationTableViewCell.reuseIdentifier, for: indexPath)
                (cell as? StandardNotificationTableViewCell)?.configure(with: notification)
            }

            return cell
        }

        feedActivityFetchedResultsController.delegate = self
        try? feedActivityFetchedResultsController.performFetch()

        feedGroupsFetchedResultsController.delegate = self
        try? feedGroupsFetchedResultsController.performFetch()

        groupEventFetchedResultsController.delegate = self
        try? groupEventFetchedResultsController.performFetch()

        friendActivityResultsController.delegate = self
        try? friendActivityResultsController.performFetch()

        updateUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // remove the red dot when the user navigates to this screen
        navigationController?.tabBarItem.badgeValue = nil

        Analytics.openScreen(.activity)
    }

    private func updateUI() {
        let snapshot = makeDataSnapshot()
        let hasUnreadItem = snapshot.itemIdentifiers.contains { $0.read == false }

        dataSource.apply(snapshot, animatingDifferences: false)
        navigationItem.rightBarButtonItem?.isEnabled = hasUnreadItem
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

        if let groups = feedGroupsFetchedResultsController.fetchedObjects, let groupEvents = groupEventFetchedResultsController.fetchedObjects {
            // only inlcude group feed events
            let groupIds = Set(groups.compactMap{$0.id})
            items += groupEvents.compactMap {
                if groupIds.contains($0.groupID) {
                    return ActivityCenterItem(content: .groupEvent($0))
                }
                return nil
            }
        }

        if let friendActivities = friendActivityResultsController.fetchedObjects {
            items += friendItems(for: friendActivities)
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
        // Add an item for each comment made by a friend
        var friendNotifications: [FeedActivity] = []
        var nonFriendNotifications: [FeedActivity] = []
        let allFriendUserIDs = UserProfile.allUserIDs(friendshipStatus: .friends, in: MainAppContext.shared.mainDataStore.viewContext)
        postNotifications.forEach { notification in
            if allFriendUserIDs.contains(notification.userID) {
                friendNotifications.append(notification)
            } else {
                nonFriendNotifications.append(notification)
            }
        }

        let itemsForFriendComments = friendNotifications.compactMap {
            ActivityCenterItem(content: .singleNotification($0))
        }
        items += itemsForFriendComments

        // Aggregate all comments from non-contacts into a single item
        let itemForNonFriendComments: ActivityCenterItem? = {
            let nonFriendsWhoCommented = Set<UserID>(nonFriendNotifications.map { $0.userID })
            if nonFriendsWhoCommented.count > 1 {
                // Aggregate comments from multiple non-contacts
                return ActivityCenterItem(content: .unknownCommenters(nonFriendNotifications))
            } else if let notification = nonFriendNotifications.first {
                // If one non-friend has commented, show his or her latest comment
                return ActivityCenterItem(content: .singleNotification(notification))
            } else {
                // No comments from non-friends
                return nil
            }
        }()
        if let itemForNonFriendComments = itemForNonFriendComments {
            items.append(itemForNonFriendComments)
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

    private func friendItems(for friendNotifications: [FriendActivity]) -> [ActivityCenterItem] {
        friendNotifications.compactMap { notification in
            switch notification.status {
            case .accepted:
                return ActivityCenterItem(content: .confirmedFriendNotification(notification))
            default:
                return ActivityCenterItem(content: .incomingFriendNotification(notification))
            }
        }
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
            guard let group = MainAppContext.shared.chatData.chatGroup(groupId: groupEvent.groupID, in: MainAppContext.shared.chatData.viewContext) else { return }
            switch group.type {
            case .groupFeed:
                let groupFeedViewController = GroupFeedViewController(group: group)
                groupFeedViewController.groupEventToScrollTo = groupEvent
                navigationController?.pushViewController(groupFeedViewController, animated: true)
            case .groupChat:
                let groupChatViewController = GroupChatViewController(for: group)
                navigationController?.pushViewController(groupChatViewController, animated: true)
            case .oneToOne:
                break
            }
        case .incomingFriendNotification:
            break
        case .confirmedFriendNotification(let activity):
            MainAppContext.shared.userProfileData.markFriendEventAsRead(userID: activity.userID)
            let viewController = UserFeedViewController(userId: activity.userID)
            navigationController?.pushViewController(viewController, animated: true)
        }
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
                MainAppContext.shared.userProfileData.markAllFriendEventsAsRead()
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

    private func confirmRequest(using notification: ActivityCenterItem) {
        guard case let .incomingFriendNotification(activity) = notification.content else {
            return
        }

        // optimistically update
        var snapshot = dataSource.snapshot()
        snapshot.deleteItems([notification])
        dataSource.apply(snapshot, animatingDifferences: true)

        Task(priority: .userInitiated) {
            do {
                try await MainAppContext.shared.userProfileData.acceptFriend(userID: activity.userID)
            } catch {
                updateUI()
                let alert = UIAlertController(title: nil, message: Localizations.genericError, preferredStyle: .alert)
                present(alert, animated: true)
            }
        }
    }

    private func ignoreRequest(using notification: ActivityCenterItem) {
        guard case let .incomingFriendNotification(activity) = notification.content else {
            return
        }

        var snapshot = dataSource.snapshot()
        snapshot.deleteItems([notification])
        dataSource.apply(snapshot, animatingDifferences: true)

        Task(priority: .userInitiated) {
            do {
                try await MainAppContext.shared.userProfileData.ignoreRequest(userID: activity.userID)
            } catch {
                updateUI()
                let alert = UIAlertController(title: nil, message: Localizations.genericError, preferredStyle: .alert)
                present(alert, animated: true)
            }
        }
    }
}

fileprivate class BaseNotificationTableViewCell: UITableViewCell {

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

    let trailingView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private func setupView() {
        contentView.addSubview(unreadBadge)
        contentView.addSubview(contactImage)
        contentView.addSubview(notificationTextLabel)
        contentView.addSubview(trailingView)
        
        NSLayoutConstraint.activate([
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

            trailingView.leadingAnchor.constraint(equalToSystemSpacingAfter: notificationTextLabel.trailingAnchor, multiplier: 1),
            trailingView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            trailingView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            trailingView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    func configure(with item: ActivityCenterItem) {
        backgroundColor = item.read ? .primaryBg : .notificationUnreadHighlight

        unreadBadge.isHidden = item.read
        notificationTextLabel.attributedText = item.text

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

// MARK: - StandardNotificationTableViewCell

fileprivate class StandardNotificationTableViewCell: BaseNotificationTableViewCell {

    static let reuseIdentifier = "standardNotificationCell"

    private let mediaPreview: UIImageView = {
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

    private lazy var mediaPreviewWidthConstraint: NSLayoutConstraint = {
        mediaPreview.widthAnchor.constraint(equalToConstant: 22)
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        trailingView.addSubview(mediaPreview)
        NSLayoutConstraint.activate([
            mediaPreview.leadingAnchor.constraint(equalTo: trailingView.leadingAnchor),
            mediaPreview.trailingAnchor.constraint(equalTo: trailingView.trailingAnchor),
            mediaPreview.topAnchor.constraint(equalTo: trailingView.topAnchor),
            mediaPreview.bottomAnchor.constraint(equalTo: trailingView.bottomAnchor),
            mediaPreview.heightAnchor.constraint(equalTo: mediaPreview.widthAnchor, multiplier: 1),
            mediaPreviewWidthConstraint,
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("StandardNotificationTableViewCell coder init not implemented...")
    }

    override func configure(with item: ActivityCenterItem) {
        super.configure(with: item)

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
        case .incomingFriendNotification, .confirmedFriendNotification:
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

        mediaPreviewWidthConstraint.constant = item.image == nil ? 0 : 44
    }
}

// MARK: - FriendNotificationTableViewCell

fileprivate class FriendNotificationTableViewCell: BaseNotificationTableViewCell {

    static let reuseIdentifier = "friendNotificationCell"

    var onConfirm: (() -> Void)?
    var onIgnore: (() -> Void)?

    private let confirmButton: UIButton = {
        let button = UIButton()
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .primaryBlue
        configuration.contentInsets = .init(top: 8, leading: 13, bottom: 8, trailing: 13)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = configuration
        return button
    }()

    private let ignoreButton: UIButton = {
        let button = UIButton(type: .custom)
        let image = UIImage(systemName: "xmark")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 6, weight: .regular))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .lightGray
        return button
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        for view in [confirmButton, ignoreButton] {
            trailingView.addSubview(view)
            view.setContentHuggingPriority(.breakable, for: .horizontal)
            view.setContentCompressionResistancePriority(.breakable, for: .horizontal)
        }

        NSLayoutConstraint.activate([
            confirmButton.leadingAnchor.constraint(equalTo: trailingView.leadingAnchor),
            confirmButton.topAnchor.constraint(greaterThanOrEqualTo: trailingView.topAnchor),
            confirmButton.bottomAnchor.constraint(equalTo: trailingView.bottomAnchor),
            confirmButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            ignoreButton.leadingAnchor.constraint(equalTo: confirmButton.trailingAnchor, constant: 12),
            ignoreButton.trailingAnchor.constraint(equalTo: trailingView.trailingAnchor),
            ignoreButton.topAnchor.constraint(greaterThanOrEqualTo: trailingView.topAnchor),
            ignoreButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

        confirmButton.configuration?.attributedTitle = .init(Localizations.confirmTitle.uppercased(),
                                                             attributes: .init([.font: UIFont.scaledSystemFont(ofSize: 14, weight: .medium)]))

        confirmButton.addAction(.init { [weak self] _ in self?.onConfirm?() }, for: .touchUpInside)
        ignoreButton.addAction(.init { [weak self] _ in self?.onIgnore?() }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("FriendNotificationTableViewCell coder init not implemented...")
    }

    override func configure(with item: ActivityCenterItem) {
        super.configure(with: item)
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
