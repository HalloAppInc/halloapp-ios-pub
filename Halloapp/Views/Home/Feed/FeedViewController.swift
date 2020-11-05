//
//  FeedViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/20/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import SwiftUI
import UIKit

class FeedViewController: FeedTableViewController {

    private var cancellables: Set<AnyCancellable> = []
    private var notificationButton: BadgedButton?
    private var notificationCount: Int = 0 {
        didSet {
            updateNotificationCount(notificationCount)
        }
    }

    private var feedPostIdToScrollTo: FeedPostID?

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        installLargeTitleUsingGothamFont()
        installFloatingActionMenu()
        installInviteFriendsButton()

        let notificationButton = BadgedButton(type: .system)
        notificationButton.setImage(UIImage(named: "FeedNavbarNotifications"), for: .normal)
        notificationButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        notificationButton.addTarget(self, action: #selector(presentNotificationsView), for: .touchUpInside)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: notificationButton)
        self.notificationButton = notificationButton

        if let feedNotifications = MainAppContext.shared.feedData.feedNotifications {
            notificationCount = feedNotifications.unreadCount
            self.cancellables.insert(feedNotifications.unreadCountDidChange.sink { [weak self] (unreadCount) in
                self?.notificationCount = unreadCount
            })
        }

        cancellables.insert(
            MainAppContext.shared.feedData.didReceiveFeedPost.sink { [weak self] (feedPost) in
                guard let self = self else { return }
                if self.feedPostIdToScrollTo == feedPost.id {
                    DDLogDebug("FeedViewController/scroll-to-post/postponed \(feedPost.id)")
                    self.scrollTo(post: feedPost)
                    self.feedPostIdToScrollTo = nil
                }
        })

        cancellables.insert(
            MainAppContext.shared.didTapNotification.sink { [weak self] (metadata) in
                guard let self = self else { return }
                self.processNotification(metadata: metadata)
        })

        // When the user was not on this view, and HomeView sends user to here
        if let metadata = NotificationMetadata.fromUserDefaults()  {
            self.processNotification(metadata: metadata)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateInviteFriendsButtonPosition()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        showNUXIfNecessary()
    }

    deinit {
        self.cancellables.forEach { $0.cancel() }
    }

    // MARK: FeedTableViewController

    override var fetchRequest: NSFetchRequest<FeedPost> {
        get {
            let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "groupId == nil")
            fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
            return fetchRequest
        }
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)

