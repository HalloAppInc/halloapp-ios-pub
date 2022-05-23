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

class NotificationsViewController: UIViewController, UITableViewDelegate, NSFetchedResultsControllerDelegate {
    private static let cellReuseIdentifier = "NotificationsTableViewCell"
    
    private let bottomSafeAreaHeight = UIApplication.shared.windows[0].safeAreaInsets.bottom

    private var dataSource: UITableViewDiffableDataSource<ActivityCenterSection, ActivityCenterItem>!
    private var fetchedResultsController: NSFetchedResultsController<FeedActivity>!
    private lazy var tableView: UITableView = { UITableView() }()
    private var bottomBar: UIView!
    private let readAllButton = UIButton()
  
    private var displayedItems: [ActivityCenterItem] = []
    /// - note: Used for when the user marks all notifications as read.
    private var cachedScrollPosition: (indexPath: IndexPath, offset: CGFloat)?

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = Localizations.titleActivity
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(cancelAction))

        tableView.delegate = self
        tableView.register(NotificationTableViewCell.self, forCellReuseIdentifier: NotificationsViewController.cellReuseIdentifier)
        tableView.separatorStyle = .none
        
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.constrain(to: view)
        
        tableView.backgroundColor = .primaryBg
        view.backgroundColor = .primaryBg
        
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60 // set a number close to default to prevent cells overlapping issue, can't be auto

        dataSource = UITableViewDiffableDataSource<ActivityCenterSection, ActivityCenterItem>(tableView: tableView) { tableView, indexPath, notification in
            let cell = tableView.dequeueReusableCell(withIdentifier: NotificationsViewController.cellReuseIdentifier, for: indexPath) as! NotificationTableViewCell
            cell.configure(with: notification)
            return cell
        }

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
        fetchedResultsController =
            NSFetchedResultsController<FeedActivity>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.mainDataStore.viewContext,
                                                         sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = self
        do {
            try fetchedResultsController!.performFetch()
            updateUI()
        } catch { }
        
        setupBottomBar()
    }

    private func updateUI() {
        let snapshot = makeDataSnapshot()
        let hasUnreadItem = snapshot.itemIdentifiers.contains { $0.read == false }

        dataSource.apply(snapshot, animatingDifferences: false)
        
        readAllButton.isEnabled = hasUnreadItem
        readAllButton.setTitleColor(hasUnreadItem ? .systemBlue : .gray, for: .normal)
    }
    
    private func setupBottomBar() {
        bottomBar = UIView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        
        bottomBar.backgroundColor = .notificationBottomBarBackground
        bottomBar.layer.shadowColor = UIColor.notificationBottomBarShadow.cgColor
        bottomBar.layer.shadowOpacity = 1
        bottomBar.layer.shadowOffset = .zero
        bottomBar.layer.shadowRadius = 4
        
        view.addSubview(bottomBar)
        bottomBar.constrain([.leading, .trailing, .bottom], to: view)

        readAllButton.addTarget(self, action: #selector(markAllNotificationsRead), for: .touchUpInside)

        let title = NSAttributedString(string: Localizations.readAll, attributes: [.font : UIFont.gothamFont(forTextStyle: .callout, weight: .medium)])
        
        readAllButton.setAttributedTitle(title, for: .normal)
        
        bottomBar.addSubview(readAllButton)

        let readAllButtonBottomPadding: CGFloat = 3
        readAllButton.translatesAutoresizingMaskIntoConstraints = false
        readAllButton.heightAnchor.constraint(equalToConstant: 48 - readAllButtonBottomPadding).isActive = true
        readAllButton.constrain([.top, .leading, .trailing], to: bottomBar)
        readAllButton.constrain(anchor: .bottom, to: bottomBar, constant: -(bottomSafeAreaHeight + readAllButtonBottomPadding))
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.contentInset.bottom = bottomBar.frame.height - bottomSafeAreaHeight
        
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
        
        let activityCenterItems = activityCenterItems(for: fetchedResultsController.fetchedObjects ?? [])
        
        snapshot.appendItems(activityCenterItems)
        displayedItems = activityCenterItems
        
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
        
        // Sort the notifications from newest to oldest before returning them
        return displayItems.sorted { lhs, rhs in
            lhs.timestamp > rhs.timestamp
        }
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
        let notification = displayedItems[indexPath.row]
        tableView.deselectRow(at: indexPath, animated: true)

        if case .singleNotification(let notif) = notification.content, notif.event == .favoritesPromo {
            MainAppContext.shared.feedData.markNotificationsAsRead(for: "favorites")
            let presentingViewController = presentingViewController
            self.dismiss(animated: true)
            presentingViewController?.present(FavoritesInformationViewController(), animated: true)
            return
        }

        guard let postId = notification.postId, MainAppContext.shared.feedData.feedPost(with: postId, in: MainAppContext.shared.feedData.viewContext) != nil else {
            return
        }

        let commentsViewController = FlatCommentsViewController(feedPostId: postId)
        commentsViewController.initiallyHighlightedCommentID = notification.commentId
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
            
            self.memoizeScrollPosition()
        })
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        present(actionSheet, animated: true)
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
        }

        let visibleBorderWidth: CGFloat = 0.5
        switch displayedMediaType {
        case .audio:
            mediaPreview.contentMode = .center
            mediaPreview.layer.borderWidth = visibleBorderWidth
        case .none:
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
