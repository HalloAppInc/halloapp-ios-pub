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
        if let feedNotifications = MainAppContext.shared.feedData.feedNotifications {
            notificationButton.isBadgeHidden = feedNotifications.unreadCount == 0
            self.cancellables.insert(feedNotifications.unreadCountDidChange.sink { (unreadCount) in
                notificationButton.isBadgeHidden = unreadCount == 0
            })
        }

        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: notificationButton)

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

    deinit {
        self.cancellables.forEach { $0.cancel() }
    }

    // MARK: FeedTableViewController

    override var fetchRequest: NSFetchRequest<FeedPost> {
        get {
            let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
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
        inviteFriendsButton.setTitle("Invite friends & family", for: .normal)
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

    // MARK: New post

    private lazy var floatingMenu: FloatingMenu = {
        FloatingMenu(
            permanentButton: .rotatingToggleButton(
                collapsedIconTemplate: UIImage(named: "icon_fab_compose_post")?.withRenderingMode(.alwaysTemplate),
                expandedRotation: 45),
            expandedButtons: [
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_image")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: "Photo",
                    action: { [weak self] in self?.presentNewPostViewController(source: .library) }),
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_camera")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: "Camera",
                    action: { [weak self] in self?.presentNewPostViewController(source: .camera) }),
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_text")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: "Text",
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
        let newPostViewController = NewPostViewController(source: source) {
            self.dismiss(animated: true)
        }
        newPostViewController.modalPresentationStyle = .fullScreen
        present(newPostViewController, animated: true)
    }

    // MARK: Notification Handling

    private func scrollTo(post feedPost: FeedPost) {
        if let indexPath = fetchedResultsController?.indexPath(forObject: feedPost) {
            tableView.scrollToRow(at: indexPath, at: .top, animated: false)
        }
    }

    private func processNotification(metadata: NotificationMetadata) {
        guard metadata.contentType == .comment || metadata.contentType == .feedpost else {
            return
        }

        metadata.removeFromUserDefaults()

        DDLogInfo("FeedViewController/notification/process type=\(metadata.contentType) contentId=\(metadata.contentId)")

        guard let protoContainer = metadata.protoContainer, protoContainer.hasComment || protoContainer.hasPost else {
            DDLogError("FeedViewController/notification/process/error Invalid protobuf")
            return
        }

        let feedPostId = protoContainer.hasPost ? metadata.contentId : protoContainer.comment.feedPostID

        let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId)
        if feedPost == nil {
            DDLogWarn("FeedViewController/notification/process/warning Missing post with id=[\(feedPostId)]")
        }

        self.navigationController?.popToRootViewController(animated: false)

        switch metadata.contentType {
        case .comment:
            self.showCommentsView(for: feedPostId, highlighting: metadata.contentId)

        case .feedpost:
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

        default:
            break
        }
    }

}