        guard scrollView == tableView else { return }
        updateInviteFriendsButtonPosition()
    }

    // MARK: UI Actions

    @objc private func presentNotificationsView() {
        self.present(UINavigationController(rootViewController: NotificationsViewController(style: .plain)), animated: true)
    }

    // MARK: Invite friends

    private let inviteFriendsButton = UIButton()

    private func installInviteFriendsButton() {
        inviteFriendsButton.setTitle(Localizations.inviteFriendsAndFamily, for: .normal)
        inviteFriendsButton.setTitleColor(.systemBlue, for: .normal)
        inviteFriendsButton.titleLabel?.font = .gothamFont(forTextStyle: .subheadline, weight: .medium)
        inviteFriendsButton.titleLabel?.numberOfLines = 0
        inviteFriendsButton.tintColor = .systemBlue
        let image = UIImage(named: "AddFriend")?
            .withRenderingMode(.alwaysTemplate)
            .imageFlippedForRightToLeftLayoutDirection()
        inviteFriendsButton.setImage(image, for: .normal)
        inviteFriendsButton.translatesAutoresizingMaskIntoConstraints = false
        inviteFriendsButton.addTarget(self, action: #selector(startInviteFriendsFlow), for: .touchUpInside)
        inviteFriendsButton.contentHorizontalAlignment = .leading
        let imageSpacing: CGFloat = 6 // NB: The image has an additional 4px of padding so it will optically center correctly
        inviteFriendsButton.contentEdgeInsets = inviteFriendsButton.getDirectionalUIEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: imageSpacing)
        inviteFriendsButton.titleEdgeInsets = inviteFriendsButton.getDirectionalUIEdgeInsets(top: 0, leading: imageSpacing, bottom: 0, trailing: -imageSpacing)
        view.addSubview(inviteFriendsButton)

        inviteFriendsButton.trailingAnchor.constraint(lessThanOrEqualTo: floatingMenu.permanentButton.leadingAnchor).isActive = true
        inviteFriendsButton.constrainMargin(anchor: .leading, to: view)
    }

    private func updateInviteFriendsButtonPosition() {
        let tableViewVisibleHeight = tableView.contentSize.height - tableView.contentOffset.y
        let floatingButtonAlignedY = floatingMenu.permanentButton.center.y - inviteFriendsButton.frame.height / 2

        inviteFriendsButton.frame.origin.y = max(tableViewVisibleHeight, floatingButtonAlignedY)
    }

    @objc
    private func startInviteFriendsFlow() {
        InviteManager.shared.requestInvitesIfNecessary()
        let inviteView = InvitePeopleView(dismiss: { [weak self] in self?.dismiss(animated: true, completion: nil) })
        let inviteVC = UIHostingController(rootView: inviteView)
        let navController = UINavigationController(rootViewController: inviteVC)
        present(navController, animated: true)
    }

    // MARK: NUX

    private lazy var overlayContainer: OverlayContainer = {
        let targetView: UIView = tabBarController?.view ?? view
        let overlayContainer = OverlayContainer()
        overlayContainer.translatesAutoresizingMaskIntoConstraints = false
        targetView.addSubview(overlayContainer)
        overlayContainer.constrain(to: targetView)
        return overlayContainer
    }()

    private weak var overlay: Overlay?

    private var isShowingNUXHeaderView = false

    private func showNUXIfNecessary() {
        if isShowingNUXHeaderView || overlay != nil {
            // only show one NUX item at a time
            return
        } else if MainAppContext.shared.nux.isIncomplete(.homeFeedIntro) {
            installNUXHeaderView()
        } else if MainAppContext.shared.nux.isIncomplete(.activityCenterIcon) && notificationCount > 0 {
            showActivityCenterNUX()
        } else if MainAppContext.shared.nux.isIncomplete(.newPostButton) {
            showFloatingMenuNUX()
        }
    }

    private func installNUXHeaderView() {
        let stringLearnMore = NSLocalizedString("nux.learn.more", value: "Learn more", comment: "Action in NUX UI in Home screen.")
        let nuxItem = NUXItem(
            message: Localizations.nuxHomeFeedIntroContent,
            icon: UIImage(named: "NUXSpeechBubble"),
            link: (text: stringLearnMore, action: { [weak self] nuxItem in
                self?.showNUXDetails { _ = nuxItem.dismiss() }
            }),
            didClose: { [weak self] in
                MainAppContext.shared.nux.didComplete(.homeFeedIntro)
                UIView.animate(
                    withDuration: 0.3,
                    delay: 0,
                    usingSpringWithDamping: 1,
                    initialSpringVelocity: 0,
                    options: UIView.AnimationOptions(),
                    animations: {
                        self?.isShowingNUXHeaderView = false
                        self?.tableView.tableHeaderView = nil
                        self?.tableView.layoutIfNeeded() },
                    completion: { [weak self] _ in
                        self?.showNUXIfNecessary()
                    })
        })
        nuxItem.frame.size = nuxItem.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: .greatestFiniteMagnitude),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        tableView.tableHeaderView = nuxItem
        isShowingNUXHeaderView = true
    }

    private func showNUXDetails(completion: (() -> Void)?) {
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = Localizations.nuxHomeFeedDetailsTitle
        titleLabel.numberOfLines = 0
        titleLabel.font = .systemFont(forTextStyle: .title3, weight: .medium)
        titleLabel.textColor = UIColor.label

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = Localizations.nuxHomeFeedDetailsBody
        label.numberOfLines = 0
        label.font = .systemFont(forTextStyle: .callout)
        label.textColor = UIColor.label.withAlphaComponent(0.5)

        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        button.setTitle(Localizations.buttonOK, for: .normal)
        button.setTitleColor(UIColor.nux, for: .normal)
        button.titleLabel?.font = .systemFont(forTextStyle: .callout, weight: .bold)
        button.addTarget(self, action: #selector(dismissOverlay), for: .touchUpInside)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(label)
        contentView.addSubview(button)

        titleLabel.constrainMargins([.top, .leading, .trailing], to: contentView)

        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.constrainMargins([.leading, .trailing], to: contentView)
        label.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 15).isActive = true

        button.constrainMargins([.trailing, .bottom], to: contentView)
        button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 15).isActive = true
        button.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor).isActive = true

        let sheet = BottomSheet(innerView: contentView, completion: completion)

        overlay = sheet
        overlayContainer.display(sheet)
    }

    private func showFloatingMenuNUX() {
        let popover = NUXPopover(
            Localizations.nuxNewPostButtonContent,
            targetRect: floatingMenu.permanentButton.bounds,
            targetSpace: floatingMenu.permanentButton.coordinateSpace,
            showButton: false) { [weak self] in
            MainAppContext.shared.nux.didComplete(.newPostButton)
            self?.overlay = nil
        }

        overlay = popover
        overlayContainer.display(popover)
    }

    private func showActivityCenterNUX() {
        guard let notificationButton = notificationButton else {
            return
        }
        let popover = NUXPopover(
            Localizations.nuxActivityCenterIconContent,
            targetRect: notificationButton.bounds,
            targetSpace: notificationButton.coordinateSpace,
            showButton: false) { [weak self] in
            MainAppContext.shared.nux.didComplete(.activityCenterIcon)
            self?.overlay = nil
        }

        overlay = popover
        overlayContainer.display(popover)
    }

    @objc
    private func dismissOverlay() {
        if let currentOverlay = overlay {
            overlayContainer.dismiss(currentOverlay)
        }
        overlay = nil
    }

    // MARK: New post

    private lazy var floatingMenu: FloatingMenu = {
        FloatingMenu(
            permanentButton: .rotatingToggleButton(
                collapsedIconTemplate: UIImage(named: "icon_fab_compose_post")?.withRenderingMode(.alwaysTemplate),
                expandedRotation: 45),
            expandedButtons: [
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_image")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: Localizations.fabAccessibilityPhotoLibrary,
                    action: { [weak self] in self?.presentNewPostViewController(source: .library) }),
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_camera")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: Localizations.fabAccessibilityCamera,
                    action: { [weak self] in self?.presentNewPostViewController(source: .camera) }),
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_text")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: Localizations.fabAccessibilityTextPost,
                    action: { [weak self] in self?.presentNewPostViewController(source: .noMedia) }),
            ]
        )
    }()

    private func installFloatingActionMenu() {
        floatingMenu.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingMenu)
        floatingMenu.constrain(to: view)

        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: floatingMenu.suggestedContentInsetHeight, right: 0)
    }

    private func presentNewPostViewController(source: NewPostMediaSource) {
        let newPostViewController = NewPostViewController(source: source, destination: .userFeed) {
            self.dismiss(animated: true)
        }
        newPostViewController.modalPresentationStyle = .fullScreen
        present(newPostViewController, animated: true)
    }

    // MARK: Notification Handling

    private func updateNotificationCount(_ unreadCount: Int) {
        notificationButton?.isBadgeHidden = unreadCount == 0
        showNUXIfNecessary()
    }

    private func scrollTo(post feedPost: FeedPost) {
        if let indexPath = fetchedResultsController?.indexPath(forObject: feedPost) {
            tableView.scrollToRow(at: indexPath, at: .top, animated: false)
        }
    }

    private func processNotification(metadata: NotificationMetadata) {
        guard metadata.isFeedNotification else {
            return
        }

        metadata.removeFromUserDefaults()

        DDLogInfo("FeedViewController/notification/process type=\(metadata.contentType) contentId=\(metadata.contentId)")

        guard let protoContainer = metadata.protoContainer, protoContainer.hasComment || protoContainer.hasPost else {
            DDLogError("FeedViewController/notification/process/error Invalid protobuf")
            return
        }
        guard let feedPostId = protoContainer.hasComment ? protoContainer.comment.feedPostID : metadata.feedPostId else {
            DDLogError("FeedViewController/notification/process/error Can't find postId")
            return
        }

        let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId)
        if feedPost == nil {
            DDLogWarn("FeedViewController/notification/process/warning Missing post with id=[\(feedPostId)]")
        }

        navigationController?.popToRootViewController(animated: false)

        switch metadata.contentType {
        case .feedComment, .groupFeedComment:
            if let commentId = metadata.feedPostCommentId {
                showCommentsView(for: feedPostId, highlighting: commentId)
            }

        case .feedPost:
            if let feedPost = feedPost {
                DDLogDebug("FeedViewController/scroll-to-post/immediate \(feedPostId)")
                // Scroll to feed post now.
                scrollTo(post: feedPost)
            } else {
                DDLogDebug("FeedViewController/scroll-to-post/postpone \(feedPostId)")
                // Scroll to the top now and wait for post to be received.
                ///TODO: some kind of indicator?
                feedPostIdToScrollTo = feedPostId
                if !(fetchedResultsController?.fetchedObjects?.isEmpty ?? true) {
                    tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
                }
            }

        case .groupFeedPost:
            if let groupId = metadata.groupId, let _ = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                navigationController?.pushViewController(GroupFeedViewController(groupId: groupId), animated: false)
            }
            break

        default:
            break
        }
    }

}
